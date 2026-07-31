import XCTest
@testable import ClarityVideo

final class ClarityVideoTests: XCTestCase {
    func testStorageEstimateIncludesSafetyAndTemporarySpace() {
        let info = VideoAssetInfo(fileName: "test.mov", encodedWidth: 1920, encodedHeight: 1080, displayWidth: 1920, displayHeight: 1080, frameRate: 30, codec: "hvc1", isHDR: false, duration: 60, estimatedSourceBytes: 10)
        let required = StorageEstimator.requiredBytes(info: info, configuration: ExportConfiguration())
        XCTAssertGreaterThan(required, 55 * 1_000_000 / 8 * 60)
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
    func testPlannerUsesFullQualityFourXFor720pTo4K() throws {
        var caps = DeviceEnhancementCapabilities()
        caps.fullSuperResolutionAvailable = true
        caps.supportedFullScaleFactors = [2, 4]
        let plan = try PipelinePlanner.plan(
            sourceWidth: 1280, sourceHeight: 720, target: .uhd4K, mode: .quality,
            capabilities: caps, lowLatencyFactorsForSource: []
        )
        XCTAssertEqual(plan.route, .fullQualitySuperResolution)
        XCTAssertEqual(plan.aiScaleFactor, 4)
        XCTAssertTrue(plan.requiresFinalResize)
    }

    func testPlannerUsesLowLatencyForFullHDWhenSupported() throws {
        var caps = DeviceEnhancementCapabilities()
        caps.fullSuperResolutionAvailable = true
        caps.lowLatencySuperResolutionAvailable = true
        caps.supportedFullScaleFactors = [2, 4]
        let plan = try PipelinePlanner.plan(
            sourceWidth: 1920, sourceHeight: 1080, target: .uhd4K, mode: .quality,
            capabilities: caps, lowLatencyFactorsForSource: [2]
        )
        XCTAssertEqual(plan.route, .lowLatencySuperResolution)
        XCTAssertFalse(plan.requiresFinalResize)
    }

    func testPlannerTiles4KTo8KWithoutLowLatencyRoute() throws {
        var caps = DeviceEnhancementCapabilities()
        caps.fullSuperResolutionAvailable = true
        caps.supportedFullScaleFactors = [2]
        let plan = try PipelinePlanner.plan(
            sourceWidth: 3840, sourceHeight: 2160, target: .uhd8K, mode: .quality,
            capabilities: caps, lowLatencyFactorsForSource: []
        )
        XCTAssertEqual(plan.route, .tiledSuperResolution)
        XCTAssertEqual(plan.tileWidth, 960)
        XCTAssertEqual(plan.overlap, 32)
        XCTAssertFalse(plan.requiresFinalResize)
    }
}
