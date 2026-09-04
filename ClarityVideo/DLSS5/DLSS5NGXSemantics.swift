import Foundation

struct DLSS5FeatureFlags: OptionSet, Codable, Equatable, Sendable {
    let rawValue: UInt32

    static let motionVectorsLowResolution = DLSS5FeatureFlags(rawValue: 1 << 0)
    static let autoExposure               = DLSS5FeatureFlags(rawValue: 1 << 1)
    static let depthInverted              = DLSS5FeatureFlags(rawValue: 1 << 2)
    static let hdr                        = DLSS5FeatureFlags(rawValue: 1 << 3)
}

enum DLSS5PerformanceQuality: String, Codable, Sendable {
    case dlaa
    case superResolution
}

struct DLSS5FeatureCreateDescriptor: Codable, Equatable, Sendable {
    var renderWidth: Int
    var renderHeight: Int
    var targetWidth: Int
    var targetHeight: Int
    var quality: DLSS5PerformanceQuality
    var flags: DLSS5FeatureFlags

    init(build: DLSS5FeedBuild) {
        renderWidth = build.workWidth
        renderHeight = build.workHeight
        targetWidth = build.targetWidth
        targetHeight = build.targetHeight
        quality = build.usesSuperResolution ? .superResolution : .dlaa
        var flags: DLSS5FeatureFlags = [.motionVectorsLowResolution, .autoExposure]
        if build.depthInverted { flags.insert(.depthInverted) }
        if build.hdr { flags.insert(.hdr) }
        self.flags = flags
    }

    func validate() throws {
        guard renderWidth > 0, renderHeight > 0,
              targetWidth > 0, targetHeight > 0 else {
            throw DLSS5ContractError.invalidDimensions
        }
        guard targetWidth >= renderWidth, targetHeight >= renderHeight else {
            throw DLSS5ContractError.runtimeUnavailable(
                "DLSS 5 target dimensions cannot be below render dimensions."
            )
        }
        guard flags.contains(.autoExposure),
              flags.contains(.motionVectorsLowResolution) else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The ClarityVideo DLSS 5 feature descriptor is missing required feeder flags."
            )
        }
    }
}

struct DLSS5EvaluateDescriptor: Codable, Equatable, Sendable {
    var sequence: UInt64
    var renderWidth: Int
    var renderHeight: Int
    var reset: Bool
    var jitterX: Float
    var jitterY: Float
    var motionVectorScaleX: Float
    var motionVectorScaleY: Float
    var preExposure: Float = 1
    var exposureScale: Float = 1

    init(build: DLSS5FeedBuild, frame: DLSS5FeedFrameMessage) {
        sequence = frame.sequence
        renderWidth = build.workWidth
        renderHeight = build.workHeight
        reset = frame.reset
        jitterX = frame.jitterX
        jitterY = frame.jitterY
        motionVectorScaleX = build.motionVectorScaleX
        motionVectorScaleY = build.motionVectorScaleY
    }

    func validate() throws {
        guard renderWidth > 0, renderHeight > 0 else {
            throw DLSS5ContractError.invalidDimensions
        }
        let values = [
            jitterX, jitterY,
            motionVectorScaleX, motionVectorScaleY,
            preExposure, exposureScale
        ]
        guard values.allSatisfy(\.isFinite), preExposure > 0, exposureScale > 0 else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The DLSS 5 evaluation descriptor contains invalid scalar parameters."
            )
        }
    }
}

struct DLSS5NGXSemanticPacket: Codable, Equatable, Sendable {
    var feature: DLSS5FeatureCreateDescriptor
    var evaluate: DLSS5EvaluateDescriptor

    init(feed: DLSS5FeedDescriptor) {
        feature = DLSS5FeatureCreateDescriptor(build: feed.build)
        evaluate = DLSS5EvaluateDescriptor(build: feed.build, frame: feed.frame)
    }

    func validate() throws {
        try feature.validate()
        try evaluate.validate()
    }
}
