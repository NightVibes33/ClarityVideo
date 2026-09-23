import CoreML
import CoreVideo
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Pass the depth mlpackage path") }
let package = URL(fileURLWithPath: CommandLine.arguments[1])
let compiled = try MLModel.compileModel(at: package)
let model = try MLModel(contentsOf: compiled, configuration: MLModelConfiguration())
guard let image = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint,
      model.modelDescription.outputDescriptionsByName["depth"]?.type == .image else {
    fatalError("Depth model must accept image and return a depth image")
}
var pixelBuffer: CVPixelBuffer?
let status = CVPixelBufferCreate(kCFAllocatorDefault, image.pixelsWide, image.pixelsHigh,
                                 kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
guard status == kCVReturnSuccess, let pixelBuffer else { fatalError("Pixel buffer: \(status)") }
CVPixelBufferLockBaseAddress(pixelBuffer, [])
if let bytes = CVPixelBufferGetBaseAddress(pixelBuffer)?.assumingMemoryBound(to: UInt8.self) {
    for y in 0..<image.pixelsHigh {
        for x in 0..<image.pixelsWide {
            let offset = y * CVPixelBufferGetBytesPerRow(pixelBuffer) + x * 4
            bytes[offset] = UInt8(x * 255 / image.pixelsWide)
            bytes[offset + 1] = UInt8(y * 255 / image.pixelsHigh)
            bytes[offset + 2] = 120
            bytes[offset + 3] = 255
        }
    }
}
CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
let features = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)])
let result = try model.prediction(from: features)
guard let depth = result.featureValue(for: "depth")?.imageBufferValue,
      CVPixelBufferGetWidth(depth) > 0, CVPixelBufferGetHeight(depth) > 0 else {
    fatalError("Depth inference returned no image")
}
print("Depth model inference passed: \(CVPixelBufferGetWidth(depth))×\(CVPixelBufferGetHeight(depth))")
