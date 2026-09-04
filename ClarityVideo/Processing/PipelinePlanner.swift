import Foundation
import CoreGraphics

enum ProcessingRoute: String, Codable, Sendable {
    case nativeEnhancement
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
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw PipelinePlanningError.noSuperResolutionRoute
        }
        let encodedPortrait = sourceHeight > sourceWidth
        let landscape = target.landscapeSize
        let targetWidth = Int(encodedPortrait ? landscape.height : landscape.width)
        let targetHeight = Int(encodedPortrait ? landscape.width : landscape.height)
        let requiredScale = max(
            Double(targetWidth) / Double(sourceWidth),
            Double(targetHeight) / Double(sourceHeight)
        )

        if requiredScale <= 1.001 {
            var nativePlan = makePlan(
                route: .nativeEnhancement, factor: 1,
                sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                targetWidth: targetWidth, targetHeight: targetHeight, tiled: false
            )
            nativePlan.disclosure = "Clarity preserves the native resolution while applying noise reduction, detail recovery, and sharpening."
            return nativePlan
        }

        let fullFactors = capabilities.supportedFullScaleFactors.sorted()
        let selectedFull = fullFactors.first { Double($0) >= requiredScale } ?? fullFactors.last
        let fullCanvasSafe: Bool
        if let selectedFull {
            let neuralWidth = Int64(sourceWidth) * Int64(selectedFull)
            let neuralHeight = Int64(sourceHeight) * Int64(selectedFull)
            // Conservative upper bound for a high-precision intermediate. Tiled processing
            // is selected when a full-frame neural surface would exceed this budget.
            let neuralCanvasBytes = neuralWidth * neuralHeight * 8
            fullCanvasSafe = neuralCanvasBytes <= 64 * 1_024 * 1_024
        } else {
            fullCanvasSafe = false
        }

        let lowFactors = lowLatencyFactorsForSource.sorted()
        let selectedLow = lowFactors.first { $0 >= requiredScale } ?? lowFactors.last
        let fullFrameEligible = capabilities.fullSuperResolutionAvailable
            && fullCanvasSafe
            && sourceWidth <= 1440
            && sourceHeight <= 1080
            && selectedFull != nil
        let preferLow = mode == .fast
            && capabilities.lowLatencySuperResolutionAvailable
            && selectedLow != nil

        if preferLow, let factor = selectedLow {
            return makePlan(
                route: .lowLatencySuperResolution,
                factor: factor,
                sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                targetWidth: targetWidth, targetHeight: targetHeight,
                tiled: false
            )
        }

        if fullFrameEligible, let factor = selectedFull {
            return makePlan(
                route: .fullQualitySuperResolution,
                factor: Double(factor),
                sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                targetWidth: targetWidth, targetHeight: targetHeight,
                tiled: false
            )
        }

        if capabilities.lowLatencySuperResolutionAvailable, let factor = selectedLow {
            return makePlan(
                route: .lowLatencySuperResolution,
                factor: factor,
                sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                targetWidth: targetWidth, targetHeight: targetHeight,
                tiled: false
            )
        }

        // If a full-quality neural factor exists, do not silently replace it with a
        // non-neural resize just because the full neural canvas is large. Process
        // smaller overlapping tiles and composite them directly into the target canvas.
        guard capabilities.fullSuperResolutionAvailable, let tileFactor = selectedFull else {
            throw PipelinePlanningError.noSuperResolutionRoute
        }

        // 960x540 keeps even a 4x neural tile at or below a single 4K BGRA surface.
        // Smaller sources simply use their full extent for that axis.
        let tileWidth = min(sourceWidth, 960)
        let tileHeight = min(sourceHeight, 540)
        guard tileWidth > 32, tileHeight > 32 else {
            throw PipelinePlanningError.noSuperResolutionRoute
        }

        var plan = makePlan(
            route: .tiledSuperResolution,
            factor: Double(tileFactor),
            sourceWidth: sourceWidth, sourceHeight: sourceHeight,
            targetWidth: targetWidth, targetHeight: targetHeight,
            tiled: true
        )
        plan.tileWidth = tileWidth
        plan.tileHeight = tileHeight
        plan.overlap = 32
        plan.disclosure = plan.requiresFinalResize
            ? "Apple super resolution runs on overlapping memory-safe tiles and each neural tile is mapped directly into the final output canvas, avoiding an oversized full-frame neural intermediate."
            : "Apple super resolution runs on overlapping memory-safe tiles and blends directly into the exact output size."
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
        let exact = abs(neuralWidth - Double(targetWidth)) < 0.5
            && abs(neuralHeight - Double(targetHeight)) < 0.5
        let disclosure: String
        if tiled {
            disclosure = exact
                ? "AI enhanced in overlapping tiles and blended to the exact output size."
                : "AI enhanced in overlapping tiles and mapped into the exact output dimensions."
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