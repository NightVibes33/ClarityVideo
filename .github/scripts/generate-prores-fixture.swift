import Foundation
import AVFoundation
import CoreVideo

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let width = 640
let height = 360
let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.proRes422,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
])
guard writer.canAdd(input) else { fatalError("macOS ProRes input unavailable") }
writer.add(input)
guard writer.startWriting() else { fatalError(writer.error?.localizedDescription ?? "ProRes writer failed") }
writer.startSession(atSourceTime: .zero)
guard let pool = adaptor.pixelBufferPool else { fatalError("ProRes pool unavailable") }
for index in 0..<2 {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
    guard status == kCVReturnSuccess, let buffer else { fatalError("ProRes buffer status \(status)") }
    CVPixelBufferLockBaseAddress(buffer, [])
    if let base = CVPixelBufferGetBaseAddress(buffer) {
        memset(base, Int32(60 + index * 80), CVPixelBufferGetBytesPerRow(buffer) * height)
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30)) else {
        fatalError(writer.error?.localizedDescription ?? "ProRes append failed")
    }
}
input.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting { semaphore.signal() }
semaphore.wait()
guard writer.status == .completed else { fatalError(writer.error?.localizedDescription ?? "ProRes finish failed") }
print("Generated ProRes fixture at \(output.path)")

let asset = AVURLAsset(url: output)
let reader = try AVAssetReader(asset: asset)
guard let track = asset.tracks(withMediaType: .video).first else { fatalError("Generated ProRes has no video track") }
let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
guard reader.canAdd(readerOutput) else { fatalError("macOS cannot attach the ProRes decoder") }
reader.add(readerOutput)
guard reader.startReading(), readerOutput.copyNextSampleBuffer() != nil else {
    fatalError(reader.error?.localizedDescription ?? "macOS could not decode the ProRes fixture")
}
print("Validated macOS ProRes 422 decode")
