import SwiftUI
import Observation
import AVFoundation
import CoreVideo
import CoreImage
import UIKit
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
    var lastSuccessfulSelfTest: Date?
    var diagnosticStillURL: URL?
    var diagnosticTestOutputURL: URL?
    var isRunningFiveSecondTest = false
    var thermalTransitions: [String] = []
    var comparisonPreview: ComparisonPreview?
    var previewProgress = 0.0
    var outputBytesSoFar: Int64 = 0
    var isGeneratingPreview = false
    var isPreparingModel = false
    private var pauseRequested = false
    let engine = VideoProcessingCoordinator()
    let capabilityDetector = CapabilityDetector()
    let backgroundExecution = BackgroundExecutionManager()
    let previewCoordinator = ComparisonPreviewCoordinator()

    init() {
        recentJobs = JobHistoryStore.load()
        if let snapshot = CapabilitySnapshotStore.loadForCurrentOS() {
            capabilities = snapshot.capabilities
            lastSuccessfulSelfTest = snapshot.lastSuccessfulSelfTest
        }
        Task { await refreshCapabilities() }
    }

    func refreshCapabilities() async {
        capabilities = await capabilityDetector.detect()
        if !capabilities.temporalNoiseFilteringAvailable { configuration.denoise = 0 }
        CapabilitySnapshotStore.save(capabilities: capabilities, lastSuccessfulSelfTest: lastSuccessfulSelfTest)
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

    func generateComparisonPreview() {
        guard let importedURL, let assetInfo else { return }
        isGeneratingPreview = true
        previewProgress = 0
        Task {
            defer { isGeneratingPreview = false }
            do {
                try StorageEstimator.validate(info: assetInfo, configuration: configuration)
                comparisonPreview = try await previewCoordinator.generate(
                    sourceURL: importedURL, sourceInfo: assetInfo, configuration: configuration
                ) { [weak self] progress in
                    Task { @MainActor in self?.previewProgress = progress }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelComparisonPreview() {
        previewCoordinator.cancel()
        isGeneratingPreview = false
    }

    func beginExport() {
        pauseRequested = false
        guard let importedURL, let assetInfo else { return }
        let output = TemporaryFileManager.outputURL(for: configuration.resolution)
        var job = ProcessingJob(sourceURL: importedURL, assetInfo: assetInfo, configuration: configuration)
        job.outputURL = output
        job.totalFrames = max(1, Int(assetInfo.duration * assetInfo.frameRate))
        if SegmentPlan.requiresSegmentation(duration: assetInfo.duration, configuration: configuration) {
            job.segmentCount = SegmentPlan.segments(duration: assetInfo.duration).count
        }
        outputBytesSoFar = 0
        activeJob = job
        route = .processing
        backgroundExecution.begin { [weak self] in self?.pauseExport() }
        Task {
            defer { backgroundExecution.end() }
            do {
                try StorageEstimator.validate(info: assetInfo, configuration: configuration)
                if assetInfo.isHDR && configuration.hdrBehavior == .preserve {
                    throw AppError.unsupported("Verified HDR preservation is not available yet for this AI path. Choose Convert to SDR; Clarity will not silently strip HDR metadata.")
                }
                if assetInfo.isHDR && configuration.hdrBehavior == .convertToSDR && configuration.resolution == .uhd8K {
                    throw AppError.unsupported("8K HDR-to-SDR export is disabled until its memory-safe tone-map path passes physical-device validation. Use 4K SDR conversion.")
                }
                guard configuration.resolution != .uhd8K || capabilities.supports8KHEVCEncode else {
                    throw AppError.unsupported("8K is hidden until this device passes the hardware encoder probe.")
                }
                var completed = try await engine.process(
                    job: job,
                    progress: { [weak self] progress in
                    Task { @MainActor in
                        self?.activeJob?.progress = progress
                        if let count = self?.activeJob?.segmentCount, count > 1 {
                            self?.activeJob?.currentSegment = min(count, Int(progress * Double(count)) + 1)
                        }
                        if let total = self?.activeJob?.totalFrames {
                            self?.activeJob?.processedFrames = min(total, Int(progress * Double(total)))
                        }
                    }
                },
                    outputBytes: { [weak self] bytes in
                        Task { @MainActor in self?.outputBytesSoFar = bytes }
                    }
                )
                completed.processingDuration = Date().timeIntervalSince(job.createdAt)
                activeJob = completed
                recentJobs.insert(completed, at: 0)
                JobHistoryStore.save(recentJobs)
                route = .results
            } catch is CancellationError {
                if pauseRequested, var paused = activeJob {
                    paused.status = .paused
                    activeJob = paused
                    recentJobs.removeAll { $0.id == paused.id }
                    recentJobs.insert(paused, at: 0)
                    JobHistoryStore.save(recentJobs)
                    route = .home
                } else {
                    activeJob?.status = .cancelled
                    if let output = activeJob?.outputURL { try? FileManager.default.removeItem(at: output) }
                    route = .editor
                }
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
            let stillFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Diagnostics", isDirectory: true)
            try FileManager.default.createDirectory(at: stillFolder, withIntermediateDirectories: true)
            let stillURL = stillFolder.appendingPathComponent("Clarity-AI-Self-Test.png")
            let image = CIImage(cvPixelBuffer: output)
            guard let cgImage = CIContext().createCGImage(image, from: image.extent),
                  let png = UIImage(cgImage: cgImage).pngData() else {
                throw AppError.exportFailed("The enhanced diagnostic still could not be encoded.")
            }
            try png.write(to: stillURL, options: .atomic)
            diagnosticStillURL = stillURL
            lastSuccessfulSelfTest = Date()
            CapabilitySnapshotStore.save(capabilities: capabilities, lastSuccessfulSelfTest: lastSuccessfulSelfTest)
            diagnosticStatus = "Passed: 1280x720 -> " + String(CVPixelBufferGetWidth(output)) + "x" + String(CVPixelBufferGetHeight(output)) + " with Apple SR"
            await refreshCapabilities()
        } catch {
            diagnosticStatus = "Failed: " + error.localizedDescription
            errorMessage = error.localizedDescription
            await refreshCapabilities()
        }
    }


    func runFiveSecondDiagnostic(resolution: OutputResolution = .uhd4K) {
        guard let importedURL, let assetInfo else {
            errorMessage = "Import a test video first, then return to Diagnostics."
            return
        }
        isRunningFiveSecondTest = true
        diagnosticStatus = "Running five-second " + resolution.rawValue + " AI export..."
        var testConfiguration = configuration
        testConfiguration.resolution = resolution
        if assetInfo.isHDR { testConfiguration.hdrBehavior = .convertToSDR }
        Task {
            defer { isRunningFiveSecondTest = false }
            do {
                if assetInfo.isHDR && resolution == .uhd8K {
                    throw AppError.unsupported("Use an SDR source for the 8K diagnostic until the memory-safe HDR tone-map path is device-validated.")
                }
                try StorageEstimator.validate(info: assetInfo, configuration: testConfiguration)
                let result = try await previewCoordinator.generate(
                    sourceURL: importedURL, sourceInfo: assetInfo,
                    configuration: testConfiguration, requestedDuration: 5
                ) { [weak self] progress in
                    Task { @MainActor in self?.previewProgress = progress }
                }
                diagnosticTestOutputURL = result.enhancedURL
                diagnosticStatus = String(format: "Passed five-second %@ export in %.1f seconds", resolution.rawValue, result.previewProcessingDuration)
            } catch {
                diagnosticStatus = "Five-second test failed: " + error.localizedDescription
            }
        }
    }

    func recordThermalTransition() {
        let state = String(describing: ProcessInfo.processInfo.thermalState)
        thermalTransitions.append(Date().formatted(date: .omitted, time: .standard) + " " + state)
    }

    func handleMemoryPressure() {
        guard route == .processing else { return }
        errorMessage = "Processing was paused because iOS reported memory pressure. Completed checkpoints were preserved."
        pauseExport()
    }

    func pauseExport() {
        pauseRequested = true
        engine.cancel()
    }

    func resume(_ job: ProcessingJob) {
        importedURL = job.sourceURL
        assetInfo = job.assetInfo
        configuration = job.configuration
        recentJobs.removeAll { $0.id == job.id }
        JobHistoryStore.save(recentJobs)
        beginExport()
    }

    func deleteActiveOutput() {
        guard let job = activeJob else { return }
        if let url = job.outputURL { try? FileManager.default.removeItem(at: url) }
        recentJobs.removeAll { $0.id == job.id }
        JobHistoryStore.save(recentJobs)
        activeJob = nil
        route = .home
    }

    func clearProcessingCache() {
        do {
            try ProcessingCache.clear()
            let previews = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ComparisonPreviews", isDirectory: true)
            try? FileManager.default.removeItem(at: previews)
            diagnosticStatus = "Processing cache cleared"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelExport() {
        engine.cancel()
    }
}
