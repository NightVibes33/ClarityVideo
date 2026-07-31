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
