import Foundation
import CoreVideo
import CoreMedia
import CoreImage
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
    case modelDownloadTimedOut
    case pixelBufferCreation(OSStatus)
    case pixelBufferAttributes(OSStatus)
    case frameCreation
    case parameterCreation
    case processing(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple super resolution is unavailable on this device."
        case .unsupportedConfiguration:
            "This frame size and AI scale are not supported by the device."
        case let .modelNotReady(state):
            "Apple's enhancement model is not ready (\(state.rawValue))."
        case .modelDownloadTimedOut:
            "Apple's enhancement model did not become ready before the download timeout."
        case let .pixelBufferCreation(status):
            status == kCVReturnInvalidArgument
                ? "Apple rejected incompatible AI pixel-buffer attributes (\(status))."
                : "Could not allocate an AI pixel buffer (\(status))."
        case let .pixelBufferAttributes(status):
            "Apple's frame-processor pixel-buffer requirements could not be resolved (\(status))."
        case .frameCreation:
            "A frame could not be wrapped for Apple frame processing."
        case .parameterCreation:
            "The super-resolution frame parameters were rejected."
        case let .processing(message):
            message
        }
    }
}

#if !targetEnvironment(simulator)
@available(iOS 26.0, *)
@MainActor
final class AppleFrameProcessorService: @unchecked Sendable {
    private let lock = NSLock()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
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
            .supportedScaleFactors(frameWidth: 1280, frameHeight: 720)
            .map(Double.init)
        let low1080Scales = VTLowLatencySuperResolutionScalerConfiguration
            .supportedScaleFactors(frameWidth: 1920, frameHeight: 1080)
            .map(Double.init)
        let revisions = VTSuperResolutionScalerConfiguration.supportedRevisions.map { $0 }
        let defaultRevision = VTSuperResolutionScalerConfiguration.defaultRevision.rawValue

        var modelReadiness: AppleModelReadiness = .unavailable
        var progress = 0.0
        var error: String?
        var sourcePixelFormats: [UInt32] = []
        var destinationPixelFormats: [UInt32] = []
        var maximumConfiguredInput: CGSize?

        if fullSupported, let scale = fullScales.first,
           let configuration = makeConfiguration(width: 1280, height: 720, scaleFactor: scale) {
            modelReadiness = readiness(for: configuration.configurationModelStatus)
            progress = Double(configuration.configurationModelPercentageAvailable)
            sourcePixelFormats = configuration.supportedPixelFormats.map { UInt32($0) }
            destinationPixelFormats = pixelFormats(from: configuration.destinationPixelBufferAttributes)
        } else if fullSupported {
            error = "No supported full-quality configuration for the 720p diagnostic probe."
        }

        if fullSupported {
            let candidates = [
                CGSize(width: 640, height: 480),
                CGSize(width: 1280, height: 720),
                CGSize(width: 1440, height: 1080)
            ]
            maximumConfiguredInput = candidates.last { size in
                fullScales.contains { scale in
                    makeConfiguration(
                        width: Int(size.width),
                        height: Int(size.height),
                        scaleFactor: scale
                    ) != nil
                }
            }
        }

        return AppleSuperResolutionProbe(
            fullSupported: fullSupported,
            lowLatencySupported: lowSupported,
            temporalNoiseSupported: noiseSupported,
            fullScaleFactors: fullScales,
            lowLatency720pScaleFactors: lowScales,
            lowLatency1080pScaleFactors: low1080Scales,
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

    static func preferredFullQualitySourcePixelFormat(width: Int, height: Int, scaleFactor: Int) -> OSType {
        guard let configuration = makeConfiguration(width: width, height: height, scaleFactor: scaleFactor) else {
            return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
        return configuration.supportedPixelFormats.first
            ?? pixelFormats(from: configuration.sourcePixelBufferAttributes).first
            ?? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    static func lowLatencyScaleFactors(width: Int, height: Int) -> [Double] {
        VTLowLatencySuperResolutionScalerConfiguration
            .supportedScaleFactors(frameWidth: width, frameHeight: height)
            .map(Double.init)
    }

    static func prepareModel(width: Int, height: Int, scaleFactor: Int) async throws -> Double {
        guard VTSuperResolutionScalerConfiguration.isSupported,
              let configuration = makeConfiguration(width: width, height: height, scaleFactor: scaleFactor)
        else {
            throw AppleFrameProcessorError.unsupportedConfiguration
        }

        var state = readiness(for: configuration.configurationModelStatus)
        if state == .ready { return 1 }

        if state == .downloadRequired {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                configuration.downloadConfigurationModel { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }

        let started = Date()
        while true {
            try Task.checkCancellation()
            state = readiness(for: configuration.configurationModelStatus)
            switch state {
            case .ready:
                return 1
            case .downloading, .downloadRequired:
                if Date().timeIntervalSince(started) > 180 {
                    throw AppleFrameProcessorError.modelDownloadTimedOut
                }
                try await Task.sleep(for: .milliseconds(300))
            case .unavailable:
                throw AppleFrameProcessorError.modelNotReady(.unavailable)
            }
        }
    }

    func startLowLatencySession(width: Int, height: Int, scaleFactor: Float) throws {
        guard VTLowLatencySuperResolutionScalerConfiguration.isSupported,
              Self.lowLatencyScaleFactors(width: width, height: height).contains(Double(scaleFactor))
        else {
            throw AppleFrameProcessorError.unsupportedConfiguration
        }
        let configuration = VTLowLatencySuperResolutionScalerConfiguration(
            frameWidth: width,
            frameHeight: height,
            scaleFactor: scaleFactor
        )
        let processor = VTFrameProcessor()
        _ = try processor.startSession(configuration: configuration)
        let oldProcessor = lock.withLock { () -> VTFrameProcessor? in
            let old = activeProcessor
            activeProcessor = processor
            activeConfiguration = nil
            activeLowLatencyConfiguration = configuration
            previousSourceFrame = nil
            previousOutputFrame = nil
            return old
        }
        oldProcessor?.endSession()
    }

    func processInActiveLowLatencySession(
        source: CVPixelBuffer,
        presentationTime: CMTime
    ) async throws -> CVPixelBuffer {
        let state = lock.withLock { (activeProcessor, activeLowLatencyConfiguration) }
        guard let processor = state.0, let configuration = state.1 else {
            throw AppleFrameProcessorError.processing("The Apple low-latency SR session is not active.")
        }
        let compatibleSource = try compatibleSourceBuffer(source, configuration: configuration)

        do {
            return try await processLowLatencyFrame(
                processor: processor,
                configuration: configuration,
                source: compatibleSource,
                presentationTime: presentationTime
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let retryProcessor = VTFrameProcessor()
            _ = try retryProcessor.startSession(configuration: configuration)
            let oldProcessor = lock.withLock { () -> VTFrameProcessor? in
                let old = activeProcessor
                activeProcessor = retryProcessor
                activeLowLatencyConfiguration = configuration
                return old
            }
            oldProcessor?.endSession()
            return try await processLowLatencyFrame(
                processor: retryProcessor,
                configuration: configuration,
                source: compatibleSource,
                presentationTime: presentationTime
            )
        }
    }

    func startFullQualitySession(width: Int, height: Int, scaleFactor: Int) throws {
        guard let configuration = Self.makeConfiguration(width: width, height: height, scaleFactor: scaleFactor) else {
            throw AppleFrameProcessorError.unsupportedConfiguration
        }
        let modelState = Self.readiness(for: configuration.configurationModelStatus)
        guard modelState == .ready else {
            throw AppleFrameProcessorError.modelNotReady(modelState)
        }
        let processor = VTFrameProcessor()
        _ = try processor.startSession(configuration: configuration)
        let oldProcessor = lock.withLock { () -> VTFrameProcessor? in
            let old = activeProcessor
            activeProcessor = processor
            activeConfiguration = configuration
            activeLowLatencyConfiguration = nil
            previousSourceFrame = nil
            previousOutputFrame = nil
            return old
        }
        oldProcessor?.endSession()
    }

    func processInActiveSession(
        source: CVPixelBuffer,
        presentationTime: CMTime,
        sequential: Bool
    ) async throws -> CVPixelBuffer {
        let state = lock.withLock {
            (activeProcessor, activeConfiguration, previousSourceFrame, previousOutputFrame)
        }
        guard let processor = state.0, let configuration = state.1 else {
            throw AppleFrameProcessorError.processing("The Apple SR session is not active.")
        }

        let compatibleSource = try compatibleSourceBuffer(source, configuration: configuration)
        do {
            let processed = try await processFullFrame(
                processor: processor,
                configuration: configuration,
                source: compatibleSource,
                presentationTime: presentationTime,
                previousSource: sequential ? state.2 : nil,
                previousOutput: sequential ? state.3 : nil,
                sequential: sequential
            )
            lock.withLock {
                previousSourceFrame = processed.sourceFrame
                previousOutputFrame = processed.destinationFrame
            }
            return processed.buffer
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A single frame-processor failure should not permanently disable Apple SR.
            // Recreate the session once and resubmit the current frame as a history reset.
            let retryProcessor = VTFrameProcessor()
            _ = try retryProcessor.startSession(configuration: configuration)
            let oldProcessor = lock.withLock { () -> VTFrameProcessor? in
                let old = activeProcessor
                activeProcessor = retryProcessor
                activeConfiguration = configuration
                previousSourceFrame = nil
                previousOutputFrame = nil
                return old
            }
            oldProcessor?.endSession()
            let processed = try await processFullFrame(
                processor: retryProcessor,
                configuration: configuration,
                source: compatibleSource,
                presentationTime: presentationTime,
                previousSource: nil,
                previousOutput: nil,
                sequential: false
            )
            lock.withLock {
                previousSourceFrame = processed.sourceFrame
                previousOutputFrame = processed.destinationFrame
            }
            return processed.buffer
        }
    }

    func resetTemporalHistory() {
        lock.withLock {
            previousSourceFrame = nil
            previousOutputFrame = nil
        }
    }

    func endSession() {
        let processor = lock.withLock { () -> VTFrameProcessor? in
            let current = activeProcessor
            activeProcessor = nil
            activeConfiguration = nil
            activeLowLatencyConfiguration = nil
            previousSourceFrame = nil
            previousOutputFrame = nil
            return current
        }
        processor?.endSession()
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
        guard let configuration = Self.makeConfiguration(width: width, height: height, scaleFactor: scaleFactor) else {
            throw AppleFrameProcessorError.unsupportedConfiguration
        }
        let modelState = Self.readiness(for: configuration.configurationModelStatus)
        guard modelState == .ready else {
            throw AppleFrameProcessorError.modelNotReady(modelState)
        }

        let compatibleSource = try compatibleSourceBuffer(source, configuration: configuration)
        let compatiblePrevious = try previousSource.map { try compatibleSourceBuffer($0, configuration: configuration) }
        let compatiblePreviousOutput = previousOutput

        let previousFrame = compatiblePrevious.flatMap {
            VTFrameProcessorFrame(buffer: $0, presentationTimeStamp: presentationTime)
        }
        let previousOutputFrame = compatiblePreviousOutput.flatMap {
            VTFrameProcessorFrame(buffer: $0, presentationTimeStamp: presentationTime)
        }
        let processor = VTFrameProcessor()
        _ = try processor.startSession(configuration: configuration)
        lock.withLock { activeProcessor = processor }
        defer {
            processor.endSession()
            lock.withLock {
                if activeProcessor === processor { activeProcessor = nil }
            }
        }
        let processed = try await processFullFrame(
            processor: processor,
            configuration: configuration,
            source: compatibleSource,
            presentationTime: presentationTime,
            previousSource: previousFrame,
            previousOutput: previousOutputFrame,
            sequential: sequential
        )
        return processed.buffer
    }

    func cancel() {
        endSession()
    }

    private func processLowLatencyFrame(
        processor: VTFrameProcessor,
        configuration: VTLowLatencySuperResolutionScalerConfiguration,
        source: CVPixelBuffer,
        presentationTime: CMTime
    ) async throws -> CVPixelBuffer {
        let width = Int(Float(configuration.frameWidth) * configuration.scaleFactor)
        let height = Int(Float(configuration.frameHeight) * configuration.scaleFactor)
        let destination = try Self.makePixelBuffer(
            required: configuration.destinationPixelBufferAttributes,
            width: width,
            height: height,
            supportedPixelFormats: configuration.supportedPixelFormats
        )
        guard let sourceFrame = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: presentationTime),
              let destinationFrame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: presentationTime)
        else {
            throw AppleFrameProcessorError.frameCreation
        }
        let parameters = VTLowLatencySuperResolutionScalerParameters(
            sourceFrame: sourceFrame,
            destinationFrame: destinationFrame
        )
        try await Self.process(processor: processor, parameters: parameters)
        return destination
    }

    private func processFullFrame(
        processor: VTFrameProcessor,
        configuration: VTSuperResolutionScalerConfiguration,
        source: CVPixelBuffer,
        presentationTime: CMTime,
        previousSource: VTFrameProcessorFrame?,
        previousOutput: VTFrameProcessorFrame?,
        sequential: Bool
    ) async throws -> (buffer: CVPixelBuffer, sourceFrame: VTFrameProcessorFrame, destinationFrame: VTFrameProcessorFrame) {
        let destination = try Self.makePixelBuffer(
            required: configuration.destinationPixelBufferAttributes,
            width: configuration.frameWidth * configuration.scaleFactor,
            height: configuration.frameHeight * configuration.scaleFactor,
            supportedPixelFormats: Self.pixelFormats(from: configuration.destinationPixelBufferAttributes)
        )
        guard let sourceFrame = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: presentationTime),
              let destinationFrame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: presentationTime)
        else {
            throw AppleFrameProcessorError.frameCreation
        }
        guard let parameters = VTSuperResolutionScalerParameters(
            sourceFrame: sourceFrame,
            previousFrame: previousSource,
            previousOutputFrame: previousOutput,
            opticalFlow: nil,
            submissionMode: sequential ? .sequential : .random,
            destinationFrame: destinationFrame
        ) else {
            throw AppleFrameProcessorError.parameterCreation
        }
        try await Self.process(processor: processor, parameters: parameters)
        return (destination, sourceFrame, destinationFrame)
    }

    private static func process(
        processor: VTFrameProcessor,
        parameters: any VTFrameProcessorParameters
    ) async throws {
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
    }

    private func compatibleSourceBuffer(
        _ source: CVPixelBuffer,
        configuration: VTSuperResolutionScalerConfiguration
    ) throws -> CVPixelBuffer {
        try compatibleSourceBuffer(
            source,
            required: configuration.sourcePixelBufferAttributes,
            width: configuration.frameWidth,
            height: configuration.frameHeight,
            supportedPixelFormats: configuration.supportedPixelFormats
        )
    }

    private func compatibleSourceBuffer(
        _ source: CVPixelBuffer,
        configuration: VTLowLatencySuperResolutionScalerConfiguration
    ) throws -> CVPixelBuffer {
        try compatibleSourceBuffer(
            source,
            required: configuration.sourcePixelBufferAttributes,
            width: configuration.frameWidth,
            height: configuration.frameHeight,
            supportedPixelFormats: configuration.supportedPixelFormats
        )
    }

    private func compatibleSourceBuffer(
        _ source: CVPixelBuffer,
        required: [String: any Sendable],
        width: Int,
        height: Int,
        supportedPixelFormats: [OSType]
    ) throws -> CVPixelBuffer {
        guard CVPixelBufferGetWidth(source) == width, CVPixelBufferGetHeight(source) == height else {
            throw AppleFrameProcessorError.unsupportedConfiguration
        }
        let requiredAny = Self.anyAttributes(required)
        let sourceFormat = CVPixelBufferGetPixelFormatType(source)
        let acceptedFormat = supportedPixelFormats.isEmpty || supportedPixelFormats.contains(sourceFormat)
        let compatible = acceptedFormat
            && CVPixelBufferGetIOSurface(source) != nil
            && CVPixelBufferIsCompatibleWithAttributes(source, requiredAny as CFDictionary)
        if compatible {
            return source
        }

        let destination = try Self.makePixelBuffer(
            required: required,
            width: width,
            height: height,
            supportedPixelFormats: supportedPixelFormats,
            preferredPixelFormat: acceptedFormat ? sourceFormat : nil
        )
        let image = CIImage(cvPixelBuffer: source)
        ciContext.render(
            image,
            to: destination,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: nil
        )
        return destination
    }

    private static func makeConfiguration(
        width: Int,
        height: Int,
        scaleFactor: Int
    ) -> VTSuperResolutionScalerConfiguration? {
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

    private static func makePixelBuffer(
        required: [String: any Sendable],
        width: Int,
        height: Int,
        supportedPixelFormats: [OSType],
        preferredPixelFormat: OSType? = nil
    ) throws -> CVPixelBuffer {
        let requiredAny = anyAttributes(required)
        let requiredFormats = pixelFormats(from: required)
        let format: OSType
        if let preferredPixelFormat,
           (supportedPixelFormats.isEmpty || supportedPixelFormats.contains(preferredPixelFormat)),
           (requiredFormats.isEmpty || requiredFormats.contains(preferredPixelFormat)) {
            format = preferredPixelFormat
        } else {
            format = supportedPixelFormats.first
                ?? requiredFormats.first
                ?? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }

        let client: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: format),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
        ]
        var resolved: CFDictionary?
        let dictionaries = [requiredAny as CFDictionary, client as CFDictionary] as CFArray
        let resolveStatus = CVPixelBufferCreateResolvedAttributesDictionary(
            kCFAllocatorDefault,
            dictionaries,
            &resolved
        )
        guard resolveStatus == kCVReturnSuccess, let resolved else {
            throw AppleFrameProcessorError.pixelBufferAttributes(resolveStatus)
        }

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            resolved,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        return buffer
    }

    private static func anyAttributes(_ attributes: [String: any Sendable]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in attributes {
            result[key] = value
        }
        return result
    }

    private static func pixelFormats(from attributes: [String: any Sendable]) -> [OSType] {
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

    private static func readiness(
        for status: VTSuperResolutionScalerConfiguration.ModelStatus
    ) -> AppleModelReadiness {
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
@MainActor
final class AppleFrameProcessorService: @unchecked Sendable {
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

    static func preferredFullQualitySourcePixelFormat(width: Int, height: Int, scaleFactor: Int) -> OSType {
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    static func lowLatencyScaleFactors(width: Int, height: Int) -> [Double] { [] }

    static func prepareModel(width: Int, height: Int, scaleFactor: Int) async throws -> Double {
        throw AppleFrameProcessorError.unavailable
    }

    func startLowLatencySession(width: Int, height: Int, scaleFactor: Float) throws {
        throw AppleFrameProcessorError.unavailable
    }

    func processInActiveLowLatencySession(
        source: CVPixelBuffer,
        presentationTime: CMTime
    ) async throws -> CVPixelBuffer {
        throw AppleFrameProcessorError.unavailable
    }

    func startFullQualitySession(width: Int, height: Int, scaleFactor: Int) throws {
        throw AppleFrameProcessorError.unavailable
    }

    func processInActiveSession(
        source: CVPixelBuffer,
        presentationTime: CMTime,
        sequential: Bool
    ) async throws -> CVPixelBuffer {
        throw AppleFrameProcessorError.unavailable
    }

    func resetTemporalHistory() {}
    func endSession() {}

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
