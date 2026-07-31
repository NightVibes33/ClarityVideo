import Foundation
import AVFoundation
import CoreGraphics

@MainActor
final class VideoProcessingCoordinator {
    private var exportSession: AVAssetExportSession?
    private var progressTask: Task<Void, Never>?
    private let aiPipeline = AIAssetReaderWriterPipeline()

    func process(job: ProcessingJob, progress: @escaping @Sendable (Double) -> Void) async throws -> ProcessingJob {
        var result = job
        result.status = .preparing
        guard let outputURL = job.outputURL else { throw AppError.exportFailed("Missing output destination.") }
        try? FileManager.default.removeItem(at: outputURL)
n        if AppleFrameProcessorService.probe().fullSupported {
            return try await aiPipeline.process(job: job, progress: progress)
        }

        let asset = AVURLAsset(url: job.sourceURL)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else { throw AppError.noVideoTrack }
        let composition = try await makeComposition(asset: asset, track: sourceTrack, job: job)
        guard let session = AVAssetExportSession(asset: composition.asset, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw AppError.exportFailed("HEVC export could not be initialized.")
        }
        session.videoComposition = composition.video
        session.metadata = try await asset.load(.metadata)
        session.shouldOptimizeForNetworkUse = false
        exportSession = session
        result.status = .processing

        progressTask = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
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
n        if AppleFrameProcessorService.probe().fullSupported {
            return try await aiPipeline.process(job: job, progress: progress)
        }
            if session.status == .cancelled { throw CancellationError() }
            throw AppError.exportFailed(session.error?.localizedDescription ?? error.localizedDescription)
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
n        if AppleFrameProcessorService.probe().fullSupported {
            return try await aiPipeline.process(job: job, progress: progress)
        }
            throw AppError.exportFailed(session.error?.localizedDescription ?? "The export did not complete.")
        }
        progress(1)
        result.progress = 1
        result.processedFrames = result.totalFrames
        result.status = .completed
        return result
    }

    func cancel() {
        aiPipeline.cancel()
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
