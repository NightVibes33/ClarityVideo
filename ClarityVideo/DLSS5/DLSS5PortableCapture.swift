import Foundation
import Metal

struct DLSS5PortableCaptureHeader: Codable, Sendable {
    var format = "ClarityVideo.DLSS5ReferenceCapture"
    var version = 2
    var metadata: DLSS5PreparedFrameMetadata
    var neuralRendering: DLSS5NeuralRenderingPacket?
    var colorBytes: Int
    var depthBytes: Int
    var motionBytes: Int
}

@MainActor
enum DLSS5PortableCaptureWriter {
    private static let magic = Data([0x43, 0x56, 0x44, 0x4C, 0x53, 0x53, 0x35, 0x00]) // CVDLSS5\0

    static func write(_ frame: DLSS5PreparedFrame, to url: URL) throws {
        try frame.metadata.validateForExecution()
        let width = frame.metadata.contract.renderWidth
        let height = frame.metadata.contract.renderHeight
        let color = try textureData(frame.color, width: width, height: height, bytesPerPixel: 8)
        let depth = try textureData(frame.depth, width: width, height: height, bytesPerPixel: 4)
        let motion = try textureData(frame.motion, width: width, height: height, bytesPerPixel: 4)

        let neuralRendering = DLSS5NeuralRenderingPacket(contract: frame.metadata.contract)
        try neuralRendering.validate()
        let header = DLSS5PortableCaptureHeader(
            metadata: frame.metadata,
            neuralRendering: neuralRendering,
            colorBytes: color.count,
            depthBytes: depth.count,
            motionBytes: motion.count
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let headerData = try encoder.encode(header)
        guard headerData.count <= Int(UInt32.max) else {
            throw DLSS5ContractError.runtimeUnavailable("The DLSS 5 capture header is unexpectedly large.")
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var package = Data()
        package.reserveCapacity(magic.count + 4 + headerData.count + color.count + depth.count + motion.count)
        package.append(magic)
        var headerLength = UInt32(headerData.count).littleEndian
        withUnsafeBytes(of: &headerLength) { package.append(contentsOf: $0) }
        package.append(headerData)
        package.append(color)
        package.append(depth)
        package.append(motion)
        try package.write(to: url, options: .atomic)
    }

    static func validate(url: URL) throws -> DLSS5PortableCaptureHeader {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= magic.count + 4,
              data.prefix(magic.count) == magic else {
            throw DLSS5ContractError.runtimeUnavailable("This is not a ClarityVideo DLSS 5 reference capture.")
        }
        let lengthOffset = magic.count
        let headerLength: UInt32 = data[lengthOffset..<(lengthOffset + 4)].withUnsafeBytes { raw in
            raw.loadUnaligned(as: UInt32.self).littleEndian
        }
        let headerStart = lengthOffset + 4
        let headerEnd = headerStart + Int(headerLength)
        guard headerEnd <= data.count else {
            throw DLSS5ContractError.runtimeUnavailable("The DLSS 5 capture header is truncated.")
        }
        let header = try JSONDecoder().decode(
            DLSS5PortableCaptureHeader.self,
            from: data.subdata(in: headerStart..<headerEnd)
        )
        let expected = headerEnd + header.colorBytes + header.depthBytes + header.motionBytes
        guard expected == data.count else {
            throw DLSS5ContractError.runtimeUnavailable(
                "The DLSS 5 capture payload size does not match its manifest."
            )
        }
        try header.metadata.validateForExecution()
        if header.version >= 2 {
            guard let neuralRendering = header.neuralRendering else {
                throw DLSS5ContractError.runtimeUnavailable(
                    "Version 2 DLSS 5 captures must contain the Neural Rendering feature-18 semantic packet."
                )
            }
            try neuralRendering.validate()
        }
        return header
    }

    private static func textureData(
        _ texture: any MTLTexture,
        width: Int,
        height: Int,
        bytesPerPixel: Int
    ) throws -> Data {
        guard texture.storageMode == .shared else {
            throw DLSS5ContractError.runtimeUnavailable(
                "Portable capture requires a CPU-readable shared Metal texture."
            )
        }
        let bytesPerRow = width * bytesPerPixel
        var data = Data(count: bytesPerRow * height)
        data.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        return data
    }
}
