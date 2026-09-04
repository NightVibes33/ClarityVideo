import Foundation
import CoreGraphics

/// Portable, Metal-native counterpart to the versioned build/frame boundary used
/// by community DLSS 5 feeders. Windows process handles, named pipes and shared
/// D3D fences are deliberately excluded; ClarityVideo owns all four resources in
/// one iOS process.
enum DLSS5FeedProtocol {
    static let magic: UInt32 = 0x35534C44 // 'DLS5'
    static let version: UInt32 = 1
}

enum DLSS5FeedSlot: Int, Codable, CaseIterable, Sendable {
    case color = 0
    case output
    case depth
    case motionVectors
}

struct DLSS5FeedBuild: Codable, Equatable, Sendable {
    var magic = DLSS5FeedProtocol.magic
    var version = DLSS5FeedProtocol.version
    var workWidth: Int
    var workHeight: Int
    var targetWidth: Int
    var targetHeight: Int
    var hdr: Bool
    var depthInverted: Bool
    var motionVectorScaleX: Float
    var motionVectorScaleY: Float

    var usesSuperResolution: Bool {
        targetWidth != workWidth || targetHeight != workHeight
    }

    init(contract: DLSS5FrameContract, hdr: Bool = true) {
        workWidth = contract.renderWidth
        workHeight = contract.renderHeight
        targetWidth = contract.outputWidth
        targetHeight = contract.outputHeight
        self.hdr = hdr
        depthInverted = contract.depthIsReversed
        motionVectorScaleX = contract.motionVectorsAreInPixels ? 1 : Float(contract.renderWidth)
        motionVectorScaleY = contract.motionVectorsAreInPixels ? 1 : Float(contract.renderHeight)
    }

    func validate() throws {
        guard magic == DLSS5FeedProtocol.magic, version == DLSS5FeedProtocol.version else {
            throw DLSS5ContractError.runtimeUnavailable("Unsupported DLSS 5 feed protocol version.")
        }
        guard workWidth > 0, workHeight > 0, targetWidth > 0, targetHeight > 0 else {
            throw DLSS5ContractError.invalidDimensions
        }
        guard targetWidth >= workWidth, targetHeight >= workHeight else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The DLSS 5 feed target cannot be smaller than its work resolution."
            )
        }
        guard motionVectorScaleX.isFinite, motionVectorScaleY.isFinite else {
            throw DLSS5ContractError.runtimeUnavailable("Invalid DLSS 5 motion-vector scale.")
        }
    }
}

struct DLSS5FeedFrameMessage: Codable, Equatable, Sendable {
    var sequence: UInt64
    var reset: Bool
    var jitterX: Float
    var jitterY: Float

    init(sequence: UInt64, contract: DLSS5FrameContract) {
        self.sequence = sequence
        reset = contract.resetHistory
        jitterX = contract.jitterX
        jitterY = contract.jitterY
    }

    func validate() throws {
        guard jitterX.isFinite, jitterY.isFinite else {
            throw DLSS5ContractError.runtimeUnavailable("DLSS 5 jitter must be finite.")
        }
    }
}

struct DLSS5FeedDescriptor: Codable, Equatable, Sendable {
    var build: DLSS5FeedBuild
    var frame: DLSS5FeedFrameMessage
    var colorFormat: DLSS5ResourceFormat
    var outputFormat: DLSS5ResourceFormat
    var depthFormat: DLSS5ResourceFormat
    var motionFormat: DLSS5ResourceFormat

    init(metadata: DLSS5PreparedFrameMetadata, sequence: UInt64) {
        build = DLSS5FeedBuild(contract: metadata.contract)
        frame = DLSS5FeedFrameMessage(sequence: sequence, contract: metadata.contract)
        colorFormat = metadata.contract.colorFormat
        outputFormat = .rgba16Float
        depthFormat = metadata.contract.depthFormat
        motionFormat = metadata.contract.motionFormat
    }

    func validate() throws {
        try build.validate()
        try frame.validate()
        guard colorFormat == .rgba16Float,
              outputFormat == .rgba16Float,
              depthFormat == .r32Float,
              motionFormat == .rg16Float else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The Metal DLSS 5 feed descriptor does not match the required resource formats."
            )
        }
    }
}
