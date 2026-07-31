import Foundation
import CoreVideo
import CoreMedia
import VideoToolbox

enum AppleModelReadiness: String, Codable, Sendable {
    case unavailable
    case downloadRequired
    case downloading
    case ready
}

struct AppleSuperResolutionProbe: Sendable {
    var fullSupported: Bool
    var lowLatencySupported: Bool
    var temporalNoiseSupported: Bool
    var fullScaleFactors: [Int]
    var lowLatency720pScaleFactors: [Double]
    var supportedRevisions: [Int]
    var defaultRevision: Int?
    var modelReadiness: AppleModelReadiness
    var modelProgress: Double
    var error: String?
}

enum AppleFrameProcessorError: LocalizedError {
    case unavailable
    case unsupportedConfiguration
    case modelNotReady(AppleModelReadiness)
    case pixelBufferCreation(OSStatus)
    case frameCreation
    case parameterCreation
    case processing(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple super resolution is unavailable on this device."
        case .unsupportedConfiguration: "This frame size and AI scale are not supported by the device."
        case let .modelNotReady(state): "Apple's enhancement model is not ready (\(state.rawValue))."
        case let .pixelBufferCreation(status): "Could not allocate an AI output buffer (\(status))."
        case .frameCreation: "The frame is not IOSurface-backed and cannot be processed."
        case .parameterCreation: "The super-resolution frame parameters were rejected."
        case let .processing(message): message
        }
    }
}

#if !targetEnvironment(simulator)
@available(iOS 26.0, *)
final class AppleFrameProcessorService: @unchecked Sendable {
    private let lock = NSLock()
    private var activeProcessor: VTFrameProcessor?

    static func probe() -> AppleSuperResolutionProbe {
        let fullSupported = VTSuperResolutionScalerConfiguration.isSupported
        let lowSupported = VTLowLatencySuperResolutionScalerConfiguration.isSupported
        let noiseSupported = VTTemporalNoiseFilterConfiguration.isSupported
        let fullScales = VTSuperResolutionScalerConfiguration.supportedScaleFactors.map(\.intValue)
        let lowScales = VTLowLatencySuperResolutionScalerConfiguration
            .supportedScaleFactorsForFrameWidth(1280, frameHeight: 720)
            .map(\.doubleValue)
        let revisions = VTSuperResolutionScalerConfiguration.supportedRevisions.map { $0 }
        let defaultRevision = VTSuperResolutionScalerConfiguration.defaultRevision.rawValue

        var readiness: AppleModelReadiness = .unavailable
        var progress = 0.0
        var error: String?
        if fullSupported, let scale = fullScales.first,
           let configuration = VTSuperResolutionScalerConfiguration(
            frameWidth: 1280,
            frameHeight: 720,
            scaleFactor: scale,
            inputType: .video,
            usePrecomputedFlow: false,
            qualityPrioritization: .normal,
            revision: VTSuperResolutionScalerConfiguration.defaultRevision
           ) {
            readiness = readiness(for: configuration.configurationModelStatus)
            progress = Double(configuration.configurationModelPercentageAvailable)
        } else if fullSupported {
            error = "No supported full-quality configuration for the 720p diagnostic probe."
        }

        return AppleSuperResolutionProbe(
            fullSupported: fullSupported,
            lowLatencySupported: lowSupported,
            temporalNoiseSupported: noiseSupported,
            fullScaleFactors: fullScales,
            lowLatency720pScaleFactors: lowScales,
            supportedRevisions: revisions,
            defaultRevision: defaultRevision,
            modelReadiness: readiness,
            modelProgress: progress,
            error: error
        )
    }

    static func prepareModel(width: Int, height: Int, scaleFactor: Int) async throws -> Double {
        guard VTSuperResolutionScalerConfiguration.isSupported,
              let configuration = makeConfiguration(width: width, height: height, scaleFactor: scaleFactor)
        else { throw AppleFrameProcessorError.unsupportedConfiguration }
        let state = readiness(for: configuration.configurationModelStatus)
        if state == .ready { return 1 }
        if state == .downloading {
            while readiness(for: configuration.configurationModelStatus) == .downloading {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(300))
            }
            guard readiness(for: configuration.configurationModelStatus) == .ready else {
                throw AppleFrameProcessorError.modelNotReady(readiness(for: configuration.configurationModelStatus))
            }
            return 1
        }
        guard state == .downloadRequired else { throw AppleFrameProcessorError.modelNotReady(state) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            configuration.downloadConfigurationModel { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        guard readiness(for: configuration.configurationModelStatus) == .ready else {
            throw AppleFrameProcessorError.modelNotReady(readiness(for: configuration.configurationModelStatus))
        }
        return 1
    }

    func processFullQuality(
        source: CVPixelBuffer,
        presentationTime: CMTime,
        scaleFactor: Int,
        previousSource: CVPixelBuffer? = nil,
        previousOutput: CVPixelBuffer? = nil,
        sequential: Bool
    ) async throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard let configuration = Self.makeConfiguration(width: width, height: height, scaleFactor: scaleFactor)
        else { throw AppleFrameProcessorError.unsupportedConfiguration }
        let modelState = Self.readiness(for: configuration.configurationModelStatus)
        guard modelState == .ready else { throw AppleFrameProcessorError.modelNotReady(modelState) }

        let destination = try Self.makeDestinationBuffer(
            configuration: configuration,
            width: width * scaleFactor,
            height: height * scaleFactor
        )
        guard let sourceFrame = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: presentationTime),
              let destinationFrame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: presentationTime)
        else { throw AppleFrameProcessorError.frameCreation }
        let previousFrame = previousSource.flatMap {
            VTFrameProcessorFrame(buffer: $0, presentationTimeStamp: presentationTime)
        }
        let previousOutputFrame = previousOutput.flatMap {
            VTFrameProcessorFrame(buffer: $0, presentationTimeStamp: presentationTime)
        }
        guard let parameters = VTSuperResolutionScalerParameters(
            sourceFrame: sourceFrame,
            previousFrame: previousFrame,
            previousOutputFrame: previousOutputFrame,
            opticalFlow: nil,
            submissionMode: sequential ? .sequential : .random,
            destinationFrame: destinationFrame
        ) else { throw AppleFrameProcessorError.parameterCreation }

        let processor = VTFrameProcessor()
        lock.withLock { activeProcessor = processor }
        defer {
            processor.endSession()
            lock.withLock { activeProcessor = nil }
        }
        _ = try processor.startSession(configuration: configuration)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            processor.process(parameters: parameters) { _, error in
                if let error { continuation.resume(throwing: AppleFrameProcessorError.processing(error.localizedDescription)) }
                else { continuation.resume() }
            }
        }
        return destination
    }

    func cancel() {
        lock.withLock {
            activeProcessor?.endSession()
            activeProcessor = nil
        }
    }

    private static func makeConfiguration(width: Int, height: Int, scaleFactor: Int) -> VTSuperResolutionScalerConfiguration? {
        guard VTSuperResolutionScalerConfiguration.supportedScaleFactors.map(\.intValue).contains(scaleFactor) else {
            return nil
        }
        return VTSuperResolutionScalerConfiguration(
            frameWidth: width,
            frameHeight: height,
            scaleFactor: scaleFactor,
            inputType: .video,
            usePrecomputedFlow: false,
            qualityPrioritization: .normal,
            revision: VTSuperResolutionScalerConfiguration.defaultRevision
        )
    }

    private static func makeDestinationBuffer(
        configuration: VTSuperResolutionScalerConfiguration,
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
        var attributes = configuration.destinationPixelBufferAttributes
        attributes[kCVPixelBufferWidthKey as String] = width
        attributes[kCVPixelBufferHeightKey as String] = height
        attributes[kCVPixelBufferIOSurfacePropertiesKey as String] = [:]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attributes as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        return buffer
    }

    private static func readiness(for status: VTSuperResolutionScalerConfiguration.ModelStatus) -> AppleModelReadiness {
        switch status {
        case .downloadRequired: .downloadRequired
        case .downloading: .downloading
        case .ready: .ready
        @unknown default: .unavailable
        }
    }
}
#else
enum AppleFrameProcessorService {
    static func probe() -> AppleSuperResolutionProbe {
        AppleSuperResolutionProbe(
            fullSupported: false,
            lowLatencySupported: false,
            temporalNoiseSupported: false,
            fullScaleFactors: [],
            lowLatency720pScaleFactors: [],
            supportedRevisions: [],
            defaultRevision: nil,
            modelReadiness: .unavailable,
            modelProgress: 0,
            error: "Apple frame processors are unavailable in the simulator."
        )
    }
}
#endif
