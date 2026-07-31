import CoreVideo

struct SceneCutDetector {
    private var previousSignature: [Float]?
    private let threshold: Float

    init(threshold: Float = 0.24) {
        self.threshold = threshold
    }

    mutating func isSceneCut(_ buffer: CVPixelBuffer) -> Bool {
        let current = Self.lumaSignature(buffer)
        defer { previousSignature = current }
        guard let previousSignature else { return false }
        return Self.isCut(previous: previousSignature, current: current, threshold: threshold)
    }

    mutating func reset() { previousSignature = nil }

    static func isCut(previous: [Float], current: [Float], threshold: Float = 0.24) -> Bool {
        guard previous.count == current.count, !current.isEmpty else { return false }
        let meanDifference = zip(previous, current).reduce(Float.zero) { partial, pair in
            partial + abs(pair.0 - pair.1)
        } / Float(current.count)
        return meanDifference >= threshold
    }

    private static func lumaSignature(_ buffer: CVPixelBuffer) -> [Float] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let columns = 12
        let rows = 8
        var values: [Float] = []
        values.reserveCapacity(columns * rows)

        if CVPixelBufferIsPlanar(buffer),
           let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            for row in 0..<rows {
                let y = min(height - 1, (row * height + height / 2) / rows)
                for column in 0..<columns {
                    let x = min(width - 1, (column * width + width / 2) / columns)
                    values.append(Float(bytes[y * stride + x]) / 255)
                }
            }
        } else if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0..<rows {
                let y = min(height - 1, (row * height + height / 2) / rows)
                for column in 0..<columns {
                    let x = min(width - 1, (column * width + width / 2) / columns)
                    let offset = y * stride + x * 4
                    let luma = 0.0722 * Float(bytes[offset])
                        + 0.7152 * Float(bytes[offset + 1])
                        + 0.2126 * Float(bytes[offset + 2])
                    values.append(luma / 255)
                }
            }
        }
        return values
    }
}
