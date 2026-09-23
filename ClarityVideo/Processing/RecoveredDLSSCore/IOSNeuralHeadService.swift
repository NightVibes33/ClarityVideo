import CoreImage
import CoreML
import CoreVideo
import Foundation
import Vision

/// Runs the recovered four-channel neural-rendering head on decoded video frames.
/// Its output retains the input resolution. The existing super-resolution stage
/// must run separately to reach a 4K or 8K export target.
@MainActor
final class IOSNeuralHeadService {
    enum Failure: LocalizedError {
        case missingModel
        case incompatibleModel
        case pixelBuffer(OSStatus)

        var errorDescription: String? {
            switch self {
            case .missingModel: "The recovered neural model is not installed."
            case .incompatibleModel: "The recovered neural model has an incompatible input or output."
            case let .pixelBuffer(status): "Could not allocate a neural frame (\(status))."
            }
        }
    }

    static let tileSize = 128
    // Core ML serializes predictions for this session. This instance is used by
    // one export task at a time; the framework's async prediction runs off actor.
    nonisolated(unsafe) private let model: MLModel
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let depthEstimator: EstimatedDepthGuideService
    private var previousFrame: CVPixelBuffer?

    func resetTemporalHistory() { previousFrame = nil }

    init(modelURL: URL) throws {
        let url: URL
        if modelURL.pathExtension == "mlmodelc" {
            url = modelURL
        } else if modelURL.pathExtension == "mlpackage" {
            url = try MLModel.compileModel(at: modelURL)
        } else {
            throw Failure.missingModel
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let loadedModel = try MLModel(contentsOf: url, configuration: configuration)
        guard loadedModel.modelDescription.inputDescriptionsByName["color"]?.multiArrayConstraint?.shape.map(\.intValue)
                == [1, 16, Self.tileSize, Self.tileSize],
              loadedModel.modelDescription.outputDescriptionsByName["restored"]?.multiArrayConstraint?.shape.map(\.intValue)
                == [1, 4, Self.tileSize, Self.tileSize] else {
            throw Failure.incompatibleModel
        }
        model = loadedModel
        depthEstimator = try EstimatedDepthGuideService()
    }

    static func bundledModelURL() -> URL? {
        Bundle.main.url(forResource: "DLSSNeuralHead128", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "DLSSNeuralHead128", withExtension: "mlpackage")
    }

    static func isReady() -> Bool {
        bundledModelURL() != nil && EstimatedDepthGuideService.bundledModelURL() != nil
    }

    func render(source: CVPixelBuffer, frameNumber: Int) async throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        var decoded: CVPixelBuffer?
        var result: CVPixelBuffer?
        let decodedStatus = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                                kCVPixelFormatType_32BGRA, attributes as CFDictionary, &decoded)
        guard decodedStatus == kCVReturnSuccess, let decoded else { throw Failure.pixelBuffer(decodedStatus) }
        let resultStatus = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                               kCVPixelFormatType_32BGRA, attributes as CFDictionary, &result)
        guard resultStatus == kCVReturnSuccess, let result else { throw Failure.pixelBuffer(resultStatus) }
        context.render(CIImage(cvPixelBuffer: source), to: decoded)
        // Infer a relative per-pixel depth layer from the actual frame, once
        // per frame. The temporal guide uses it to choose foreground motion.
        let depthGuide = try await depthEstimator.estimate(source: decoded)
        CVPixelBufferLockBaseAddress(depthGuide, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthGuide, .readOnly) }
        guard let depthBase = CVPixelBufferGetBaseAddress(depthGuide)?.assumingMemoryBound(to: UInt8.self),
              CVPixelBufferGetPixelFormatType(depthGuide) == kCVPixelFormatType_OneComponent32Float else {
            throw Failure.incompatibleModel
        }
        let depthWidth = CVPixelBufferGetWidth(depthGuide)
        let depthHeight = CVPixelBufferGetHeight(depthGuide)
        let depthStride = CVPixelBufferGetBytesPerRow(depthGuide)
        // Ask Vision for current-to-previous pixel displacement. Do this once per
        // frame, never once per tile; scene cuts explicitly clear the history.
        let historyFrame = previousFrame
        let flow: CVPixelBuffer?
        if let historyFrame {
            let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: decoded, options: [:])
            request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
            request.computationAccuracy = .medium
            try VNImageRequestHandler(cvPixelBuffer: historyFrame, options: [:]).perform([request])
            flow = request.results?.first?.pixelBuffer
            guard let flow,
                  CVPixelBufferGetPixelFormatType(flow) == kCVPixelFormatType_TwoComponent32Float,
                  CVPixelBufferGetWidth(flow) == width,
                  CVPixelBufferGetHeight(flow) == height else { throw Failure.incompatibleModel }
        } else {
            flow = nil
        }
        if let flow { CVPixelBufferLockBaseAddress(flow, .readOnly) }
        if let historyFrame { CVPixelBufferLockBaseAddress(historyFrame, .readOnly) }
        CVPixelBufferLockBaseAddress(decoded, .readOnly)
        CVPixelBufferLockBaseAddress(result, [])
        defer {
            CVPixelBufferUnlockBaseAddress(result, [])
            CVPixelBufferUnlockBaseAddress(decoded, .readOnly)
            if let historyFrame { CVPixelBufferUnlockBaseAddress(historyFrame, .readOnly) }
            if let flow { CVPixelBufferUnlockBaseAddress(flow, .readOnly) }
        }
        guard let inputBase = CVPixelBufferGetBaseAddress(decoded)?.assumingMemoryBound(to: UInt8.self),
              let outputBase = CVPixelBufferGetBaseAddress(result)?.assumingMemoryBound(to: UInt8.self) else {
            throw Failure.incompatibleModel
        }
        let inputStride = CVPixelBufferGetBytesPerRow(decoded)
        let outputStride = CVPixelBufferGetBytesPerRow(result)
        for tileY in stride(from: 0, to: height, by: Self.tileSize) {
            for tileX in stride(from: 0, to: width, by: Self.tileSize) {
                try Task.checkCancellation()
                var rgb = [Float](repeating: 0, count: Self.tileSize * Self.tileSize * 3)
                for y in 0..<Self.tileSize {
                    for x in 0..<Self.tileSize {
                        let srcX = min(width - 1, tileX + x)
                        let srcY = min(height - 1, tileY + y)
                        let offset = srcY * inputStride + srcX * 4
                        let target = (y * Self.tileSize + x) * 3
                        rgb[target] = Float(inputBase[offset + 2]) / 255
                        rgb[target + 1] = Float(inputBase[offset + 1]) / 255
                        rgb[target + 2] = Float(inputBase[offset]) / 255
                    }
                }
                let color = try HostTensor(
                    descriptor: TensorDescriptor(name: "color", shape: [1, Self.tileSize, Self.tileSize, 3],
                                                 dataType: .float32, layout: .nhwc),
                    bytes: rgb.withUnsafeBytes { Data($0) }
                )
                let features: HostTensor
                if let historyFrame, let flow,
                   let previousBase = CVPixelBufferGetBaseAddress(historyFrame)?.assumingMemoryBound(to: UInt8.self),
                   let flowBase = CVPixelBufferGetBaseAddress(flow)?.assumingMemoryBound(to: UInt8.self) {
                    let previousStride = CVPixelBufferGetBytesPerRow(historyFrame)
                    let flowStride = CVPixelBufferGetBytesPerRow(flow)
                    var history = [Float](repeating: 0, count: Self.tileSize * Self.tileSize * 3)
                    var motion = [Float](repeating: 0, count: Self.tileSize * Self.tileSize * 2)
                    for y in 0..<Self.tileSize {
                        for x in 0..<Self.tileSize {
                            let px = min(width - 1, tileX + x), py = min(height - 1, tileY + y)
                            let inputOffset = py * previousStride + px * 4
                            let rgbOffset = (y * Self.tileSize + x) * 3
                            history[rgbOffset] = Float(previousBase[inputOffset + 2]) / 255
                            history[rgbOffset + 1] = Float(previousBase[inputOffset + 1]) / 255
                            history[rgbOffset + 2] = Float(previousBase[inputOffset]) / 255
                            let flowOffset = py * flowStride + px * MemoryLayout<Float>.size * 2
                            let displacement = flowBase.advanced(by: flowOffset).withMemoryRebound(to: Float.self, capacity: 2) {
                                ($0[0], $0[1])
                            }
                            guard displacement.0.isFinite, displacement.1.isFinite else { throw Failure.incompatibleModel }
                            let motionOffset = (y * Self.tileSize + x) * 2
                            motion[motionOffset] = displacement.0 / Float(Self.tileSize)
                            motion[motionOffset + 1] = displacement.1 / Float(Self.tileSize)
                        }
                    }
                    let historyTensor = try HostTensor(descriptor: TensorDescriptor(name: "history", shape: [1, Self.tileSize, Self.tileSize, 3], dataType: .float32, layout: .nhwc), bytes: history.withUnsafeBytes { Data($0) })
                    let motionTensor = try HostTensor(descriptor: TensorDescriptor(name: "motion", shape: [1, Self.tileSize, Self.tileSize, 2], dataType: .float32, layout: .nhwc), bytes: motion.withUnsafeBytes { Data($0) })
                    var depth = [Float](repeating: 0, count: Self.tileSize * Self.tileSize)
                    for y in 0..<Self.tileSize {
                        for x in 0..<Self.tileSize {
                            let px = min(width - 1, tileX + x), py = min(height - 1, tileY + y)
                            let dx = min(depthWidth - 1, px * depthWidth / width)
                            let dy = min(depthHeight - 1, py * depthHeight / height)
                            let offset = dy * depthStride + dx * MemoryLayout<Float>.size
                            let value = depthBase.advanced(by: offset).withMemoryRebound(to: Float.self, capacity: 1) { $0.pointee }
                            guard value.isFinite else { throw Failure.incompatibleModel }
                            depth[y * Self.tileSize + x] = value
                        }
                    }
                    let depthTensor = try HostTensor(descriptor: TensorDescriptor(name: "depth", shape: [1, Self.tileSize, Self.tileSize, 1], dataType: .float32, layout: .nhwc), bytes: depth.withUnsafeBytes { Data($0) })
                    features = try NeuralRenderingTemporalReferencePreprocessor.makeFeatureTensor(currentColor: color, historyColor: historyTensor, normalizedMotion: motionTensor, depth: depthTensor, depthInverted: true, depthGuideMode: .closestDepth, noiseFrameIndex: UInt32(truncatingIfNeeded: frameNumber))
                } else {
                    features = try NeuralRenderingFirstFramePreprocessor.makeFeatureTensor(from: color, noiseFrameIndex: UInt32(truncatingIfNeeded: frameNumber))
                }
                let input = try MLMultiArray(shape: [1, 16, NSNumber(value: Self.tileSize), NSNumber(value: Self.tileSize)],
                                             dataType: .float32)
                let featureValues = features.bytes.withUnsafeBytes { bytes in
                    [Float](unsafeUninitializedCapacity: features.descriptor.elementCount) { buffer, count in
                        bytes.copyBytes(to: buffer)
                        count = features.descriptor.elementCount
                    }
                }
                let inputValues = input.dataPointer.assumingMemoryBound(to: Float.self)
                let inputStrides = input.strides.map(\.intValue)
                for y in 0..<Self.tileSize {
                    for x in 0..<Self.tileSize {
                        let pixel = y * Self.tileSize + x
                        for channel in 0..<16 {
                            inputValues[channel * inputStrides[1] + y * inputStrides[2] + x * inputStrides[3]]
                                = featureValues[pixel * 16 + channel]
                        }
                    }
                }
                let provider = try MLDictionaryFeatureProvider(dictionary: ["color": MLFeatureValue(multiArray: input)])
                let predicted = try await model.prediction(from: provider, options: MLPredictionOptions())
                guard let head = predicted.featureValue(for: "restored")?.multiArrayValue,
                      head.dataType == .float32,
                      head.shape.map(\.intValue) == [1, 4, Self.tileSize, Self.tileSize],
                      head.strides.count == 4 else { throw Failure.incompatibleModel }
                let headValues = head.dataPointer.assumingMemoryBound(to: Float.self)
                let headStrides = head.strides.map(\.intValue)
                var output = [Float](repeating: 0, count: Self.tileSize * Self.tileSize * 4)
                for y in 0..<Self.tileSize {
                    for x in 0..<Self.tileSize {
                        for channel in 0..<4 {
                            output[(y * Self.tileSize + x) * 4 + channel]
                                = headValues[channel * headStrides[1] + y * headStrides[2] + x * headStrides[3]]
                        }
                    }
                }
                let neuralHead = try HostTensor(
                    descriptor: TensorDescriptor(name: "restored", shape: [1, Self.tileSize, Self.tileSize, 4],
                                                 dataType: .float32, layout: .nhwc),
                    bytes: output.withUnsafeBytes { Data($0) }
                )
                let composed = try NeuralRenderingFirstFramePostprocessor.compose(head: neuralHead, over: color)
                try composed.bytes.withUnsafeBytes { raw in
                    let rendered = raw.bindMemory(to: Float.self)
                    for y in 0..<min(Self.tileSize, height - tileY) {
                        for x in 0..<min(Self.tileSize, width - tileX) {
                            let pixel = (y * Self.tileSize + x) * 3
                            let destination = (tileY + y) * outputStride + (tileX + x) * 4
                            guard rendered[pixel].isFinite, rendered[pixel + 1].isFinite,
                                  rendered[pixel + 2].isFinite else { throw Failure.incompatibleModel }
                            outputBase[destination] = UInt8(clamping: Int((rendered[pixel + 2] * 255).rounded()))
                            outputBase[destination + 1] = UInt8(clamping: Int((rendered[pixel + 1] * 255).rounded()))
                            outputBase[destination + 2] = UInt8(clamping: Int((rendered[pixel] * 255).rounded()))
                            outputBase[destination + 3] = 255
                        }
                    }
                }
            }
        }
        CVBufferPropagateAttachments(source, result)
        previousFrame = decoded
        return result
    }
}
