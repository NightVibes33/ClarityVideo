import XCTest
import AVFoundation
import CoreVideo
@testable import ClarityVideo

@MainActor
final class SimulatorProcessingIntegrationTests: XCTestCase {
    func testSimulatorImports720pPortraitMP4AndUpscalesTo4K() async throws {
        #if targetEnvironment(simulator)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaritySimulatorIntegration-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let sourceURL = folder.appendingPathComponent("portrait-720x1280.mp4")
        let outputURL = folder.appendingPathComponent("portrait-4k.mov")
        try await makePortraitFixture(at: sourceURL)
        let info = try await AssetInspector.inspect(sourceURL)
        XCTAssertTrue(info.isPortrait)
        XCTAssertEqual(info.encodedWidth, 720)
        XCTAssertEqual(info.encodedHeight, 1280)
        XCTAssertTrue(info.codec.lowercased().contains("avc") || info.codec.lowercased().contains("h264"))

        var configuration = ExportConfiguration()
        configuration.resolution = .uhd4K
        configuration.codec = .h264
        configuration.denoise = 0
        configuration.detailRecovery = 0
        configuration.sharpening = 0
        configuration.bitrateMbps = 4

        var job = ProcessingJob(sourceURL: sourceURL, assetInfo: info, configuration: configuration)
        job.outputURL = outputURL
        job.totalFrames = 3
        let result = try await VideoProcessingCoordinator().process(job: job, progress: { _ in })
        XCTAssertTrue(result.status == .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let outputInfo = try await AssetInspector.inspect(outputURL)
        XCTAssertEqual(outputInfo.displayWidth, 2160)
        XCTAssertEqual(outputInfo.displayHeight, 3840)
        XCTAssertGreaterThan(outputInfo.displayWidth, info.displayWidth)
        XCTAssertGreaterThan(outputInfo.displayHeight, info.displayHeight)
        print("SIMULATOR_MP4_UPSCALE_PASS 720x1280 MP4 -> 2160x3840 video")
        #else
        throw XCTSkip("The end-to-end fallback processing test runs on the iOS simulator job.")
        #endif
    }

    #if targetEnvironment(simulator)
    private func makePortraitFixture(at url: URL) async throws {
        let width = 720
        let height = 1280
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else {
            throw NSError(domain: "ClaritySimulatorTest", code: 1)
        }

        for frameIndex in 0..<3 {
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
                memset(base, Int32(frameIndex * 50), CVPixelBufferGetBytesPerRow(buffer) * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: 30)
            ))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "ClaritySimulatorTest", code: 2)
        }
    }
    #endif
}
