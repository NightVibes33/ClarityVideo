import XCTest
import CoreMedia
@testable import ClarityVideo

final class DLSS5ContractTests: XCTestCase {
    func testVideoFeederContractMatchesExpectedPlaneFormats() throws {
        let contract = DLSS5FrameContract(
            presentationTime: CMTime(value: 1, timescale: 30),
            renderWidth: 1920,
            renderHeight: 1080,
            outputWidth: 1920,
            outputHeight: 1080,
            resetHistory: true
        )
        XCTAssertNoThrow(try contract.validate())
        XCTAssertEqual(contract.colorFormat, .rgba16Float)
        XCTAssertEqual(contract.depthFormat, .r32Float)
        XCTAssertEqual(contract.motionFormat, .rg16Float)
        XCTAssertTrue(contract.motionVectorsAreInPixels)
        XCTAssertTrue(contract.depthIsReversed)
    }

    func testInvalidDLSS5DimensionsAreRejected() {
        let contract = DLSS5FrameContract(
            presentationTime: .zero,
            renderWidth: 0,
            renderHeight: 1080,
            outputWidth: 1920,
            outputHeight: 1080,
            resetHistory: true
        )
        XCTAssertThrowsError(try contract.validate())
    }

    func testHaltonJitterIsCenteredAndDeterministic() {
        let first = DLSS5Jitter.offset(frameIndex: 0)
        let second = DLSS5Jitter.offset(frameIndex: 1)
        XCTAssertEqual(first.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(first.y, -1.0 / 6.0, accuracy: 0.000_001)
        XCTAssertEqual(second.x, -0.25, accuracy: 0.000_001)
        XCTAssertEqual(second.y, 1.0 / 6.0, accuracy: 0.000_001)
    }

    func testEvaluationConfigurationUsesDLAAReferenceMode() throws {
        let configuration = DLSS5EvaluationConfiguration()
        XCTAssertNoThrow(try configuration.validate())
        XCTAssertEqual(configuration.qualityMode, .dlaa)
        XCTAssertTrue(configuration.inputIsHDR)
        XCTAssertTrue(configuration.autoExposure)
        XCTAssertTrue(configuration.depthIsInverted)
        XCTAssertEqual(configuration.motionVectorScaleX, 1)
        XCTAssertEqual(configuration.motionVectorScaleY, 1)
    }

    func testRuntimeProbeNeverClaimsUnlinkedDLSS5IsAvailable() {
        XCTAssertFalse(DLSS5RuntimeProbe.current.available)
    }
}
