import Foundation
import Metal

struct DLSS5EvaluationConfiguration: Codable, Equatable, Sendable {
    enum QualityMode: String, Codable, Sendable {
        case dlaa
    }

    var qualityMode: QualityMode = .dlaa
    var inputIsHDR = true
    var autoExposure = true
    var depthIsInverted = true
    var motionVectorScaleX: Float = 1
    var motionVectorScaleY: Float = 1

    func validate() throws {
        guard qualityMode == .dlaa else {
            throw DLSS5ContractError.runtimeUnavailable("The current DLSS 5 reference contract expects a DLAA evaluation.")
        }
        guard motionVectorScaleX.isFinite, motionVectorScaleY.isFinite else {
            throw DLSS5ContractError.runtimeUnavailable("DLSS 5 motion-vector scale must be finite.")
        }
    }
}

@MainActor
protocol DLSS5ExecutionBackend: AnyObject {
    var availability: DLSS5RuntimeAvailability { get }
    var evaluationConfiguration: DLSS5EvaluationConfiguration { get }

    func start(renderWidth: Int, renderHeight: Int) throws
    func evaluate(_ frame: DLSS5PreparedFrame) async throws -> any MTLTexture
    func resetHistory()
    func end()
}

/// The production boundary for the eventual ARM64/Metal rehost. Keeping this as
/// a concrete backend prevents ClarityVideo from ever silently substituting Apple
/// SR while reporting that NVIDIA DLSS 5 ran.
@MainActor
final class DLSS5UnlinkedMetalRuntime: DLSS5ExecutionBackend {
    let evaluationConfiguration = DLSS5EvaluationConfiguration()
    var availability: DLSS5RuntimeAvailability { DLSS5RuntimeProbe.current }

    func start(renderWidth: Int, renderHeight: Int) throws {
        try evaluationConfiguration.validate()
        guard availability.available else {
            throw DLSS5ContractError.runtimeUnavailable(
                availability.reason ?? "The ARM64/Metal DLSS 5 runtime is not linked."
            )
        }
    }

    func evaluate(_ frame: DLSS5PreparedFrame) async throws -> any MTLTexture {
        try frame.metadata.validateForExecution()
        throw DLSS5ContractError.runtimeUnavailable(
            availability.reason ?? "The ARM64/Metal DLSS 5 runtime is not linked."
        )
    }

    func resetHistory() {}
    func end() {}
}

/// Useful during the port: validates the exact feeder resources and captures them
/// without pretending an NVIDIA neural evaluation occurred.
@MainActor
final class DLSS5ReferenceCaptureBackend {
    private(set) var captureCount = 0

    func capture(_ frame: DLSS5PreparedFrame, folder: URL) throws -> URL {
        try frame.metadata.validateForExecution()
        let destination = folder.appendingPathComponent(
            String(format: "frame-%06d", captureCount),
            isDirectory: true
        )
        let manifest = try DLSS5ReferenceCaptureWriter.write(frame, to: destination)
        captureCount += 1
        return manifest
    }

    func reset() {
        captureCount = 0
    }
}
