import Foundation
import AVFoundation

struct ComparisonPreview: Identifiable, Sendable {
    let id = UUID()
    var sourceURL: URL
    var enhancedURL: URL
    var previewProcessingDuration: Double
    var estimatedFullDuration: Double
    var estimatedOutputBytes: Int64
    var selectedStartSeconds: Double
    var selectedDurationSeconds: Double
}

struct PreviewSelection: Equatable, Sendable {
    var startSeconds: Double
    var durationSeconds: Double

    static func resolve(sourceDuration: Double, requestedStart: Double, requestedDuration: Double) -> PreviewSelection {
        let duration = min(max(0, sourceDuration), min(5, max(2, requestedDuration)))
        let latestStart = max(0, sourceDuration - duration)
        return PreviewSelection(
            startSeconds: min(max(0, requestedStart), latestStart),
            durationSeconds: duration
        )
    }
}

@MainActor
final class ComparisonPreviewCoordinator {
    private let pipeline = AIAssetReaderWriterPipeline()
    private var extractionSession: AVAssetExportSession?

    func cancel() {
        extractionSession?.cancelExport()
        pipeline.cancel()
    }

    func generate(
        sourceURL: URL,
        sourceInfo: VideoAssetInfo,
        configuration: ExportConfiguration,
        requestedDuration: Double = 3,
        requestedStart: Double? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ComparisonPreview {
        let selection = PreviewSelection.resolve(
            sourceDuration: sourceInfo.duration,
            requestedStart: requestedStart ?? sourceInfo.duration * 0.25,
            requestedDuration: requestedDuration
        )
        let previewDuration = selection.durationSeconds
        guard previewDuration > 0 else { throw AppError.exportFailed("The video has no previewable duration.") }
        let start = selection.startSeconds
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ComparisonPreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sourceClip = folder.appendingPathComponent("source-" + UUID().uuidString + ".mov")
        let enhancedClip = folder.appendingPathComponent("enhanced-" + UUID().uuidString + ".mov")
        try await extract(sourceURL: sourceURL, start: start, duration: previewDuration, outputURL: sourceClip)
        progress(0.05)

        let clipInfo = try await AssetInspector.inspect(sourceClip)
        var job = ProcessingJob(sourceURL: sourceClip, assetInfo: clipInfo, configuration: configuration)
        job.outputURL = enhancedClip
        job.totalFrames = max(1, Int(clipInfo.duration * clipInfo.frameRate))
        let started = Date()
        _ = try await pipeline.process(
            job: job,
            progress: { local in progress(0.05 + local * 0.95) }
        )
        let elapsed = Date().timeIntervalSince(started)
        return ComparisonPreview(
            sourceURL: sourceClip,
            enhancedURL: enhancedClip,
            previewProcessingDuration: elapsed,
            estimatedFullDuration: elapsed / max(0.1, previewDuration) * sourceInfo.duration,
            estimatedOutputBytes: StorageEstimator.estimatedOutputBytes(info: sourceInfo, configuration: configuration),
            selectedStartSeconds: start,
            selectedDurationSeconds: previewDuration
        )
    }

    private func extract(sourceURL: URL, start: Double, duration: Double, outputURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw AppError.exportFailed("The comparison range could not be prepared.")
        }
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        session.metadata = try await asset.load(.metadata)
        extractionSession = session
        defer { extractionSession = nil }
        try await session.export(to: outputURL, as: .mov)
    }
}
