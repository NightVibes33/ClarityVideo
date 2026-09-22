import XCTest
@testable import ClarityVideo

final class ClarityVideoTests: XCTestCase {

    func testSpatialNoiseParametersRemainInsideDocumentedFilterRange() {
        let minimum = SpatialNoiseParameters(strength: -1)
        let maximum = SpatialNoiseParameters(strength: 2)
        XCTAssertEqual(minimum.noiseLevel, 0.005, accuracy: 0.0001)
        XCTAssertEqual(minimum.sharpness, 0.60, accuracy: 0.0001)
        XCTAssertEqual(maximum.noiseLevel, 0.05, accuracy: 0.0001)
        XCTAssertEqual(maximum.sharpness, 0.40, accuracy: 0.0001)
    }

    func testPreviewSelectionClampsToTwoToFiveSecondsAndSourceEnd() {
        XCTAssertEqual(
            PreviewSelection.resolve(sourceDuration: 20, requestedStart: 19, requestedDuration: 9),
            PreviewSelection(startSeconds: 15, durationSeconds: 5)
        )
        XCTAssertEqual(
            PreviewSelection.resolve(sourceDuration: 20, requestedStart: -4, requestedDuration: 1),
            PreviewSelection(startSeconds: 0, durationSeconds: 2)
        )
    }

    func testPreviewSelectionSupportsShortSources() {
        XCTAssertEqual(
            PreviewSelection.resolve(sourceDuration: 1.25, requestedStart: 1, requestedDuration: 3),
            PreviewSelection(startSeconds: 0, durationSeconds: 1.25)
        )
    }

    func testStorageEstimateIncludesSafetyAndTemporarySpace() {
        let info = VideoAssetInfo(fileName: "test.mov", encodedWidth: 1920, encodedHeight: 1080, displayWidth: 1920, displayHeight: 1080, frameRate: 30, codec: "hvc1", isHDR: false, duration: 60, estimatedSourceBytes: 10)
        let required = StorageEstimator.requiredBytes(info: info, configuration: ExportConfiguration())
        XCTAssertGreaterThan(required, 55 * 1_000_000 / 8 * 60)
    }

    func testShort4KExportDoesNotReserveOneGigabyte() {
        let info = VideoAssetInfo(
            fileName: "short.mov",
            encodedWidth: 1920,
            encodedHeight: 1080,
            displayWidth: 1920,
            displayHeight: 1080,
            frameRate: 30,
            codec: "hvc1",
            isHDR: false,
            duration: 19,
            estimatedSourceBytes: 25_000_000
        )
        var configuration = ExportConfiguration()
        configuration.resolution = .uhd4K
        configuration.bitrateMbps = 55
        let output = StorageEstimator.estimatedOutputBytes(info: info, configuration: configuration)
        let required = StorageEstimator.requiredBytes(info: info, configuration: configuration)
        XCTAssertGreaterThan(required, output)
        XCTAssertLessThan(required, 400_000_000)
    }


    func testShort4KStorageBudgetTracksOutputInsteadOfGigabytes() {
        let info = VideoAssetInfo(
            fileName: "short.mov",
            encodedWidth: 1920,
            encodedHeight: 1080,
            displayWidth: 1920,
            displayHeight: 1080,
            frameRate: 30,
            codec: "hvc1",
            isHDR: false,
            duration: 19,
            estimatedSourceBytes: 25_000_000
        )
        var configuration = ExportConfiguration()
        configuration.resolution = .uhd4K
        configuration.bitrateMbps = 40

        let output = StorageEstimator.estimatedOutputBytes(info: info, configuration: configuration)
        let required = StorageEstimator.requiredBytes(info: info, configuration: configuration)

        XCTAssertEqual(output, 95_000_000)
        XCTAssertEqual(required, 286_000_000)
    }

    @MainActor
    func testComparisonPreviewCacheDoesNotAccumulate() throws {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ComparisonPreviews", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stale = folder.appendingPathComponent("stale-preview.mov")
        try Data(repeating: 0x41, count: 1024).write(to: stale)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stale.path))

        let coordinator = ComparisonPreviewCoordinator()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 1024).write(to: stale)
        coordinator.clearCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testPortraitDetectionUsesDisplayDimensions() {
        let info = VideoAssetInfo(fileName: "portrait.mov", encodedWidth: 1920, encodedHeight: 1080, displayWidth: 1080, displayHeight: 1920, frameRate: 30, codec: "hvc1", isHDR: true, duration: 5, estimatedSourceBytes: 1)
        XCTAssertTrue(info.isPortrait)
    }

    func test8KDimensionsAreStandardUHD() {
        XCTAssertEqual(OutputResolution.uhd8K.landscapeSize.width, 7680)
        XCTAssertEqual(OutputResolution.uhd8K.landscapeSize.height, 4320)
    }
}

extension ClarityVideoTests {
    func testNative4KInputAvoidsOversizedAIIntermediate() throws {
        var caps = DeviceEnhancementCapabilities()
        caps.fullSuperResolutionAvailable = true
        caps.supportedFullScaleFactors = [4]
        let plan = try PipelinePlanner.plan(
            sourceWidth: 3840, sourceHeight: 2160, target: .uhd4K, qualityPreset: .quality,
            capabilities: caps, lowLatencyFactorsForSource: []
        )
        XCTAssertEqual(plan.route, .nativeEnhancement)
        XCTAssertEqual(plan.aiScaleFactor, 1)
        XCTAssertFalse(plan.requiresFinalResize)
    }

    func test1080pTo4KAvoidsEightKHalfFloatIntermediate() throws {
        var caps = DeviceEnhancementCapabilities()
        caps.fullSuperResolutionAvailable = true
        caps.supportedFullScaleFactors = [4]
        let plan = try PipelinePlanner.plan(
            sourceWidth: 1920, sourceHeight: 1080, target: .uhd4K, qualityPreset: .quality,
            capabilities: caps, lowLatencyFactorsForSource: []
        )
        XCTAssertEqual(plan.route, .tiledSuperResolution)
        XCTAssertTrue(plan.requiresFinalResize)
    }

    func test4KTo8KUsesTiledNeuralRouteWhenOnlyFourXIsAvailable() throws {
        var caps = DeviceEnhancementCapabilities()
        caps.fullSuperResolutionAvailable = true
        caps.supportedFullScaleFactors = [4]
        let plan = try PipelinePlanner.plan(
            sourceWidth: 3840, sourceHeight: 2160, target: .uhd8K, qualityPreset: .quality,
            capabilities: caps, lowLatencyFactorsForSource: []
        )
        XCTAssertEqual(plan.route, .tiledSuperResolution)
        XCTAssertEqual(plan.aiScaleFactor, 4)
        XCTAssertTrue(plan.requiresFinalResize)
        XCTAssertTrue(plan.disclosure.contains("tiles"))
    }

    func testRequestedUpscaleFailsWhenNoNeuralRouteExists() {
        XCTAssertThrowsError(
            try PipelinePlanner.plan(
                sourceWidth: 1920, sourceHeight: 1080, target: .uhd4K, qualityPreset: .quality,
                capabilities: DeviceEnhancementCapabilities(), lowLatencyFactorsForSource: []
            )
        ) { error in
            XCTAssertTrue(error is PipelinePlanningError)
        }
    }

    func testPlannerAvoidsLargeHalfFloatCanvasFor720pTo4K() throws {
        var caps = DeviceEnhancementCapabilities()
        caps.fullSuperResolutionAvailable = true
        caps.supportedFullScaleFactors = [2, 4]
        let plan = try PipelinePlanner.plan(
            sourceWidth: 1280, sourceHeight: 720, target: .uhd4K, qualityPreset: .quality,
            capabilities: caps, lowLatencyFactorsForSource: []
        )
        XCTAssertEqual(plan.route, .tiledSuperResolution)
        XCTAssertEqual(plan.aiScaleFactor, 4)
        XCTAssertTrue(plan.requiresFinalResize)
    }

    func testPlannerUsesLowLatencyForFullHDWhenSupported() throws {
        var caps = DeviceEnhancementCapabilities()
        caps.fullSuperResolutionAvailable = true
        caps.lowLatencySuperResolutionAvailable = true
        caps.supportedFullScaleFactors = [2, 4]
        let plan = try PipelinePlanner.plan(
            sourceWidth: 1920, sourceHeight: 1080, target: .uhd4K, qualityPreset: .quality,
            capabilities: caps, lowLatencyFactorsForSource: [2]
        )
        XCTAssertEqual(plan.route, .lowLatencySuperResolution)
        XCTAssertFalse(plan.requiresFinalResize)
    }

    func testPlannerLabelsMemorySafe8KFallback() throws {
        var caps = DeviceEnhancementCapabilities()
        caps.fullSuperResolutionAvailable = true
        caps.supportedFullScaleFactors = [2, 4]
        let plan = try PipelinePlanner.plan(
            sourceWidth: 1280, sourceHeight: 720, target: .uhd8K, qualityPreset: .quality,
            capabilities: caps, lowLatencyFactorsForSource: []
        )
        XCTAssertEqual(plan.route, .tiledSuperResolution)
        XCTAssertTrue(plan.requiresFinalResize)
        XCTAssertTrue(plan.disclosure.contains("tiles"))
    }

    func testPlannerTiles4KTo8KWithoutLowLatencyRoute() throws {
        var caps = DeviceEnhancementCapabilities()
        caps.fullSuperResolutionAvailable = true
        caps.supportedFullScaleFactors = [2]
        let plan = try PipelinePlanner.plan(
            sourceWidth: 3840, sourceHeight: 2160, target: .uhd8K, qualityPreset: .quality,
            capabilities: caps, lowLatencyFactorsForSource: []
        )
        XCTAssertEqual(plan.route, .tiledSuperResolution)
        XCTAssertFalse(plan.requiresFinalResize) // Exact 2× tiles write directly into the 8K output.
        XCTAssertTrue(plan.disclosure.contains("tiles"))
    }
}

extension ClarityVideoTests {
    func testTileLayoutCoversFrameAndKeepsConsistentTileSize() {
        let regions = TileLayout.regions(
            frameWidth: 3840, frameHeight: 2160,
            tileWidth: 960, tileHeight: 540, overlap: 32
        )
        XCTAssertFalse(regions.isEmpty)
        XCTAssertTrue(regions.allSatisfy { $0.width == 960 && $0.height == 540 })
        XCTAssertTrue(regions.contains { $0.touchesLeft && $0.touchesTop })
        XCTAssertTrue(regions.contains { $0.touchesRight && $0.touchesBottom })
        XCTAssertEqual(regions.map(\.x).min(), 0)
        XCTAssertEqual(regions.map { $0.x + $0.width }.max(), 3840)
        XCTAssertEqual(regions.map { $0.y + $0.height }.max(), 2160)
    }

    func testTileLayoutHasRequiredOverlap() {
        let regions = TileLayout.regions(
            frameWidth: 1920, frameHeight: 1080,
            tileWidth: 960, tileHeight: 540, overlap: 32
        )
        let firstRow = regions.filter { $0.y == 0 }.sorted { $0.x < $1.x }
        XCTAssertGreaterThan(firstRow.count, 1)
        for pair in zip(firstRow, firstRow.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.0.x + pair.0.width - pair.1.x, 32)
        }
    }
}

extension ClarityVideoTests {
    func testShort8KJobsUseBoundedStreamingAndLong8KJobsCheckpoint() {
        var configuration = ExportConfiguration()
        configuration.resolution = .uhd8K
        XCTAssertFalse(SegmentPlan.requiresSegmentation(duration: 19, configuration: configuration))
        XCTAssertTrue(SegmentPlan.requiresSegmentation(duration: 46, configuration: configuration))
    }

    func testSegmentPlanHasNoTimelineGaps() {
        let segments = SegmentPlan.segments(duration: 95, segmentDuration: 30)
        XCTAssertEqual(segments.count, 4)
        XCTAssertEqual(segments.first?.startSeconds, 0)
        XCTAssertEqual(segments.last?.endSeconds, 95)
        for pair in zip(segments, segments.dropFirst()) {
            XCTAssertEqual(pair.0.endSeconds, pair.1.startSeconds, accuracy: 0.0001)
        }
    }

    func testCheckpointRejectsMissingCompletedSegment() {
        let configuration = ExportConfiguration()
        let checkpoint = ProcessingCheckpoint(
            jobID: UUID(),
            sourceFingerprint: "source",
            configuration: configuration,
            completedSegments: [0],
            completedSegmentFiles: ["0": URL(fileURLWithPath: "/missing/segment.mov")],
            expectedSegmentCount: 2
        )
        XCTAssertFalse(checkpoint.isCompatible(
            sourceFingerprint: "source", configuration: configuration, segmentCount: 2
        ))
    }
    func testSceneCutDetectorSeparatesCutsFromSmallChanges() {
        XCTAssertFalse(SceneCutDetector.isCut(previous: [0.20, 0.22, 0.21], current: [0.23, 0.24, 0.22]))
        XCTAssertTrue(SceneCutDetector.isCut(previous: [0.05, 0.08, 0.06], current: [0.90, 0.86, 0.92]))
    }
    func testUltraPresetChangesQualityWithoutChangingUpscaler() {
        var configuration = ExportConfiguration()
        configuration.upscaler = .dlss5
        configuration.applyPreset(.ultra, temporalDenoiseAvailable: true)
        XCTAssertEqual(configuration.qualityPreset, .ultra)
        XCTAssertEqual(configuration.upscaler, .dlss5)
        XCTAssertGreaterThan(configuration.detailRecovery, 0.5)
        configuration.applyPreset(.balanced, temporalDenoiseAvailable: false)
        XCTAssertEqual(configuration.upscaler, .dlss5)
        XCTAssertEqual(configuration.denoise, 0)
    }

    func testLegacyBitrateIsClampedToCurrentResolutionBudget() {
        var configuration = ExportConfiguration()
        configuration.resolution = .uhd8K
        configuration.bitrateMbps = 220
        configuration.clampBitrateToSupportedRange()
        XCTAssertEqual(configuration.bitrateMbps, 85)

        configuration.resolution = .uhd4K
        configuration.clampBitrateToSupportedRange()
        XCTAssertEqual(configuration.bitrateMbps, 55)
    }

    func testUpscalerCanChangeWithoutChangingResolutionOrQuality() {
        var configuration = ExportConfiguration()
        configuration.resolution = .uhd8K
        configuration.qualityPreset = .quality
        configuration.upscaler = .appleSR
        configuration.upscaler = .dlss5
        XCTAssertEqual(configuration.resolution, .uhd8K)
        XCTAssertEqual(configuration.qualityPreset, .quality)
        XCTAssertEqual(configuration.upscaler, .dlss5)
    }

    func testAllResolutionAndUpscalerCombinationsAreIndependent() {
        for resolution in [OutputResolution.uhd4K, .uhd8K] {
            for upscaler in [UpscalerEngine.appleSR, .dlss5] {
                var configuration = ExportConfiguration()
                configuration.resolution = resolution
                configuration.upscaler = upscaler
                configuration.applyPreset(
                    .ultra,
                    temporalDenoiseAvailable: true
                )
                XCTAssertEqual(configuration.resolution, resolution)
                XCTAssertEqual(configuration.upscaler, upscaler)
                XCTAssertEqual(configuration.qualityPreset, .ultra)
            }
        }
    }

    func testLegacyDLSSModeMigratesToDLSSUpscalerAndUltraPreset() throws {
        let json = """
        {
          "resolution":"4K UHD",
          "mode":"DLSS 5 (experimental)",
          "denoise":0.0,
          "detailRecovery":0.25,
          "sharpening":0.1,
          "bitrateMbps":55,
          "codec":"HEVC",
          "hdrBehavior":"Preserve HDR",
          "preserveFrameRate":true
        }
        """.data(using: .utf8)!
        let configuration = try JSONDecoder().decode(ExportConfiguration.self, from: json)
        XCTAssertEqual(configuration.upscaler, .dlss5)
        XCTAssertEqual(configuration.qualityPreset, .ultra)
    }
    func testOutputEstimateUsesSelectedBitrateAndDuration() {
        let info = VideoAssetInfo(fileName: "x.mov", encodedWidth: 1280, encodedHeight: 720, displayWidth: 1280, displayHeight: 720, frameRate: 30, codec: "hvc1", isHDR: false, duration: 8, estimatedSourceBytes: 1)
        var configuration = ExportConfiguration()
        configuration.bitrateMbps = 50
        XCTAssertEqual(StorageEstimator.estimatedOutputBytes(info: info, configuration: configuration), 50_000_000)
    }
    func testShort8KMaximumQualityFitsUnderHalfGigabyteWorkingBudget() {
        let info = VideoAssetInfo(fileName: "short.mov", encodedWidth: 1920, encodedHeight: 1080, displayWidth: 1920, displayHeight: 1080, frameRate: 30, codec: "hvc1", isHDR: false, duration: 19, estimatedSourceBytes: 25_000_000)
        var configuration = ExportConfiguration()
        configuration.resolution = .uhd8K
        configuration.bitrateMbps = 85
        XCTAssertFalse(SegmentPlan.requiresSegmentation(duration: info.duration, configuration: configuration))
        XCTAssertLessThan(StorageEstimator.requiredBytes(info: info, configuration: configuration), 500_000_000)
    }

    func test8KStoragePreflightAllowsFinalAndSegmentCopies() {
        let info = VideoAssetInfo(fileName: "x.mov", encodedWidth: 1920, encodedHeight: 1080, displayWidth: 1920, displayHeight: 1080, frameRate: 30, codec: "hvc1", isHDR: false, duration: 60, estimatedSourceBytes: 1)
        var configuration = ExportConfiguration()
        configuration.resolution = .uhd8K
        let output = StorageEstimator.estimatedOutputBytes(info: info, configuration: configuration)
        XCTAssertGreaterThan(StorageEstimator.requiredBytes(info: info, configuration: configuration), output * 2)
    }
    func testDefaultSegmentsStayWithinFiveSeconds() {
        let segments = SegmentPlan.segments(duration: 12)
        XCTAssertEqual(segments.map(\.durationSeconds), [5, 5, 2])
    }

    func testCheckpointRejectsOldPipelineVersion() {
        let configuration = ExportConfiguration()
        let checkpoint = ProcessingCheckpoint(
            jobID: UUID(), sourceFingerprint: "source", configuration: configuration,
            expectedSegmentCount: 1, pipelineVersion: 1
        )
        XCTAssertFalse(checkpoint.isCompatible(sourceFingerprint: "source", configuration: configuration, segmentCount: 1))
    }

    func testCheckpointRejectsVersionThreeAfterFailClosedRoutingChange() {
        let configuration = ExportConfiguration()
        let checkpoint = ProcessingCheckpoint(
            jobID: UUID(), sourceFingerprint: "source", configuration: configuration,
            expectedSegmentCount: 1, pipelineVersion: 3
        )
        XCTAssertFalse(checkpoint.isCompatible(sourceFingerprint: "source", configuration: configuration, segmentCount: 1))
    }
}


extension ClarityVideoTests {
    func testCodecSelectionDefaultsToHEVC() {
        XCTAssertEqual(ExportConfiguration().codec, .hevc)
    }

    func test8KBalancedBitrateFitsConfiguredRange() {
        var configuration = ExportConfiguration()
        configuration.resolution = .uhd8K
        configuration.bitrateMbps = 70
        XCTAssertEqual(StorageEstimator.estimatedOutputBytes(
            info: VideoAssetInfo(fileName: "x.mov", encodedWidth: 1920, encodedHeight: 1080, displayWidth: 1920, displayHeight: 1080, frameRate: 30, codec: "hvc1", isHDR: false, duration: 1, estimatedSourceBytes: 1),
            configuration: configuration
        ), 8_750_000)
    }
}
