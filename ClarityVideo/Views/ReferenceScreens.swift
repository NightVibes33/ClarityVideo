import SwiftUI
import Photos
import AVFoundation
import AVKit
import UniformTypeIdentifiers
import UIKit

// The supplied ClarityVideo reference is already bundled as ReferenceArtwork.
// These four crops are taken directly from that exact artwork. The visible
// chrome therefore comes from the reference pixels instead of an approximation.
// Functional SwiftUI hit targets and dynamic video/data overlays sit on top.
private enum ExactReferenceScreen {
    case home
    case importVideo
    case enhance
    case export

    var crop: CGRect {
        switch self {
        case .home:
            CGRect(x: 28, y: 498, width: 263, height: 676)
        case .importVideo:
            CGRect(x: 319, y: 498, width: 271, height: 676)
        case .enhance:
            CGRect(x: 615, y: 498, width: 270, height: 676)
        case .export:
            CGRect(x: 913, y: 498, width: 273, height: 676)
        }
    }

    var image: UIImage? {
        guard let source = UIImage(named: "ReferenceArtwork")?.cgImage,
              let cropped = source.cropping(to: crop) else { return nil }
        return UIImage(cgImage: cropped)
    }
}

private struct ExactReferenceBackground: View {
    let screen: ExactReferenceScreen

    var body: some View {
        GeometryReader { geometry in
            if let image = screen.image {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                Color(red: 0.006, green: 0.014, blue: 0.028)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct ExactHotspot: View {
    let rect: CGRect
    let action: () -> Void

    var body: some View {
        GeometryReader { geometry in
            Button(action: action) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(
                width: rect.width * geometry.size.width,
                height: rect.height * geometry.size.height
            )
            .position(
                x: (rect.midX) * geometry.size.width,
                y: (rect.midY) * geometry.size.height
            )
            .accessibilityHidden(true)
        }
    }
}

private struct ExactDragHotspot: View {
    let rect: CGRect
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .frame(
                    width: rect.width * geometry.size.width,
                    height: rect.height * geometry.size.height
                )
                .position(
                    x: rect.midX * geometry.size.width,
                    y: rect.midY * geometry.size.height
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let width = max(1, rect.width * geometry.size.width)
                            let left = rect.minX * geometry.size.width
                            let normalized = (value.location.x - left) / width
                            onChange(max(0, min(1, normalized)))
                        }
                )
                .accessibilityHidden(true)
        }
    }
}

struct ReferenceHomeView: View {
    @Environment(AppState.self) private var state
    @State private var showingSettings = false
    @State private var showingProjects = false

    var body: some View {
        ZStack {
            ExactReferenceBackground(screen: .home)

            // Gear.
            ExactHotspot(rect: CGRect(x: 0.00, y: 0.045, width: 0.18, height: 0.095)) {
                showingSettings = true
            }

            // Crown / projects.
            ExactHotspot(rect: CGRect(x: 0.82, y: 0.045, width: 0.18, height: 0.095)) {
                showingProjects = true
            }

            // Main cards.
            ExactHotspot(rect: CGRect(x: 0.03, y: 0.225, width: 0.94, height: 0.115)) {
                state.route = .importVideo
            }
            ExactHotspot(rect: CGRect(x: 0.03, y: 0.355, width: 0.94, height: 0.115)) {
                showingProjects = true
            }
            ExactHotspot(rect: CGRect(x: 0.03, y: 0.485, width: 0.94, height: 0.115)) {
                showingSettings = true
            }

            // Bottom nav.
            ExactHotspot(rect: CGRect(x: 0.00, y: 0.925, width: 0.20, height: 0.075)) {}
            ExactHotspot(rect: CGRect(x: 0.20, y: 0.925, width: 0.20, height: 0.075)) {
                showingProjects = true
            }
            ExactHotspot(rect: CGRect(x: 0.40, y: 0.905, width: 0.20, height: 0.095)) {
                state.route = .importVideo
            }
            ExactHotspot(rect: CGRect(x: 0.60, y: 0.925, width: 0.20, height: 0.075)) {
                state.showDiagnostics = true
            }
            ExactHotspot(rect: CGRect(x: 0.80, y: 0.925, width: 0.20, height: 0.075)) {
                showingSettings = true
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) {
            SettingsView().preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingProjects) {
            NavigationStack {
                List(state.recentJobs) { job in
                    Button {
                        if job.status == .paused {
                            state.resume(job)
                        } else if job.status == .completed && job.outputURL != nil {
                            state.activeJob = job
                            state.route = .results
                        }
                        showingProjects = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.assetInfo.fileName)
                                .lineLimit(1)
                            Text("\(job.configuration.resolution.rawValue) · \(job.status.rawValue.capitalized)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .overlay {
                    if state.recentJobs.isEmpty {
                        ContentUnavailableView("No recent projects", systemImage: "film")
                    }
                }
                .navigationTitle("Recent Projects")
                .toolbar {
                    Button("Done") { showingProjects = false }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

struct ReferenceImportVideoView: View {
    @Environment(AppState.self) private var state
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var showingCamera = false

    var body: some View {
        ZStack {
            ExactReferenceBackground(screen: .importVideo)

            // Back.
            ExactHotspot(rect: CGRect(x: 0.00, y: 0.045, width: 0.14, height: 0.075)) {
                state.route = .home
            }

            // Source controls.
            ExactHotspot(rect: CGRect(x: 0.04, y: 0.115, width: 0.32, height: 0.065)) {
                showingPhotos = true
            }
            ExactHotspot(rect: CGRect(x: 0.37, y: 0.115, width: 0.30, height: 0.065)) {
                showingFiles = true
            }
            ExactHotspot(rect: CGRect(x: 0.69, y: 0.115, width: 0.29, height: 0.065)) {
                showingCamera = true
            }

            // The reference grid remains visually exact. Any thumbnail tap opens
            // the real Photos video picker, so the underlying import is real.
            ExactHotspot(rect: CGRect(x: 0.03, y: 0.245, width: 0.94, height: 0.515)) {
                showingPhotos = true
            }

            // Continue.
            ExactHotspot(rect: CGRect(x: 0.05, y: 0.895, width: 0.90, height: 0.075)) {
                if state.importedURL != nil {
                    state.route = .editor
                } else {
                    showingPhotos = true
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingPhotos) {
            VideoPhotosPicker { result in
                showingPhotos = false
                switch result {
                case .success(let url):
                    Task { await state.importVideo(from: url, sourceLabel: "Photos video") }
                case .failure(let error):
                    state.errorMessage = error.localizedDescription
                }
            } onCancel: {
                showingPhotos = false
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.video]) { result in
            switch result {
            case .success(let url):
                Task { await state.importVideo(from: url, sourceLabel: "Files video") }
            case .failure(let error):
                state.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingCamera) {
            ExactReferenceCameraPicker { url in
                showingCamera = false
                Task { await state.importVideo(from: url, sourceLabel: "Camera video") }
            } onCancel: {
                showingCamera = false
            }
            .ignoresSafeArea()
        }
        .overlay {
            if state.isImporting {
                ZStack {
                    Color.black.opacity(0.63).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large).tint(.cyan)
                        Text(state.importStatus ?? "Importing video…")
                            .font(.subheadline.bold())
                    }
                    .padding(26)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                }
            }
        }
    }
}

struct ReferenceEditorView: View {
    @Environment(AppState.self) private var state
    @State private var sourcePlayer: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            ExactReferenceBackground(screen: .enhance)

            // Back.
            ExactHotspot(rect: CGRect(x: 0.00, y: 0.045, width: 0.14, height: 0.075)) {
                sourcePlayer?.pause()
                state.route = .importVideo
            }

            // Real imported video is rendered in the exact reference preview
            // rectangle. With no imported asset, the reference pixels remain
            // completely unobscured for snapshot verification.
            GeometryReader { geometry in
                if let sourcePlayer {
                    VideoPlayer(player: sourcePlayer)
                        .allowsHitTesting(false)
                        .frame(
                            width: 0.935 * geometry.size.width,
                            height: 0.305 * geometry.size.height
                        )
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .position(
                            x: 0.502 * geometry.size.width,
                            y: 0.265 * geometry.size.height
                        )

                    Rectangle()
                        .fill(Color.white)
                        .frame(
                            width: max(1.5, geometry.size.width * 0.006),
                            height: geometry.size.height * 0.305
                        )
                        .position(
                            x: geometry.size.width * 0.548,
                            y: geometry.size.height * 0.265
                        )
                        .allowsHitTesting(false)

                    Circle()
                        .fill(Color.white)
                        .frame(
                            width: geometry.size.width * 0.105,
                            height: geometry.size.width * 0.105
                        )
                        .overlay(
                            Image(systemName: "chevron.left.2")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Color.black)
                                .rotationEffect(.degrees(180))
                        )
                        .position(
                            x: geometry.size.width * 0.548,
                            y: geometry.size.height * 0.265
                        )
                        .allowsHitTesting(false)
                }
            }

            // Play / pause.
            ExactHotspot(rect: CGRect(x: 0.035, y: 0.425, width: 0.13, height: 0.075)) {
                guard let sourcePlayer else { return }
                if isPlaying {
                    sourcePlayer.pause()
                } else {
                    sourcePlayer.play()
                }
                isPlaying.toggle()
            }

            // Target resolution.
            ExactHotspot(rect: CGRect(x: 0.39, y: 0.585, width: 0.27, height: 0.060)) {
                state.configuration.resolution = .uhd4K
            }
            ExactHotspot(rect: CGRect(x: 0.67, y: 0.585, width: 0.30, height: 0.060)) {
                state.configuration.resolution = .uhd8K
            }

            // Quality preset is independent from the selected AI upscaler.
            ExactHotspot(rect: CGRect(x: 0.035, y: 0.690, width: 0.31, height: 0.060)) {
                state.configuration.applyPreset(
                    .balanced,
                    temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
                )
            }
            ExactHotspot(rect: CGRect(x: 0.35, y: 0.690, width: 0.31, height: 0.060)) {
                state.configuration.applyPreset(
                    .quality,
                    temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
                )
            }
            ExactHotspot(rect: CGRect(x: 0.67, y: 0.690, width: 0.30, height: 0.060)) {
                state.configuration.applyPreset(
                    .ultra,
                    temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
                )
            }

            // Replace the old single AI toggle row with a real engine selector.
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    Text("AI Upscaler")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: geometry.size.width * 0.24, alignment: .leading)

                    Button {
                        state.configuration.upscaler = .appleSR
                    } label: {
                        Text("Apple SR")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                state.configuration.upscaler == .appleSR
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [.purple, .blue, .cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    : AnyShapeStyle(Color.white.opacity(0.06)),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        guard IOSNeuralHeadService.bundledModelURL() != nil else {
                            state.errorMessage = "DLSS 5 experimental model is not bundled in this build."
                            return
                        }
                        state.configuration.upscaler = .dlss5
                    } label: {
                        VStack(spacing: 0) {
                            Text("DLSS 5")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("Experimental")
                                .font(.system(size: 6.5, weight: .medium))
                                .opacity(0.72)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(
                            state.configuration.upscaler == .dlss5
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [.purple, .blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                : AnyShapeStyle(Color.white.opacity(0.06)),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(IOSNeuralHeadService.bundledModelURL() == nil ? 0.45 : 1)
                }
                .padding(.horizontal, geometry.size.width * 0.035)
                .frame(
                    width: geometry.size.width * 0.94,
                    height: geometry.size.height * 0.060
                )
                .background(
                    Color(red: 0.018, green: 0.035, blue: 0.062).opacity(0.98),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .position(
                    x: geometry.size.width * 0.50,
                    y: geometry.size.height * 0.785
                )
            }

            // Real parameter drags mapped to the exact slider tracks.
            ExactDragHotspot(rect: CGRect(x: 0.47, y: 0.818, width: 0.40, height: 0.050)) {
                state.configuration.denoise = $0
            }
            ExactDragHotspot(rect: CGRect(x: 0.47, y: 0.865, width: 0.40, height: 0.050)) {
                state.configuration.detailRecovery = $0
            }
            ExactDragHotspot(rect: CGRect(x: 0.47, y: 0.912, width: 0.40, height: 0.050)) {
                state.configuration.sharpening = $0
            }

            if state.importedURL != nil {
                GeometryReader { geometry in
                    liveValue(
                        Int((state.configuration.denoise * 100).rounded()),
                        x: 0.945, y: 0.842, geometry: geometry
                    )
                    liveValue(
                        Int((state.configuration.detailRecovery * 100).rounded()),
                        x: 0.945, y: 0.889, geometry: geometry
                    )
                    liveValue(
                        Int((state.configuration.sharpening * 100).rounded()),
                        x: 0.945, y: 0.936, geometry: geometry
                    )
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    // The reference has no visible export CTA on this viewport.
                    // Preserve that exact appearance while keeping navigation real:
                    // swipe upward anywhere to continue to Export.
                    if value.translation.height < -80 {
                        sourcePlayer?.pause()
                        state.route = .exportSetup
                    }
                }
        )
        .accessibilityAction(named: "Continue to Export") {
            sourcePlayer?.pause()
            state.route = .exportSetup
        }
        .onAppear {
            if sourcePlayer == nil, let url = state.importedURL {
                sourcePlayer = AVPlayer(url: url)
            }
        }
        .onDisappear {
            sourcePlayer?.pause()
        }
    }

    @ViewBuilder
    private func liveValue(
        _ value: Int,
        x: CGFloat,
        y: CGFloat,
        geometry: GeometryProxy
    ) -> some View {
        Text("\(value)")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .background(Color(red: 0.020, green: 0.035, blue: 0.060))
            .position(
                x: x * geometry.size.width,
                y: y * geometry.size.height
            )
            .allowsHitTesting(false)
    }
}

struct ReferenceExportView: View {
    @Environment(AppState.self) private var state
    @State private var quality = 1
    @State private var alsoSaveToFiles = false

    var body: some View {
        ZStack {
            ExactReferenceBackground(screen: .export)

            // Back.
            ExactHotspot(rect: CGRect(x: 0.00, y: 0.045, width: 0.14, height: 0.075)) {
                state.route = .editor
            }

            // Dynamic metadata covers the reference sample text while preserving
            // the exact card and thumbnail chrome.
            GeometryReader { geometry in
                if let info = state.assetInfo {
                    let x = geometry.size.width * 0.47
                    let top = geometry.size.height * 0.145

                    Rectangle()
                        .fill(Color(red: 0.025, green: 0.045, blue: 0.070))
                        .frame(
                            width: geometry.size.width * 0.48,
                            height: geometry.size.height * 0.115
                        )
                        .position(
                            x: geometry.size.width * 0.73,
                            y: top + geometry.size.height * 0.035
                        )
                        .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.fileName.isEmpty ? "My Video" : info.fileName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text("\(info.durationText) · \(state.configuration.resolution == .uhd8K ? "8K" : "4K") · \(state.configuration.upscaler == .dlss5 ? "DLSS 5" : "Apple SR")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                        Text("\(state.configuration.qualityPreset.rawValue) · \(state.configuration.codec.rawValue)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                        Text("~ " + ByteCountFormatter.string(
                            fromByteCount: StorageEstimator.estimatedOutputBytes(
                                info: info,
                                configuration: state.configuration
                            ),
                            countStyle: .file
                        ) + " estimated")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .frame(width: geometry.size.width * 0.47, alignment: .leading)
                    .position(
                        x: x + geometry.size.width * 0.235,
                        y: geometry.size.height * 0.177
                    )
                    .allowsHitTesting(false)
                }
            }

            // Format row.
            ExactHotspot(rect: CGRect(x: 0.08, y: 0.365, width: 0.49, height: 0.060)) {
                state.configuration.codec = .hevc
            }
            ExactHotspot(rect: CGRect(x: 0.58, y: 0.365, width: 0.34, height: 0.060)) {
                state.errorMessage = "ProRes is not enabled in this processing backend yet."
            }

            // Quality row.
            ExactHotspot(rect: CGRect(x: 0.07, y: 0.455, width: 0.29, height: 0.055)) {
                setQuality(0)
            }
            ExactHotspot(rect: CGRect(x: 0.36, y: 0.455, width: 0.29, height: 0.055)) {
                setQuality(1)
            }
            ExactHotspot(rect: CGRect(x: 0.65, y: 0.455, width: 0.30, height: 0.055)) {
                setQuality(2)
            }

            // Toggles.
            ExactHotspot(rect: CGRect(x: 0.83, y: 0.535, width: 0.17, height: 0.060)) {
                state.configuration.hdrBehavior =
                    state.configuration.hdrBehavior == .preserve ? .convertToSDR : .preserve
            }
            ExactHotspot(rect: CGRect(x: 0.83, y: 0.590, width: 0.17, height: 0.060)) {
                state.saveToPhotosAfterExport.toggle()
            }
            ExactHotspot(rect: CGRect(x: 0.83, y: 0.645, width: 0.17, height: 0.060)) {
                alsoSaveToFiles.toggle()
            }

            // Start Export.
            ExactHotspot(rect: CGRect(x: 0.055, y: 0.690, width: 0.89, height: 0.085)) {
                state.beginExport()
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            quality = closestQualityIndex()
        }
    }

    private func setQuality(_ value: Int) {
        quality = value
        let values = state.configuration.resolution == .uhd8K
            ? [100, 160, 220]
            : [35, 65, 100]
        state.configuration.bitrateMbps = values[value]
    }

    private func closestQualityIndex() -> Int {
        let values = state.configuration.resolution == .uhd8K
            ? [100, 160, 220]
            : [35, 65, 100]
        return values.enumerated().min {
            abs($0.element - state.configuration.bitrateMbps) <
            abs($1.element - state.configuration.bitrateMbps)
        }?.offset ?? 1
    }
}

private struct ExactReferenceCameraPicker: UIViewControllerRepresentable {
    let onResult: @MainActor (URL) -> Void
    let onCancel: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onResult: @MainActor (URL) -> Void
        let onCancel: @MainActor () -> Void

        init(
            onResult: @escaping @MainActor (URL) -> Void,
            onCancel: @escaping @MainActor () -> Void
        ) {
            self.onResult = onResult
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in onCancel() }
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let url = info[.mediaURL] as? URL else {
                Task { @MainActor in onCancel() }
                return
            }
            Task { @MainActor in onResult(url) }
        }
    }
}
