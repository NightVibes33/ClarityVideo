import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox

#if !targetEnvironment(simulator)
@available(iOS 26.0, *)
@MainActor
final class TemporalNoiseFilterService {
    private var processor: VTFrameProcessor?
    private var configuration: VTTemporalNoiseFilterConfiguration?
    private var previousFrames: [VTFrameProcessorFrame] = []
    private var strength: Float = 0

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

        // Apple requires at least one past or future reference. Keep the first frame
        // unchanged and use it as the reference for the next frame.
        guard !previousFrames.isEmpty else {
            previousFrames = [sourceFrame]
            return source
        }

        var attributes = configuration.destinationPixelBufferAttributes
        attributes[kCVPixelBufferWidthKey as String] = configuration.frameWidth
        attributes[kCVPixelBufferHeightKey as String] = configuration.frameHeight
        attributes[kCVPixelBufferIOSurfacePropertiesKey as String] = [String: String]()
        var destination: CVPixelBuffer?
        let pixelFormat = CVPixelBufferGetPixelFormatType(source)
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, configuration.frameWidth, configuration.frameHeight,
            pixelFormat, attributes as CFDictionary, &destination
        )
        guard status == kCVReturnSuccess, let destination else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        guard let destinationFrame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: presentationTime),
              let parameters = VTTemporalNoiseFilterParameters(
                sourceFrame: sourceFrame,
                nextFrames: [],
                previousFrames: Array(previousFrames.suffix(configuration.previousFrameCount)),
                destinationFrame: destinationFrame,
                filterStrength: strength,
                hasDiscontinuity: hasDiscontinuity
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
        if hasDiscontinuity {
            previousFrames.removeAll(keepingCapacity: true)
        }
        previousFrames.append(sourceFrame)
        if previousFrames.count > configuration.previousFrameCount {
            previousFrames.removeFirst(previousFrames.count - configuration.previousFrameCount)
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
