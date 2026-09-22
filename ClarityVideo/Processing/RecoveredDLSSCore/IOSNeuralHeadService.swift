import CoreImage
import CoreML
import CoreVideo
import Foundation

/// Runs the recovered four-channel neural-rendering head on decoded video frames.
/// Its output retains the input resolution. The existing super-resolution stage
/// must run separately to reach a 4K or 8K export target.
@MainActor
final class IOSNeuralHeadService {
    enum Failure: LocalizedError {
        case missingModel
        case incompatibleModel
        case pixelBuffer(OSStatus)

        var errorDescription: String? {
            switch self {
            case .missingModel: "The recovered neural model is not installed."
            case .incompatibleModel: "The recovered neural model has an incompatible input or output."
            case let .pixelBuffer(status): "Could not allocate a neural frame (\(status))."
            }
        }
    }

    static let tileSize = 128
    // Core ML serializes predictions for this session. This instance is used by
    // one export task at a time; the framework's async prediction runs off actor.
    nonisolated(unsafe) private let model: MLModel
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(modelURL: URL) throws {
        let url: URL
        if modelURL.pathExtension == "mlmodelc" {
            url = modelURL
        } else if modelURL.pathExtension == "mlpackage" {
            url = try MLModel.compileModel(at: modelURL)
        } else {
            throw Failure.missingModel
        }
        model = try MLModel(contentsOf: url, configuration: MLModelConfiguration())
        guard model.modelDescription.inputDescriptionsByName["color"]?.multiArrayConstraint?.shape.map(\.intValue)
                == [1, 16, Self.tileSize, Self.tileSize],
              model.modelDescription.outputDescriptionsByName["restored"]?.multiArrayConstraint?.shape.map(\.intValue)
                == [1, 4, Self.tileSize, Self.tileSize] else {
            throw Failure.incompatibleModel
        }
    }

    static func bundledModelURL() -> URL? {
        Bundle.main.url(forResource: "DLSSNeuralHead128", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "DLSSNeuralHead128", withExtension: "mlpackage")
    }

    func render(source: CVPixelBuffer, frameNumber: Int) async throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        var decoded: CVPixelBuffer?
        var result: CVPixelBuffer?
        let decodedStatus = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                                kCVPixelFormatType_32BGRA, attributes as CFDictionary, &decoded)
        guard decodedStatus == kCVReturnSuccess, let decoded else { throw Failure.pixelBuffer(decodedStatus) }
        let resultStatus = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                               kCVPixelFormatType_32BGRA, attributes as CFDictionary, &result)
        guard resultStatus == kCVReturnSuccess, let result else { throw Failure.pixelBuffer(resultStatus) }
        context.render(CIImage(cvPixelBuffer: source), to: decoded)
        CVPixelBufferLockBaseAddress(decoded, .readOnly)
        CVPixelBufferLockBaseAddress(result, [])
        defer {
            CVPixelBufferUnlockBaseAddress(result, [])
            CVPixelBufferUnlockBaseAddress(decoded, .readOnly)
        }
        guard let inputBase = CVPixelBufferGetBaseAddress(decoded)?.assumingMemoryBound(to: UInt8.self),
              let outputBase = CVPixelBufferGetBaseAddress(result)?.assumingMemoryBound(to: UInt8.self) else {
            throw Failure.incompatibleModel
        }
        let inputStride = CVPixelBufferGetBytesPerRow(decoded)
        let outputStride = CVPixelBufferGetBytesPerRow(result)
        for tileY in stride(from: 0, to: height, by: Self.tileSize) {
            for tileX in stride(from: 0, to: width, by: Self.tileSize) {
                try Task.checkCancellation()
                var rgb = [Float](repeating: 0, count: Self.tileSize * Self.tileSize * 3)
                for y in 0..<Self.tileSize {
                    for x in 0..<Self.tileSize {
                        let srcX = min(width - 1, tileX + x)
                        let srcY = min(height - 1, tileY + y)
                        let offset = srcY * inputStride + srcX * 4
                        let target = (y * Self.tileSize + x) * 3
                        rgb[target] = Float(inputBase[offset + 2]) / 255
                        rgb[target + 1] = Float(inputBase[offset + 1]) / 255
                        rgb[target + 2] = Float(inputBase[offset]) / 255
                    }
                }
                let color = try HostTensor(
                    descriptor: TensorDescriptor(name: "color", shape: [1, Self.tileSize, Self.tileSize, 3],
                                                 dataType: .float32, layout: .nhwc),
                    bytes: rgb.withUnsafeBytes { Data($0) }
                )
                let features = try NeuralRenderingFirstFramePreprocessor.makeFeatureTensor(
                    from: color, noiseFrameIndex: UInt32(truncatingIfNeeded: frameNumber)
                )
                let input = try MLMultiArray(shape: [1, 16, NSNumber(value: Self.tileSize), NSNumber(value: Self.tileSize)],
                                             dataType: .float32)
                let featureValues = features.bytes.withUnsafeBytes { bytes in
                    [Float](unsafeUninitializedCapacity: features.descriptor.elementCount) { buffer, count in
                        bytes.copyBytes(to: buffer)
                        count = features.descriptor.elementCount
                    }
                }
                let inputValues = input.dataPointer.assumingMemoryBound(to: Float.self)
                for y in 0..<Self.tileSize {
                    for x in 0..<Self.tileSize {
                        let pixel = y * Self.tileSize + x
                        for channel in 0..<16 {
                            inputValues[channel * Self.tileSize * Self.tileSize + pixel] = featureValues[pixel * 16 + channel]
                        }
                    }
                }
                let provider = try MLDictionaryFeatureProvider(dictionary: ["color": MLFeatureValue(multiArray: input)])
                let predicted = try await model.prediction(from: provider, options: MLPredictionOptions())
                guard let head = predicted.featureValue(for: "restored")?.multiArrayValue,
                      head.dataType == .float32 else { throw Failure.incompatibleModel }
                let headValues = head.dataPointer.assumingMemoryBound(to: Float.self)
                var output = [Float](repeating: 0, count: Self.tileSize * Self.tileSize * 4)
                for pixel in 0..<(Self.tileSize * Self.tileSize) {
                    for channel in 0..<4 {
                        output[pixel * 4 + channel] = headValues[channel * Self.tileSize * Self.tileSize + pixel]
                    }
                }
                let neuralHead = try HostTensor(
                    descriptor: TensorDescriptor(name: "restored", shape: [1, Self.tileSize, Self.tileSize, 4],
                                                 dataType: .float32, layout: .nhwc),
                    bytes: output.withUnsafeBytes { Data($0) }
                )
                let composed = try NeuralRenderingFirstFramePostprocessor.compose(head: neuralHead, over: color)
                composed.bytes.withUnsafeBytes { raw in
                    let rendered = raw.bindMemory(to: Float.self)
                    for y in 0..<min(Self.tileSize, height - tileY) {
                        for x in 0..<min(Self.tileSize, width - tileX) {
                            let pixel = (y * Self.tileSize + x) * 3
                            let destination = (tileY + y) * outputStride + (tileX + x) * 4
                            outputBase[destination] = UInt8(clamping: Int((rendered[pixel + 2] * 255).rounded()))
                            outputBase[destination + 1] = UInt8(clamping: Int((rendered[pixel + 1] * 255).rounded()))
                            outputBase[destination + 2] = UInt8(clamping: Int((rendered[pixel] * 255).rounded()))
                            outputBase[destination + 3] = 255
                        }
                    }
                }
            }
        }
        CVBufferPropagateAttachments(source, result)
        return result
    }
}
