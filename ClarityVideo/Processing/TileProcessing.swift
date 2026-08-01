import Foundation
import CoreGraphics
import CoreVideo
import CoreMedia
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

struct TileRegion: Codable, Equatable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var touchesLeft: Bool
    var touchesRight: Bool
    var touchesTop: Bool
    var touchesBottom: Bool
}

enum TileLayout {
    static func regions(frameWidth: Int, frameHeight: Int, tileWidth: Int, tileHeight: Int, overlap: Int) -> [TileRegion] {
        precondition(frameWidth > 0 && frameHeight > 0 && tileWidth > overlap && tileHeight > overlap)
        let width = min(frameWidth, tileWidth)
        let height = min(frameHeight, tileHeight)
        let xs = positions(length: frameWidth, tile: width, overlap: min(overlap, width - 1))
        let ys = positions(length: frameHeight, tile: height, overlap: min(overlap, height - 1))
        return ys.flatMap { y in
            xs.map { x in
                TileRegion(
                    x: x, y: y, width: width, height: height,
                    touchesLeft: x == 0,
                    touchesRight: x + width >= frameWidth,
                    touchesTop: y == 0,
                    touchesBottom: y + height >= frameHeight
                )
            }
        }
    }

    private static func positions(length: Int, tile: Int, overlap: Int) -> [Int] {
        guard length > tile else { return [0] }
        let stride = tile - overlap
        var result = [0]
        while let last = result.last, last + tile < length {
            let next = min(last + stride, length - tile)
            if next == last { break }
            result.append(next)
        }
        return result
    }
}

enum TileProcessingError: LocalizedError {
    case metalUnavailable
    case kernelUnavailable
    case textureCreation
    case commandEncoding
    case unsupportedPixelFormat
    var errorDescription: String? {
        switch self {
        case .metalUnavailable: "Metal is unavailable for tiled reconstruction."
        case .kernelUnavailable: "The tiled overlap-blending kernel is unavailable."
        case .textureCreation: "A tiled Metal texture could not be created."
        case .commandEncoding: "The tiled Metal command could not be encoded."
        case .unsupportedPixelFormat: "Apple SR rejected the BGRA tile format required for reconstruction."
        }
    }
}

@MainActor
final class MetalTileAssembler {
    private struct Uniforms {
        var originX: UInt32
        var originY: UInt32
        var overlapX: UInt32
        var overlapY: UInt32
        var leftBoundary: UInt32
        var rightBoundary: UInt32
        var topBoundary: UInt32
        var bottomBoundary: UInt32
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private var textureCache: CVMetalTextureCache?

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw TileProcessingError.metalUnavailable
        }
        guard let function = device.makeDefaultLibrary()?.makeFunction(name: "blendOverlappingTile") else {
            throw TileProcessingError.kernelUnavailable
        }
        self.device = device
        self.queue = queue
        self.pipeline = try device.makeComputePipelineState(function: function)
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    func makeCanvas(width: Int, height: Int) throws -> CVPixelBuffer {
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0, CVPixelBufferGetBytesPerRow(buffer) * height)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    func blend(tile: CVPixelBuffer, into canvas: CVPixelBuffer, region: TileRegion, scale: Int, overlap: Int) throws {
        guard CVPixelBufferGetPixelFormatType(tile) == kCVPixelFormatType_32BGRA,
              CVPixelBufferGetPixelFormatType(canvas) == kCVPixelFormatType_32BGRA else {
            throw TileProcessingError.unsupportedPixelFormat
        }
        let tileTexture = try texture(for: tile)
        let canvasTexture = try texture(for: canvas)
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            throw TileProcessingError.commandEncoding
        }
        var uniforms = Uniforms(
            originX: UInt32(region.x * scale),
            originY: UInt32(region.y * scale),
            overlapX: UInt32(overlap * scale),
            overlapY: UInt32(overlap * scale),
            leftBoundary: region.touchesLeft ? 1 : 0,
            rightBoundary: region.touchesRight ? 1 : 0,
            topBoundary: region.touchesTop ? 1 : 0,
            bottomBoundary: region.touchesBottom ? 1 : 0
        )
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(tileTexture, index: 0)
        encoder.setTexture(canvasTexture, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        let width = pipeline.threadExecutionWidth
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        encoder.dispatchThreads(
            MTLSize(width: tileTexture.width, height: tileTexture.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
        )
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
    }

    private func texture(for buffer: CVPixelBuffer) throws -> MTLTexture {
        guard let textureCache else { throw TileProcessingError.textureCreation }
        var image: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, buffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &image
        )
        guard status == kCVReturnSuccess, let image, let texture = CVMetalTextureGetTexture(image) else {
            throw TileProcessingError.textureCreation
        }
        return texture
    }
}

@MainActor
final class TiledAppleSRProcessor {
    private let sourceWidth: Int
    private let sourceHeight: Int
    private let tileWidth: Int
    private let tileHeight: Int
    private let overlap: Int
    private let scale: Int
    private let regions: [TileRegion]
    private let frameProcessor = AppleFrameProcessorService()
    private let assembler: MetalTileAssembler
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let sourceTilePool: CVPixelBufferPool
    private let blendTilePool: CVPixelBufferPool

    init(sourceWidth: Int, sourceHeight: Int, tileWidth: Int, tileHeight: Int, overlap: Int, scale: Int) throws {
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.tileWidth = min(sourceWidth, tileWidth)
        self.tileHeight = min(sourceHeight, tileHeight)
        self.overlap = overlap
        self.scale = scale
        self.regions = TileLayout.regions(
            frameWidth: sourceWidth, frameHeight: sourceHeight,
            tileWidth: tileWidth, tileHeight: tileHeight, overlap: overlap
        )
        let sourcePixelFormat = AppleFrameProcessorService.preferredFullQualitySourcePixelFormat(width: self.tileWidth, height: self.tileHeight, scaleFactor: scale)
        self.sourceTilePool = try Self.makePool(width: self.tileWidth, height: self.tileHeight, pixelFormat: sourcePixelFormat)
        self.blendTilePool = try Self.makePool(width: self.tileWidth * scale, height: self.tileHeight * scale, pixelFormat: kCVPixelFormatType_32BGRA)
        self.assembler = try MetalTileAssembler()
    }

    func prepare() async throws {
        _ = try await AppleFrameProcessorService.prepareModel(
            width: tileWidth, height: tileHeight, scaleFactor: scale
        )
        try frameProcessor.startFullQualitySession(
            width: tileWidth, height: tileHeight, scaleFactor: scale
        )
    }

    func process(frame: CVPixelBuffer, presentationTime: CMTime, canvas suppliedCanvas: CVPixelBuffer? = nil, detailRecovery: Double = 0, sharpening: Double = 0) async throws -> CVPixelBuffer {
        let canvas: CVPixelBuffer
        if let suppliedCanvas {
            guard CVPixelBufferGetWidth(suppliedCanvas) == sourceWidth * scale,
                  CVPixelBufferGetHeight(suppliedCanvas) == sourceHeight * scale,
                  CVPixelBufferGetPixelFormatType(suppliedCanvas) == kCVPixelFormatType_32BGRA else {
                throw TileProcessingError.unsupportedPixelFormat
            }
            canvas = suppliedCanvas
            CVPixelBufferLockBaseAddress(canvas, [])
            if let base = CVPixelBufferGetBaseAddress(canvas) {
                memset(base, 0, CVPixelBufferGetBytesPerRow(canvas) * CVPixelBufferGetHeight(canvas))
            }
            CVPixelBufferUnlockBaseAddress(canvas, [])
        } else {
            canvas = try assembler.makeCanvas(width: sourceWidth * scale, height: sourceHeight * scale)
        }
        for region in regions {
            try Task.checkCancellation()
            let tile = try makeSourceTile(from: frame, region: region)
            let enhanced = try await frameProcessor.processInActiveSession(
                source: tile, presentationTime: presentationTime, sequential: false
            )
            let blendable = try makeBlendableTile(from: enhanced, detailRecovery: detailRecovery, sharpening: sharpening)
            try assembler.blend(tile: blendable, into: canvas, region: region, scale: scale, overlap: overlap)
        }
        return canvas
    }

    func cancel() { frameProcessor.cancel() }
    func endSession() { frameProcessor.endSession() }

    private static func makePool(width: Int, height: Int, pixelFormat: OSType) throws -> CVPixelBufferPool {
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault, [kCVPixelBufferPoolMinimumBufferCountKey as String: 1] as CFDictionary,
            attributes as CFDictionary, &pool
        )
        guard status == kCVReturnSuccess, let pool else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        return pool
    }

    private func makeBlendableTile(from source: CVPixelBuffer, detailRecovery: Double, sharpening: Double) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        var output: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, blendTilePool, &output)
        guard status == kCVReturnSuccess, let output else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        var processed = CIImage(cvPixelBuffer: source)
        if detailRecovery > 0 {
            let filter = CIFilter.unsharpMask()
            filter.inputImage = processed
            filter.radius = 1.5
            filter.intensity = Float(detailRecovery * 0.55)
            if let filtered = filter.outputImage { processed = filtered }
        }
        if sharpening > 0 {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = processed
            filter.sharpness = Float(sharpening * 0.8)
            if let filtered = filter.outputImage { processed = filtered }
        }
        ciContext.render(
            processed, to: output,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return output
    }

    private func makeSourceTile(from source: CVPixelBuffer, region: TileRegion) throws -> CVPixelBuffer {
        var tile: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, sourceTilePool, &tile)
        guard status == kCVReturnSuccess, let tile else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        let sourceImage = CIImage(cvPixelBuffer: source)
        let sourceY = sourceHeight - region.y - region.height
        let crop = sourceImage
            .cropped(to: CGRect(x: region.x, y: sourceY, width: region.width, height: region.height))
            .transformed(by: CGAffineTransform(translationX: -CGFloat(region.x), y: -CGFloat(sourceY)))
            .clampedToExtent()
            .cropped(to: CGRect(x: 0, y: 0, width: tileWidth, height: tileHeight))
        ciContext.render(crop, to: tile, bounds: CGRect(x: 0, y: 0, width: tileWidth, height: tileHeight), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return tile
    }
}
