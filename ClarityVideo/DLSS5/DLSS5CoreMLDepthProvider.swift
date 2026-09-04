import Foundation
import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Metal

@MainActor
final class DLSS5CoreMLDepthProvider: DLSS5DepthProvider {
    let providerDescription: String

    private let model: MLModel
    private let inputName: String
    private let inputWidth: Int
    private let inputHeight: Int
    private let inputPixelFormat: OSType
    private let ciContext: CIContext
    private let commandQueue: any MTLCommandQueue
    private let contrast: Float
    private let depthColorSpace = CGColorSpaceCreateDeviceGray()

    init(
        compiledModelURL: URL,
        device: any MTLDevice,
        contrast: Float = 1
    ) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: compiledModelURL, configuration: configuration)

        guard let input = model.modelDescription.inputDescriptionsByName.first(where: { _, description in
            description.type == .image && description.imageConstraint != nil
        }), let constraint = input.value.imageConstraint else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The bundled depth model has no Core ML image input."
            )
        }
        inputName = input.key
        inputWidth = constraint.pixelsWide
        inputHeight = constraint.pixelsHigh
        inputPixelFormat = constraint.pixelFormatType
        guard inputWidth > 0, inputHeight > 0 else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The bundled depth model reported invalid input dimensions."
            )
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw DLSS5ContractError.runtimeUnavailable(
                "Metal could not create a command queue for depth estimation."
            )
        }
        self.commandQueue = commandQueue
        ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        self.contrast = min(5, max(0.2, contrast))
        providerDescription = "Core ML depth: \(compiledModelURL.deletingPathExtension().lastPathComponent)"
    }

    func makeDepthTexture(source: CVPixelBuffer, device: any MTLDevice) throws -> any MTLTexture {
        let modelInput = try makeModelInput(source: source)
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(pixelBuffer: modelInput)
        ])
        let prediction = try model.prediction(from: provider)
        let plane = try depthPlane(in: prediction)
        let outputWidth = CVPixelBufferGetWidth(source)
        let outputHeight = CVPixelBufferGetHeight(source)
        let destination = try DLSS5TextureFactory.makeSharedTexture(
            device: device,
            pixelFormat: .r32Float,
            width: outputWidth,
            height: outputHeight,
            usage: [.shaderRead, .shaderWrite]
        )

        let data = plane.values.withUnsafeBytes { Data($0) }
        let depthImage = CIImage(
            bitmapData: data,
            bytesPerRow: plane.width * MemoryLayout<Float>.stride,
            size: CGSize(width: plane.width, height: plane.height),
            format: .Rf,
            colorSpace: nil
        )
        let sx = CGFloat(outputWidth) / CGFloat(plane.width)
        let sy = CGFloat(outputHeight) / CGFloat(plane.height)
        let scaled = depthImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw DLSS5ContractError.runtimeUnavailable(
                "Metal could not prepare the depth resize command."
            )
        }
        ciContext.render(
            scaled,
            to: destination,
            commandBuffer: commandBuffer,
            bounds: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight),
            colorSpace: depthColorSpace
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw DLSS5ContractError.runtimeUnavailable(
                "Depth texture preparation failed: \(error.localizedDescription)"
            )
        }
        return destination
    }

    private func makeModelInput(source: CVPixelBuffer) throws -> CVPixelBuffer {
        let pixelFormat: OSType
        switch inputPixelFormat {
        case kCVPixelFormatType_32ARGB,
             kCVPixelFormatType_32BGRA,
             kCVPixelFormatType_OneComponent8,
             kCVPixelFormatType_OneComponent16Half,
             kCVPixelFormatType_OneComponent32Float,
             kCVPixelFormatType_64RGBAHalf:
            pixelFormat = inputPixelFormat
        default:
            pixelFormat = kCVPixelFormatType_32BGRA
        }

        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
        ]
        var destination: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            inputWidth,
            inputHeight,
            pixelFormat,
            attributes as CFDictionary,
            &destination
        )
        guard status == kCVReturnSuccess, let destination else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }

        let image = CIImage(cvPixelBuffer: source)
        let sx = CGFloat(inputWidth) / max(1, image.extent.width)
        let sy = CGFloat(inputHeight) / max(1, image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        ciContext.render(
            scaled,
            to: destination,
            bounds: CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return destination
    }

    private func depthPlane(in prediction: any MLFeatureProvider) throws -> (values: [Float], width: Int, height: Int) {
        for name in prediction.featureNames {
            guard let value = prediction.featureValue(for: name) else { continue }
            if value.type == .image, let buffer = value.imageBufferValue {
                return try normalizedDepthPlane(buffer)
            }
            if value.type == .multiArray, let array = value.multiArrayValue {
                return try normalizedDepthPlane(array)
            }
        }
        throw DLSS5ContractError.runtimeUnavailable(
            "The bundled depth model produced neither an image-buffer nor multi-array depth map."
        )
    }

    private func normalizedDepthPlane(_ buffer: CVPixelBuffer) throws -> (values: [Float], width: Int, height: Int) {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { throw DLSS5ContractError.invalidDimensions }

        let format = CVPixelBufferGetPixelFormatType(buffer)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw DLSS5ContractError.runtimeUnavailable("The Core ML depth buffer has no CPU-readable base address.")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        var raw = Array(repeating: Float.zero, count: width * height)

        switch format {
        case kCVPixelFormatType_OneComponent32Float,
             kCVPixelFormatType_DepthFloat32:
            let values = base.assumingMemoryBound(to: Float.self)
            let stride = bytesPerRow / MemoryLayout<Float>.stride
            for y in 0..<height {
                for x in 0..<width { raw[y * width + x] = values[y * stride + x] }
            }
        case kCVPixelFormatType_OneComponent16Half,
             kCVPixelFormatType_DepthFloat16:
            let values = base.assumingMemoryBound(to: Float16.self)
            let stride = bytesPerRow / MemoryLayout<Float16>.stride
            for y in 0..<height {
                for x in 0..<width { raw[y * width + x] = Float(values[y * stride + x]) }
            }
        case kCVPixelFormatType_OneComponent8:
            let values = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width { raw[y * width + x] = Float(values[y * bytesPerRow + x]) / 255 }
            }
        case kCVPixelFormatType_32ARGB:
            let values = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width { raw[y * width + x] = Float(values[y * bytesPerRow + x * 4 + 1]) / 255 }
            }
        case kCVPixelFormatType_32BGRA:
            let values = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width { raw[y * width + x] = Float(values[y * bytesPerRow + x * 4 + 2]) / 255 }
            }
        default:
            throw DLSS5ContractError.runtimeUnavailable(
                String(format: "Unsupported Core ML depth pixel format 0x%08X.", format)
            )
        }
        return normalize(raw, width: width, height: height)
    }

    private func normalizedDepthPlane(_ array: MLMultiArray) throws -> (values: [Float], width: Int, height: Int) {
        let shape = array.shape.map(\.intValue)
        let strides = array.strides.map(\.intValue)
        guard shape.count >= 2,
              shape.count == strides.count,
              let width = shape.last,
              width > 0 else {
            throw DLSS5ContractError.runtimeUnavailable("The depth model output shape is unsupported.")
        }
        let height = shape[shape.count - 2]
        guard height > 0 else {
            throw DLSS5ContractError.runtimeUnavailable("The depth model output has zero height.")
        }
        let yStride = strides[strides.count - 2]
        let xStride = strides[strides.count - 1]
        var raw = Array(repeating: Float.zero, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * yStride + x * xStride
                raw[y * width + x] = array[offset].floatValue
            }
        }
        return normalize(raw, width: width, height: height)
    }

    /// Depth Anything V2 produces relative inverse depth (larger values are nearer),
    /// which already matches the reversed-Z direction expected by the feeder. Normalize
    /// its finite range into (0, 1) while preserving that ordering.
    private func normalize(_ values: [Float], width: Int, height: Int) -> (values: [Float], width: Int, height: Int) {
        var result = values
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        for value in result where value.isFinite {
            minimum = min(minimum, value)
            maximum = max(maximum, value)
        }
        let range = maximum - minimum
        let epsilon = Float(1.0 / 65_504.0)
        if !minimum.isFinite || !maximum.isFinite || !range.isFinite || range <= 1e-8 {
            return (Array(repeating: 0.5, count: result.count), width, height)
        }
        for index in result.indices {
            var normalized = result[index].isFinite ? (result[index] - minimum) / range : 0.5
            normalized = min(1, max(0, normalized))
            if abs(contrast - 1) > 0.001 {
                normalized = pow(normalized, 1 / contrast)
            }
            result[index] = min(1 - 1e-6, max(epsilon, normalized))
        }
        return (result, width, height)
    }
}

@MainActor
enum DLSS5DepthProviderFactory {
    static func bestAvailable(device: any MTLDevice) -> any DLSS5DepthProvider {
        let preferredNames = [
            "DepthAnythingV2SmallF16P6",
            "DepthAnythingV2SmallF16P8",
            "DepthAnythingV2SmallF16",
            "DepthAnythingV2Small",
            "DepthAnythingV2",
            "DepthAnything"
        ]
        for name in preferredNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
               let provider = try? DLSS5CoreMLDepthProvider(compiledModelURL: url, device: device) {
                return provider
            }
        }
        if let urls = Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) {
            for url in urls where url.lastPathComponent.localizedCaseInsensitiveContains("depth") {
                if let provider = try? DLSS5CoreMLDepthProvider(compiledModelURL: url, device: device) {
                    return provider
                }
            }
        }
        return DLSS5FlatDepthProvider()
    }
}
