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
    static let motionSubrectBaseX = "DLSSNR.MVecSubrectBaseX"
    static let motionSubrectBaseY = "DLSSNR.MVecSubrectBaseY"
    static let outputSubrectBaseX = "DLSSNR.OutputSubrectBaseX"
    static let outputSubrectBaseY = "DLSSNR.OutputSubrectBaseY"
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

struct DLSS5NeuralRenderingCreateDescriptor: Codable, Equatable, Sendable {
    var featureID: UInt32 = 18
    var inputWidth: Int
    var inputHeight: Int
    var outputWidth: Int
    var outputHeight: Int
    var upscaling: Bool
    var depthInverted: Bool
    var model: DLSS5NeuralRenderingModelParameters

    init(
        contract: DLSS5FrameContract,
        model: DLSS5NeuralRenderingModelParameters = .init()
    ) {
        inputWidth = contract.renderWidth
        inputHeight = contract.renderHeight
        outputWidth = contract.outputWidth
        outputHeight = contract.outputHeight
        upscaling = contract.outputWidth != contract.renderWidth || contract.outputHeight != contract.renderHeight
        depthInverted = contract.depthIsReversed
        self.model = model
    }

    var scaleX: Float {
        guard inputWidth > 0 else { return 0 }
        return Float(outputWidth) / Float(inputWidth)
    }

    var scaleY: Float {
        guard inputHeight > 0 else { return 0 }
        return Float(outputHeight) / Float(inputHeight)
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
        guard outputWidth >= inputWidth, outputHeight >= inputHeight else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The current DLSS Neural Rendering reference only models native-resolution or upscale output."
            )
        }
        try model.validate()
    }
}

struct DLSS5NeuralRenderingEvaluateDescriptor: Codable, Equatable, Sendable {
    var reset: Bool
    var motionVectorScaleX: Float
    var motionVectorScaleY: Float
    var colorSubrectBaseX: Int = 0
    var colorSubrectBaseY: Int = 0
    var colorSubrectWidth: Int
    var colorSubrectHeight: Int
    var depthSubrectBaseX: Int = 0
    var depthSubrectBaseY: Int = 0
    var motionSubrectBaseX: Int = 0
    var motionSubrectBaseY: Int = 0
    var outputSubrectBaseX: Int = 0
    var outputSubrectBaseY: Int = 0

    init(contract: DLSS5FrameContract, motionVectorScaleX: Float = 1, motionVectorScaleY: Float = 1) {
        reset = contract.resetHistory
        self.motionVectorScaleX = motionVectorScaleX
        self.motionVectorScaleY = motionVectorScaleY
        colorSubrectWidth = contract.renderWidth
        colorSubrectHeight = contract.renderHeight
    }

    func validate() throws {
        guard colorSubrectWidth > 0, colorSubrectHeight > 0 else {
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
    var create: DLSS5NeuralRenderingCreateDescriptor
    var evaluate: DLSS5NeuralRenderingEvaluateDescriptor

    init(
        contract: DLSS5FrameContract,
        model: DLSS5NeuralRenderingModelParameters = .init(),
        motionVectorScaleX: Float = 1,
        motionVectorScaleY: Float = 1
    ) {
        create = DLSS5NeuralRenderingCreateDescriptor(contract: contract, model: model)
        evaluate = DLSS5NeuralRenderingEvaluateDescriptor(
            contract: contract,
            motionVectorScaleX: motionVectorScaleX,
            motionVectorScaleY: motionVectorScaleY
        )
    }

    func validate() throws {
        try create.validate()
        try evaluate.validate()
    }
}
