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
            frameWidth: width,
            frameHeight: height,
            sourcePixelFormat: pixelFormat
        ) != nil
    }

    func start(width: Int, height: Int, pixelFormat: OSType, strength: Double) throws {
        guard VTTemporalNoiseFilterConfiguration.isSupported,
              let configuration = VTTemporalNoiseFilterConfiguration(
                frameWidth: width,
                frameHeight: height,
                sourcePixelFormat: pixelFormat
              ) else {
            throw AppleFrameProcessorError.processing(
                "Apple temporal denoise does not support this frame size or pixel format."
            )
        }
        let newProcessor = VTFrameProcessor()
        _ = try newProcessor.startSession(configuration: configuration)
        processor?.endSession()
        processor = newProcessor
        self.configuration = configuration
        self.strength = Float(max(0, min(1, strength)))
        previousFrames.removeAll(keepingCapacity: true)
    }

    func process(
        source: CVPixelBuffer,
        presentationTime: CMTime,
        hasDiscontinuity: Bool = false
    ) async throws -> CVPixelBuffer {
        guard let configuration else {
            throw AppleFrameProcessorError.processing("The temporal-denoise session is not active.")
        }
        guard CVPixelBufferGetWidth(source) == configuration.frameWidth,
              CVPixelBufferGetHeight(source) == configuration.frameHeight else {
            throw AppleFrameProcessorError.unsupportedConfiguration
        }

        if hasDiscontinuity {
            try restartSession(configuration: configuration)
            guard let sourceFrame = VTFrameProcessorFrame(
                buffer: source,
                presentationTimeStamp: presentationTime
            ) else {
                throw AppleFrameProcessorError.frameCreation
            }
            previousFrames = [sourceFrame]
            return source
        }

        guard let sourceFrame = VTFrameProcessorFrame(
            buffer: source,
            presentationTimeStamp: presentationTime
        ) else {
            throw AppleFrameProcessorError.frameCreation
        }

        // Apple requires at least one temporal reference. Preserve the first frame and
        // seed history so the second and subsequent frames can be filtered correctly.
        guard !previousFrames.isEmpty else {
            previousFrames = [sourceFrame]
            return source
        }

        do {
            return try await processFrame(
                sourceFrame: sourceFrame,
                sourcePixelFormat: CVPixelBufferGetPixelFormatType(source),
                presentationTime: presentationTime,
                configuration: configuration
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A frame-processor session can become invalid after a transient VideoToolbox
            // failure. Recreate it once and retry the current frame with reset history.
            try restartSession(configuration: configuration)
            previousFrames = [sourceFrame]
            return source
        }
    }

    private func processFrame(
        sourceFrame: VTFrameProcessorFrame,
        sourcePixelFormat: OSType,
        presentationTime: CMTime,
        configuration: VTTemporalNoiseFilterConfiguration
    ) async throws -> CVPixelBuffer {
        guard let processor else {
            throw AppleFrameProcessorError.processing("The temporal-denoise session is not active.")
        }
        let destination = try Self.makeDestinationBuffer(
            configuration: configuration,
            fallbackPixelFormat: sourcePixelFormat
        )
        let previousFrameLimit = max(1, configuration.previousFrameCount ?? 1)
        guard let destinationFrame = VTFrameProcessorFrame(
            buffer: destination,
            presentationTimeStamp: presentationTime
        ), let parameters = VTTemporalNoiseFilterParameters(
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
                    continuation.resume(
                        throwing: AppleFrameProcessorError.processing(error.localizedDescription)
                    )
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

    private func restartSession(configuration: VTTemporalNoiseFilterConfiguration) throws {
        processor?.endSession()
        let restarted = VTFrameProcessor()
        _ = try restarted.startSession(configuration: configuration)
        processor = restarted
        previousFrames.removeAll(keepingCapacity: true)
    }

    private static func makeDestinationBuffer(
        configuration: VTTemporalNoiseFilterConfiguration,
        fallbackPixelFormat: OSType
    ) throws -> CVPixelBuffer {
        let required = anyAttributes(configuration.destinationPixelBufferAttributes)
        let requiredFormats = pixelFormats(from: required)
        let pixelFormat = requiredFormats.first ?? fallbackPixelFormat
        let client: [String: Any] = [
            kCVPixelBufferWidthKey as String: configuration.frameWidth,
            kCVPixelBufferHeightKey as String: configuration.frameHeight,
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: pixelFormat),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
        ]

        var resolved: CFDictionary?
        let resolveStatus = CVPixelBufferCreateResolvedAttributesDictionary(
            kCFAllocatorDefault,
            [required as CFDictionary, client as CFDictionary] as CFArray,
            &resolved
        )
        guard resolveStatus == kCVReturnSuccess, let resolved else {
            throw AppleFrameProcessorError.pixelBufferAttributes(resolveStatus)
        }

        var destination: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            configuration.frameWidth,
            configuration.frameHeight,
            pixelFormat,
            resolved,
            &destination
        )
        guard status == kCVReturnSuccess, let destination else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        return destination
    }

    private static func anyAttributes(_ attributes: [String: any Sendable]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in attributes {
            result[key] = value
        }
        return result
    }

    private static func pixelFormats(from attributes: [String: Any]) -> [OSType] {
        let value = attributes[kCVPixelBufferPixelFormatTypeKey as String]
        if let values = value as? [NSNumber] {
            return values.map { $0.uint32Value }
        }
        if let value = value as? NSNumber {
            return [value.uint32Value]
        }
        if let values = value as? [OSType] {
            return values
        }
        return []
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
    func process(
        source: CVPixelBuffer,
        presentationTime: CMTime,
        hasDiscontinuity: Bool = false
    ) async throws -> CVPixelBuffer {
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
        parameters = SpatialNoiseParameters(strength: strength)
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
        let sourceImage = CIImage(cvPixelBuffer: source)
        filter.inputImage = sourceImage
        filter.noiseLevel = parameters.noiseLevel
        filter.sharpness = parameters.sharpness
        guard let filtered = filter.outputImage else {
            throw AppError.exportFailed("Core Image spatial denoise did not produce a frame.")
        }
        context.render(
            filtered,
            to: output,
            bounds: CGRect(
                x: 0,
                y: 0,
                width: CVPixelBufferGetWidth(source),
                height: CVPixelBufferGetHeight(source)
            ),
            colorSpace: sourceImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        )
        return output
    }
}
