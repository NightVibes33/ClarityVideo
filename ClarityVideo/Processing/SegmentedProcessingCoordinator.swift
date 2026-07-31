import Foundation
import AVFoundation
import CryptoKit

struct ProcessingSegment: Codable, Equatable, Sendable {
    var index: Int
    var startSeconds: Double
    var durationSeconds: Double
    var endSeconds: Double { startSeconds + durationSeconds }
}

enum SegmentPlan {
    static let defaultDuration = 30.0

    static func requiresSegmentation(duration: Double, configuration: ExportConfiguration) -> Bool {
        configuration.resolution == .uhd8K
            || (configuration.mode == .quality && duration > 60)
            || duration > 180
    }

    static func segments(duration: Double, segmentDuration: Double = defaultDuration) -> [ProcessingSegment] {
        guard duration > 0, segmentDuration > 0 else { return [] }
        var result: [ProcessingSegment] = []
        var start = 0.0
        var index = 0
        while start < duration {
            let length = min(segmentDuration, duration - start)
            result.append(ProcessingSegment(index: index, startSeconds: start, durationSeconds: length))
            start += length
            index += 1
        }
        return result
    }
}

@MainActor
final class SegmentedProcessingCoordinator {
    private let aiPipeline: AIAssetReaderWriterPipeline
    private let checkpointStore = CheckpointStore()
    private var activeExportSession: AVAssetExportSession?
    private var inProgressURLs: Set<URL> = []
    private var cancelled = false

    init(aiPipeline: AIAssetReaderWriterPipeline) {
        self.aiPipeline = aiPipeline
    }

    func cancel() {
        cancelled = true
        activeExportSession?.cancelExport()
        aiPipeline.cancel()
        for url in inProgressURLs { try? FileManager.default.removeItem(at: url) }
        inProgressURLs.removeAll()
    }

    func process(job: ProcessingJob, progress: @escaping @Sendable (Double) -> Void) async throws -> ProcessingJob {
        cancelled = false
        guard let finalURL = job.outputURL else { throw AppError.exportFailed("Missing segmented output destination.") }
        let segments = SegmentPlan.segments(duration: job.assetInfo.duration)
        guard !segments.isEmpty else { throw AppError.exportFailed("The source has no processable duration.") }
        let fingerprint = try sourceFingerprint(job: job)
        var checkpoint = try await checkpointStore.loadCompatible(
            sourceFingerprint: fingerprint,
            configuration: job.configuration,
            segmentCount: segments.count
        ) ?? ProcessingCheckpoint(
            jobID: job.id,
            sourceFingerprint: fingerprint,
            configuration: job.configuration,
            expectedSegmentCount: segments.count
        )
        let folder = try segmentFolder(checkpointID: checkpoint.jobID)
        var completedFiles: [URL] = []

        for segment in segments {
            if cancelled { throw CancellationError() }
            try Task.checkCancellation()
            if checkpoint.completedSegments.contains(segment.index),
               let existing = checkpoint.completedSegmentFiles[String(segment.index)],
               FileManager.default.fileExists(atPath: existing.path) {
                completedFiles.append(existing)
                progress(Double(segment.index + 1) / Double(segments.count) * 0.94)
                continue
            }

            let extracted = folder.appendingPathComponent("source-" + String(segment.index) + ".mov")
            let enhanced = folder.appendingPathComponent("enhanced-" + String(segment.index) + ".mov")
            try? FileManager.default.removeItem(at: extracted)
            try? FileManager.default.removeItem(at: enhanced)
            inProgressURLs.formUnion([extracted, enhanced])
            try await extract(segment: segment, from: job.sourceURL, to: extracted)
            if cancelled { throw CancellationError() }

            var segmentInfo = job.assetInfo
            segmentInfo.fileName = extracted.lastPathComponent
            segmentInfo.duration = segment.durationSeconds
            segmentInfo.estimatedSourceBytes = Int64((try? extracted.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            var segmentJob = ProcessingJob(
                id: UUID(),
                sourceURL: extracted,
                outputURL: enhanced,
                assetInfo: segmentInfo,
                configuration: job.configuration,
                status: .preparing,
                progress: 0,
                processedFrames: 0,
                totalFrames: max(1, Int(segment.durationSeconds * job.assetInfo.frameRate)),
                currentSegment: segment.index + 1,
                segmentCount: segments.count,
                errorMessage: nil,
                createdAt: job.createdAt
            )
            segmentJob = try await aiPipeline.process(job: segmentJob) { local in
                let overall = (Double(segment.index) + local) / Double(segments.count)
                progress(min(0.94, overall * 0.94))
            }
            guard segmentJob.status == .completed, FileManager.default.fileExists(atPath: enhanced.path) else {
                throw AppError.exportFailed("Enhanced segment " + String(segment.index + 1) + " did not complete.")
            }
            try? FileManager.default.removeItem(at: extracted)
            inProgressURLs.remove(extracted)
            inProgressURLs.remove(enhanced)
            checkpoint.completedSegments.append(segment.index)
            checkpoint.completedSegments.sort()
            checkpoint.completedSegmentFiles[String(segment.index)] = enhanced
            checkpoint.lastPresentationSeconds = segment.endSeconds
            checkpoint.updatedAt = Date()
            try await checkpointStore.save(checkpoint)
            completedFiles.append(enhanced)
        }

        guard completedFiles.count == segments.count else {
            throw AppError.exportFailed("The completed segment set is incomplete.")
        }
        progress(0.95)
        try await assemble(segmentURLs: completedFiles, sourceURL: job.sourceURL, outputURL: finalURL)
        progress(1)

        var result = job
        result.status = .completed
        result.progress = 1
        result.processedFrames = result.totalFrames
        result.currentSegment = segments.count
        result.segmentCount = segments.count
        try await checkpointStore.remove(checkpoint.jobID)
        try? FileManager.default.removeItem(at: folder)
        return result
    }

    private func extract(segment: ProcessingSegment, from sourceURL: URL, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw AppError.exportFailed("Segment extraction could not be initialized.")
        }
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: segment.startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: segment.durationSeconds, preferredTimescale: 600)
        )
        session.metadata = try await asset.load(.metadata)
        activeExportSession = session
        defer { activeExportSession = nil }
        try await session.export(to: outputURL, as: .mov)
    }

    private func assemble(segmentURLs: [URL], sourceURL: URL, outputURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        let composition = AVMutableComposition()
        guard let videoDestination = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw AppError.exportFailed("The segmented video assembly track could not be created.") }
        let audioDestination = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var cursor = CMTime.zero
        var firstTransform: CGAffineTransform?
        for url in segmentURLs {
            if cancelled { throw CancellationError() }
            let asset = AVURLAsset(url: url)
            guard let video = try await asset.loadTracks(withMediaType: .video).first else {
                throw AppError.exportFailed("A completed segment has no video track.")
            }
            let duration = try await asset.load(.duration)
            try videoDestination.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration), of: video, at: cursor
            )
            if firstTransform == nil { firstTransform = try await video.load(.preferredTransform) }
            if let audio = try await asset.loadTracks(withMediaType: .audio).first, let audioDestination {
                let audioDuration = min(duration, try await audio.load(.timeRange).duration)
                try audioDestination.insertTimeRange(
                    CMTimeRange(start: .zero, duration: audioDuration), of: audio, at: cursor
                )
            }
            cursor = cursor + duration
        }
        if let firstTransform { videoDestination.preferredTransform = firstTransform }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw AppError.exportFailed("Final segment assembly could not be initialized.")
        }
        session.metadata = try await AVURLAsset(url: sourceURL).load(.metadata)
        activeExportSession = session
        defer { activeExportSession = nil }
        try await session.export(to: outputURL, as: .mov)
    }

    private func segmentFolder(checkpointID: UUID) throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Segments", isDirectory: true)
            .appendingPathComponent(checkpointID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func sourceFingerprint(job: ProcessingJob) throws -> String {
        let values = try job.sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let material = [
            job.sourceURL.lastPathComponent,
            String(values.fileSize ?? 0),
            String(values.contentModificationDate?.timeIntervalSince1970 ?? 0),
            String(job.assetInfo.duration),
            String(job.assetInfo.encodedWidth),
            String(job.assetInfo.encodedHeight)
        ].joined(separator: "|")
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
