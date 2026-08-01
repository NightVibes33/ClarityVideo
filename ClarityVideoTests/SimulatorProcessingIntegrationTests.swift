import XCTest
import AVFoundation
import CoreVideo
@testable import ClarityVideo

@MainActor
final class SimulatorProcessingIntegrationTests: XCTestCase {
    #if targetEnvironment(simulator)
    private struct FixtureFormat {
        let name: String
        let fileType: AVFileType
        let fileExtension: String
        let codec: AVVideoCodecType
        let expectedCodecTokens: [String]
    }

    private struct AspectCase {
        let name: String
        let width: Int
        let height: Int
    }

    private let h264MP4 = FixtureFormat(
        name: "MP4-H264", fileType: .mp4, fileExtension: "mp4", codec: .h264,
        expectedCodecTokens: ["avc", "h264"]
    )

    private var aspectCases: [AspectCase] {
        [
            AspectCase(name: "16x9", width: 640, height: 360),
            AspectCase(name: "9x16", width: 360, height: 640),
            AspectCase(name: "4x3", width: 640, height: 480),
            AspectCase(name: "3x4", width: 480, height: 640),
            AspectCase(name: "1x1", width: 512, height: 512),
            AspectCase(name: "21x9", width: 840, height: 360),
            AspectCase(name: "9x21", width: 360, height: 840),
            AspectCase(name: "3x2", width: 720, height: 480),
            AspectCase(name: "2x3", width: 480, height: 720),
            AspectCase(name: "1_85x1", width: 666, height: 360),
            AspectCase(name: "2_39x1", width: 860, height: 360)
        ]
    }

    private var formatCases: [FixtureFormat] {
        [
            h264MP4,
            FixtureFormat(name: "MOV-H264", fileType: .mov, fileExtension: "mov", codec: .h264, expectedCodecTokens: ["avc", "h264"]),
            FixtureFormat(name: "M4V-H264", fileType: .m4v, fileExtension: "m4v", codec: .h264, expectedCodecTokens: ["avc", "h264"]),
            FixtureFormat(name: "MP4-HEVC", fileType: .mp4, fileExtension: "mp4", codec: .hevc, expectedCodecTokens: ["hvc", "hevc"]),
            FixtureFormat(name: "MOV-HEVC", fileType: .mov, fileExtension: "mov", codec: .hevc, expectedCodecTokens: ["hvc", "hevc"]),
            FixtureFormat(name: "MOV-ProRes422", fileType: .mov, fileExtension: "mov", codec: .proRes422, expectedCodecTokens: ["apcn", "prores"])
        ]
    }
    #endif

    func testEverySupportedAspectRatioUpscalesTo4K() async throws {
        #if targetEnvironment(simulator)
        for aspect in aspectCases {
            try await runUpscaleCase(
                label: "aspect-" + aspect.name,
                width: aspect.width,
                height: aspect.height,
                format: h264MP4
            )
        }
        #else
        throw XCTSkip("The aspect-ratio processing matrix runs on the iOS simulator job.")
        #endif
    }

    func testEverySupportedContainerAndCodecUpscalesTo4K() async throws {
        #if targetEnvironment(simulator)
        for format in formatCases {
            try await runUpscaleCase(
                label: "format-" + format.name,
                width: 640,
                height: 360,
                format: format
            )
        }
        #else
        throw XCTSkip("The format processing matrix runs on the iOS simulator job.")
        #endif
    }

    #if targetEnvironment(simulator)
    private func runUpscaleCase(
        label: String,
        width: Int,
        height: Int,
        format: FixtureFormat
    ) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaritySimulator-" + label + "-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let sourceURL = folder.appendingPathComponent("source." + format.fileExtension)
        let outputURL = folder.appendingPathComponent("upscaled-4k.mov")
        try await makeFixture(at: sourceURL, width: width, height: height, format: format)
        let info = try await AssetInspector.inspect(sourceURL)
        XCTAssertEqual(info.encodedWidth, width, label + " encoded width")
        XCTAssertEqual(info.encodedHeight, height, label + " encoded height")
        XCTAssertTrue(
            format.expectedCodecTokens.contains { info.codec.lowercased().contains($0) },
            label + " codec was " + info.codec
        )

        var configuration = ExportConfiguration()
        configuration.resolution = .uhd4K
        configuration.codec = .h264
        configuration.denoise = 0
        configuration.detailRecovery = 0
        configuration.sharpening = 0
        configuration.bitrateMbps = 4

        var job = ProcessingJob(sourceURL: sourceURL, assetInfo: info, configuration: configuration)
        job.outputURL = outputURL
        job.totalFrames = 2
        let result = try await VideoProcessingCoordinator().process(job: job, progress: { _ in })
        XCTAssertTrue(result.status == .completed, label + " processing status")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), label + " output file")

        let outputInfo = try await AssetInspector.inspect(outputURL)
        let expectedWidth = height > width ? 2160 : 3840
        let expectedHeight = height > width ? 3840 : 2160
        XCTAssertEqual(outputInfo.displayWidth, expectedWidth, label + " output width")
        XCTAssertEqual(outputInfo.displayHeight, expectedHeight, label + " output height")
        XCTAssertGreaterThan(outputInfo.displayWidth * outputInfo.displayHeight, info.displayWidth * info.displayHeight)
        print("SIMULATOR_VIDEO_MATRIX_PASS " + label + " " + String(width) + "x" + String(height) + " " + format.name + " -> " + String(expectedWidth) + "x" + String(expectedHeight))
    }

    private func makeFixture(
        at url: URL,
        width: Int,
        height: Int,
        format: FixtureFormat
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: format.fileType)
        var settings: [String: Any] = [
            AVVideoCodecKey: format.codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        if format.codec == .h264 || format.codec == .hevc {
            settings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: 1_000_000]
        }
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            XCTFail(format.name + " encoder is unavailable on the required iOS simulator runner")
            throw NSError(domain: "ClaritySimulatorTest", code: 10)
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
            ]
        )
        guard writer.canAdd(input) else {
            throw NSError(domain: "ClaritySimulatorTest", code: 11)
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "ClaritySimulatorTest", code: 12)
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else {
            throw NSError(domain: "ClaritySimulatorTest", code: 13)
        }

        for frameIndex in 0..<2 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
            guard status == kCVReturnSuccess, let buffer else {
                throw NSError(domain: "ClaritySimulatorTest", code: Int(status))
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(40 + frameIndex * 80), CVPixelBufferGetBytesPerRow(buffer) * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: 30)
            ) else {
                throw writer.error ?? NSError(domain: "ClaritySimulatorTest", code: 14)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "ClaritySimulatorTest", code: 15)
        }
    }
    #endif
}
