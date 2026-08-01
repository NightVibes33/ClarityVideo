import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox
import CoreImage
import CoreGraphics
import CoreImage.CIFilterBuiltins

#if !targetEnvironment(simulator)
@available(iOS 26.0, *)
@MainActor
final class TemporalNoiseFilterService {
    private var processor: VTFrameProcessor?
    private var configuration: VTTemporalNoiseFilterConfiguration?
    private var previousFrames: [VTFrameProcessorFrame] = []
    private var strength: Float = 0
    static func supports(width: Int, height: Int, pixelFormat: OSType) -> Bool {
        guard VTTemporalNoiseFilterConfiguration.isSupported else { return false }
        return VTTemporalNoiseFilterConfiguration(
            frameWidth: width, frameHeight: height, sourcePixelFormat: pixelFormat
        ) != nil
    }

    func start(width: Int, height: Int, pixelFormat: OSType, strength: Double) throws {
        guard VTTemporalNoiseFilterConfiguration.isSupported,
              let configuration = VTTemporalNoiseFilterConfiguration(
                frameWidth: width,
                frameHeight: height,
                sourcePixelFormat: pixelFormat
              ) else {
            throw AppleFrameProcessorError.processing("Apple temporal denoise does not support this frame size or pixel format.")
        }
        let processor = VTFrameProcessor()
        _ = try processor.startSession(configuration: configuration)
        self.processor = processor
        self.configuration = configuration
        self.strength = Float(max(0, min(1, strength)))
        previousFrames.removeAll(keepingCapacity: true)
    }

    func process(source: CVPixelBuffer, presentationTime: CMTime, hasDiscontinuity: Bool = false) async throws -> CVPixelBuffer {
        guard let processor, let configuration else {
            throw AppleFrameProcessorError.processing("The temporal-denoise session is not active.")
        }
        guard let sourceFrame = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: presentationTime) else {
            throw AppleFrameProcessorError.frameCreation
        }
        if hasDiscontinuity {
            processor.endSession()
            let restarted = VTFrameProcessor()
            _ = try restarted.startSession(configuration: configuration)
            self.processor = restarted
            previousFrames = [sourceFrame]
            return source
        }

        // Apple requires at least one past or future reference. Keep the first frame
        // unchanged and use it as the reference for the next frame.
        guard !previousFrames.isEmpty else {
            previousFrames = [sourceFrame]
            return source
        }

        let destinationAttributes = configuration.destinationPixelBufferAttributes
        let formatValue = destinationAttributes[kCVPixelBufferPixelFormatTypeKey as String]
        let sourcePixelFormat = CVPixelBufferGetPixelFormatType(source)
        let pixelFormat: OSType
        if let formats = formatValue as? [NSNumber], let first = formats.first {
            pixelFormat = first.uint32Value
        } else if let format = formatValue as? NSNumber {
            pixelFormat = format.uint32Value
        } else {
            pixelFormat = sourcePixelFormat
        }
        var destination: CVPixelBuffer?
        let creationAttributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, configuration.frameWidth, configuration.frameHeight,
            pixelFormat, creationAttributes as CFDictionary, &destination
        )
        guard status == kCVReturnSuccess, let destination else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        let previousFrameLimit = max(1, configuration.previousFrameCount ?? 1)
        guard let destinationFrame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: presentationTime),
              let parameters = VTTemporalNoiseFilterParameters(
                sourceFrame: sourceFrame,
                nextFrames: [],
                previousFrames: Array(previousFrames.suffix(previousFrameLimit)),
                destinationFrame: destinationFrame,
                filterStrength: strength,
                hasDiscontinuity: false
              ) else {
            throw AppleFrameProcessorError.parameterCreation
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            processor.process(parameters: parameters) { _, error in
                if let error {
                    continuation.resume(throwing: AppleFrameProcessorError.processing(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
        previousFrames.append(sourceFrame)
        if previousFrames.count > previousFrameLimit {
            previousFrames.removeFirst(previousFrames.count - previousFrameLimit)
        }
        return destination
    }

    func endSession() {
        processor?.endSession()
        processor = nil
        configuration = nil
        previousFrames.removeAll()
    }

    func cancel() { endSession() }
}
#else
@available(iOS 26.0, *)
@MainActor
final class TemporalNoiseFilterService {
    static func supports(width: Int, height: Int, pixelFormat: OSType) -> Bool { false }
    func start(width: Int, height: Int, pixelFormat: OSType, strength: Double) throws {
        throw AppleFrameProcessorError.unavailable
    }
    func process(source: CVPixelBuffer, presentationTime: CMTime, hasDiscontinuity: Bool = false) async throws -> CVPixelBuffer {
        throw AppleFrameProcessorError.unavailable
    }
    func endSession() {}
    func cancel() {}
}
#endif

struct SpatialNoiseParameters: Equatable, Sendable {
    let noiseLevel: Float
    let sharpness: Float

    init(strength: Double) {
        let bounded = max(0, min(1, strength))
        noiseLevel = Float(0.005 + bounded * 0.045)
        sharpness = Float(0.60 - bounded * 0.20)
    }
}


@MainActor
final class SpatialNoiseFilterService {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let pool: CVPixelBufferPool
    private let parameters: SpatialNoiseParameters

    init(width: Int, height: Int, strength: Double) throws {
        self.parameters = SpatialNoiseParameters(strength: strength)
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
        ]
        var createdPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey as String: 1] as CFDictionary,
            attributes as CFDictionary,
            &createdPool
        )
        guard status == kCVReturnSuccess, let createdPool else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        pool = createdPool
    }

    func process(source: CVPixelBuffer) throws -> CVPixelBuffer {
        var output: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output)
        guard status == kCVReturnSuccess, let output else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        let filter = CIFilter.noiseReduction()
        filter.inputImage = CIImage(cvPixelBuffer: source)
        filter.noiseLevel = parameters.noiseLevel
        filter.sharpness = parameters.sharpness
        guard let filtered = filter.outputImage else {
            throw AppError.exportFailed("Core Image spatial denoise did not produce a frame.")
        }
        context.render(
            filtered, to: output,
            bounds: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source)),
            colorSpace: CIImage(cvPixelBuffer: source).colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        )
        return output
    }
}
