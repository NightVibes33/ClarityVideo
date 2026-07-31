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
    var resolutionText: String { "\(displayWidth) \u{00D7} \(displayHeight)" }
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

enum OutputCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case hevc = "HEVC"
    case h264 = "H.264"
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
    var codec: OutputCodec = .hevc
    var hdrBehavior: HDRBehavior = .preserve
    var preserveFrameRate = true
}

extension ExportConfiguration {
    mutating func applyPreset(_ mode: EnhancementMode, temporalDenoiseAvailable: Bool) {
        self.mode = mode
        switch mode {
        case .fast:
            denoise = temporalDenoiseAvailable ? 0.08 : 0
            detailRecovery = 0.25
            sharpening = 0.10
        case .quality:
            denoise = temporalDenoiseAvailable ? 0.20 : 0
            detailRecovery = 0.50
            sharpening = 0.15
        case .restore:
            denoise = temporalDenoiseAvailable ? 0.65 : 0
            detailRecovery = 0.55
            sharpening = 0.10
        case .anime:
            denoise = temporalDenoiseAvailable ? 0.10 : 0
            detailRecovery = 0.70
            sharpening = 0.35
        }
    }
}

struct DeviceEnhancementCapabilities: Codable, Equatable, Sendable {
    var fullSuperResolutionAvailable = false
    var lowLatencySuperResolutionAvailable = false
    var supportedFullScaleFactors: [Int] = []
    var supportedLowLatencyScaleFactors: [Double] = []
    var supportedLowLatency1080pScaleFactors: [Double] = []
    var supportedProcessorRevisions: [Int] = []
    var defaultProcessorRevision: Int?
    var sourcePixelFormats: [UInt32] = []
    var destinationPixelFormats: [UInt32] = []
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
    var processingDuration: Double?
    var errorMessage: String?
    var outputCodec: String?
    var createdAt = Date()
}

struct ProcessingCheckpoint: Codable, Sendable {
    var jobID: UUID
    var sourceFingerprint: String
    var configuration: ExportConfiguration
    var completedSegments: [Int]
    var completedSegmentFiles: [String: URL]
    var expectedSegmentCount: Int
    var lastPresentationSeconds: Double
    var osBuild: String
    var appBuild: String
    var pipelineVersion: Int
    var updatedAt: Date

    init(
        jobID: UUID, sourceFingerprint: String, configuration: ExportConfiguration,
        completedSegments: [Int] = [], completedSegmentFiles: [String: URL] = [:],
        expectedSegmentCount: Int, lastPresentationSeconds: Double = 0,
        osBuild: String = ProcessInfo.processInfo.operatingSystemVersionString,
        appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
        pipelineVersion: Int = 2,
        updatedAt: Date = Date()
    ) {
        self.jobID = jobID
        self.sourceFingerprint = sourceFingerprint
        self.configuration = configuration
        self.completedSegments = completedSegments
        self.completedSegmentFiles = completedSegmentFiles
        self.expectedSegmentCount = expectedSegmentCount
        self.lastPresentationSeconds = lastPresentationSeconds
        self.osBuild = osBuild
        self.appBuild = appBuild
        self.pipelineVersion = pipelineVersion
        self.updatedAt = updatedAt
    }

    func isCompatible(sourceFingerprint: String, configuration: ExportConfiguration, segmentCount: Int) -> Bool {
        self.sourceFingerprint == sourceFingerprint
            && self.configuration == configuration
            && expectedSegmentCount == segmentCount
            && osBuild == ProcessInfo.processInfo.operatingSystemVersionString
            && appBuild == (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
            && pipelineVersion == 2
            && completedSegments.allSatisfy { index in
                guard let url = completedSegmentFiles[String(index)] else { return false }
                return FileManager.default.fileExists(atPath: url.path)
            }
    }
}

struct DiagnosticReport: Codable, Sendable {
    var generatedAt = Date()
    var appVersion: String
    var appBuild: String
    var sourceRevision: String
    var capabilities: DeviceEnhancementCapabilities
    var configurationAttempts: [String]
    var exactErrors: [String]
    var processorRevision: String?
    var modelStatus: String
    var encoderResults: [String: Bool]
    var peakMemoryBytes: UInt64?
    var thermalTransitions: [String]
    var diagnosticStatus: String
    var lastSuccessfulSelfTest: Date?
    var lastImportedSummary: String?
    var enhancedStillCreated: Bool
    var diagnosticVideoCreated: Bool
    var activeJobStatus: String?
    var activeJobError: String?
    var processingFPS: Double?
}
