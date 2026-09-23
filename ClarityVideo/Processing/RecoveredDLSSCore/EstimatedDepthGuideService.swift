import CoreImage
import CoreML
import CoreVideo
import Foundation

/// Relative depth inferred from a single video frame. It is not an engine
/// depth buffer: no monocular model can recover hidden geometry or exact units.
@MainActor
final class EstimatedDepthGuideService {
    enum Failure: LocalizedError {
        case missingModel
        case incompatibleModel
        case pixelBuffer(OSStatus)

        var errorDescription: String? {
            switch self {
            case .missingModel: "The on-device depth model is not installed."
            case .incompatibleModel: "The depth model returned an incompatible image."
            case let .pixelBuffer(status): "Could not allocate a depth image (\(status))."
            }
        }
    }

    nonisolated(unsafe) private let model: MLModel
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let inputWidth: Int
    private let inputHeight: Int

    static func bundledModelURL() -> URL? {
        Bundle.main.url(forResource: "DepthAnythingV2SmallF16P6", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "DepthAnythingV2SmallF16P6", withExtension: "mlpackage")
    }

    init() throws {
        guard let bundled = Self.bundledModelURL() else { throw Failure.missingModel }
        let url = bundled.pathExtension == "mlmodelc" ? bundled : try MLModel.compileModel(at: bundled)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let loadedModel = try MLModel(contentsOf: url, configuration: configuration)
        guard let constraint = loadedModel.modelDescription.inputDescriptionsByName["image"]?.imageConstraint,
              loadedModel.modelDescription.outputDescriptionsByName["depth"]?.type == .image,
              constraint.pixelsWide > 0, constraint.pixelsHigh > 0 else {
            throw Failure.incompatibleModel
        }
        model = loadedModel
        inputWidth = constraint.pixelsWide
        inputHeight = constraint.pixelsHigh
    }

    func estimate(source: CVPixelBuffer) async throws -> CVPixelBuffer {
        var input: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, inputWidth, inputHeight,
                                         kCVPixelFormatType_32BGRA, nil, &input)
        guard status == kCVReturnSuccess, let input else { throw Failure.pixelBuffer(status) }
        let scale = CGAffineTransform(
            scaleX: CGFloat(inputWidth) / CGFloat(CVPixelBufferGetWidth(source)),
            y: CGFloat(inputHeight) / CGFloat(CVPixelBufferGetHeight(source))
        )
        context.render(CIImage(cvPixelBuffer: source).transformed(by: scale), to: input)
        let features = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: input)])
        let prediction = try await model.prediction(from: features, options: MLPredictionOptions())
        guard let raw = prediction.featureValue(for: "depth")?.imageBufferValue else {
            throw Failure.incompatibleModel
        }
        var result: CVPixelBuffer?
        let depthStatus = CVPixelBufferCreate(kCFAllocatorDefault,
                                              CVPixelBufferGetWidth(raw), CVPixelBufferGetHeight(raw),
                                              kCVPixelFormatType_OneComponent32Float, nil, &result)
        guard depthStatus == kCVReturnSuccess, let result else { throw Failure.pixelBuffer(depthStatus) }
        context.render(CIImage(cvPixelBuffer: raw), to: result)
        return result
    }
}
