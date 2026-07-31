import Foundation
import CoreGraphics
import CoreMedia

struct VideoAssetInfo: Codable, Equatable, Sendable {
    var fileName: String
    var encodedWidth: Int
    var encodedHeight: Int
    var displayWidth: Int
    var displayHeight: Int
    var frameRate: Double
    var codec: String
    var isHDR: Bool
    var duration: Double
    var estimatedSourceBytes: Int64
    var isPortrait: Bool { displayHeight > displayWidth }
    var resolutionText: String { "\(displayWidth) Ã \(displayHeight)" }
    var durationText: String {
        let seconds = Int(duration.rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

enum OutputResolution: String, Codable, CaseIterable, Identifiable, Sendable {
    case uhd4K = "4K UHD"
    case uhd8K = "8K UHD"
    var id: String { rawValue }
    var landscapeSize: CGSize {
        switch self {
        case .uhd4K: CGSize(width: 3840, height: 2160)
        case .uhd8K: CGSize(width: 7680, height: 4320)
        }
    }
}

enum EnhancementMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fast = "Fast"
    case quality = "Quality"
    case restore = "Restore Old Video"
    case anime = "Anime & Game"
    var id: String { rawValue }
}

enum HDRBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case preserve = "Preserve HDR"
    case convertToSDR = "Convert to SDR"
    var id: String { rawValue }
}

struct ExportConfiguration: Codable, Equatable, Sendable {
    var resolution: OutputResolution = .uhd4K
    var mode: EnhancementMode = .quality
    var denoise = 0.2
    var detailRecovery = 0.5
    var sharpening = 0.15
    var bitrateMbps = 55
    var hdrBehavior: HDRBehavior = .preserve
    var preserveFrameRate = true
}

struct DeviceEnhancementCapabilities: Codable, Equatable, Sendable {
    var fullSuperResolutionAvailable = false
    var lowLatencySuperResolutionAvailable = false
    var supportedFullScaleFactors: [Int] = []
    var supportedLowLatencyScaleFactors: [Double] = []
    var supportedProcessorRevisions: [Int] = []
    var defaultProcessorRevision: Int?
    var modelReadiness: AppleModelReadiness = .unavailable
    var modelDownloadProgress = 0.0
    var temporalNoiseFilteringAvailable = false
    var supports4KHEVCEncode = false
    var supports8KHEVCEncode = false
    var supportsMain10 = false
    var maximumSafeInputSize: CGSize?
    var maximumSafeOutputSize: CGSize?
    var osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    var deviceModel = "Unknown"
    var lastProbeError: String?
}

enum JobStatus: String, Codable, Sendable {
    case queued, preparing, processing, paused, completed, cancelled, failed
}

struct ProcessingJob: Codable, Identifiable, Sendable {
    var id = UUID()
    var sourceURL: URL
    var outputURL: URL?
    var assetInfo: VideoAssetInfo
    var configuration: ExportConfiguration
    var status: JobStatus = .queued
    var progress = 0.0
    var processedFrames = 0
    var totalFrames = 0
    var currentSegment = 0
    var segmentCount = 1
    var errorMessage: String?
    var createdAt = Date()
}

struct ProcessingCheckpoint: Codable, Sendable {
    var jobID: UUID
    var sourceFingerprint: String
    var configuration: ExportConfiguration
    var completedSegments: [Int]
    var lastPresentationSeconds: Double
    var updatedAt = Date()
}

struct DiagnosticReport: Codable, Sendable {
    var generatedAt = Date()
    var capabilities: DeviceEnhancementCapabilities
    var configurationAttempts: [String]
    var exactErrors: [String]
    var processorRevision: String?
    var modelStatus: String
    var encoderResults: [String: Bool]
    var peakMemoryBytes: UInt64
    var thermalTransitions: [String]
    var processingFPS: Double?
}
