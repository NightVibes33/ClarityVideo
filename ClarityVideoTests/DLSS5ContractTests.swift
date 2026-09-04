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
        XCTAssertEqual(contract.motionDirection, .currentToPrevious)
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

    func testSceneCutMetricMatchesReferenceThresholdBehavior() {
        let black = [UInt8](repeating: 0, count: 64 * 36 * 4)
        var smallChange = black
        var hardCut = black
        for index in stride(from: 0, to: smallChange.count, by: 4) {
            smallChange[index] = 32
            smallChange[index + 1] = 32
            smallChange[index + 2] = 32
            smallChange[index + 3] = 255
            hardCut[index] = 255
            hardCut[index + 1] = 255
            hardCut[index + 2] = 255
            hardCut[index + 3] = 255
        }

        let smallDifference = DLSS5SceneCutDetector.meanAbsoluteLumaDifference(black, smallChange)
        let cutDifference = DLSS5SceneCutDetector.meanAbsoluteLumaDifference(black, hardCut)
        XCTAssertLessThan(smallDifference, 0.24)
        XCTAssertGreaterThan(cutDifference, 0.24)
    }

    func testNeuralRenderingFeature18RunsAtFinalResolutionAfterSR() throws {
        let contract = DLSS5FrameContract(
            presentationTime: CMTime(value: 2, timescale: 60),
            renderWidth: 1920,
            renderHeight: 1080,
            outputWidth: 3840,
            outputHeight: 2160,
            resetHistory: false
        )
        let model = DLSS5NeuralRenderingModelParameters(
            preset: 2,
            intensity: 1.25,
            style: .cinematic,
            localStructureStrength: 1.1,
            localToneStrength: 0.9,
            skinStructureStrength: -1,
            globalToneStrength: -1,
            autoMask: false,
            uiCorrection: false
        )
        let packet = DLSS5NeuralRenderingPacket(
            contract: contract,
            model: model,
            motionVectorScaleX: 1,
            motionVectorScaleY: 1
        )
        XCTAssertNoThrow(try packet.validate())
        XCTAssertEqual(packet.create.featureID, 18)
        XCTAssertTrue(packet.pipeline.superResolutionRequired)
        XCTAssertEqual(packet.pipeline.superResolutionRenderWidth, 1920)
        XCTAssertEqual(packet.pipeline.superResolutionRenderHeight, 1080)
        XCTAssertEqual(packet.pipeline.superResolutionTargetWidth, 3840)
        XCTAssertEqual(packet.pipeline.superResolutionTargetHeight, 2160)
        XCTAssertFalse(packet.create.upscaling)
        XCTAssertEqual(packet.create.inputWidth, 3840)
        XCTAssertEqual(packet.create.inputHeight, 2160)
        XCTAssertEqual(packet.create.outputWidth, 3840)
        XCTAssertEqual(packet.create.outputHeight, 2160)
        XCTAssertTrue(packet.create.depthInverted)
        XCTAssertEqual(packet.create.scale, 1, accuracy: 0.000_001)
        XCTAssertEqual(packet.create.scalingRatio, 1, accuracy: 0.000_001)
        XCTAssertEqual(packet.evaluate.colorSubrectWidth, 3840)
        XCTAssertEqual(packet.evaluate.colorSubrectHeight, 2160)
        XCTAssertEqual(packet.evaluate.depthSubrectWidth, 3840)
        XCTAssertEqual(packet.evaluate.motionSubrectWidth, 3840)
        XCTAssertEqual(packet.evaluate.outputSubrectWidth, 3840)
        XCTAssertFalse(packet.evaluate.reset)
        XCTAssertEqual(DLSS5NeuralRenderingKey.motion, "DLSSNR.MVec")
        XCTAssertEqual(DLSS5NeuralRenderingKey.reset, "DLSSNR.Reset")
        XCTAssertEqual(DLSS5NeuralRenderingKey.outputWidthAlias, "DLSSNR.Output.Width")
    }
}
