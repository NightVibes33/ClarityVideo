import Foundation
import CoreGraphics

enum ProcessingRoute: String, Codable, Sendable {
    case fullQualitySuperResolution
    case lowLatencySuperResolution
    case tiledSuperResolution
    case cascadedTiledSuperResolution
}

struct PipelinePlan: Codable, Equatable, Sendable {
    var route: ProcessingRoute
    var aiScaleFactor: Double
    var targetWidth: Int
    var targetHeight: Int
    var requiresFinalResize: Bool
    var requiresTiling: Bool
    var tileWidth: Int?
    var tileHeight: Int?
    var overlap: Int?
    var disclosure: String
}

enum PipelinePlanningError: LocalizedError {
    case noSuperResolutionRoute
    var errorDescription: String? {
        "This device reported no Apple super-resolution route for the selected source and output."
    }
}

enum PipelinePlanner {
    static func plan(
        sourceWidth: Int,
        sourceHeight: Int,
        target: OutputResolution,
        mode: EnhancementMode,
        capabilities: DeviceEnhancementCapabilities,
        lowLatencyFactorsForSource: [Double]
    ) throws -> PipelinePlan {
        let encodedPortrait = sourceHeight > sourceWidth
        let landscape = target.landscapeSize
        let targetWidth = Int(encodedPortrait ? landscape.height : landscape.width)
        let targetHeight = Int(encodedPortrait ? landscape.width : landscape.height)
        let requiredScale = max(Double(targetWidth) / Double(sourceWidth), Double(targetHeight) / Double(sourceHeight))

        let fullFactors = capabilities.supportedFullScaleFactors.sorted()
        let selectedFull = fullFactors.first { Double($0) >= requiredScale } ?? fullFactors.last
        let lowFactors = lowLatencyFactorsForSource.sorted()
        let selectedLow = lowFactors.first { $0 >= requiredScale } ?? lowFactors.last
        let fullFrameEligible = capabilities.fullSuperResolutionAvailable
            && sourceWidth <= 1440 && sourceHeight <= 1080 && selectedFull != nil
        let preferLow = mode == .fast && capabilities.lowLatencySuperResolutionAvailable && selectedLow != nil

        if preferLow, let factor = selectedLow {
            return makePlan(
                route: .lowLatencySuperResolution,
                factor: factor,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                tiled: false
            )
        }
        if fullFrameEligible, let factor = selectedFull {
            return makePlan(
                route: .fullQualitySuperResolution,
                factor: Double(factor),
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                tiled: false
            )
        }
        if capabilities.lowLatencySuperResolutionAvailable, let factor = selectedLow {
            return makePlan(
                route: .lowLatencySuperResolution,
                factor: factor,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                tiled: false
            )
        }
        guard capabilities.fullSuperResolutionAvailable, let tileFactor = selectedFull else {
            throw PipelinePlanningError.noSuperResolutionRoute
        }

        let tileWidth = sourceWidth >= 1920 ? 960 : min(sourceWidth, 1280)
        let tileHeight = sourceHeight >= 1080 ? 540 : min(sourceHeight, 720)
        let route: ProcessingRoute = .tiledSuperResolution
        var plan = makePlan(
            route: route,
            factor: Double(tileFactor),
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            tiled: true
        )
        plan.tileWidth = tileWidth
        plan.tileHeight = tileHeight
        plan.overlap = 32
        return plan
    }

    private static func makePlan(
        route: ProcessingRoute,
        factor: Double,
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        tiled: Bool
    ) -> PipelinePlan {
        let neuralWidth = Double(sourceWidth) * factor
        let neuralHeight = Double(sourceHeight) * factor
        let exact = abs(neuralWidth - Double(targetWidth)) < 0.5 && abs(neuralHeight - Double(targetHeight)) < 0.5
        let disclosure: String
        if tiled {
            disclosure = exact
                ? "AI enhanced in overlapping tiles and blended to the exact output size."
                : "AI enhanced in overlapping tiles; a high-quality final resize produces the exact output dimensions."
        } else {
            disclosure = exact
                ? "Apple super resolution produces the exact output dimensions."
                : "Apple super resolution supplies the neural scale; a high-quality final resize produces the exact output dimensions."
        }
        return PipelinePlan(
            route: route,
            aiScaleFactor: factor,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            requiresFinalResize: !exact,
            requiresTiling: tiled,
            disclosure: disclosure
        )
    }
}
