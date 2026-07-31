import SwiftUI
import Observation
import AVFoundation
import CoreVideo
import CoreMedia

@MainActor @Observable
final class AppState {
    enum Route { case home, editor, processing, results }
    var route: Route = .home
    var importedURL: URL?
    var assetInfo: VideoAssetInfo?
    var configuration = ExportConfiguration()
    var capabilities = DeviceEnhancementCapabilities()
    var activeJob: ProcessingJob?
    var recentJobs: [ProcessingJob] = []
    var errorMessage: String?
    var isImporting = false
    var showDiagnostics = false
    var diagnosticStatus = "Not run"
    var isPreparingModel = false
    let engine = VideoProcessingCoordinator()
    let capabilityDetector = CapabilityDetector()

    init() {
        Task { await refreshCapabilities() }
    }

    func refreshCapabilities() async {
        capabilities = await capabilityDetector.detect()
    }

    func importVideo(from url: URL) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let localURL = try SecurityScopedFileManager.copyToWorkspace(url)
            let info = try await AssetInspector.inspect(localURL)
            importedURL = localURL
            assetInfo = info
            route = .editor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginExport() {
        guard let importedURL, let assetInfo else { return }
        let output = TemporaryFileManager.outputURL(for: configuration.resolution)
        var job = ProcessingJob(sourceURL: importedURL, assetInfo: assetInfo, configuration: configuration)
        job.outputURL = output
        job.totalFrames = max(1, Int(assetInfo.duration * assetInfo.frameRate))
        activeJob = job
        route = .processing
        Task {
            do {
                try StorageEstimator.validate(info: assetInfo, configuration: configuration)
                guard configuration.resolution != .uhd8K || capabilities.supports8KHEVCEncode else {
                    throw AppError.unsupported("8K is hidden until this device passes the hardware encoder probe.")
                }
                let completed = try await engine.process(job: job) { [weak self] progress in
                    Task { @MainActor in self?.activeJob?.progress = progress }
                }
                activeJob = completed
                recentJobs.insert(completed, at: 0)
                route = .results
            } catch is CancellationError {
                activeJob?.status = .cancelled
                if let output = activeJob?.outputURL { try? FileManager.default.removeItem(at: output) }
                route = .editor
            } catch {
                activeJob?.status = .failed
                activeJob?.errorMessage = error.localizedDescription
                errorMessage = error.localizedDescription
                route = .editor
            }
        }
    }

    func prepareModelAndRunSelfTest() async {
        guard let scale = capabilities.supportedFullScaleFactors.first else {
            diagnosticStatus = "No supported full-quality AI scale"
            return
        }
        isPreparingModel = true
        diagnosticStatus = "Preparing Apple enhancement model..."
        defer { isPreparingModel = false }
        do {
            _ = try await AppleFrameProcessorService.prepareModel(width: 1280, height: 720, scaleFactor: scale)
            diagnosticStatus = "Running one-frame AI test..."
            let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()] as CFDictionary
            var source: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, 1280, 720, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes, &source)
            guard status == kCVReturnSuccess, let source else { throw AppleFrameProcessorError.pixelBufferCreation(status) }
            CVPixelBufferLockBaseAddress(source, [])
            if let y = CVPixelBufferGetBaseAddressOfPlane(source, 0) { memset(y, 96, CVPixelBufferGetBytesPerRowOfPlane(source, 0) * 720) }
            if let uv = CVPixelBufferGetBaseAddressOfPlane(source, 1) { memset(uv, 128, CVPixelBufferGetBytesPerRowOfPlane(source, 1) * 360) }
            CVPixelBufferUnlockBaseAddress(source, [])
            let output = try await AppleFrameProcessorService().processFullQuality(source: source, presentationTime: .zero, scaleFactor: scale, sequential: false)
            diagnosticStatus = "Passed: 1280x720 -> " + String(CVPixelBufferGetWidth(output)) + "x" + String(CVPixelBufferGetHeight(output)) + " with Apple SR"
            await refreshCapabilities()
        } catch {
            diagnosticStatus = "Failed: " + error.localizedDescription
            errorMessage = error.localizedDescription
            await refreshCapabilities()
        }
    }


    func cancelExport() {
        engine.cancel()
    }
}
