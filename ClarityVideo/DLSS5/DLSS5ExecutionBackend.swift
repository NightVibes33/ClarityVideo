import Foundation
import Metal

/// Static execution invariants for the real Neural Rendering stage. Transfer
/// characteristics (SDR display-referred vs HDR linear) belong to each frame's
/// contract and are deliberately not hard-coded here.
struct DLSS5EvaluationConfiguration: Codable, Equatable, Sendable {
    enum ExecutionMode: String, Codable, Sendable {
        case neuralRenderingFeature18
    }

    var executionMode: ExecutionMode = .neuralRenderingFeature18
    var featureID: UInt32 = 18
    var nativeResolutionOnly = true
    var depthIsInverted = true
    var motionVectorScaleX: Float = 1
    var motionVectorScaleY: Float = 1

    func validate() throws {
        guard executionMode == .neuralRenderingFeature18, featureID == 18 else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The current DLSS 5 execution contract targets NGX Neural Rendering feature 18."
            )
        }
        guard nativeResolutionOnly else {
            throw DLSS5ContractError.runtimeUnavailable(
                "Feature 18 is modeled as a native-resolution stage; DLSS Super Resolution runs before it."
            )
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

/// Production boundary for the eventual ARM64/Metal rehost. It remains unavailable
/// until a genuine feature-18-compatible executor exists; Apple SR/Core Image is never
/// substituted behind this type and reported as NVIDIA DLSS.
@MainActor
final class DLSS5UnlinkedMetalRuntime: DLSS5ExecutionBackend {
    let evaluationConfiguration = DLSS5EvaluationConfiguration()
    var availability: DLSS5RuntimeAvailability { DLSS5RuntimeProbe.current }

    func start(renderWidth: Int, renderHeight: Int) throws {
        try evaluationConfiguration.validate()
        guard renderWidth > 0, renderHeight > 0 else {
            throw DLSS5ContractError.invalidDimensions
        }
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

/// Useful during the port: validates and captures the exact feeder resources without
/// pretending an NVIDIA neural evaluation occurred.
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
