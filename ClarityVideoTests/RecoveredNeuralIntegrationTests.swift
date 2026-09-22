import CoreVideo
import XCTest
@testable import ClarityVideo

@MainActor
final class RecoveredNeuralIntegrationTests: XCTestCase {
    func testRecoveredFeaturePreparationMatchesUpstreamNumbers() throws {
        let values: [Float] = [0.25, 0.5, 0.75, 1, 0, 0.5]
        let color = try HostTensor(
            descriptor: TensorDescriptor(name: "color", shape: [1, 1, 2, 3], dataType: .float32, layout: .nhwc),
            bytes: values.withUnsafeBytes { Data($0) }
        )
        let features = try NeuralRenderingFirstFramePreprocessor.makeFeatureTensor(from: color)
        let actual = features.bytes.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: MemoryLayout<Float>.size).map {
                bytes.loadUnaligned(fromByteOffset: $0, as: Float.self)
            }
        }
        XCTAssertEqual(actual, [
            -0.219_604_492_187_5, 1.028_320_312_5, 0.127_319_335_937_5, 1,
            -0.031_25, 0, 0.031_25, -0.031_25, 0, 0.031_25, 0, 1, 1, -1, -1, 0,
            0.170_166_015_625, 1.937_5, 0.325_439_453_125, 1,
            0.062_5, -0.062_5, 0, 0.062_5, -0.062_5, 0,
            0, 1, 1, -1, -1, 0
        ])
    }

    func testRecoveredModelLoadsWithExpectedIOSInterface() throws {
        let modelURL = try XCTUnwrap(
            IOSNeuralHeadService.bundledModelURL(),
            "Converted recovered model must be bundled for this integration run."
        )
        _ = try IOSNeuralHeadService(modelURL: modelURL)
    }

    func testRecoveredModelProcessesARealPixelBuffer() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Full recovered-model prediction is device-only; simulator compile/load and I/O contract are validated separately.")
#else
        guard let modelURL = IOSNeuralHeadService.bundledModelURL() else {
            throw XCTSkip("The optional recovered model is not bundled with this build.")
        }
        let renderer = try IOSNeuralHeadService(modelURL: modelURL)
        var source: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 128, 128,
                                        kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()] as CFDictionary,
                                        &source)
        XCTAssertEqual(status, kCVReturnSuccess)
        let sourceFrame = try XCTUnwrap(source)
        CVPixelBufferLockBaseAddress(sourceFrame, [])
        if let base = CVPixelBufferGetBaseAddress(sourceFrame)?.assumingMemoryBound(to: UInt8.self) {
            for y in 0..<128 {
                for x in 0..<128 {
                    let index = y * CVPixelBufferGetBytesPerRow(sourceFrame) + x * 4
                    base[index] = UInt8(64 + x / 4)
                    base[index + 1] = UInt8(64 + y / 4)
                    base[index + 2] = 144
                    base[index + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(sourceFrame, [])

        let output = try await renderer.render(source: sourceFrame, frameNumber: 0)
        XCTAssertEqual(CVPixelBufferGetWidth(output), 128)
        XCTAssertEqual(CVPixelBufferGetHeight(output), 128)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(output), kCVPixelFormatType_32BGRA)
        CVPixelBufferLockBaseAddress(output, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(output, .readOnly) }
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(output)?.assumingMemoryBound(to: UInt8.self))
        XCTAssertEqual(bytes[3], 255)
        XCTAssertGreaterThan(bytes[2], 0)
#endif
    }
}
