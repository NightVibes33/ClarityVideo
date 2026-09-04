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
        XCTAssertEqual(first.x, Float(0), accuracy: 0.000_001)
        XCTAssertEqual(first.y, Float(-1.0 / 6.0), accuracy: 0.000_001)
        XCTAssertEqual(second.x, Float(-0.25), accuracy: 0.000_001)
        XCTAssertEqual(second.y, Float(1.0 / 6.0), accuracy: 0.000_001)
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

    func testFeedDescriptorUsesDLAAWhenWorkAndTargetMatch() throws {
        let contract = DLSS5FrameContract(
            presentationTime: .zero,
            renderWidth: 1280,
            renderHeight: 720,
            outputWidth: 1280,
            outputHeight: 720,
            resetHistory: true
        )
        let metadata = DLSS5PreparedFrameMetadata(
            contract: contract,
            hasColor: true,
            hasDepth: true,
            hasMotionVectors: true,
            sourceDescription: "test"
        )
        let feed = DLSS5FeedDescriptor(metadata: metadata, sequence: 7)
        XCTAssertNoThrow(try feed.validate())
        XCTAssertFalse(feed.build.usesSuperResolution)
        XCTAssertEqual(feed.frame.sequence, 7)
        let ngx = DLSS5NGXSemanticPacket(feed: feed)
        XCTAssertNoThrow(try ngx.validate())
        XCTAssertEqual(ngx.feature.quality, .dlaa)
        XCTAssertTrue(ngx.feature.flags.contains(.motionVectorsLowResolution))
        XCTAssertTrue(ngx.feature.flags.contains(.autoExposure))
        XCTAssertTrue(ngx.feature.flags.contains(.depthInverted))
        XCTAssertTrue(ngx.feature.flags.contains(.hdr))
        XCTAssertTrue(ngx.evaluate.reset)
        XCTAssertEqual(ngx.evaluate.preExposure, 1)
        XCTAssertEqual(ngx.evaluate.exposureScale, 1)
    }

    func testFeedDescriptorSupportsSuperResolutionTarget() throws {
        var contract = DLSS5FrameContract(
            presentationTime: .zero,
            renderWidth: 1280,
            renderHeight: 720,
            outputWidth: 3840,
            outputHeight: 2160,
            resetHistory: false
        )
        contract.jitterX = 0.25
        contract.jitterY = -0.125
        let metadata = DLSS5PreparedFrameMetadata(
            contract: contract,
            hasColor: true,
            hasDepth: true,
            hasMotionVectors: true,
            sourceDescription: "test SR"
        )
        let feed = DLSS5FeedDescriptor(metadata: metadata, sequence: 9)
        XCTAssertNoThrow(try feed.validate())
        XCTAssertTrue(feed.build.usesSuperResolution)
        let ngx = DLSS5NGXSemanticPacket(feed: feed)
        XCTAssertEqual(ngx.feature.quality, .superResolution)
        XCTAssertEqual(ngx.feature.targetWidth, 3840)
        XCTAssertEqual(ngx.feature.targetHeight, 2160)
        XCTAssertEqual(ngx.evaluate.jitterX, 0.25)
        XCTAssertEqual(ngx.evaluate.jitterY, -0.125)
        XCTAssertFalse(ngx.evaluate.reset)
    }
}
