import Foundation
import CoreGraphics
import CoreMedia

/// Data contract for the DLSS 5 feeder/rehosting work.
///
/// This intentionally does not claim that NVIDIA NGX executes on iOS. It models the
/// resources a real DLSS 5 feeder supplies so ClarityVideo can generate, validate,
/// record, and later route those resources into an ARM64/Metal runtime if/when that
/// runtime exists.
enum DLSS5ResourceFormat: String, Codable, Sendable {
    case rgba16Float
    case r32Float
    case rg16Float
}

enum DLSS5ColorEncoding: String, Codable, Sendable {
    /// Current standalone video references feed SDR content display-referred into
    /// the RGBA16F texture rather than linearising it first.
    case sRGBDisplayReferred

    /// HDR mode feeds linear-light RGB into the RGBA16F Neural Rendering texture.
    case linearHDR

    var isHDR: Bool { self == .linearHDR }
}

enum DLSS5MotionDirection: String, Codable, Sendable {
    /// Backward flow: for a pixel in the current frame, the vector locates the
    /// corresponding sample in the previous frame. This matches the current
    /// standalone DLSS Neural Rendering video reference.
    case currentToPrevious
}

struct DLSS5FrameContract: Codable, Equatable, Sendable {
    var presentationTimeSeconds: Double
    var renderWidth: Int
    var renderHeight: Int
    var outputWidth: Int
    var outputHeight: Int
    var colorFormat: DLSS5ResourceFormat = .rgba16Float
    var colorEncoding: DLSS5ColorEncoding = .sRGBDisplayReferred
    var depthFormat: DLSS5ResourceFormat = .r32Float
    var motionFormat: DLSS5ResourceFormat = .rg16Float
    var jitterX: Float = 0
    var jitterY: Float = 0
    var resetHistory: Bool
    var motionVectorsAreInPixels: Bool = true
    var motionDirection: DLSS5MotionDirection = .currentToPrevious
    var depthIsReversed: Bool = true

    init(
        presentationTime: CMTime,
        renderWidth: Int,
        renderHeight: Int,
        outputWidth: Int,
        outputHeight: Int,
        resetHistory: Bool,
        colorEncoding: DLSS5ColorEncoding = .sRGBDisplayReferred
    ) {
        self.presentationTimeSeconds = presentationTime.seconds.isFinite
            ? presentationTime.seconds
            : 0
        self.renderWidth = renderWidth
        self.renderHeight = renderHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.resetHistory = resetHistory
        self.colorEncoding = colorEncoding
    }

    var renderSize: CGSize {
        CGSize(width: renderWidth, height: renderHeight)
    }

    var outputSize: CGSize {
        CGSize(width: outputWidth, height: outputHeight)
    }

    func validate() throws {
        guard renderWidth > 0,
              renderHeight > 0,
              outputWidth > 0,
              outputHeight > 0 else {
            throw DLSS5ContractError.invalidDimensions
        }
        guard colorFormat == .rgba16Float else {
            throw DLSS5ContractError.invalidColorFormat
        }
        guard depthFormat == .r32Float else {
            throw DLSS5ContractError.invalidDepthFormat
        }
        guard motionFormat == .rg16Float else {
            throw DLSS5ContractError.invalidMotionFormat
        }
        guard motionVectorsAreInPixels,
              motionDirection == .currentToPrevious else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The current DLSS Neural Rendering reference expects current-to-previous pixel-space motion vectors."
            )
        }
    }
}

enum DLSS5ContractError: LocalizedError {
    case invalidDimensions
    case invalidColorFormat
    case invalidDepthFormat
    case invalidMotionFormat
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidDimensions:
            "The DLSS 5 frame contract has invalid dimensions."
        case .invalidColorFormat:
            "DLSS 5 color input must use the RGBA16Float feeder contract."
        case .invalidDepthFormat:
            "DLSS 5 depth input must use the R32Float feeder contract."
        case .invalidMotionFormat:
            "DLSS 5 motion input must use the RG16Float feeder contract."
        case let .runtimeUnavailable(reason):
            reason
        }
    }
}

struct DLSS5RuntimeAvailability: Codable, Equatable, Sendable {
    var available: Bool
    var executionBackend: String
    var reason: String?
}

enum DLSS5RuntimeProbe {
    /// The current iOS runtime boundary is explicit. ClarityVideo will not silently
    /// substitute Apple SR and label the result as NVIDIA DLSS 5.
    static var current: DLSS5RuntimeAvailability {
        #if os(iOS)
        DLSS5RuntimeAvailability(
            available: false,
            executionBackend: "ARM64 / Metal",
            reason: "NVIDIA's current NGX/DLSS neural-rendering runtime is a proprietary NVIDIA GPU runtime and has no iOS/Metal ARM64 implementation. The feeder contract is implemented, but NVIDIA DLSS 5 execution is not yet available on-device."
        )
        #else
        DLSS5RuntimeAvailability(
            available: false,
            executionBackend: "Unsupported host",
            reason: "No DLSS 5 execution backend is linked into this ClarityVideo target."
        )
        #endif
    }
}

/// Resources produced by motion/depth preparation stages. The concrete GPU textures
/// deliberately live outside this Codable contract so the same metadata can be
/// recorded in diagnostics and reference captures.
struct DLSS5PreparedFrameMetadata: Codable, Equatable, Sendable {
    var contract: DLSS5FrameContract
    var hasColor: Bool
    var hasDepth: Bool
    var hasMotionVectors: Bool
    var sourceDescription: String

    func validateForExecution() throws {
        try contract.validate()
        guard hasColor, hasDepth, hasMotionVectors else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The DLSS 5 feeder frame is incomplete: color, depth, and motion-vector resources are all required before execution."
            )
        }
    }
}
