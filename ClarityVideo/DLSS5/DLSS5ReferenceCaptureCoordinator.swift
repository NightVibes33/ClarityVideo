import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

struct DLSS5ReferenceCaptureResult: Sendable {
    var folderURL: URL
    var manifestURL: URL
    var packageURL: URL
    var frameTimestampSeconds: Double
    var width: Int
    var height: Int
}

@MainActor
final class DLSS5ReferenceCaptureCoordinator {
    func captureVideoFrame(
        sourceURL: URL,
        requestedSeconds: Double = 0
    ) async throws -> DLSS5ReferenceCaptureResult {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.noVideoTrack
        }
        let duration = try await asset.load(.duration)
        let safeStart = min(max(0, requestedSeconds), max(0, duration.seconds - 0.05))

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: safeStart, preferredTimescale: 600),
            duration: CMTime(seconds: 0.35, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw AppError.exportFailed("The DLSS 5 reference decoder output could not be attached.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw AppError.exportFailed(reader.error?.localizedDescription ?? "The DLSS 5 reference decoder did not start.")
        }

        guard let firstSample = output.copyNextSampleBuffer(),
              let firstBuffer = CMSampleBufferGetImageBuffer(firstSample) else {
            throw AppError.exportFailed(reader.error?.localizedDescription ?? "No decoded frame was available for the DLSS 5 reference capture.")
        }

        // Prime temporal history with the first decoded frame, then capture the next
        // frame when available. This exercises the real Vision RG16F motion path for
        // ordinary video while preserving a valid first-frame fallback for one-frame
        // clips and cut boundaries.
        let temporal = try DLSS5TemporalVideoPreparer(
            depthProvider: DLSS5DepthProviderFactory.bestAvailable(),
            motionProvider: DLSS5VisionMotionProvider(accuracy: .high)
        )
        let firstTimestamp = CMSampleBufferGetPresentationTimeStamp(firstSample)
        let firstPrepared = try temporal.prepare(
            source: firstBuffer,
            presentationTime: firstTimestamp,
            frameIndex: 0,
            useJitter: false
        )

        let prepared: DLSS5PreparedFrame
        let timestamp: CMTime
        if let secondSample = output.copyNextSampleBuffer(),
           let secondBuffer = CMSampleBufferGetImageBuffer(secondSample) {
            let secondTimestamp = CMSampleBufferGetPresentationTimeStamp(secondSample)
            prepared = try temporal.prepare(
                source: secondBuffer,
                presentationTime: secondTimestamp,
                frameIndex: 1,
                useJitter: false
            )
            timestamp = secondTimestamp
        } else {
            prepared = firstPrepared
            timestamp = firstTimestamp
        }

        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DLSS5ReferenceCaptures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let backend = DLSS5ReferenceCaptureBackend()
        let manifest = try backend.capture(prepared, folder: root)
        let packageURL = root.appendingPathComponent("ClarityVideo-Frame.cvdlss5")
        try DLSS5PortableCaptureWriter.write(prepared, to: packageURL)
        _ = try DLSS5PortableCaptureWriter.validate(url: packageURL)

        return DLSS5ReferenceCaptureResult(
            folderURL: root,
            manifestURL: manifest,
            packageURL: packageURL,
            frameTimestampSeconds: timestamp.seconds.isFinite ? timestamp.seconds : safeStart,
            width: prepared.metadata.contract.renderWidth,
            height: prepared.metadata.contract.renderHeight
        )
    }
}
