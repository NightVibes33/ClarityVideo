import Metal

@MainActor
extension DLSS5DepthProviderFactory {
    static func bestAvailable() -> any DLSS5DepthProvider {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return DLSS5FlatDepthProvider()
        }
        return bestAvailable(device: device)
    }
}
