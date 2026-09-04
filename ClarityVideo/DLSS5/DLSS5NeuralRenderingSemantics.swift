import Foundation

/// Semantic model of the currently observed DLSS Neural Rendering (NGX feature 18)
/// parameter surface. These keys are intentionally isolated from the Apple execution
/// path: they describe the reference contract and can be serialized/tested without
/// pretending that NVIDIA's runtime is present on iOS.
enum DLSS5NeuralRenderingKey {
    static let enabled = "DLSSNR.Enabled"
    static let upscaling = "DLSSNR.Upscaling"
    static let scale = "DLSSNR.Scale"
    static let scalingRatio = "DLSSNR.ScalingRatio"
    static let preset = "DLSSNR.Hint.Render.Preset"
    static let reset = "DLSSNR.Reset"

    static let inputWidth = "DLSSNR.InputWidth"
    static let inputHeight = "DLSSNR.InputHeight"
    static let outputWidth = "DLSSNR.OutputWidth"
    static let outputHeight = "DLSSNR.OutputHeight"
    static let outputWidthAlias = "DLSSNR.Output.Width"
    static let outputHeightAlias = "DLSSNR.Output.Height"
    static let width = "DLSSNR.Width"
    static let height = "DLSSNR.Height"

    static let color = "DLSSNR.Color"
    static let depth = "DLSSNR.Depth"
    static let motion = "DLSSNR.MVec"
    static let output = "DLSSNR.Output"

    static let depthInverted = "DLSSNR.DepthInverted"
    static let motionVectorScaleX = "DLSSNR.MVecScaleX"
    static let motionVectorScaleY = "DLSSNR.MVecScaleY"
    static let useAutoMask = "DLSSNR.UseAutoMask"

    static let intensity = "DLSSNR.Intensity"
    static let localStructureStrength = "DLSSNR.LocalStructureStrength"
    static let localToneStrength = "DLSSNR.LocalToneStrength"
    static let skinStructureStrength = "DLSSNR.SkinStructureStrength"
    static let globalToneStrength = "DLSSNR.GlobalToneStrength"
    static let style = "DLSSNR.Style"
    static let uiCorrection = "DLSSNR.UICorrection"

    static let colorSubrectBaseX = "DLSSNR.ColorSubrectBaseX"
    static let colorSubrectBaseY = "DLSSNR.ColorSubrectBaseY"
    static let colorSubrectWidth = "DLSSNR.ColorSubrectWidth"
    static let colorSubrectHeight = "DLSSNR.ColorSubrectHeight"

    static let depthSubrectBaseX = "DLSSNR.DepthSubrectBaseX"
    static let depthSubrectBaseY = "DLSSNR.DepthSubrectBaseY"
    static let depthSubrectWidth = "DLSSNR.DepthSubrectWidth"
    static let depthSubrectHeight = "DLSSNR.DepthSubrectHeight"

    static let motionSubrectBaseX = "DLSSNR.MVecSubrectBaseX"
    static let motionSubrectBaseY = "DLSSNR.MVecSubrectBaseY"
    static let motionSubrectWidth = "DLSSNR.MVecSubrectWidth"
    static let motionSubrectHeight = "DLSSNR.MVecSubrectHeight"

    static let outputSubrectBaseX = "DLSSNR.OutputSubrectBaseX"
    static let outputSubrectBaseY = "DLSSNR.OutputSubrectBaseY"
    static let outputSubrectWidth = "DLSSNR.OutputSubrectWidth"
    static let outputSubrectHeight = "DLSSNR.OutputSubrectHeight"
}

enum DLSS5NeuralRenderingStyle: UInt32, Codable, Sendable {
    case standard = 0
    case natural = 1
    case cinematic = 2
}

struct DLSS5NeuralRenderingModelParameters: Codable, Equatable, Sendable {
    var preset: UInt32 = 0
    var intensity: Float = 1
    var style: DLSS5NeuralRenderingStyle = .standard
    var localStructureStrength: Float = 1
    var localToneStrength: Float = 1
    var skinStructureStrength: Float = -1
    var globalToneStrength: Float = -1
    var autoMask = false
    var uiCorrection = false

    func validate() throws {
        let finiteValues = [
            intensity,
            localStructureStrength,
            localToneStrength,
            skinStructureStrength,
            globalToneStrength
        ]
        guard finiteValues.allSatisfy(\.isFinite),
              intensity >= 0,
              intensity <= 2,
              localStructureStrength >= 0,
              localStructureStrength <= 2,
              localToneStrength >= 0,
              localToneStrength <= 2 else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The DLSS Neural Rendering model parameters are outside the observed reference range."
            )
        }
    }
}

/// The observed video path enlarges with DLSS Super Resolution first, then runs
/// feature 18 at the final target resolution. Feature 18 itself is therefore a 1:1
/// stage even when the overall pipeline upscales.
struct DLSS5NeuralRenderingPipelinePlan: Codable, Equatable, Sendable {
    var superResolutionRequired: Bool
    var superResolutionRenderWidth: Int
    var superResolutionRenderHeight: Int
    var superResolutionTargetWidth: Int
    var superResolutionTargetHeight: Int
    var neuralRenderingWidth: Int
    var neuralRenderingHeight: Int

    init(contract: DLSS5FrameContract) {
        superResolutionRenderWidth = contract.renderWidth
        superResolutionRenderHeight = contract.renderHeight
        superResolutionTargetWidth = contract.outputWidth
        superResolutionTargetHeight = contract.outputHeight
        superResolutionRequired = contract.outputWidth != contract.renderWidth ||
            contract.outputHeight != contract.renderHeight
        neuralRenderingWidth = contract.outputWidth
        neuralRenderingHeight = contract.outputHeight
    }

    func validate() throws {
        guard superResolutionRenderWidth > 0,
              superResolutionRenderHeight > 0,
              superResolutionTargetWidth > 0,
              superResolutionTargetHeight > 0,
              neuralRenderingWidth > 0,
              neuralRenderingHeight > 0 else {
            throw DLSS5ContractError.invalidDimensions
        }
        guard superResolutionTargetWidth >= superResolutionRenderWidth,
              superResolutionTargetHeight >= superResolutionRenderHeight else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The current reference pipeline only models native-resolution or enlarged output."
            )
        }
        guard neuralRenderingWidth == superResolutionTargetWidth,
              neuralRenderingHeight == superResolutionTargetHeight else {
            throw DLSS5ContractError.runtimeUnavailable(
                "DLSS Neural Rendering must consume the final SR target resolution."
            )
        }
    }
}

struct DLSS5NeuralRenderingCreateDescriptor: Codable, Equatable, Sendable {
    var featureID: UInt32 = 18
    var inputWidth: Int
    var inputHeight: Int
    var outputWidth: Int
    var outputHeight: Int
    var upscaling = false
    var scale: Float = 1
    var scalingRatio: Float = 1
    var depthInverted: Bool
    var model: DLSS5NeuralRenderingModelParameters

    init(
        plan: DLSS5NeuralRenderingPipelinePlan,
        depthInverted: Bool,
        model: DLSS5NeuralRenderingModelParameters = .init()
    ) {
        inputWidth = plan.neuralRenderingWidth
        inputHeight = plan.neuralRenderingHeight
        outputWidth = plan.neuralRenderingWidth
        outputHeight = plan.neuralRenderingHeight
        self.depthInverted = depthInverted
        self.model = model
    }

    func validate() throws {
        guard featureID == 18 else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The Neural Rendering reference currently targets NGX feature 18."
            )
        }
        guard inputWidth > 0, inputHeight > 0,
              outputWidth > 0, outputHeight > 0 else {
            throw DLSS5ContractError.invalidDimensions
        }
        guard inputWidth == outputWidth,
              inputHeight == outputHeight,
              !upscaling,
              scale == 1,
              scalingRatio == 1 else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The observed feature-18 path is native-resolution; DLSS SR must perform enlargement before Neural Rendering."
            )
        }
        try model.validate()
    }
}

struct DLSS5NeuralRenderingEvaluateDescriptor: Codable, Equatable, Sendable {
    var reset: Bool
    var motionVectorScaleX: Float
    var motionVectorScaleY: Float

    var colorSubrectBaseX = 0
    var colorSubrectBaseY = 0
    var colorSubrectWidth: Int
    var colorSubrectHeight: Int

    var depthSubrectBaseX = 0
    var depthSubrectBaseY = 0
    var depthSubrectWidth: Int
    var depthSubrectHeight: Int

    var motionSubrectBaseX = 0
    var motionSubrectBaseY = 0
    var motionSubrectWidth: Int
    var motionSubrectHeight: Int

    var outputSubrectBaseX = 0
    var outputSubrectBaseY = 0
    var outputSubrectWidth: Int
    var outputSubrectHeight: Int

    init(
        plan: DLSS5NeuralRenderingPipelinePlan,
        reset: Bool,
        motionVectorScaleX: Float = 1,
        motionVectorScaleY: Float = 1
    ) {
        self.reset = reset
        self.motionVectorScaleX = motionVectorScaleX
        self.motionVectorScaleY = motionVectorScaleY
        colorSubrectWidth = plan.neuralRenderingWidth
        colorSubrectHeight = plan.neuralRenderingHeight
        depthSubrectWidth = plan.neuralRenderingWidth
        depthSubrectHeight = plan.neuralRenderingHeight
        motionSubrectWidth = plan.neuralRenderingWidth
        motionSubrectHeight = plan.neuralRenderingHeight
        outputSubrectWidth = plan.neuralRenderingWidth
        outputSubrectHeight = plan.neuralRenderingHeight
    }

    func validate() throws {
        let dimensions = [
            colorSubrectWidth, colorSubrectHeight,
            depthSubrectWidth, depthSubrectHeight,
            motionSubrectWidth, motionSubrectHeight,
            outputSubrectWidth, outputSubrectHeight
        ]
        guard dimensions.allSatisfy({ $0 > 0 }) else {
            throw DLSS5ContractError.invalidDimensions
        }
        guard motionVectorScaleX.isFinite, motionVectorScaleY.isFinite else {
            throw DLSS5ContractError.runtimeUnavailable(
                "DLSS Neural Rendering motion-vector scales must be finite."
            )
        }
    }
}

struct DLSS5NeuralRenderingPacket: Codable, Equatable, Sendable {
    var pipeline: DLSS5NeuralRenderingPipelinePlan
    var create: DLSS5NeuralRenderingCreateDescriptor
    var evaluate: DLSS5NeuralRenderingEvaluateDescriptor

    init(
        contract: DLSS5FrameContract,
        model: DLSS5NeuralRenderingModelParameters = .init(),
        motionVectorScaleX: Float = 1,
        motionVectorScaleY: Float = 1
    ) {
        let plan = DLSS5NeuralRenderingPipelinePlan(contract: contract)
        pipeline = plan
        create = DLSS5NeuralRenderingCreateDescriptor(
            plan: plan,
            depthInverted: contract.depthIsReversed,
            model: model
        )
        evaluate = DLSS5NeuralRenderingEvaluateDescriptor(
            plan: plan,
            reset: contract.resetHistory,
            motionVectorScaleX: motionVectorScaleX,
            motionVectorScaleY: motionVectorScaleY
        )
    }

    func validate() throws {
        try pipeline.validate()
        try create.validate()
        try evaluate.validate()
    }
}
