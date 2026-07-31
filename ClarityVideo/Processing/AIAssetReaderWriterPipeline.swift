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
    private var cancelled = false
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func cancel() {
        cancelled = true
        reader?.cancelReading()
        writer?.cancelWriting()
        remuxSession?.cancelExport()
        frameProcessor?.cancel()
    }

    func process(job: ProcessingJob, progress: @escaping @Sendable (Double) -> Void) async throws -> ProcessingJob {
        #if targetEnvironment(simulator)
        throw AppleFrameProcessorError.unavailable
        #else
        cancelled = false
        var result = job
        result.status = .preparing
        guard let finalURL = job.outputURL else { throw AppError.exportFailed("Missing output destination.") }
        let asset = AVURLAsset(url: job.sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw AppError.noVideoTrack }
        let naturalSize = try await track.load(.naturalSize)
        let sourceWidth = Int(abs(naturalSize.width))
        let sourceHeight = Int(abs(naturalSize.height))
        let probe = AppleFrameProcessorService.probe()
        guard probe.fullSupported, !probe.fullScaleFactors.isEmpty else {
            throw AppError.unsupported("Apple full-quality super resolution is unavailable on this device.")
        }

        let targetLandscape = job.configuration.resolution.landscapeSize
        let encodedPortrait = sourceHeight > sourceWidth
        let targetSize = encodedPortrait
            ? CGSize(width: targetLandscape.height, height: targetLandscape.width)
            : targetLandscape
        let neededScale = max(targetSize.width / CGFloat(sourceWidth), targetSize.height / CGFloat(sourceHeight))
        let scale = probe.fullScaleFactors.sorted().first { CGFloat($0) >= neededScale }
            ?? probe.fullScaleFactors.max()!
        guard sourceWidth <= 1440, sourceHeight <= 1080 else {
            throw AppError.unsupported("This source requires tiled Apple SR. Full-frame AI supports up to 1440x1080 on iPhone; tiled processing is required for this clip.")
        }

        progress(0.01)
        _ = try await AppleFrameProcessorService.prepareModel(width: sourceWidth, height: sourceHeight, scaleFactor: scale)
        try Task.checkCancellation()
        let sourcePixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let assetReader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: sourcePixelFormat,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
            ]
        )
        trackOutput.alwaysCopiesSampleData = false
        guard assetReader.canAdd(trackOutput) else { throw AppError.exportFailed("The video decoder output could not be attached.") }
        assetReader.add(trackOutput)
        reader = assetReader

        let temporaryVideo = finalURL.deletingLastPathComponent()
            .appendingPathComponent("AI-video-" + UUID().uuidString + ".mov")
        try? FileManager.default.removeItem(at: temporaryVideo)
        let assetWriter = try AVAssetWriter(outputURL: temporaryVideo, fileType: .mov)
        assetWriter.metadata = try await asset.load(.metadata)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(targetSize.width),
            AVVideoHeightKey: Int(targetSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: job.configuration.bitrateMbps * 1_000_000,
                AVVideoExpectedSourceFrameRateKey: max(1, Int(job.assetInfo.frameRate.rounded())),
                AVVideoMaxKeyFrameIntervalKey: max(1, Int(job.assetInfo.frameRate.rounded() * 2))
            ]
        ]
        guard assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw AppError.unsupported("The hardware encoder rejected the selected output dimensions and HEVC settings.")
        }
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        writerInput.transform = try await track.load(.preferredTransform)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(targetSize.width),
                kCVPixelBufferHeightKey as String: Int(targetSize.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
            ]
        )
        guard assetWriter.canAdd(writerInput) else { throw AppError.exportFailed("The HEVC writer input could not be attached.") }
        assetWriter.add(writerInput)
        writer = assetWriter
        guard assetReader.startReading(), assetWriter.startWriting() else {
            throw AppError.exportFailed(assetReader.error?.localizedDescription ?? assetWriter.error?.localizedDescription ?? "Could not start the frame pipeline.")
        }
        assetWriter.startSession(atSourceTime: .zero)

        let processor = AppleFrameProcessorService()
        frameProcessor = processor
        try processor.startFullQualitySession(width: sourceWidth, height: sourceHeight, scaleFactor: scale)
        defer {
            processor.endSession()
            frameProcessor = nil
            reader = nil
            writer = nil
        }

        result.status = .processing
        var frameIndex = 0
        let totalFrames = max(1, result.totalFrames)
        while let sample = trackOutput.copyNextSampleBuffer() {
            if cancelled { throw CancellationError() }
            try Task.checkCancellation()
            while ProcessInfo.processInfo.thermalState == .critical {
                if cancelled { throw CancellationError() }
                try await Task.sleep(for: .seconds(1))
            }
            guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            let aiBuffer = try await processor.processInActiveSession(
                source: sourceBuffer,
                presentationTime: timestamp,
                sequential: frameIndex > 0
            )
            while !writerInput.isReadyForMoreMediaData {
                if cancelled { throw CancellationError() }
                try await Task.sleep(for: .milliseconds(4))
            }
            let outputBuffer = try makeExactSizeBuffer(from: aiBuffer, adaptor: adaptor, size: targetSize)
            guard adaptor.append(outputBuffer, withPresentationTime: timestamp) else {
                throw AppError.exportFailed(assetWriter.error?.localizedDescription ?? "The enhanced frame could not be encoded.")
            }
            frameIndex += 1
            result.processedFrames = frameIndex
            progress(min(0.92, Double(frameIndex) / Double(totalFrames) * 0.92))
        }
        guard assetReader.status == .completed else {
            throw AppError.exportFailed(assetReader.error?.localizedDescription ?? "Video decoding did not complete.")
        }
        writerInput.markAsFinished()
        await assetWriter.finishWriting()
        guard assetWriter.status == .completed else {
            throw AppError.exportFailed(assetWriter.error?.localizedDescription ?? "HEVC encoding did not complete.")
        }
        processor.endSession()
        progress(0.94)

        try await remuxAudioAndMetadata(videoURL: temporaryVideo, sourceAsset: asset, finalURL: finalURL)
        try? FileManager.default.removeItem(at: temporaryVideo)
        progress(1)
        result.outputURL = finalURL
        result.progress = 1
        result.processedFrames = frameIndex
        result.status = .completed
        return result
        #endif
    }

    private func makeExactSizeBuffer(
        from source: CVPixelBuffer,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        size: CGSize
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
        let sx = size.width / image.extent.width
        let sy = size.height / image.extent.height
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(sy)
        filter.aspectRatio = Float(sx / sy)
        guard let scaled = filter.outputImage else {
            throw AppError.exportFailed("The exact-size Metal resize failed.")
        }
        ciContext.render(
            scaled,
            to: output,
            bounds: CGRect(origin: .zero, size: size),
            colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        )
        return output
    }

    private func remuxAudioAndMetadata(videoURL: URL, sourceAsset: AVAsset, finalURL: URL) async throws {
        try? FileManager.default.removeItem(at: finalURL)
        let videoAsset = AVURLAsset(url: videoURL)
        guard let enhancedTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw AppError.exportFailed("The enhanced video track could not be reopened.")
        }
        let duration = try await videoAsset.load(.duration)
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AppError.exportFailed("The final video track could not be created.")
        }
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: enhancedTrack, at: .zero)
        videoTrack.preferredTransform = try await enhancedTrack.load(.preferredTransform)
        if let sourceAudio = try await sourceAsset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let audioDuration = min(duration, try await sourceAsset.load(.duration))
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: audioDuration), of: sourceAudio, at: .zero)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw AppError.exportFailed("Audio remuxing could not be initialized.")
        }
        session.metadata = try await sourceAsset.load(.metadata)
        remuxSession = session
        defer { remuxSession = nil }
        try await session.export(to: finalURL, as: .mov)
    }
}
