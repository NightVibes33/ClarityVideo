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
    var lowLatency1080pScaleFactors: [Double]
    var supportedRevisions: [Int]
    var defaultRevision: Int?
    var sourcePixelFormats: [UInt32]
    var destinationPixelFormats: [UInt32]
    var maximumConfiguredInput: CGSize?
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
@MainActor final class AppleFrameProcessorService: @unchecked Sendable {
    private let lock = NSLock()
    private var activeProcessor: VTFrameProcessor?
    private var activeConfiguration: VTSuperResolutionScalerConfiguration?
    private var activeLowLatencyConfiguration: VTLowLatencySuperResolutionScalerConfiguration?
    private var previousSourceFrame: VTFrameProcessorFrame?
    private var previousOutputFrame: VTFrameProcessorFrame?

    static func probe() -> AppleSuperResolutionProbe {
        let fullSupported = VTSuperResolutionScalerConfiguration.isSupported
        let lowSupported = VTLowLatencySuperResolutionScalerConfiguration.isSupported
        let noiseSupported = VTTemporalNoiseFilterConfiguration.isSupported
        let fullScales = VTSuperResolutionScalerConfiguration.supportedScaleFactors
        let lowScales = VTLowLatencySuperResolutionScalerConfiguration
            .supportedScaleFactors(frameWidth: 1280, frameHeight: 720).map(Double.init)
        let low1080Scales = VTLowLatencySuperResolutionScalerConfiguration
            .supportedScaleFactors(frameWidth: 1920, frameHeight: 1080).map(Double.init)

        let revisions = VTSuperResolutionScalerConfiguration.supportedRevisions.map { $0 }
        let defaultRevision = VTSuperResolutionScalerConfiguration.defaultRevision.rawValue

        var modelReadiness: AppleModelReadiness = .unavailable
        var progress = 0.0
        var error: String?
        var sourcePixelFormats: [UInt32] = []
        var destinationPixelFormats: [UInt32] = []
        var maximumConfiguredInput: CGSize?
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
            modelReadiness = Self.readiness(for: configuration.configurationModelStatus)
            progress = Double(configuration.configurationModelPercentageAvailable)
            let sourceValue = configuration.sourcePixelBufferAttributes[kCVPixelBufferPixelFormatTypeKey as String]
            if let values = sourceValue as? [NSNumber] {
                sourcePixelFormats = values.map { $0.uint32Value }
            } else if let value = sourceValue as? NSNumber {
                sourcePixelFormats = [value.uint32Value]
            }
            let destinationValue = configuration.destinationPixelBufferAttributes[kCVPixelBufferPixelFormatTypeKey as String]
            if let values = destinationValue as? [NSNumber] {
                destinationPixelFormats = values.map { $0.uint32Value }
            } else if let value = destinationValue as? NSNumber {
                destinationPixelFormats = [value.uint32Value]
            }
        } else if fullSupported {
            error = "No supported full-quality configuration for the 720p diagnostic probe."
        }

        if fullSupported {
            let candidates = [CGSize(width: 640, height: 480), CGSize(width: 1280, height: 720), CGSize(width: 1440, height: 1080)]
            maximumConfiguredInput = candidates.last { size in
                fullScales.contains { scale in
                    VTSuperResolutionScalerConfiguration(
                        frameWidth: Int(size.width), frameHeight: Int(size.height), scaleFactor: scale,
                        inputType: .video, usePrecomputedFlow: false, qualityPrioritization: .normal,
                        revision: VTSuperResolutionScalerConfiguration.defaultRevision
                    ) != nil
                }
            }
        }

        return AppleSuperResolutionProbe(
            fullSupported: fullSupported,
            lowLatencySupported: lowSupported,
            temporalNoiseSupported: noiseSupported,
            fullScaleFactors: fullScales,
            lowLatency1080pScaleFactors: low1080Scales,
            lowLatency720pScaleFactors: lowScales,
            supportedRevisions: revisions,
            defaultRevision: defaultRevision,
            sourcePixelFormats: sourcePixelFormats,
            destinationPixelFormats: destinationPixelFormats,
            maximumConfiguredInput: maximumConfiguredInput,
            modelReadiness: modelReadiness,
            modelProgress: progress,
            error: error
        )
    }


    static func lowLatencyScaleFactors(width: Int, height: Int) -> [Double] {
        VTLowLatencySuperResolutionScalerConfiguration
            .supportedScaleFactors(frameWidth: width, frameHeight: height)
            .map(Double.init)
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

    func startLowLatencySession(width: Int, height: Int, scaleFactor: Float) throws {
        guard VTLowLatencySuperResolutionScalerConfiguration.isSupported,
              Self.lowLatencyScaleFactors(width: width, height: height).contains(Double(scaleFactor)) else {
            throw AppleFrameProcessorError.unsupportedConfiguration
        }
        let configuration = VTLowLatencySuperResolutionScalerConfiguration(
            frameWidth: width, frameHeight: height, scaleFactor: scaleFactor
        )
        let processor = VTFrameProcessor()
        _ = try processor.startSession(configuration: configuration)
        lock.withLock {
            activeProcessor?.endSession()
            activeProcessor = processor
            activeConfiguration = nil
            activeLowLatencyConfiguration = configuration
            previousSourceFrame = nil
            previousOutputFrame = nil
        }
    }

    func processInActiveLowLatencySession(source: CVPixelBuffer, presentationTime: CMTime) async throws -> CVPixelBuffer {
        let state = lock.withLock { (activeProcessor, activeLowLatencyConfiguration) }
        guard let processor = state.0, let configuration = state.1 else {
            throw AppleFrameProcessorError.processing("The Apple low-latency SR session is not active.")
        }
        let width = Int(Float(configuration.frameWidth) * configuration.scaleFactor)
        let height = Int(Float(configuration.frameHeight) * configuration.scaleFactor)
        var attributes = configuration.destinationPixelBufferAttributes
        attributes[kCVPixelBufferWidthKey as String] = width
        attributes[kCVPixelBufferHeightKey as String] = height
        attributes[kCVPixelBufferIOSurfacePropertiesKey as String] = [String: String]()
        var destination: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes as CFDictionary, &destination)
        guard status == kCVReturnSuccess, let destination else { throw AppleFrameProcessorError.pixelBufferCreation(status) }
        guard let sourceFrame = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: presentationTime),
              let destinationFrame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: presentationTime) else {
            throw AppleFrameProcessorError.frameCreation
        }
        let parameters = VTLowLatencySuperResolutionScalerParameters(sourceFrame: sourceFrame, destinationFrame: destinationFrame)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            processor.process(parameters: parameters) { _, error in
                if let error { continuation.resume(throwing: AppleFrameProcessorError.processing(error.localizedDescription)) }
                else { continuation.resume() }
            }
        }
        return destination
    }


    func startFullQualitySession(width: Int, height: Int, scaleFactor: Int) throws {
        guard let configuration = Self.makeConfiguration(width: width, height: height, scaleFactor: scaleFactor) else {
            throw AppleFrameProcessorError.unsupportedConfiguration
        }
        let modelState = Self.readiness(for: configuration.configurationModelStatus)
        guard modelState == .ready else { throw AppleFrameProcessorError.modelNotReady(modelState) }
        let processor = VTFrameProcessor()
        _ = try processor.startSession(configuration: configuration)
        lock.withLock {
            activeProcessor?.endSession()
            activeProcessor = processor
            activeConfiguration = configuration
            activeLowLatencyConfiguration = nil
            previousSourceFrame = nil
            previousOutputFrame = nil
        }
    }

    func processInActiveSession(source: CVPixelBuffer, presentationTime: CMTime, sequential: Bool) async throws -> CVPixelBuffer {
        let state = lock.withLock { (activeProcessor, activeConfiguration, previousSourceFrame, previousOutputFrame) }
        guard let processor = state.0, let configuration = state.1 else {
            throw AppleFrameProcessorError.processing("The Apple SR session is not active.")
        }
        let destination = try Self.makeDestinationBuffer(
            configuration: configuration,
            width: configuration.frameWidth * configuration.scaleFactor,
            height: configuration.frameHeight * configuration.scaleFactor
        )
        guard let sourceFrame = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: presentationTime),
              let destinationFrame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: presentationTime),
              let parameters = VTSuperResolutionScalerParameters(
                sourceFrame: sourceFrame,
                previousFrame: state.2,
                previousOutputFrame: state.3,
                opticalFlow: nil,
                submissionMode: sequential ? .sequential : .random,
                destinationFrame: destinationFrame
              ) else { throw AppleFrameProcessorError.parameterCreation }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            processor.process(parameters: parameters) { _, error in
                if let error { continuation.resume(throwing: AppleFrameProcessorError.processing(error.localizedDescription)) }
                else { continuation.resume() }
            }
        }
        lock.withLock {
            previousSourceFrame = sourceFrame
            previousOutputFrame = destinationFrame
        }
        return destination
    }

    func resetTemporalHistory() {
        lock.withLock {
            previousSourceFrame = nil
            previousOutputFrame = nil
        }
    }

    func endSession() {
        lock.withLock {
            activeProcessor?.endSession()
            activeProcessor = nil
            activeConfiguration = nil
            activeLowLatencyConfiguration = nil
            previousSourceFrame = nil
            previousOutputFrame = nil
        }
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
        guard VTSuperResolutionScalerConfiguration.supportedScaleFactors.contains(scaleFactor) else {
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
        attributes[kCVPixelBufferIOSurfacePropertiesKey as String] = [String: String]()
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
@available(iOS 26.0, *)
@MainActor final class AppleFrameProcessorService: @unchecked Sendable {
    static func probe() -> AppleSuperResolutionProbe {
        AppleSuperResolutionProbe(
            fullSupported: false,
            lowLatencySupported: false,
            temporalNoiseSupported: false,
            fullScaleFactors: [],
            lowLatency720pScaleFactors: [],
            lowLatency1080pScaleFactors: [],
            supportedRevisions: [],
            defaultRevision: nil,
            sourcePixelFormats: [],
            destinationPixelFormats: [],
            maximumConfiguredInput: nil,
            modelReadiness: .unavailable,
            modelProgress: 0,
            error: "Apple frame processors are unavailable in the simulator."
        )
    }

    func startFullQualitySession(width: Int, height: Int, scaleFactor: Int) throws { throw AppleFrameProcessorError.unavailable }
    func processInActiveSession(source: CVPixelBuffer, presentationTime: CMTime, sequential: Bool) async throws -> CVPixelBuffer { throw AppleFrameProcessorError.unavailable }

    func resetTemporalHistory() {}
    func endSession() {}



    static func lowLatencyScaleFactors(width: Int, height: Int) -> [Double] { [] }
    func startLowLatencySession(width: Int, height: Int, scaleFactor: Float) throws { throw AppleFrameProcessorError.unavailable }
    func processInActiveLowLatencySession(source: CVPixelBuffer, presentationTime: CMTime) async throws -> CVPixelBuffer { throw AppleFrameProcessorError.unavailable }

    static func prepareModel(width: Int, height: Int, scaleFactor: Int) async throws -> Double {
        throw AppleFrameProcessorError.unavailable
    }


    func processFullQuality(
        source: CVPixelBuffer,
        presentationTime: CMTime,
        scaleFactor: Int,
        previousSource: CVPixelBuffer? = nil,
        previousOutput: CVPixelBuffer? = nil,
        sequential: Bool
    ) async throws -> CVPixelBuffer {
        throw AppleFrameProcessorError.unavailable
    }

    func cancel() {}
}
#endif
