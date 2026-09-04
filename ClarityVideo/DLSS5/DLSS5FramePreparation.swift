import Foundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Metal

@MainActor
final class DLSS5PreparedFrame {
    let metadata: DLSS5PreparedFrameMetadata
    let color: any MTLTexture
    let depth: any MTLTexture
    let motion: any MTLTexture

    init(
        metadata: DLSS5PreparedFrameMetadata,
        color: any MTLTexture,
        depth: any MTLTexture,
        motion: any MTLTexture
    ) {
        self.metadata = metadata
        self.color = color
        self.depth = depth
        self.motion = motion
    }
}

@MainActor
protocol DLSS5DepthProvider: AnyObject {
    var providerDescription: String { get }
    func makeDepthTexture(source: CVPixelBuffer, device: any MTLDevice) throws -> any MTLTexture
}

/// Valid reversed-Z fallback used to bring up the feeder and reference-capture path.
/// It is intentionally not presented as estimated scene depth.
@MainActor
final class DLSS5FlatDepthProvider: DLSS5DepthProvider {
    let providerDescription = "constant reversed-Z reference depth"
    private let value: Float

    init(value: Float = 0.5) {
        self.value = min(0.999_999, max(1.0 / 65_504.0, value))
    }

    func makeDepthTexture(source: CVPixelBuffer, device: any MTLDevice) throws -> any MTLTexture {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let texture = try DLSS5TextureFactory.makeSharedTexture(
            device: device,
            pixelFormat: .r32Float,
            width: width,
            height: height,
            usage: [.shaderRead]
        )
        var row = Array(repeating: value, count: width)
        row.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            for y in 0..<height {
                texture.replace(
                    region: MTLRegionMake2D(0, y, width, 1),
                    mipmapLevel: 0,
                    withBytes: base,
                    bytesPerRow: width * MemoryLayout<Float>.stride
                )
            }
        }
        return texture
    }
}

enum DLSS5Jitter {
    static func halton(index: Int, base: Int) -> Float {
        guard index > 0, base > 1 else { return 0 }
        var value = index
        var fraction: Float = 1
        var result: Float = 0
        while value > 0 {
            fraction /= Float(base)
            result += fraction * Float(value % base)
            value /= base
        }
        return result
    }

    static func offset(frameIndex: Int) -> SIMD2<Float> {
        let index = max(0, frameIndex) + 1
        return SIMD2(
            halton(index: index, base: 2) - 0.5,
            halton(index: index, base: 3) - 0.5
        )
    }
}

@MainActor
enum DLSS5TextureFactory {
    static func makeSharedTexture(
        device: any MTLDevice,
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int,
        usage: MTLTextureUsage
    ) throws -> any MTLTexture {
        guard width > 0, height > 0 else { throw DLSS5ContractError.invalidDimensions }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw DLSS5ContractError.runtimeUnavailable(
                "Metal could not allocate a DLSS 5 feeder texture (\(pixelFormat.rawValue), \(width)x\(height))."
            )
        }
        return texture
    }
}

/// Converts decoded video into the resource formats and transfer characteristics
/// observed in current real DLSS Neural Rendering video hosts:
/// - RGBA16F color, display-referred for SDR / linear-light for HDR
/// - reversed-Z R32F depth
/// - current-to-previous RG16F pixel-space motion vectors
@MainActor
final class DLSS5FramePreparer {
    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let ciContext: CIContext
    private let depthProvider: any DLSS5DepthProvider
    private let motionProvider: any DLSS5MotionProvider

    init(
        depthProvider: any DLSS5DepthProvider = DLSS5FlatDepthProvider(),
        motionProvider: any DLSS5MotionProvider = DLSS5ZeroMotionProvider()
    ) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw DLSS5ContractError.runtimeUnavailable("Metal is unavailable for DLSS 5 feeder preparation.")
        }
        self.device = device
        self.commandQueue = commandQueue
        self.ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        self.depthProvider = depthProvider
        self.motionProvider = motionProvider
    }

    func prepareVideoFrame(
        source: CVPixelBuffer,
        previousSource: CVPixelBuffer? = nil,
        presentationTime: CMTime,
        frameIndex: Int,
        resetHistory: Bool = true,
        useJitter: Bool = false,
        colorEncoding: DLSS5ColorEncoding = .sRGBDisplayReferred
    ) throws -> DLSS5PreparedFrame {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard width >= 64, height >= 64 else { throw DLSS5ContractError.invalidDimensions }

        let color = try DLSS5TextureFactory.makeSharedTexture(
            device: device,
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            usage: [.shaderRead, .shaderWrite]
        )
        let image = CIImage(cvPixelBuffer: source)
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let outputColorSpace = Self.outputColorSpace(for: colorEncoding) else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The DLSS 5 input color conversion could not be initialized for \(colorEncoding.rawValue)."
            )
        }
        ciContext.render(
            image,
            to: color,
            commandBuffer: commandBuffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: outputColorSpace
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw DLSS5ContractError.runtimeUnavailable("DLSS 5 color preparation failed: \(error.localizedDescription)")
        }

        let depth = try depthProvider.makeDepthTexture(source: source, device: device)
        guard depth.pixelFormat == .r32Float,
              depth.width == width,
              depth.height == height else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The DLSS 5 depth provider returned a resource outside the R32F full-resolution contract."
            )
        }

        let motion = try motionProvider.makeMotionTexture(
            previous: previousSource,
            current: source,
            resetHistory: resetHistory,
            device: device
        )
        guard motion.pixelFormat == .rg16Float,
              motion.width == width,
              motion.height == height else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The DLSS 5 motion provider returned a resource outside the RG16F full-resolution contract."
            )
        }

        let jitter = useJitter ? DLSS5Jitter.offset(frameIndex: frameIndex) : .zero
        var contract = DLSS5FrameContract(
            presentationTime: presentationTime,
            renderWidth: width,
            renderHeight: height,
            outputWidth: width,
            outputHeight: height,
            resetHistory: resetHistory,
            colorEncoding: colorEncoding
        )
        contract.jitterX = jitter.x
        contract.jitterY = jitter.y
        try contract.validate()

        let metadata = DLSS5PreparedFrameMetadata(
            contract: contract,
            hasColor: true,
            hasDepth: true,
            hasMotionVectors: true,
            sourceDescription: "video frame; \(colorEncoding.rawValue); \(depthProvider.providerDescription); \(motionProvider.providerDescription)"
        )
        try metadata.validateForExecution()
        return DLSS5PreparedFrame(metadata: metadata, color: color, depth: depth, motion: motion)
    }

    private static func outputColorSpace(for encoding: DLSS5ColorEncoding) -> CGColorSpace? {
        switch encoding {
        case .sRGBDisplayReferred:
            return CGColorSpace(name: CGColorSpace.sRGB)
        case .linearHDR:
            return CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        }
    }
}

struct DLSS5ReferenceCaptureManifest: Codable, Sendable {
    var version = 2
    var metadata: DLSS5PreparedFrameMetadata
    var colorFile = "color.rgba16f"
    var depthFile = "depth.r32f"
    var motionFile = "motion.rg16f"
}

@MainActor
enum DLSS5ReferenceCaptureWriter {
    static func write(_ frame: DLSS5PreparedFrame, to folder: URL) throws -> URL {
        try frame.metadata.validateForExecution()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let width = frame.metadata.contract.renderWidth
        let height = frame.metadata.contract.renderHeight
        try textureData(frame.color, width: width, height: height, bytesPerPixel: 8)
            .write(to: folder.appendingPathComponent("color.rgba16f"), options: .atomic)
        try textureData(frame.depth, width: width, height: height, bytesPerPixel: 4)
            .write(to: folder.appendingPathComponent("depth.r32f"), options: .atomic)
        try textureData(frame.motion, width: width, height: height, bytesPerPixel: 4)
            .write(to: folder.appendingPathComponent("motion.rg16f"), options: .atomic)

        let manifestURL = folder.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(DLSS5ReferenceCaptureManifest(metadata: frame.metadata))
            .write(to: manifestURL, options: .atomic)
        return manifestURL
    }

    private static func textureData(
        _ texture: any MTLTexture,
        width: Int,
        height: Int,
        bytesPerPixel: Int
    ) throws -> Data {
        guard texture.storageMode == .shared else {
            throw DLSS5ContractError.runtimeUnavailable("Reference capture requires a CPU-readable shared Metal texture.")
        }
        let bytesPerRow = width * bytesPerPixel
        var data = Data(count: bytesPerRow * height)
        data.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        return data
    }
}
