import Foundation
import AVFoundation
import VideoToolbox
import Photos
import UIKit

enum AppError: LocalizedError {
    case noVideoTrack
    case importFailed
    case insufficientStorage(required: Int64, available: Int64)
    case unsupported(String)
    case exportFailed(String)
    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "The selected file has no readable video track."
        case .importFailed: "The selected video could not be copied into the private workspace."
        case let .insufficientStorage(required, available): "Not enough free storage. Required \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)); available \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))."
        case let .unsupported(message): message
        case let .exportFailed(message): message
        }
    }
}

enum SecurityScopedFileManager {
    static func copyToWorkspace(_ source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            throw AppError.importFailed
        }
    }
}

enum AssetInspector {
    static func inspect(_ url: URL) async throws -> VideoAssetInfo {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw AppError.noVideoTrack }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = size.applying(transform)
        let displayWidth = Int(abs(transformed.width).rounded())
        let displayHeight = Int(abs(transformed.height).rounded())
        let rate = Double(try await track.load(.nominalFrameRate))
        let duration = try await asset.load(.duration).seconds
        let descriptions = try await track.load(.formatDescriptions)
        let format = descriptions.first
        let subtype = format.map(CMFormatDescriptionGetMediaSubType) ?? 0
        let extensions = format.flatMap { CMFormatDescriptionGetExtensions($0) as? [String: Any] } ?? [:]
        let transfer = String(describing: extensions[kCMFormatDescriptionExtension_TransferFunction as String] ?? "")
        let isHDR = transfer.localizedCaseInsensitiveContains("HLG") || transfer.localizedCaseInsensitiveContains("PQ") || transfer.localizedCaseInsensitiveContains("2084")
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return VideoAssetInfo(
            fileName: url.lastPathComponent,
            encodedWidth: Int(abs(size.width)),
            encodedHeight: Int(abs(size.height)),
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            frameRate: rate,
            codec: fourCC(subtype),
            isHDR: isHDR,
            duration: duration.isFinite ? duration : 0,
            estimatedSourceBytes: Int64(values.fileSize ?? 0)
        )
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff), UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
    }
}

@MainActor
final class CapabilityDetector {
    func detect() async -> DeviceEnhancementCapabilities {
        var result = DeviceEnhancementCapabilities()
        result.deviceModel = UIDevice.current.model
        let appleProbe = AppleFrameProcessorService.probe()
        result.fullSuperResolutionAvailable = appleProbe.fullSupported
        result.lowLatencySuperResolutionAvailable = appleProbe.lowLatencySupported
        result.temporalNoiseFilteringAvailable = appleProbe.temporalNoiseSupported
        result.supportedFullScaleFactors = appleProbe.fullScaleFactors
        result.supportedLowLatencyScaleFactors = appleProbe.lowLatency720pScaleFactors
        result.supportedProcessorRevisions = appleProbe.supportedRevisions
        result.defaultProcessorRevision = appleProbe.defaultRevision
        result.sourcePixelFormats = appleProbe.sourcePixelFormats
        result.destinationPixelFormats = appleProbe.destinationPixelFormats
        result.maximumSafeInputSize = appleProbe.maximumConfiguredInput
        result.modelReadiness = appleProbe.modelReadiness
        result.modelDownloadProgress = appleProbe.modelProgress
        result.lastProbeError = appleProbe.error
        result.supports4KHEVCEncode = encoderProbe(width: 3840, height: 2160, main10: false)
        result.supports8KHEVCEncode = encoderProbe(width: 7680, height: 4320, main10: false)
        result.supportsMain10 = encoderProbe(width: 3840, height: 2160, main10: true)
        if result.supports8KHEVCEncode { result.maximumSafeOutputSize = CGSize(width: 7680, height: 4320) }
        else if result.supports4KHEVCEncode { result.maximumSafeOutputSize = CGSize(width: 3840, height: 2160) }
        return result
    }

    private func encoderProbe(width: Int32, height: Int32, main10: Bool) -> Bool {
        var session: VTCompressionSession?
        let specification = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true] as CFDictionary
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: specification,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr, let session else { return false }
        defer { VTCompressionSessionInvalidate(session) }
        if main10 {
            let profile = kVTProfileLevel_HEVC_Main10_AutoLevel
            guard VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: profile) == noErr else { return false }
        }
        return VTCompressionSessionPrepareToEncodeFrames(session) == noErr
    }
}

enum StorageEstimator {
    static func estimatedOutputBytes(info: VideoAssetInfo, configuration: ExportConfiguration) -> Int64 {
        Int64(Double(configuration.bitrateMbps) * 1_000_000 / 8 * info.duration)
    }
    static func requiredBytes(info: VideoAssetInfo, configuration: ExportConfiguration) -> Int64 {
        let output = estimatedOutputBytes(info: info, configuration: configuration)
        let temporary = output + (configuration.resolution == .uhd8K ? output / 4 : output / 10)
        return output + temporary + 1_000_000_000
    }
    static func validate(info: VideoAssetInfo, configuration: ExportConfiguration) throws {
        let required = requiredBytes(info: info, configuration: configuration)
        let home = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let values = try home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        guard available >= required else { throw AppError.insufficientStorage(required: required, available: available) }
    }
}

enum TemporaryFileManager {
    static func outputURL(for resolution: OutputResolution) -> URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Clarity-\(resolution.rawValue.replacingOccurrences(of: " ", with: "-"))-\(UUID().uuidString).mov")
    }
}

enum PhotosExportService {
    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw AppError.unsupported("Photos access was not granted.") }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

enum OutputValidator {
    static func validate(
        outputURL: URL,
        sourceURL: URL,
        info: VideoAssetInfo,
        configuration: ExportConfiguration
    ) async throws {
        let output = AVURLAsset(url: outputURL)
        guard try await output.load(.isPlayable),
              let video = try await output.loadTracks(withMediaType: .video).first else {
            throw AppError.exportFailed("The completed output could not be reopened as playable video.")
        }
        let natural = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let display = CGRect(origin: .zero, size: natural).applying(transform).standardized.size
        let landscape = configuration.resolution.landscapeSize
        let expectedWidth = info.isPortrait ? landscape.height : landscape.width
        let expectedHeight = info.isPortrait ? landscape.width : landscape.height
        guard abs(abs(display.width) - expectedWidth) < 1,
              abs(abs(display.height) - expectedHeight) < 1 else {
            throw AppError.exportFailed("Output validation found unexpected dimensions: \(Int(abs(display.width)))x\(Int(abs(display.height))).")
        }

        let source = AVURLAsset(url: sourceURL)
        let sourceHasAudio = !(try await source.loadTracks(withMediaType: .audio)).isEmpty
        let outputAudio = try await output.loadTracks(withMediaType: .audio).first
        if sourceHasAudio && outputAudio == nil {
            throw AppError.exportFailed("The completed output is missing the source audio track.")
        }
        if let outputAudio {
            let videoRange = try await video.load(.timeRange)
            let audioRange = try await outputAudio.load(.timeRange)
            let durationDrift = abs(videoRange.duration.seconds - audioRange.duration.seconds)
            let startDrift = abs(videoRange.start.seconds - audioRange.start.seconds)
            let frameDuration = 1 / max(1, info.frameRate)
            guard durationDrift <= frameDuration, startDrift <= frameDuration else {
                throw AppError.exportFailed(String(
                    format: "Audio validation failed (duration drift %.4fs, start drift %.4fs).",
                    durationDrift, startDrift
                ))
            }
        }
    }
}
