import Foundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Metal
import Vision

@MainActor
protocol DLSS5MotionProvider: AnyObject {
    var providerDescription: String { get }

    func makeMotionTexture(
        previous: CVPixelBuffer?,
        current: CVPixelBuffer,
        resetHistory: Bool,
        device: any MTLDevice
    ) throws -> any MTLTexture
}

@MainActor
final class DLSS5ZeroMotionProvider: DLSS5MotionProvider {
    let providerDescription = "zero motion"

    func makeMotionTexture(
        previous: CVPixelBuffer?,
        current: CVPixelBuffer,
        resetHistory: Bool,
        device: any MTLDevice
    ) throws -> any MTLTexture {
        try Self.makeZeroTexture(current: current, device: device)
    }

    static func makeZeroTexture(
        current: CVPixelBuffer,
        device: any MTLDevice
    ) throws -> any MTLTexture {
        let width = CVPixelBufferGetWidth(current)
        let height = CVPixelBufferGetHeight(current)
        let texture = try DLSS5TextureFactory.makeSharedTexture(
            device: device,
            pixelFormat: .rg16Float,
            width: width,
            height: height,
            usage: [.shaderRead, .shaderWrite]
        )

        let zeroRow = Data(count: width * 4)
        zeroRow.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            for y in 0..<height {
                texture.replace(
                    region: MTLRegionMake2D(0, y, width, 1),
                    mipmapLevel: 0,
                    withBytes: base,
                    bytesPerRow: width * 4
                )
            }
        }
        return texture
    }
}

/// Produces a full-resolution two-component half-float optical-flow field. The
/// request is intentionally arranged with the current frame as the targeted image
/// and the previous frame as the processed image so the result can be validated
/// against the current-to-previous pixel-space convention used by the DLSSNR
/// reference path.
@MainActor
final class DLSS5VisionMotionProvider: DLSS5MotionProvider {
    let providerDescription = "Vision optical flow; targeted current vs previous; RG16F"

    private let accuracy: VNGenerateOpticalFlowRequest.ComputationAccuracy
    private var textureCache: CVMetalTextureCache?
    private var commandQueue: (any MTLCommandQueue)?

    init(accuracy: VNGenerateOpticalFlowRequest.ComputationAccuracy = .high) {
        self.accuracy = accuracy
    }

    func makeMotionTexture(
        previous: CVPixelBuffer?,
        current: CVPixelBuffer,
        resetHistory: Bool,
        device: any MTLDevice
    ) throws -> any MTLTexture {
        guard !resetHistory, let previous else {
            return try DLSS5ZeroMotionProvider.makeZeroTexture(current: current, device: device)
        }

        let width = CVPixelBufferGetWidth(current)
        let height = CVPixelBufferGetHeight(current)
        guard width == CVPixelBufferGetWidth(previous),
              height == CVPixelBufferGetHeight(previous) else {
            throw DLSS5ContractError.runtimeUnavailable(
                "Optical-flow frames must have identical dimensions."
            )
        }

        let request = VNGenerateOpticalFlowRequest(
            targetedCVPixelBuffer: current,
            options: [:]
        )
        request.computationAccuracy = accuracy
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent16Half
        request.keepNetworkOutput = false

        let handler = VNImageRequestHandler(cvPixelBuffer: previous, options: [:])
        try handler.perform([request])

        guard let flow = request.results?.first?.pixelBuffer else {
            throw DLSS5ContractError.runtimeUnavailable(
                "Vision did not return an optical-flow pixel buffer."
            )
        }
        guard CVPixelBufferGetPixelFormatType(flow) == kCVPixelFormatType_TwoComponent16Half else {
            throw DLSS5ContractError.runtimeUnavailable(
                "Vision returned an unexpected optical-flow pixel format."
            )
        }
        guard CVPixelBufferGetWidth(flow) == width,
              CVPixelBufferGetHeight(flow) == height else {
            throw DLSS5ContractError.runtimeUnavailable(
                "Vision optical flow did not preserve full frame resolution."
            )
        }

        let destination = try DLSS5TextureFactory.makeSharedTexture(
            device: device,
            pixelFormat: .rg16Float,
            width: width,
            height: height,
            usage: [.shaderRead, .shaderWrite]
        )

        if try copyWithMetal(flow: flow, into: destination, device: device) {
            return destination
        }

        try copyWithCPU(flow: flow, into: destination, width: width, height: height)
        return destination
    }

    private func copyWithMetal(
        flow: CVPixelBuffer,
        into destination: any MTLTexture,
        device: any MTLDevice
    ) throws -> Bool {
        if textureCache == nil {
            var created: CVMetalTextureCache?
            let status = CVMetalTextureCacheCreate(
                kCFAllocatorDefault,
                nil,
                device,
                nil,
                &created
            )
            guard status == kCVReturnSuccess, let created else { return false }
            textureCache = created
        }
        guard let textureCache else { return false }

        var wrapped: CVMetalTexture?
        let width = CVPixelBufferGetWidth(flow)
        let height = CVPixelBufferGetHeight(flow)
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            flow,
            nil,
            .rg16Float,
            width,
            height,
            0,
            &wrapped
        )
        guard status == kCVReturnSuccess,
              let wrapped,
              let source = CVMetalTextureGetTexture(wrapped) else {
            return false
        }

        if commandQueue == nil {
            commandQueue = device.makeCommandQueue()
        }
        guard let commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            return false
        }

        blit.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: destination,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw DLSS5ContractError.runtimeUnavailable(
                "Metal optical-flow copy failed: \(error.localizedDescription)"
            )
        }
        return true
    }

    private func copyWithCPU(
        flow: CVPixelBuffer,
        into destination: any MTLTexture,
        width: Int,
        height: Int
    ) throws {
        CVPixelBufferLockBaseAddress(flow, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(flow, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(flow) else {
            throw DLSS5ContractError.runtimeUnavailable(
                "Vision optical flow is not CPU-readable and could not be imported into Metal."
            )
        }
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(flow)
        let packedBytesPerRow = width * 4
        for y in 0..<height {
            destination.replace(
                region: MTLRegionMake2D(0, y, width, 1),
                mipmapLevel: 0,
                withBytes: base.advanced(by: y * sourceBytesPerRow),
                bytesPerRow: packedBytesPerRow
            )
        }
    }
}

/// Matches the scene-cut policy used by the current standalone DLSSNR video
/// reference: compare tiny luminance thumbnails and reset temporal history when
/// mean absolute difference exceeds 0.24 of full scale.
@MainActor
final class DLSS5SceneCutDetector {
    let threshold: Float
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init(threshold: Float = 0.24) {
        self.threshold = min(1, max(0, threshold))
    }

    func isSceneCut(previous: CVPixelBuffer, current: CVPixelBuffer) throws -> Bool {
        let previousWidth = CVPixelBufferGetWidth(previous)
        let previousHeight = CVPixelBufferGetHeight(previous)
        let currentWidth = CVPixelBufferGetWidth(current)
        let currentHeight = CVPixelBufferGetHeight(current)
        guard previousWidth == currentWidth, previousHeight == currentHeight else {
            return true
        }
        guard currentWidth > 0, currentHeight > 0 else {
            throw DLSS5ContractError.invalidDimensions
        }

        let thumbWidth = 64
        let thumbHeight = max(1, Int((Double(currentHeight) * 64.0 / Double(currentWidth)).rounded()))
        let a = try thumbnail(previous, width: thumbWidth, height: thumbHeight)
        let b = try thumbnail(current, width: thumbWidth, height: thumbHeight)
        return Self.meanAbsoluteLumaDifference(a, b) > threshold
    }

    static func meanAbsoluteLumaDifference(_ a: [UInt8], _ b: [UInt8]) -> Float {
        guard a.count == b.count, a.count >= 4 else { return 1 }
        var total: Float = 0
        var samples = 0
        var index = 0
        while index + 3 < a.count {
            let ar = Float(a[index])
            let ag = Float(a[index + 1])
            let ab = Float(a[index + 2])
            let br = Float(b[index])
            let bg = Float(b[index + 1])
            let bb = Float(b[index + 2])
            let al = 0.2126 * ar + 0.7152 * ag + 0.0722 * ab
            let bl = 0.2126 * br + 0.7152 * bg + 0.0722 * bb
            total += abs(al - bl) / 255
            samples += 1
            index += 4
        }
        return samples > 0 ? total / Float(samples) : 1
    }

    private func thumbnail(
        _ pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        guard source.extent.width > 0, source.extent.height > 0 else {
            throw DLSS5ContractError.invalidDimensions
        }
        let originNormalized = source.transformed(
            by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY)
        )
        let scaled = originNormalized.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(width) / source.extent.width,
                y: CGFloat(height) / source.extent.height
            )
        )
        bytes.withUnsafeMutableBytes { storage in
            guard let base = storage.baseAddress else { return }
            context.render(
                scaled,
                toBitmap: base,
                rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return bytes
    }
}

@MainActor
final class DLSS5TemporalVideoPreparer {
    private let preparer: DLSS5FramePreparer
    private let sceneCutDetector: DLSS5SceneCutDetector
    private let colorEncoding: DLSS5ColorEncoding
    private var previousFrame: CVPixelBuffer?

    init(
        depthProvider: (any DLSS5DepthProvider)? = nil,
        motionProvider: (any DLSS5MotionProvider)? = nil,
        sceneCutThreshold: Float = 0.24,
        colorEncoding: DLSS5ColorEncoding = .sRGBDisplayReferred
    ) throws {
        let resolvedDepthProvider = depthProvider ?? DLSS5DepthProviderFactory.bestAvailable()
        let resolvedMotionProvider = motionProvider ?? DLSS5VisionMotionProvider()
        preparer = try DLSS5FramePreparer(
            depthProvider: resolvedDepthProvider,
            motionProvider: resolvedMotionProvider
        )
        sceneCutDetector = DLSS5SceneCutDetector(threshold: sceneCutThreshold)
        self.colorEncoding = colorEncoding
    }

    func reset() {
        previousFrame = nil
    }

    func prepare(
        source: CVPixelBuffer,
        presentationTime: CMTime,
        frameIndex: Int,
        useJitter: Bool = false
    ) throws -> DLSS5PreparedFrame {
        let resetHistory: Bool
        if let previousFrame {
            resetHistory = try sceneCutDetector.isSceneCut(previous: previousFrame, current: source)
        } else {
            resetHistory = true
        }

        let prepared = try preparer.prepareVideoFrame(
            source: source,
            previousSource: resetHistory ? nil : previousFrame,
            presentationTime: presentationTime,
            frameIndex: frameIndex,
            resetHistory: resetHistory,
            useJitter: useJitter,
            colorEncoding: colorEncoding
        )
        previousFrame = source
        return prepared
    }
}
