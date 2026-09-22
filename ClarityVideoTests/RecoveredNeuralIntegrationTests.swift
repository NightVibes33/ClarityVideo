import CoreVideo
import XCTest
@testable import ClarityVideo

@MainActor
final class RecoveredNeuralIntegrationTests: XCTestCase {
    func testRecoveredModelProcessesARealPixelBuffer() async throws {
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
    }
}
