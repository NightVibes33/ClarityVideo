import Foundation
import AVFoundation
import CoreGraphics

@MainActor
final class VideoProcessingCoordinator {
    private var exportSession: AVAssetExportSession?
    private var progressTask: Task<Void, Never>?
    private let aiPipeline = AIAssetReaderWriterPipeline()
    private lazy var segmentedPipeline = SegmentedProcessingCoordinator(aiPipeline: aiPipeline)

    func process(job: ProcessingJob, progress: @escaping @Sendable (Double) -> Void, outputBytes: @escaping @Sendable (Int64) -> Void = { _ in }) async throws -> ProcessingJob {
        var result = job
        result.status = .preparing
        guard let outputURL = job.outputURL else { throw AppError.exportFailed("Missing output destination.") }
        if job.configuration.mode == .dlss5 && IOSNeuralHeadService.bundledModelURL() == nil {
            throw AppError.exportFailed("DLSS 5 model is not installed in this build.")
        }
        let probe = AppleFrameProcessorService.probe()
        if job.configuration.mode == .dlss5 && !probe.fullSupported && !probe.lowLatencySupported {
            throw AppError.unsupported("The neural renderer needs Apple Super Resolution to reach the selected 4K or 8K output on this device.")
        }
        if probe.fullSupported || probe.lowLatencySupported {
            do {
                if SegmentPlan.requiresSegmentation(duration: job.assetInfo.duration, configuration: job.configuration) {
                    return try await segmentedPipeline.process(job: job, progress: progress, outputBytes: outputBytes)
                }
                return try await aiPipeline.process(job: job, progress: progress, outputBytes: outputBytes)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if job.configuration.mode == .dlss5 { throw error }
                // An advertised scaler can still reject a particular source or require
                // a model download. Keep the export usable and label the actual route.
                if let output = job.outputURL { try? FileManager.default.removeItem(at: output) }
                progress(0)
            }
        }

        let asset = AVURLAsset(url: job.sourceURL)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else { throw AppError.noVideoTrack }
        let composition = try await makeComposition(asset: asset, track: sourceTrack, job: job)
        let preset = job.configuration.codec == .hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: composition.asset, presetName: preset) else {
            throw AppError.exportFailed("Video export could not be initialized.")
        }
        session.videoComposition = composition.video
        session.metadata = try await asset.load(.metadata)
        session.shouldOptimizeForNetworkUse = false
        exportSession = session
        result.status = .processing

        progressTask = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                outputBytes(Int64((try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer {
            progressTask?.cancel()
            progressTask = nil
            exportSession = nil
        }

        do {
            try await session.export(to: outputURL, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            if session.status == .cancelled { throw CancellationError() }
            throw AppError.exportFailed(session.error?.localizedDescription ?? error.localizedDescription)
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw AppError.exportFailed(session.error?.localizedDescription ?? "The export did not complete.")
        }
        try await OutputValidator.validate(
            outputURL: outputURL, sourceURL: job.sourceURL,
            info: job.assetInfo, configuration: job.configuration
        )
        progress(1)
        result.progress = 1
        result.outputCodec = job.configuration.codec == .hevc ? "HEVC (spatial upscale)" : "H.264 (spatial upscale)"
        result.processedFrames = result.totalFrames
        result.status = .completed
        return result
    }

    func cancel() {
        aiPipeline.cancel()
        segmentedPipeline.cancel()
        exportSession?.cancelExport()
        progressTask?.cancel()
    }

    private func makeComposition(asset: AVAsset, track: AVAssetTrack, job: ProcessingJob) async throws -> (asset: AVMutableComposition, video: AVMutableVideoComposition) {
        let duration = try await asset.load(.duration)
        let sourceSize = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let orientedRect = CGRect(origin: .zero, size: sourceSize).applying(preferred).standardized
        let targetLandscape = job.configuration.resolution.landscapeSize
        let target = orientedRect.height > orientedRect.width
            ? CGSize(width: targetLandscape.height, height: targetLandscape.width)
            : targetLandscape

        let mix = AVMutableComposition()
        guard let videoTrack = mix.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AppError.exportFailed("Could not create the video track.")
        }
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)

        if let audio = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = mix.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audio, at: .zero)
        }

        let scale = min(target.width / orientedRect.width, target.height / orientedRect.height)
        var transform = preferred
        transform = transform.concatenating(CGAffineTransform(translationX: -orientedRect.minX, y: -orientedRect.minY))
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let rendered = CGSize(width: orientedRect.width * scale, height: orientedRect.height * scale)
        transform = transform.concatenating(CGAffineTransform(
            translationX: (target.width - rendered.width) / 2,
            y: (target.height - rendered.height) / 2
        ))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layer.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = target
        let fps = max(1, Int32(job.assetInfo.frameRate.rounded()))
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
        return (mix, videoComposition)
    }
}
