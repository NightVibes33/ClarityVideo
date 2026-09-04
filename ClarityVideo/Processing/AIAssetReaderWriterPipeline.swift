import Foundation
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import VideoToolbox

@MainActor
final class AIAssetReaderWriterPipeline {
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private var remuxSession: AVAssetExportSession?
    private var frameProcessor: AppleFrameProcessorService?
    private var tiledProcessor: TiledAppleSRProcessor?
    private var temporalDenoiser: TemporalNoiseFilterService?
    private var cancelled = false
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func cancel() {
        cancelled = true
        reader?.cancelReading()
        writer?.cancelWriting()
        remuxSession?.cancelExport()
        frameProcessor?.cancel()
        tiledProcessor?.cancel()
        temporalDenoiser?.cancel()
    }

    func process(
        job: ProcessingJob,
        progress: @escaping @Sendable (Double) -> Void,
        outputBytes: @escaping @Sendable (Int64) -> Void = { _ in }
    ) async throws -> ProcessingJob {
        #if targetEnvironment(simulator)
        throw AppleFrameProcessorError.unavailable
        #else
        cancelled = false
        var result = job
        result.status = .preparing
        result.enhancementFailureCount = 0
        result.enhancementFallbackReason = nil
        guard let finalURL = job.outputURL else {
            throw AppError.exportFailed("Missing output destination.")
        }

        let asset = AVURLAsset(url: job.sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.noVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let sourceWidth = Int(abs(naturalSize.width))
        let sourceHeight = Int(abs(naturalSize.height))
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw AppError.exportFailed("The decoded video dimensions are invalid.")
        }

        let probe = AppleFrameProcessorService.probe()
        var planningCapabilities = DeviceEnhancementCapabilities()
        planningCapabilities.fullSuperResolutionAvailable = probe.fullSupported
        planningCapabilities.lowLatencySuperResolutionAvailable = probe.lowLatencySupported
        planningCapabilities.supportedFullScaleFactors = probe.fullScaleFactors
        let sourceLowLatencyFactors = AppleFrameProcessorService.lowLatencyScaleFactors(
            width: sourceWidth,
            height: sourceHeight
        )
        let plan = try PipelinePlanner.plan(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            target: job.configuration.resolution,
            mode: job.configuration.mode,
            capabilities: planningCapabilities,
            lowLatencyFactorsForSource: sourceLowLatencyFactors
        )
        let targetSize = CGSize(width: plan.targetWidth, height: plan.targetHeight)
        let useLowLatency = plan.route == .lowLatencySuperResolution
        let useNativeEnhancement = plan.route == .nativeEnhancement
        let lowScale: Double? = useLowLatency ? plan.aiScaleFactor : nil
        let fullScale: Int? = (useLowLatency || useNativeEnhancement) ? nil : Int(plan.aiScaleFactor)
        switch plan.route {
        case .nativeEnhancement:
            result.enhancementMethod = "Core Image native enhancement"
        case .lowLatencySuperResolution:
            result.enhancementMethod = "Apple low-latency super resolution"
        case .fullQualitySuperResolution:
            result.enhancementMethod = "Apple full-quality super resolution"
        case .tiledSuperResolution:
            result.enhancementMethod = "Apple full-quality super resolution (tiled)"
        case .cascadedTiledSuperResolution:
            result.enhancementMethod = "Apple full-quality super resolution (cascaded tiled)"
        }

        progress(0.01)
        var tiled: TiledAppleSRProcessor?
        if plan.requiresTiling {
            guard let tileWidth = plan.tileWidth,
                  let tileHeight = plan.tileHeight,
                  let overlap = plan.overlap,
                  let fullScale else {
                throw PipelinePlanningError.noSuperResolutionRoute
            }
            let processor = try TiledAppleSRProcessor(
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: plan.targetWidth,
                targetHeight: plan.targetHeight,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
                overlap: overlap,
                scale: fullScale
            )
            try await processor.prepare()
            tiled = processor
            tiledProcessor = processor
        } else if let fullScale {
            _ = try await AppleFrameProcessorService.prepareModel(
                width: sourceWidth,
                height: sourceHeight,
                scaleFactor: fullScale
            )
        }
        try Task.checkCancellation()

        let sourcePixelFormat: OSType
        if plan.requiresTiling {
            sourcePixelFormat = kCVPixelFormatType_32BGRA
        } else if let fullScale {
            sourcePixelFormat = AppleFrameProcessorService.preferredFullQualitySourcePixelFormat(
                width: sourceWidth,
                height: sourceHeight,
                scaleFactor: fullScale
            )
        } else {
            sourcePixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }

        var denoiser: TemporalNoiseFilterService?
        var spatialDenoiser: SpatialNoiseFilterService?
        result.denoiseMethod = job.configuration.denoise > 0 ? "Requested" : "Off"
        if job.configuration.denoise > 0,
           probe.temporalNoiseSupported,
           TemporalNoiseFilterService.supports(
            width: sourceWidth,
            height: sourceHeight,
            pixelFormat: sourcePixelFormat
           ) {
            let service = TemporalNoiseFilterService()
            try service.start(
                width: sourceWidth,
                height: sourceHeight,
                pixelFormat: sourcePixelFormat,
                strength: job.configuration.denoise
            )
            denoiser = service
            temporalDenoiser = service
            result.denoiseMethod = "Apple temporal"
        } else if job.configuration.denoise > 0, plan.requiresTiling {
            spatialDenoiser = try? SpatialNoiseFilterService(
                width: sourceWidth,
                height: sourceHeight,
                strength: job.configuration.denoise
            )
            result.denoiseMethod = spatialDenoiser == nil
                ? "Off (spatial fallback unavailable)"
                : "Core Image spatial fallback"
        } else if job.configuration.denoise > 0, useNativeEnhancement {
            result.denoiseMethod = "Core Image inline spatial fallback"
        } else if job.configuration.denoise > 0 {
            result.denoiseMethod = "Off (unsupported input)"
        }

        let assetReader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: sourcePixelFormat,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
            ]
        )
        trackOutput.alwaysCopiesSampleData = false
        guard assetReader.canAdd(trackOutput) else {
            throw AppError.exportFailed("The video decoder output could not be attached.")
        }
        assetReader.add(trackOutput)
        reader = assetReader

        let temporaryVideo = finalURL.deletingLastPathComponent()
            .appendingPathComponent("AI-video-" + UUID().uuidString + ".mov")
        try? FileManager.default.removeItem(at: temporaryVideo)
        defer { try? FileManager.default.removeItem(at: temporaryVideo) }
        let assetWriter = try AVAssetWriter(outputURL: temporaryVideo, fileType: .mov)
        assetWriter.metadata = try await asset.load(.metadata)
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: job.configuration.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(targetSize.width),
            AVVideoHeightKey: Int(targetSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: job.configuration.bitrateMbps * 1_000_000,
                AVVideoExpectedSourceFrameRateKey: max(1, Int(job.assetInfo.frameRate.rounded())),
                AVVideoMaxKeyFrameIntervalKey: max(1, Int(job.assetInfo.frameRate.rounded() * 2))
            ]
        ]
        let sourceColorProperties = try await colorProperties(for: track)
        if !sourceColorProperties.isEmpty {
            videoSettings[AVVideoColorPropertiesKey] = sourceColorProperties
        }
        if job.assetInfo.isHDR && job.configuration.hdrBehavior == .convertToSDR {
            videoSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        }

        var selectedCodec = job.configuration.codec.rawValue
        if !assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) {
            guard job.configuration.codec == .hevc else {
                throw AppError.unsupported("The hardware encoder rejected the selected 4K H.264 settings.")
            }
            guard job.configuration.resolution == .uhd4K, !job.assetInfo.isHDR else {
                throw AppError.unsupported("The hardware encoder rejected the selected output dimensions and HEVC settings.")
            }
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.h264
            if var compression = videoSettings[AVVideoCompressionPropertiesKey] as? [String: Any] {
                compression[AVVideoAverageBitRateKey] = min(job.configuration.bitrateMbps, 50) * 1_000_000
                videoSettings[AVVideoCompressionPropertiesKey] = compression
            }
            guard assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) else {
                throw AppError.unsupported("Both HEVC and the 4K SDR H.264 fallback were rejected by the encoder.")
            }
            selectedCodec = "H.264"
        }
        result.outputCodec = selectedCodec

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        writerInput.transform = try await track.load(.preferredTransform)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(targetSize.width),
                kCVPixelBufferHeightKey as String: Int(targetSize.height),
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
            ]
        )
        guard assetWriter.canAdd(writerInput) else {
            throw AppError.exportFailed("The selected video encoder input could not be attached.")
        }
        assetWriter.add(writerInput)
        writer = assetWriter
        guard assetReader.startReading(), assetWriter.startWriting() else {
            throw AppError.exportFailed(
                assetReader.error?.localizedDescription
                    ?? assetWriter.error?.localizedDescription
                    ?? "Could not start the frame pipeline."
            )
        }
        assetWriter.startSession(atSourceTime: .zero)

        let processor = AppleFrameProcessorService()
        if tiled == nil {
            frameProcessor = processor
            if useLowLatency, let lowScale {
                try processor.startLowLatencySession(
                    width: sourceWidth,
                    height: sourceHeight,
                    scaleFactor: Float(lowScale)
                )
            } else if let fullScale {
                try processor.startFullQualitySession(
                    width: sourceWidth,
                    height: sourceHeight,
                    scaleFactor: fullScale
                )
            }
        }
        defer {
            processor.endSession()
            tiled?.endSession()
            frameProcessor = nil
            tiledProcessor = nil
            denoiser?.endSession()
            temporalDenoiser = nil
            reader = nil
            writer = nil
        }

        result.status = .processing
        var frameIndex = 0
        var sceneCutDetector = SceneCutDetector()
        let totalFrames = max(1, result.totalFrames)
        var writesTiledFramesDirectly = tiled != nil
            && !(job.assetInfo.isHDR && job.configuration.hdrBehavior == .convertToSDR)
        var appleSRFallback = false
        var firstVideoTimestamp: CMTime?

        while let sample = trackOutput.copyNextSampleBuffer() {
            if cancelled { throw CancellationError() }
            try Task.checkCancellation()
            while ProcessInfo.processInfo.thermalState == .critical {
                if cancelled { throw CancellationError() }
                try await Task.sleep(for: .seconds(1))
            }
            guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let sourceTimestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            if firstVideoTimestamp == nil { firstVideoTimestamp = sourceTimestamp }
            let timestamp = CMTimeSubtract(sourceTimestamp, firstVideoTimestamp ?? .zero)
            let isSceneCut = sceneCutDetector.isSceneCut(sourceBuffer)
            if isSceneCut { processor.resetTemporalHistory() }

            let enhancementSource: CVPixelBuffer
            if let activeDenoiser = denoiser {
                do {
                    enhancementSource = try await activeDenoiser.process(
                        source: sourceBuffer,
                        presentationTime: timestamp,
                        hasDiscontinuity: isSceneCut
                    )
                } catch {
                    activeDenoiser.endSession()
                    denoiser = nil
                    temporalDenoiser = nil
                    if plan.requiresTiling {
                        if spatialDenoiser == nil {
                            spatialDenoiser = try? SpatialNoiseFilterService(
                                width: sourceWidth,
                                height: sourceHeight,
                                strength: job.configuration.denoise
                            )
                        }
                        if let spatialDenoiser {
                            enhancementSource = try spatialDenoiser.process(source: sourceBuffer)
                            result.denoiseMethod = "Core Image spatial fallback"
                        } else {
                            enhancementSource = sourceBuffer
                            result.denoiseMethod = "Off (spatial fallback unavailable)"
                        }
                    } else {
                        enhancementSource = sourceBuffer
                        result.denoiseMethod = useNativeEnhancement
                            ? "Core Image inline spatial fallback"
                            : "Off (Apple temporal failed)"
                    }
                }
            } else if let spatialDenoiser {
                enhancementSource = try spatialDenoiser.process(source: sourceBuffer)
            } else {
                enhancementSource = sourceBuffer
            }

            let aiBuffer: CVPixelBuffer
            if useNativeEnhancement || appleSRFallback {
                aiBuffer = enhancementSource
            } else {
                do {
                    if let tiled {
                        let canvas = writesTiledFramesDirectly ? try makeWriterBuffer(adaptor: adaptor) : nil
                        aiBuffer = try await tiled.process(
                            frame: enhancementSource,
                            presentationTime: timestamp,
                            canvas: canvas,
                            detailRecovery: writesTiledFramesDirectly ? job.configuration.detailRecovery : 0,
                            sharpening: writesTiledFramesDirectly ? job.configuration.sharpening : 0
                        )
                    } else if useLowLatency {
                        aiBuffer = try await processor.processInActiveLowLatencySession(
                            source: enhancementSource,
                            presentationTime: timestamp
                        )
                    } else {
                        aiBuffer = try await processor.processInActiveSession(
                            source: enhancementSource,
                            presentationTime: timestamp,
                            sequential: frameIndex > 0 && !isSceneCut
                        )
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    appleSRFallback = true
                    writesTiledFramesDirectly = false
                    processor.endSession()
                    tiled?.endSession()
                    aiBuffer = enhancementSource
                    result.enhancementFailureCount = (result.enhancementFailureCount ?? 0) + 1
                    result.enhancementFallbackReason = error.localizedDescription
                    result.enhancementMethod = "Core Image upscale fallback"
                }
            }

            while !writerInput.isReadyForMoreMediaData {
                if cancelled { throw CancellationError() }
                try await Task.sleep(for: .milliseconds(4))
            }
            let outputBuffer = writesTiledFramesDirectly
                ? aiBuffer
                : try makeExactSizeBuffer(
                    from: aiBuffer,
                    adaptor: adaptor,
                    size: targetSize,
                    configuration: job.configuration,
                    sourceIsHDR: job.assetInfo.isHDR,
                    spatialDenoiseStrength: (useNativeEnhancement || appleSRFallback) && denoiser == nil
                        ? job.configuration.denoise
                        : 0
                )
            guard adaptor.append(outputBuffer, withPresentationTime: timestamp) else {
                throw AppError.exportFailed(
                    assetWriter.error?.localizedDescription ?? "The enhanced frame could not be encoded."
                )
            }

            frameIndex += 1
            if frameIndex % 15 == 0 {
                let bytes = (try? temporaryVideo.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                    .map(Int64.init) ?? 0
                outputBytes(bytes)
            }
            result.processedFrames = frameIndex
            progress(min(0.92, Double(frameIndex) / Double(totalFrames) * 0.92))
        }

        guard assetReader.status == .completed else {
            throw AppError.exportFailed(
                assetReader.error?.localizedDescription ?? "Video decoding did not complete."
            )
        }
        guard frameIndex > 0 else {
            throw AppError.exportFailed("The decoder produced no video frames.")
        }
        writerInput.markAsFinished()
        await assetWriter.finishWriting()
        guard assetWriter.status == .completed else {
            throw AppError.exportFailed(
                assetWriter.error?.localizedDescription ?? "Video encoding did not complete."
            )
        }
        processor.endSession()
        progress(0.94)

        try await remuxAudioAndMetadata(
            videoURL: temporaryVideo,
            sourceAsset: asset,
            finalURL: finalURL
        )
        try await OutputValidator.validate(
            outputURL: finalURL,
            sourceURL: job.sourceURL,
            info: job.assetInfo,
            configuration: job.configuration
        )
        try? FileManager.default.removeItem(at: temporaryVideo)
        outputBytes(Int64((try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        progress(1)
        result.outputURL = finalURL
        result.progress = 1
        result.processedFrames = frameIndex
        result.status = .completed
        return result
        #endif
    }

    private func makeWriterBuffer(adaptor: AVAssetWriterInputPixelBufferAdaptor) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else {
            throw AppError.exportFailed("The encoder pixel-buffer pool is unavailable.")
        }
        var output: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output)
        guard status == kCVReturnSuccess, let output else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        return output
    }

    private func makeExactSizeBuffer(
        from source: CVPixelBuffer,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        size: CGSize,
        configuration: ExportConfiguration,
        sourceIsHDR: Bool,
        spatialDenoiseStrength: Double
    ) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else {
            throw AppError.exportFailed("The encoder pixel-buffer pool is unavailable.")
        }
        var output: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output)
        guard status == kCVReturnSuccess, let output else {
            throw AppleFrameProcessorError.pixelBufferCreation(status)
        }
        let image = CIImage(cvPixelBuffer: source)
        var resizeInput = image
        if spatialDenoiseStrength > 0 {
            let denoise = CIFilter.noiseReduction()
            let parameters = SpatialNoiseParameters(strength: spatialDenoiseStrength)
            denoise.inputImage = resizeInput
            denoise.noiseLevel = parameters.noiseLevel
            denoise.sharpness = parameters.sharpness
            if let filtered = denoise.outputImage { resizeInput = filtered }
        }
        let sx = size.width / image.extent.width
        let sy = size.height / image.extent.height
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = resizeInput
        filter.scale = Float(sy)
        filter.aspectRatio = Float(sx / sy)
        guard var processed = filter.outputImage else {
            throw AppError.exportFailed("The exact-size resize failed.")
        }
        if configuration.detailRecovery > 0 {
            let recovery = CIFilter.unsharpMask()
            recovery.inputImage = processed
            recovery.radius = 1.5
            recovery.intensity = Float(configuration.detailRecovery * 0.55)
            if let output = recovery.outputImage { processed = output }
        }
        if configuration.sharpening > 0 {
            let sharpening = CIFilter.sharpenLuminance()
            sharpening.inputImage = processed
            sharpening.sharpness = Float(configuration.sharpening * 0.8)
            if let output = sharpening.outputImage { processed = output }
        }
        if sourceIsHDR && configuration.hdrBehavior == .convertToSDR {
            guard let toneMap = CIFilter(name: "CIToneMapHeadroom") else {
                throw AppError.unsupported("The system SDR tone-map filter is unavailable on this device.")
            }
            toneMap.setValue(processed, forKey: kCIInputImageKey)
            toneMap.setValue(4.0, forKey: "inputSourceHeadroom")
            toneMap.setValue(1.0, forKey: "inputTargetHeadroom")
            guard let toneMapped = toneMap.outputImage else {
                throw AppError.exportFailed("HDR-to-SDR tone mapping did not produce a frame.")
            }
            processed = toneMapped
        }
        let renderColorSpace = sourceIsHDR && configuration.hdrBehavior == .convertToSDR
            ? CGColorSpace(name: CGColorSpace.sRGB)
            : image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        ciContext.render(
            processed,
            to: output,
            bounds: CGRect(origin: .zero, size: size),
            colorSpace: renderColorSpace
        )
        return output
    }

    private func colorProperties(for track: AVAssetTrack) async throws -> [String: Any] {
        guard let description = try await track.load(.formatDescriptions).first else { return [:] }
        guard let rawExtensions = CMFormatDescriptionGetExtensions(description) else { return [:] }
        let extensions = rawExtensions as NSDictionary as? [String: Any] ?? [:]
        let mappings: [(CFString, String)] = [
            (kCMFormatDescriptionExtension_ColorPrimaries, AVVideoColorPrimariesKey),
            (kCMFormatDescriptionExtension_TransferFunction, AVVideoTransferFunctionKey),
            (kCMFormatDescriptionExtension_YCbCrMatrix, AVVideoYCbCrMatrixKey)
        ]
        var result: [String: Any] = [:]
        for (sourceKey, destinationKey) in mappings {
            if let value = extensions[sourceKey as String] {
                result[destinationKey] = value
            }
        }
        return result
    }

    private func remuxAudioAndMetadata(
        videoURL: URL,
        sourceAsset: AVAsset,
        finalURL: URL
    ) async throws {
        try? FileManager.default.removeItem(at: finalURL)
        let videoAsset = AVURLAsset(url: videoURL)
        guard let enhancedTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw AppError.exportFailed("The enhanced video track could not be reopened.")
        }
        let duration = try await videoAsset.load(.duration)
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AppError.exportFailed("The final video track could not be created.")
        }
        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: enhancedTrack,
            at: .zero
        )
        videoTrack.preferredTransform = try await enhancedTrack.load(.preferredTransform)

        if let sourceAudio = try await sourceAsset.loadTracks(withMediaType: .audio).first,
           let sourceVideo = try await sourceAsset.loadTracks(withMediaType: .video).first,
           let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let audioRange = try await sourceAudio.load(.timeRange)
            let videoRange = try await sourceVideo.load(.timeRange)
            let offsetSeconds = max(0, audioRange.start.seconds - videoRange.start.seconds)
            let outputStart = CMTime(seconds: offsetSeconds, preferredTimescale: 600)
            let available = max(0, duration.seconds - offsetSeconds)
            let audioDuration = CMTime(
                seconds: min(audioRange.duration.seconds, available),
                preferredTimescale: 600
            )
            if audioDuration > .zero {
                try audioTrack.insertTimeRange(
                    CMTimeRange(start: audioRange.start, duration: audioDuration),
                    of: sourceAudio,
                    at: outputStart
                )
            }
        }

        let metadata = try await sourceAsset.load(.metadata)
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw AppError.exportFailed("Audio remuxing could not be initialized.")
        }
        session.metadata = metadata
        remuxSession = session
        do {
            try await session.export(to: finalURL, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: finalURL)
            guard let fallback = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHEVCHighestQuality
            ) else {
                throw AppError.exportFailed(
                    "Compressed audio passthrough failed and the AAC-compatible fallback could not be initialized: "
                        + error.localizedDescription
                )
            }
            fallback.metadata = metadata
            remuxSession = fallback
            do {
                try await fallback.export(to: finalURL, as: .mov)
            } catch {
                throw AppError.exportFailed(
                    "Compressed audio passthrough and AAC-compatible fallback both failed: "
                        + error.localizedDescription
                )
            }
        }
        remuxSession = nil
    }
}