import SwiftUI
import Photos
import AVFoundation
import AVKit
import UniformTypeIdentifiers
import UIKit

private enum ClarityNativeTheme {
    static let background = Color(red: 0.005, green: 0.015, blue: 0.030)
    static let panel = Color(red: 0.025, green: 0.055, blue: 0.095)
    static let stroke = Color(red: 0.10, green: 0.48, blue: 1.0).opacity(0.45)
    static let muted = Color.white.opacity(0.58)
    static let brand = LinearGradient(
        colors: [Color(red: 0.69, green: 0.42, blue: 1.0), Color(red: 0.16, green: 0.58, blue: 1.0), .cyan],
        startPoint: .leading, endPoint: .trailing
    )
    static let card = LinearGradient(
        colors: [Color(red: 0.02, green: 0.17, blue: 0.36), Color(red: 0.03, green: 0.10, blue: 0.22)],
        startPoint: .leading, endPoint: .trailing
    )
}

private enum ReferenceArtworkCrop {
    static var mountain: UIImage? {
        guard let source = UIImage(named: "ReferenceArtwork")?.cgImage else { return nil }
        let w = CGFloat(source.width), h = CGFloat(source.height)
        // Clean mountain artwork only. This deliberately excludes every piece of
        // promotional text, iconography, and phone UI from the reference poster.
        let rect = CGRect(
            x: w * 0.26917,
            y: h * 0.12081,
            width: w * 0.48124,
            height: h * 0.12860
        ).integral
        guard let cropped = source.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}

private struct NativePanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ClarityNativeTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(ClarityNativeTheme.stroke, lineWidth: 1)
                    )
                    .shadow(color: .blue.opacity(0.10), radius: 12, y: 7)
            )
    }
}

private struct NativeHeader: View {
    let title: String
    var showsBack = true
    var trailingIcon: String? = nil
    var onBack: (() -> Void)? = nil
    var onTrailing: (() -> Void)? = nil

    var body: some View {
        HStack {
            Group {
                if showsBack {
                    Button { onBack?() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
            Spacer()
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Group {
                if let trailingIcon {
                    Button { onTrailing?() } label: {
                        Image(systemName: trailingIcon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
        }
        .foregroundStyle(.white)
    }
}

private struct NativeWordmark: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Clarity").foregroundStyle(.white)
            Text("Video").foregroundStyle(ClarityNativeTheme.brand)
        }
        .font(.system(size: 30, weight: .bold, design: .rounded))
    }
}

private struct NativeActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [.blue.opacity(0.95), .indigo.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 58, height: 58)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(Color(red: 0.42, green: 0.90, blue: 1.0))
                    )
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer(minLength: 0)
            }
            .padding(15)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ClarityNativeTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.blue.opacity(0.55), lineWidth: 1)
                )
        )
    }
}

struct ReferenceHomeView: View {
    @Environment(AppState.self) private var state
    @State private var showingSettings = false
    @State private var showingProjects = false

    var body: some View {
        ZStack {
            ClarityNativeTheme.background.ignoresSafeArea()
            LinearGradient(colors: [Color.blue.opacity(0.08), .clear, Color.purple.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(Color(red: 0.57, green: 0.88, blue: 1))
                    }
                    Spacer()
                    Button { showingProjects = true } label: {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(ClarityNativeTheme.brand)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                NativeWordmark().padding(.top, 12)
                Text("Sharper.  Clearer.  Better.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.56))
                    .padding(.top, 5)

                VStack(spacing: 12) {
                    NativeActionCard(icon: "video.fill", title: "Enhance Video", subtitle: "Import from Photos, Files or Camera") {
                        state.route = .importVideo
                    }
                    NativeActionCard(icon: "clock.fill", title: "Recent Projects", subtitle: "Continue your work") {
                        showingProjects = true
                    }
                    NativeActionCard(icon: "gearshape.fill", title: "Settings", subtitle: "Quality, export and advanced options") {
                        showingSettings = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                Spacer(minLength: 16)

                ZStack(alignment: .bottom) {
                    if let mountain = ReferenceArtworkCrop.mountain {
                        Image(uiImage: mountain).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom)
                            .overlay(Image(systemName: "mountain.2.fill").font(.system(size: 70)).foregroundStyle(.white.opacity(0.18)))
                    }
                    LinearGradient(colors: [.clear, ClarityNativeTheme.background.opacity(0.98)], startPoint: .top, endPoint: .bottom)
                    Text("TURN GOOD FOOTAGE\nINTO GREAT MEMORIES.")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(3.2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.bottom, 18)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 225)
                .clipped()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { homeTabBar }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) { SettingsView().preferredColorScheme(.dark) }
        .sheet(isPresented: $showingProjects) {
            NavigationStack {
                List(state.recentJobs) { job in
                    Button {
                        if job.status == .paused {
                            state.resume(job)
                        } else if job.status == .completed, job.outputURL != nil {
                            state.activeJob = job
                            state.route = .results
                        }
                        showingProjects = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.assetInfo.fileName).lineLimit(1)
                            Text("\(job.configuration.resolution.rawValue) · \(job.configuration.upscaler.rawValue) · \(job.status.rawValue.capitalized)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .overlay {
                    if state.recentJobs.isEmpty {
                        ContentUnavailableView("No recent projects", systemImage: "film")
                    }
                }
                .navigationTitle("Recent Projects")
                .toolbar { Button("Done") { showingProjects = false } }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var homeTabBar: some View {
        ZStack {
            Rectangle().fill(ClarityNativeTheme.background.opacity(0.97))
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }

            HStack {
                tab(icon: "house.fill", title: "Home", selected: true) {}
                tab(icon: "folder.fill", title: "Projects") { showingProjects = true }
                Spacer().frame(width: 78)
                tab(icon: "bolt.fill", title: "Tools") { state.showDiagnostics = true }
                tab(icon: "gearshape.fill", title: "Settings") { showingSettings = true }
            }
            .padding(.horizontal, 13)

            Button { state.route = .importVideo } label: {
                Circle()
                    .fill(Color(red: 0.04, green: 0.22, blue: 0.58))
                    .frame(width: 62, height: 62)
                    .overlay(Circle().stroke(Color.cyan.opacity(0.9), lineWidth: 2))
                    .overlay(Image(systemName: "plus").font(.system(size: 29, weight: .medium)).foregroundStyle(Color(red: 0.54, green: 0.86, blue: 1)))
                    .shadow(color: .blue.opacity(0.9), radius: 12)
            }
            .offset(y: -13)
        }
        .frame(height: 70)
    }

    private func tab(icon: String, title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(selected ? Color.cyan : Color.white.opacity(0.55))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private enum ImportSource: String, CaseIterable, Identifiable {
    case photos = "Photos", files = "Files", camera = "Camera"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .photos: "photo.on.rectangle"
        case .files: "doc.fill"
        case .camera: "camera.fill"
        }
    }
}

private enum ImportFilter: String, CaseIterable, Identifiable {
    case all = "All", videos = "Videos", favorites = "Favorites", recents = "Recents"
    var id: String { rawValue }
}

struct ReferenceImportVideoView: View {
    @Environment(AppState.self) private var state
    @State private var source: ImportSource = .photos
    @State private var filter: ImportFilter = .all
    @State private var assets: [PHAsset] = []
    @State private var selectedAsset: PHAsset?
    @State private var showingFiles = false
    @State private var showingCamera = false
    @State private var authorizationDenied = false

    private let grid = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        ZStack {
            ClarityNativeTheme.background.ignoresSafeArea()
            VStack(spacing: 12) {
                NativeHeader(title: "Import Video", onBack: { state.route = .home })
                    .padding(.horizontal, 14)

                sourceSelector.padding(.horizontal, 16)
                filterSelector.padding(.horizontal, 16)

                if authorizationDenied {
                    Spacer()
                    ContentUnavailableView(
                        "Photos Access Needed",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("Allow Photos access in Settings, or choose Files or Camera.")
                    )
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: grid, spacing: 6) {
                            ForEach(filteredAssets, id: \.localIdentifier) { asset in
                                Button { selectedAsset = asset } label: {
                                    NativeVideoThumbnail(asset: asset, selected: selectedAsset?.localIdentifier == asset.localIdentifier)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { selectionFooter }
        .preferredColorScheme(.dark)
        .task { await loadPhotoAssets() }
        .onChange(of: source) { _, newValue in
            if newValue == .files { showingFiles = true }
            if newValue == .camera { showingCamera = true }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.movie]) { result in
            source = .photos
            switch result {
            case .success(let url): Task { await state.importVideo(from: url, sourceLabel: "Files video") }
            case .failure(let error): state.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingCamera, onDismiss: { source = .photos }) {
            NativeVideoCameraPicker { url in
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
                    Color.black.opacity(0.62).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large).tint(.cyan)
                        Text(state.importStatus ?? "Importing video…").font(.subheadline.bold())
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }

    private var sourceSelector: some View {
        HStack(spacing: 7) {
            ForEach(ImportSource.allCases) { item in
                Button { source = item } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            item == source ? AnyShapeStyle(ClarityNativeTheme.brand) : AnyShapeStyle(Color.white.opacity(0.07)),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }

    private var filterSelector: some View {
        HStack(spacing: 6) {
            ForEach(ImportFilter.allCases) { item in
                Button { filter = item } label: {
                    Text(item.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            item == filter ? AnyShapeStyle(ClarityNativeTheme.brand) : AnyShapeStyle(Color.white.opacity(0.055)),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filteredAssets: [PHAsset] {
        switch filter {
        case .favorites:
            return assets.filter(\.isFavorite)
        case .recents:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            return assets.filter { ($0.creationDate ?? .distantPast) >= cutoff }
        case .all, .videos:
            return assets
        }
    }

    private var selectionFooter: some View {
        VStack(spacing: 10) {
            if let selectedAsset {
                NativePanel {
                    HStack(spacing: 11) {
                        NativeVideoThumbnail(asset: selectedAsset, selected: false)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("1 Video Selected").font(.subheadline.bold())
                            Text(durationText(selectedAsset.duration))
                                .font(.caption).foregroundStyle(ClarityNativeTheme.muted)
                        }
                        Spacer()
                    }
                    .padding(11)
                }
                .padding(.horizontal, 16)
            }

            Button {
                guard let selectedAsset else { return }
                Task {
                    do {
                        let url = try await NativePhotoAssetResolver.videoURL(for: selectedAsset)
                        await state.importVideo(from: url, sourceLabel: "Photos video")
                    } catch {
                        state.errorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Continue")
                    Image(systemName: "arrow.right")
                    Spacer()
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.vertical, 15)
                .background(ClarityNativeTheme.brand, in: RoundedRectangle(cornerRadius: 14))
                .opacity(selectedAsset == nil ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(selectedAsset == nil || state.isImporting)
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(ClarityNativeTheme.background.opacity(0.98))
    }

    @MainActor
    private func loadPhotoAssets() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            authorizationDenied = true
            return
        }
        authorizationDenied = false
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 90
        let result = PHAsset.fetchAssets(with: .video, options: options)
        var loaded: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in loaded.append(asset) }
        assets = loaded
    }

    private func durationText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct NativeVideoThumbnail: View {
    let asset: PHAsset
    let selected: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.white.opacity(0.06))
                        .overlay(ProgressView().tint(.cyan))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1.05, contentMode: .fit)
            .clipped()

            Text(durationText(asset.duration))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(5)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.cyan, .blue)
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.cyan : Color.white.opacity(0.08), lineWidth: selected ? 2 : 1))
        .task(id: asset.localIdentifier) { await loadImage() }
    }

    @MainActor
    private func loadImage() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 360, height: 360),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result { image = result }
        }
    }

    private func durationText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private enum NativePhotoAssetResolver {
    static func videoURL(for asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(throwing: AppError.importFailedReason("Photos could not provide a local video file."))
                    return
                }
                continuation.resume(returning: urlAsset.url)
            }
        }
    }
}

struct ReferenceEditorView: View {
    @Environment(AppState.self) private var state
    @State private var beforePlayer: AVPlayer?
    @State private var afterPlayer: AVPlayer?
    @State private var reveal = 0.5
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            ClarityNativeTheme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    NativeHeader(title: "Enhance", onBack: { state.route = .importVideo })
                    comparisonCard.frame(height: 250)
                    playbackBar

                    NativePanel {
                        VStack(alignment: .leading, spacing: 17) {
                            Text("Enhancement Settings")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))

                            settingLabel("Target Resolution")
                            resolutionControl

                            settingLabel("Enhancement Mode")
                            qualityControl

                            settingLabel("AI Upscaler")
                            upscalerControl

                            NativeValueSlider(
                                title: "Denoise",
                                value: Binding(get: { state.configuration.denoise }, set: { state.configuration.denoise = $0 })
                            )
                            NativeValueSlider(
                                title: "Detail Recovery",
                                value: Binding(get: { state.configuration.detailRecovery }, set: { state.configuration.detailRecovery = $0 })
                            )
                            NativeValueSlider(
                                title: "Sharpen",
                                value: Binding(get: { state.configuration.sharpening }, set: { state.configuration.sharpening = $0 })
                            )
                        }
                        .padding(14)
                    }

                    Button {
                        pausePlayers()
                        state.route = .exportSetup
                    } label: {
                        HStack {
                            Spacer()
                            Text("Continue")
                            Image(systemName: "arrow.right")
                            Spacer()
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.vertical, 15)
                        .background(ClarityNativeTheme.brand, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 16)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { configurePlayersAndPreview() }
        .onChange(of: state.comparisonPreview?.enhancedURL) { _, url in
            if let url { afterPlayer = AVPlayer(url: url) }
        }
        .onDisappear { pausePlayers() }
    }

    private var comparisonCard: some View {
        GeometryReader { geometry in
            let split = geometry.size.width * reveal
            ZStack(alignment: .leading) {
                comparisonLayer(player: afterPlayer ?? beforePlayer)
                comparisonLayer(player: beforePlayer)
                    .mask(alignment: .leading) { Rectangle().frame(width: max(1, split)) }

                Rectangle().fill(.white).frame(width: 2).offset(x: split - 1)
                Circle()
                    .fill(.white)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.black))
                    .offset(x: split - 15, y: geometry.size.height / 2 - 15)

                Text("Before")
                    .font(.caption.bold())
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(.black.opacity(0.58), in: Capsule())
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                Text("After")
                    .font(.caption.bold())
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.cyan.opacity(0.9), in: Capsule())
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                Text(state.configuration.resolution == .uhd8K ? "8K" : "4K")
                    .font(.caption.bold())
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 6))
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                if state.isGeneratingPreview {
                    VStack(spacing: 7) {
                        ProgressView(value: state.previewProgress).tint(.cyan)
                        Text("Generating real AI preview…").font(.caption.bold())
                    }
                    .padding(12)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.09), lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                reveal = max(0.05, min(0.95, value.location.x / max(1, geometry.size.width)))
            })
        }
    }

    @ViewBuilder
    private func comparisonLayer(player: AVPlayer?) -> some View {
        if let player {
            VideoPlayer(player: player).allowsHitTesting(false)
        } else if let mountain = ReferenceArtworkCrop.mountain {
            Image(uiImage: mountain).resizable().scaledToFill()
        } else {
            Rectangle().fill(Color.indigo.opacity(0.35))
        }
    }

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button {
                isPlaying.toggle()
                if isPlaying {
                    beforePlayer?.play(); afterPlayer?.play()
                } else {
                    pausePlayers()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            Text("00:00").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.66))
            Capsule().fill(Color.white.opacity(0.13)).frame(height: 4)
                .overlay(alignment: .leading) { Capsule().fill(Color.cyan).frame(width: 42, height: 4) }
            Text(state.assetInfo?.durationText ?? "00:00").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.66))
        }
        .foregroundStyle(.white)
    }

    private var resolutionControl: some View {
        NativeChoiceRow(
            options: ["4K", "8K"],
            selected: state.configuration.resolution == .uhd4K ? "4K" : "8K"
        ) { value in
            state.configuration.resolution = value == "8K" ? .uhd8K : .uhd4K
            regeneratePreview()
        }
    }

    private var qualityControl: some View {
        NativeChoiceRow(
            options: QualityPreset.allCases.map(\.rawValue),
            selected: state.configuration.qualityPreset.rawValue
        ) { value in
            guard let preset = QualityPreset(rawValue: value) else { return }
            state.configuration.applyPreset(preset, temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable)
            regeneratePreview()
        }
    }

    private var upscalerControl: some View {
        NativeChoiceRow(
            options: ["Apple SR", "DLSS 5"],
            selected: state.configuration.upscaler == .dlss5 ? "DLSS 5" : "Apple SR"
        ) { value in
            if value == "DLSS 5" {
                guard IOSNeuralHeadService.bundledModelURL() != nil else {
                    state.errorMessage = "DLSS 5 experimental model is not bundled in this build."
                    return
                }
                state.configuration.upscaler = .dlss5
            } else {
                state.configuration.upscaler = .appleSR
            }
            regeneratePreview()
        }
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
    }

    private func configurePlayersAndPreview() {
        if beforePlayer == nil, let url = state.importedURL { beforePlayer = AVPlayer(url: url) }
        if let url = state.comparisonPreview?.enhancedURL {
            afterPlayer = AVPlayer(url: url)
        } else if state.importedURL != nil && !state.isGeneratingPreview {
            state.generateComparisonPreview()
        }
    }

    private func regeneratePreview() {
        afterPlayer?.pause()
        afterPlayer = nil
        state.cancelComparisonPreview()
        state.generateComparisonPreview()
    }

    private func pausePlayers() {
        beforePlayer?.pause()
        afterPlayer?.pause()
        isPlaying = false
    }
}

private struct NativeChoiceRow: View {
    let options: [String]
    let selected: String
    let select: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button { select(option) } label: {
                    Text(option)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            option == selected ? AnyShapeStyle(ClarityNativeTheme.brand) : AnyShapeStyle(Color.white.opacity(0.055)),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct NativeValueSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 104, alignment: .leading)
            Slider(value: $value, in: 0...1).tint(.cyan)
            Text("\(Int((value * 100).rounded()))")
                .font(.caption.monospacedDigit())
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}

struct ReferenceExportView: View {
    @Environment(AppState.self) private var state
    @State private var qualityIndex = 1

    var body: some View {
        ZStack {
            ClarityNativeTheme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    NativeHeader(title: "Export", trailingIcon: "magnifyingglass", onBack: { state.route = .editor })
                    videoSummary
                    exportSettings

                    Button { state.beginExport() } label: {
                        HStack {
                            Spacer()
                            Text("Start Export")
                            Spacer()
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.vertical, 16)
                        .background(ClarityNativeTheme.brand, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Text("Processing will continue in the background.\nYou’ll be notified when it’s done.")
                        .font(.system(size: 10, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.45))

                    NativePanel {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 11)
                                .fill(Color.blue.opacity(0.13))
                                .frame(width: 44, height: 44)
                                .overlay(Image(systemName: "camera.aperture").font(.title2).foregroundStyle(.blue))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("AI Powered. On Device.").font(.subheadline.bold())
                                Text("Your privacy stays with you.").font(.caption).foregroundStyle(ClarityNativeTheme.muted)
                            }
                            Spacer()
                        }
                        .padding(13)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { qualityIndex = closestQualityIndex() }
    }

    private var videoSummary: some View {
        NativePanel {
            HStack(spacing: 12) {
                Group {
                    if let mountain = ReferenceArtworkCrop.mountain {
                        Image(uiImage: mountain).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.indigo.opacity(0.3))
                    }
                }
                .frame(width: 82, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    Text(state.assetInfo?.fileName ?? "My Video")
                        .font(.subheadline.bold()).lineLimit(1)
                    Text("\(state.assetInfo?.durationText ?? "00:00") · \(state.configuration.resolution == .uhd8K ? "8K" : "4K") · \(state.configuration.upscaler == .dlss5 ? "DLSS 5" : "Apple SR")")
                        .font(.caption).foregroundStyle(.white.opacity(0.62))
                    if let info = state.assetInfo {
                        Text("~ " + ByteCountFormatter.string(
                            fromByteCount: StorageEstimator.estimatedOutputBytes(info: info, configuration: state.configuration),
                            countStyle: .file
                        ) + " estimated")
                            .font(.caption).foregroundStyle(.white.opacity(0.48))
                    }
                }
                Spacer()
            }
            .padding(13)
        }
    }

    private var exportSettings: some View {
        NativePanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("Export Settings").font(.headline)
                Divider().overlay(Color.white.opacity(0.07))

                settingLabel("Format")
                HStack(spacing: 4) {
                    exportChoice("HEVC (H.265)", selected: state.configuration.codec == .hevc) {
                        state.configuration.codec = .hevc
                    }
                    exportChoice("ProRes", selected: false, enabled: false) {
                        state.errorMessage = "ProRes is not enabled in this processing backend yet."
                    }
                }

                settingLabel("Quality")
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        let labels = ["Standard", "High", "Maximum"]
                        exportChoice(labels[index], selected: index == qualityIndex) { setQuality(index) }
                    }
                }

                nativeToggle(
                    "Preserve HDR (when available)",
                    isOn: Binding(
                        get: { state.configuration.hdrBehavior == .preserve },
                        set: { state.configuration.hdrBehavior = $0 ? .preserve : .convertToSDR }
                    )
                )
                nativeToggle(
                    "Save to Photos",
                    isOn: Binding(
                        get: { state.saveToPhotosAfterExport },
                        set: { state.saveToPhotosAfterExport = $0 }
                    )
                )
                nativeToggle(
                    "Also Save to Files",
                    isOn: Binding(
                        get: { state.saveToFilesAfterExport },
                        set: { state.saveToFilesAfterExport = $0 }
                    )
                )
            }
            .padding(14)
        }
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.74))
    }

    private func exportChoice(_ title: String, selected: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? .white : .white.opacity(0.42))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    selected ? AnyShapeStyle(ClarityNativeTheme.brand) : AnyShapeStyle(Color.white.opacity(0.055)),
                    in: RoundedRectangle(cornerRadius: 9)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func nativeToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.system(size: 12, weight: .medium))
            .tint(.cyan)
    }

    private func setQuality(_ index: Int) {
        qualityIndex = index
        let values = state.configuration.resolution == .uhd8K ? [100, 160, 220] : [35, 65, 100]
        state.configuration.bitrateMbps = values[index]
    }

    private func closestQualityIndex() -> Int {
        let values = state.configuration.resolution == .uhd8K ? [100, 160, 220] : [35, 65, 100]
        return values.enumerated().min {
            abs($0.element - state.configuration.bitrateMbps) < abs($1.element - state.configuration.bitrateMbps)
        }?.offset ?? 1
    }
}

private struct NativeVideoCameraPicker: UIViewControllerRepresentable {
    let onResult: @MainActor (URL) -> Void
    let onCancel: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult, onCancel: onCancel) }

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

        init(onResult: @escaping @MainActor (URL) -> Void, onCancel: @escaping @MainActor () -> Void) {
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
