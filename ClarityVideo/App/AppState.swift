import SwiftUI
import Observation
import AVFoundation
import CoreVideo
import CoreImage
import UIKit
import CoreMedia

private enum ConfigurationDefaultsStore {
    private static let key = "clarity.export-configuration.v2"

    static func load() -> ExportConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              var configuration = try? JSONDecoder().decode(ExportConfiguration.self, from: data) else {
            return ExportConfiguration()
        }
        configuration.clampBitrateToSupportedRange()
        return configuration
    }

    static func save(_ configuration: ExportConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor @Observable
final class AppState {
    enum Route { case home, importVideo, editor, exportSetup, processing, results }
    var route: Route = .home
    var importedURL: URL?
    var assetInfo: VideoAssetInfo?
    var configuration = ConfigurationDefaultsStore.load() {
        didSet { ConfigurationDefaultsStore.save(configuration) }
    }
    var capabilities = DeviceEnhancementCapabilities()
    var activeJob: ProcessingJob?
    var recentJobs: [ProcessingJob] = []
    var errorMessage: String?
    var isImporting = false
    var importStatus: String?
    var lastImportError: String?
    var lastImportedSummary: String?
    var showDiagnostics = false
    var diagnosticStatus = "Not run"
    var lastSuccessfulSelfTest: Date?
    var diagnosticStillURL: URL?
    var diagnosticTestOutputURL: URL?
    var isRunningFiveSecondTest = false
    var thermalTransitions: [String] = []
    var comparisonPreview: ComparisonPreview?
    var previewProgress = 0.0
    var previewErrorMessage: String?
    var previewStartSeconds = 0.0
    var previewDurationSeconds = 3.0
    var outputBytesSoFar: Int64 = 0
    var isGeneratingPreview = false
    var isPreparingModel = false
    var saveToPhotosAfterExport = UserDefaults.standard.object(
        forKey: "clarity.export.save-to-photos"
    ) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(
                saveToPhotosAfterExport,
                forKey: "clarity.export.save-to-photos"
            )
        }
    }
    var saveToFilesAfterExport = UserDefaults.standard.object(
        forKey: "clarity.export.save-to-files"
    ) as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(
                saveToFilesAfterExport,
                forKey: "clarity.export.save-to-files"
            )
        }
    }
    var pendingFilesExportURL: URL?
    private var pauseRequested = false
    let engine = VideoProcessingCoordinator()
    let capabilityDetector = CapabilityDetector()
    let backgroundExecution = BackgroundExecutionManager()
    let previewCoordinator = ComparisonPreviewCoordinator()

    init() {
        recentJobs = JobHistoryStore.load()

#if targetEnvironment(simulator)
        let isUISnapshot = ProcessInfo.processInfo.environment["CLARITY_UI_SNAPSHOT"] == "1"
#else
        let isUISnapshot = false
#endif

        if isUISnapshot {
            configuration = ExportConfiguration()
            var snapshotCapabilities = DeviceEnhancementCapabilities()
            snapshotCapabilities.fullSuperResolutionAvailable = true
            snapshotCapabilities.lowLatencySuperResolutionAvailable = true
            snapshotCapabilities.supportedFullScaleFactors = [2, 4]
            snapshotCapabilities.supportedLowLatencyScaleFactors = [1.5, 2.0]
            snapshotCapabilities.supportedLowLatency1080pScaleFactors = [2.0]
            snapshotCapabilities.temporalNoiseFilteringAvailable = true
            snapshotCapabilities.supports4KHEVCEncode = true
            snapshotCapabilities.supports8KHEVCEncode = true
            snapshotCapabilities.supportsMain10 = true
            snapshotCapabilities.modelReadiness = .ready
            snapshotCapabilities.osVersion = "iOS 27.0 (Build 24A5380h)"
            snapshotCapabilities.deviceModel = "iPhone17,3"
            capabilities = snapshotCapabilities

            let routeName = ProcessInfo.processInfo.environment["CLARITY_UI_ROUTE"]
            if routeName == "enhance"
                || routeName == "export"
                || routeName == "processing"
                || routeName == "processing-confirm"
                || routeName == "results"
                || routeName == "results-confirm" {
                let fixtureInfo = VideoAssetInfo(
                    fileName: "My Video.mov",
                    encodedWidth: 1920,
                    encodedHeight: 1080,
                    displayWidth: 1920,
                    displayHeight: 1080,
                    frameRate: 30,
                    codec: "HEVC",
                    isHDR: false,
                    duration: 19,
                    estimatedSourceBytes: 25_000_000
                )
                assetInfo = fixtureInfo

                if routeName == "processing"
                    || routeName == "processing-confirm"
                    || routeName == "results"
                    || routeName == "results-confirm" {
                    let source = FileManager.default.temporaryDirectory
                        .appendingPathComponent("Clarity-UI-source.mov")
                    let output = FileManager.default.temporaryDirectory
                        .appendingPathComponent("Clarity-UI-output.mov")
                    var job = ProcessingJob(
                        sourceURL: source,
                        assetInfo: fixtureInfo,
                        configuration: configuration
                    )
                    job.outputURL = output
                    job.totalFrames = 570
                    job.outputCodec = "HEVC (Apple AI upscale)"
                    job.denoiseMethod = "Apple temporal"

                    if routeName == "processing" || routeName == "processing-confirm" {
                        job.status = .processing
                        job.progress = 0.62
                        job.processedFrames = 353
                        outputBytesSoFar = 61_000_000
                    } else {
                        job.status = .completed
                        job.progress = 1
                        job.processedFrames = 570
                        job.processingDuration = 41.8
                    }
                    activeJob = job
                }
            }
        }

        // An interrupted import that was never turned into a resumable job has
        // no reason to survive the next launch. Keep only sources required by
        // paused jobs so abandoned imports cannot quietly occupy device storage.
        let resumableSources = Set(
            recentJobs
                .filter { $0.status == .paused }
                .map(\.sourceURL)
        )
        SecurityScopedFileManager.cleanupWorkspace(keeping: resumableSources)

        if let snapshot = CapabilitySnapshotStore.loadForCurrentOS() {
            capabilities = snapshot.capabilities
            lastSuccessfulSelfTest = snapshot.lastSuccessfulSelfTest
        }
        if let snapshotRoute = ProcessInfo.processInfo.environment["CLARITY_UI_ROUTE"] {
            switch snapshotRoute {
            case "home": route = .home
            case "import": route = .importVideo
            case "enhance": route = .editor
            case "export": route = .exportSetup
            case "processing", "processing-confirm": route = .processing
            case "results", "results-confirm": route = .results
            default: break
            }
        }
        if !isUISnapshot {
            Task { await refreshCapabilities() }
        }
    }

    func refreshCapabilities() async {
        capabilities = await capabilityDetector.detect()

        if !capabilities.temporalNoiseFilteringAvailable {
            configuration.denoise = 0
        }

        if !capabilities.supports8KHEVCEncode,
           configuration.resolution == .uhd8K {
            configuration.resolution = .uhd4K
            configuration.clampBitrateToSupportedRange()
        }

        if configuration.resolution == .uhd8K {
            configuration.codec = .hevc
        }

        if IOSNeuralHeadService.bundledModelURL() == nil,
           configuration.upscaler == .dlss5 {
            configuration.upscaler = .appleSR
        }

        CapabilitySnapshotStore.save(
            capabilities: capabilities,
            lastSuccessfulSelfTest: lastSuccessfulSelfTest
        )
    }
    func importVideo(from url: URL, sourceLabel: String = "video") async {
        errorMessage = nil
        previewErrorMessage = nil
        lastImportError = nil
        isImporting = true
        importStatus = "Copying " + sourceLabel + " into Clarity..."
        var copiedURL: URL?
        defer {
            isImporting = false
            importStatus = nil
        }
        do {
            let localURL = try SecurityScopedFileManager.copyToWorkspace(url)
            copiedURL = localURL
            if url.standardizedFileURL.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path) {
                try? FileManager.default.removeItem(at: url)
            }
            importStatus = "Reading video tracks and metadata..."
            let info = try await AssetInspector.inspect(localURL)
            guard info.duration > 0, info.encodedWidth > 0, info.encodedHeight > 0 else {
                throw AppError.importFailedReason("The selected video has invalid dimensions or duration.")
            }
            lastImportedSummary = info.fileName + " " + info.resolutionText + " " + info.durationText
            if let previous = importedURL, previous != localURL {
                SecurityScopedFileManager.removeWorkspaceCopyIfOwned(previous)
            }
            previewCoordinator.clearCache()
            comparisonPreview = nil
            importedURL = localURL
            assetInfo = info
            if info.isHDR { configuration.hdrBehavior = .convertToSDR }
            previewDurationSeconds = min(3, info.duration)
            previewStartSeconds = max(0, min(info.duration - previewDurationSeconds, info.duration * 0.25))
            route = .editor
        } catch {
            if let copiedURL { try? FileManager.default.removeItem(at: copiedURL) }
            lastImportError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func generateComparisonPreview() {
        guard let importedURL, let assetInfo else { return }
        isGeneratingPreview = true
        previewProgress = 0
        previewErrorMessage = nil
        Task {
            defer { isGeneratingPreview = false }
            do {
                comparisonPreview = try await previewCoordinator.generate(
                    sourceURL: importedURL, sourceInfo: assetInfo, configuration: configuration,
                    requestedDuration: previewDurationSeconds,
                    requestedStart: previewStartSeconds
                ) { [weak self] progress in
                    Task { @MainActor in self?.previewProgress = progress }
                }
            } catch is CancellationError {
                // Expected when the user changes enhancement controls and the
                // native comparison schedules a replacement preview.
            } catch {
                previewErrorMessage = error.localizedDescription
            }
        }
    }

    func cancelComparisonPreview() {
        previewCoordinator.clearCache()
        comparisonPreview = nil
        isGeneratingPreview = false
    }

    func beginExport() {
        pauseRequested = false
        pendingFilesExportURL = nil
        guard let importedURL, let assetInfo else { return }
        // Clamp legacy/recent-job settings so older 160–220 Mbps presets cannot
        // resurrect multi-gigabyte scratch-space requirements on short exports.
        configuration.clampBitrateToSupportedRange()
        if configuration.resolution == .uhd8K && !capabilities.supports8KHEVCEncode {
            errorMessage = "This device did not pass Clarity’s real 8K hardware encoder validation."
            return
        }
        if configuration.resolution == .uhd4K && configuration.codec == .hevc && !capabilities.supports4KHEVCEncode {
            errorMessage = "This device did not pass Clarity’s real 4K HEVC hardware encoder validation. Choose H.264 for 4K SDR or use a supported device."
            return
        }
        // The editor preview is disposable once an export starts. Clearing it
        // first makes the preflight reflect the export itself rather than stale
        // preview clips produced while the user tuned settings.
        previewCoordinator.clearCache()
        comparisonPreview = nil

        do {
            try StorageEstimator.validate(info: assetInfo, configuration: configuration)
        } catch {
            // Fail before changing routes so a storage issue stays on the export
            // screen instead of flashing the processing UI and then bouncing back.
            errorMessage = error.localizedDescription
            return
        }
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
                if configuration.codec == .h264 && (configuration.resolution == .uhd8K || assetInfo.isHDR) {
                    throw AppError.unsupported("H.264 is available only for 4K SDR exports. Choose HEVC for 8K or HDR sources.")
                }
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
                if saveToFilesAfterExport, let url = completed.outputURL {
                    pendingFilesExportURL = url
                }
                route = .results
                if saveToPhotosAfterExport, let url = completed.outputURL {
                    do { try await PhotosExportService.save(url) }
                    catch { errorMessage = "Export completed, but saving to Photos failed: " + error.localizedDescription }
                }
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
                    route = .exportSetup
                }
            } catch {
                if let output = activeJob?.outputURL {
                    try? FileManager.default.removeItem(at: output)
                }
                activeJob?.status = .failed
                activeJob?.errorMessage = error.localizedDescription
                errorMessage = error.localizedDescription
                route = .exportSetup
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


    func runRecoveredNeuralHeadSelfTest() async {
#if targetEnvironment(simulator)
        diagnosticStatus = "DLSS 5 neural inference must be validated on a physical iPhone."
        return
#else
        guard let modelURL = IOSNeuralHeadService.bundledModelURL() else {
            diagnosticStatus = "DLSS 5 neural model is not bundled in this build."
            return
        }

        isPreparingModel = true
        diagnosticStatus = "Loading DLSS 5 neural model..."
        defer { isPreparingModel = false }

        do {
            let renderer = try IOSNeuralHeadService(modelURL: modelURL)
            let attributes: [String: Any] = [
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            var source: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                IOSNeuralHeadService.tileSize,
                IOSNeuralHeadService.tileSize,
                kCVPixelFormatType_32BGRA,
                attributes as CFDictionary,
                &source
            )
            guard status == kCVReturnSuccess, let source else {
                throw IOSNeuralHeadService.Failure.pixelBuffer(status)
            }

            CVPixelBufferLockBaseAddress(source, [])
            if let base = CVPixelBufferGetBaseAddress(source)?.assumingMemoryBound(to: UInt8.self) {
                let stride = CVPixelBufferGetBytesPerRow(source)
                for y in 0..<IOSNeuralHeadService.tileSize {
                    for x in 0..<IOSNeuralHeadService.tileSize {
                        let offset = y * stride + x * 4
                        base[offset] = UInt8(48 + (x * 160 / IOSNeuralHeadService.tileSize))
                        base[offset + 1] = UInt8(48 + (y * 160 / IOSNeuralHeadService.tileSize))
                        base[offset + 2] = 160
                        base[offset + 3] = 255
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(source, [])

            let start = ContinuousClock.now
            let output = try await renderer.render(source: source, frameNumber: 0)
            let elapsed = start.duration(to: .now)

            guard CVPixelBufferGetWidth(output) == IOSNeuralHeadService.tileSize,
                  CVPixelBufferGetHeight(output) == IOSNeuralHeadService.tileSize else {
                throw IOSNeuralHeadService.Failure.incompatibleModel
            }

            let components = elapsed.components
            let seconds = Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000
            diagnosticStatus = String(
                format: "DLSS 5 neural test passed: 128x128 tile in %.3f s (%.2f tiles/s)",
                seconds,
                1 / max(seconds, 0.000_001)
            )
            lastSuccessfulSelfTest = Date()
            CapabilitySnapshotStore.save(
                capabilities: capabilities,
                lastSuccessfulSelfTest: lastSuccessfulSelfTest
            )
        } catch {
            diagnosticStatus = "DLSS 5 neural test failed: " + error.localizedDescription
            errorMessage = error.localizedDescription
        }
#endif
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

    func leaveCompletedResult(startAnother: Bool = false) {
        if let job = activeJob, job.status == .completed {
            SecurityScopedFileManager.removeWorkspaceCopyIfOwned(job.sourceURL)
        }
        previewCoordinator.clearCache()
        importedURL = nil
        assetInfo = nil
        comparisonPreview = nil
        previewErrorMessage = nil
        route = startAnother ? .importVideo : .home
    }

    func deleteRecentJob(_ job: ProcessingJob) {
        if let output = job.outputURL {
            try? FileManager.default.removeItem(at: output)
        }
        SecurityScopedFileManager.removeWorkspaceCopyIfOwned(job.sourceURL)
        recentJobs.removeAll { $0.id == job.id }
        JobHistoryStore.save(recentJobs)

        if activeJob?.id == job.id {
            activeJob = nil
        }
        if pendingFilesExportURL == job.outputURL {
            pendingFilesExportURL = nil
        }
    }

    func deleteActiveOutput() {
        guard let job = activeJob else { return }
        if let url = job.outputURL { try? FileManager.default.removeItem(at: url) }
        SecurityScopedFileManager.removeWorkspaceCopyIfOwned(job.sourceURL)
        recentJobs.removeAll { $0.id == job.id }
        JobHistoryStore.save(recentJobs)
        if pendingFilesExportURL == job.outputURL {
            pendingFilesExportURL = nil
        }
        activeJob = nil
        route = .home
    }

    func clearProcessingCache() {
        do {
            try ProcessingCache.clear()

            previewCoordinator.clearCache()
            comparisonPreview = nil

            var keepImports = Set(
                recentJobs
                    .filter { $0.status == .paused }
                    .map(\.sourceURL)
            )
            if let importedURL {
                keepImports.insert(importedURL)
            }
            SecurityScopedFileManager.cleanupWorkspace(keeping: keepImports)

            diagnosticStatus = "Temporary processing files cleared"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelExport() {
        engine.cancel()
    }
}
