import SwiftUI
import Photos
import AVFoundation
import AVKit
import UniformTypeIdentifiers
import UIKit

private enum ReferenceTheme {
    static let background = Color(red: 0.006, green: 0.014, blue: 0.028)
    static let panel = Color(red: 0.035, green: 0.060, blue: 0.100)
    static let panelStrong = Color(red: 0.045, green: 0.075, blue: 0.125)
    static let stroke = Color(red: 0.14, green: 0.38, blue: 0.72).opacity(0.55)
    static let brand = LinearGradient(
        colors: [
            Color(red: 0.14, green: 0.72, blue: 1.0),
            Color(red: 0.27, green: 0.55, blue: 1.0),
            Color(red: 0.63, green: 0.27, blue: 1.0)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let button = LinearGradient(
        colors: [
            Color(red: 0.65, green: 0.38, blue: 1.0),
            Color(red: 0.24, green: 0.54, blue: 1.0),
            Color(red: 0.08, green: 0.78, blue: 1.0)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

private enum ReferenceArt {
    static let mountain: UIImage? = {
        guard let image = UIImage(named: "ReferenceArtwork")?.cgImage else { return nil }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let rect = CGRect(
            x: width * 0.16,
            y: height * 0.135,
            width: width * 0.68,
            height: height * 0.145
        ).integral
        guard let crop = image.cropping(to: rect) else { return nil }
        return UIImage(cgImage: crop)
    }()
}

private struct ReferenceBackground: View {
    var body: some View {
        ZStack {
            ReferenceTheme.background
            RadialGradient(
                colors: [Color.blue.opacity(0.15), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 470
            )
            RadialGradient(
                colors: [Color.purple.opacity(0.09), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 430
            )
        }
        .ignoresSafeArea()
    }
}

private struct ReferenceHeader: View {
    let title: String
    let onBack: () -> Void
    var trailingSymbol: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
            }
            Spacer()
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            if let trailingSymbol {
                Button(action: trailingAction ?? {}) {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                }
            } else {
                Color.clear.frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }
}

private struct ReferencePanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(
                ReferenceTheme.panel,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.055), lineWidth: 1)
            )
    }
}

struct ReferenceHomeView: View {
    @Environment(AppState.self) private var state
    @State private var showingSettings = false
    @State private var showingProjects = false

    var body: some View {
        ZStack {
            ReferenceBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    HStack {
                        Button { showingSettings = true } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.cyan)
                                .frame(width: 38, height: 38)
                        }
                        Spacer()
                        Button { showingProjects = true } label: {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(colors: [.cyan, .purple], startPoint: .top, endPoint: .bottom)
                                )
                                .frame(width: 38, height: 38)
                        }
                    }

                    VStack(spacing: 3) {
                        HStack(spacing: 0) {
                            Text("Clarity")
                                .foregroundStyle(.white)
                            Text("Video")
                                .foregroundStyle(ReferenceTheme.brand)
                        }
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                        Text("Sharper. Clearer. Better.")
                            .font(.system(size: 12, weight: .medium))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.60))
                    }
                    .padding(.bottom, 6)

                    VStack(spacing: 10) {
                        referenceMenuButton(
                            icon: "video.fill",
                            title: "Enhance Video",
                            subtitle: "Import from Photos, Files or Camera"
                        ) {
                            state.route = .importVideo
                        }

                        referenceMenuButton(
                            icon: "clock.fill",
                            title: "Recent Projects",
                            subtitle: "Continue your work"
                        ) {
                            showingProjects = true
                        }

                        referenceMenuButton(
                            icon: "gearshape.fill",
                            title: "Settings",
                            subtitle: "Quality, export and advanced options"
                        ) {
                            showingSettings = true
                        }
                    }

                    mountainHero
                        .padding(.top, 3)
                }
                .padding(.horizontal, 17)
                .padding(.top, 5)
                .padding(.bottom, 94)
            }

            VStack {
                Spacer()
                homeBottomBar
            }
        }
        .navigationBarHidden(true)
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
                            Text(job.assetInfo.fileName).lineLimit(1)
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

    private func referenceMenuButton(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(ReferenceTheme.brand)
                    .frame(width: 47, height: 47)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                }

                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.16, blue: 0.31),
                        ReferenceTheme.panelStrong
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.blue.opacity(0.34), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var mountainHero: some View {
        ZStack(alignment: .bottom) {
            if let mountain = ReferenceArt.mountain {
                Image(uiImage: mountain)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 236)
                    .clipped()
            } else {
                LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 236)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.82)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text("TURN GOOD FOOTAGE\nINTO GREAT MEMORIES.")
                .font(.system(size: 10, weight: .bold))
                .tracking(2.9)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.82))
                .padding(.bottom, 17)
        }
        .frame(height: 236)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.blue.opacity(0.20), lineWidth: 1)
        )
    }

    private var homeBottomBar: some View {
        HStack(spacing: 2) {
            referenceTab("house.fill", "Home", selected: true) {}
            referenceTab("folder.fill", "Projects") { showingProjects = true }

            Button { state.route = .importVideo } label: {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.035, green: 0.12, blue: 0.31))
                        .frame(width: 55, height: 55)
                    Circle()
                        .stroke(ReferenceTheme.brand, lineWidth: 2.2)
                        .frame(width: 55, height: 55)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                }
                .shadow(color: .blue.opacity(0.75), radius: 11)
            }
            .frame(maxWidth: .infinity)

            referenceTab("bolt.fill", "Tools") { state.showDiagnostics = true }
            referenceTab("gearshape.fill", "Settings") { showingSettings = true }
        }
        .padding(.horizontal, 8)
        .padding(.top, 9)
        .padding(.bottom, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5)
        }
    }

    private func referenceTab(
        _ symbol: String,
        _ title: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 8.5, weight: .medium))
            }
            .foregroundStyle(selected ? Color.cyan : Color.white.opacity(0.55))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct ReferenceImportVideoView: View {
    @Environment(AppState.self) private var state
    @State private var assets: [PHAsset] = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selected: PHAsset?
    @State private var showingFiles = false
    @State private var showingCamera = false
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case videos = "Videos"
        case favorites = "Favorites"
        case recents = "Recents"
        var id: String { rawValue }
    }

    private var filteredAssets: [PHAsset] {
        switch filter {
        case .favorites:
            assets.filter(\.isFavorite)
        case .recents:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            assets.filter { ($0.creationDate ?? .distantPast) >= cutoff }
        case .all, .videos:
            assets
        }
    }

    var body: some View {
        ZStack {
            ReferenceBackground()

            VStack(spacing: 0) {
                ReferenceHeader(title: "Import Video") {
                    state.route = .home
                }

                sourceTabs
                    .padding(.horizontal, 15)
                    .padding(.top, 4)

                filterTabs
                    .padding(.horizontal, 15)
                    .padding(.top, 12)
                    .padding(.bottom, 5)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                        spacing: 7
                    ) {
                        ForEach(filteredAssets, id: \.localIdentifier) { asset in
                            ReferencePhotoCell(
                                asset: asset,
                                image: thumbnails[asset.localIdentifier],
                                selected: selected?.localIdentifier == asset.localIdentifier
                            )
                            .onTapGesture { selected = asset }
                            .task { await loadThumbnail(for: asset) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, selected == nil ? 28 : 125)
                }

                if let selected {
                    selectedBar(selected)
                }
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .task { await loadAssets() }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.video]) { result in
            switch result {
            case .success(let url):
                Task { await state.importVideo(from: url, sourceLabel: "Files video") }
            case .failure(let error):
                state.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingCamera) {
            ReferenceVideoCameraPicker { url in
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

    private var sourceTabs: some View {
        HStack(spacing: 8) {
            sourceButton("Photos", "photo.on.rectangle", active: true) {}
            sourceButton("Files", "folder.fill", active: false) { showingFiles = true }
            sourceButton("Camera", "camera.fill", active: false) { showingCamera = true }
        }
    }

    private func sourceButton(
        _ title: String,
        _ symbol: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(
                    active
                        ? AnyShapeStyle(ReferenceTheme.button)
                        : AnyShapeStyle(Color.white.opacity(0.065)),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(active ? Color.cyan.opacity(0.55) : Color.white.opacity(0.05), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var filterTabs: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases) { item in
                Button(item.rawValue) { filter = item }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(filter == item ? .white : .white.opacity(0.58))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        filter == item
                            ? AnyShapeStyle(ReferenceTheme.button)
                            : AnyShapeStyle(Color.white.opacity(0.055)),
                        in: Capsule()
                    )
            }
            Spacer(minLength: 0)
        }
    }

    private func selectedBar(_ asset: PHAsset) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let image = thumbnails[asset.localIdentifier] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 46, height: 46)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("1 Video Selected")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(duration(asset.duration)) · \(asset.pixelWidth)p")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                }
                Spacer()
            }

            Button {
                Task { await importAsset(asset) }
            } label: {
                HStack {
                    Spacer()
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .background(
                    ReferenceTheme.button,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 11)
        .background(.ultraThinMaterial)
    }

    private func loadAssets() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            state.errorMessage = "Photos access is required to show your video library. Files import remains available."
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .video, options: options)
        var values: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in values.append(asset) }
        assets = values
    }

    private func loadThumbnail(for asset: PHAsset) async {
        guard thumbnails[asset.localIdentifier] == nil else { return }

        let manager = PHCachingImageManager()
        let image = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            var resumed = false

            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 360, height: 240),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let requestError = info?[PHImageErrorKey] as? Error
                if (!degraded || cancelled || requestError != nil) && !resumed {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }

        if let image {
            thumbnails[asset.localIdentifier] = image
        }
    }

    private func importAsset(_ asset: PHAsset) async {
        state.isImporting = true
        state.importStatus = "Preparing selected video…"

        do {
            let url = try await ReferencePhotoAssetResolver.videoURL(for: asset)
            await state.importVideo(from: url, sourceLabel: "Photos video")
        } catch {
            state.isImporting = false
            state.errorMessage = error.localizedDescription
        }
    }

    private func duration(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct ReferencePhotoCell: View {
    let asset: PHAsset
    let image: UIImage?
    let selected: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.055))
                        .overlay(ProgressView().tint(.cyan))
                }
            }
            .frame(height: 102)
            .clipped()

            Text(String(format: "%d:%02d", Int(asset.duration) / 60, Int(asset.duration) % 60))
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(5)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.cyan)
                    .background(Circle().fill(.black))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? Color.cyan : Color.white.opacity(0.05), lineWidth: selected ? 2 : 1)
        )
    }
}

private enum ReferencePhotoAssetResolver {
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
                    continuation.resume(
                        throwing: AppError.importFailedReason("Photos could not provide a local video file.")
                    )
                    return
                }

                continuation.resume(returning: urlAsset.url)
            }
        }
    }
}

private struct ReferenceVideoCameraPicker: UIViewControllerRepresentable {
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

struct ReferenceEditorView: View {
    @Environment(AppState.self) private var state
    @State private var reveal = 0.50
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var aiSuperResolution = true

    var body: some View {
        ZStack {
            ReferenceBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ReferenceHeader(title: "Enhance") {
                        player?.pause()
                        state.route = .importVideo
                    }

                    comparisonCard

                    playbackBar

                    settingsPanel

                    Button {
                        player?.pause()
                        state.route = .exportSetup
                    } label: {
                        HStack {
                            Spacer()
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 15)
                        .background(
                            ReferenceTheme.button,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 15)
                    .padding(.top, 2)
                }
                .padding(.bottom, 22)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            if player == nil, let url = state.importedURL {
                player = AVPlayer(url: url)
            }
            aiSuperResolution = state.configuration.mode != .fast
        }
        .onDisappear {
            player?.pause()
        }
    }

    private var comparisonCard: some View {
        GeometryReader { geometry in
            let split = max(0, min(geometry.size.width, geometry.size.width * reveal))

            ZStack(alignment: .leading) {
                if let player {
                    VideoPlayer(player: player)
                        .allowsHitTesting(false)
                } else if let mountain = ReferenceArt.mountain {
                    Image(uiImage: mountain)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(Color.blue.opacity(0.18))
                }

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.10), Color.purple.opacity(0.14)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.screen)
                    .mask(
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle().frame(width: max(0, geometry.size.width - split))
                        }
                    )

                HStack {
                    Text("Before")
                    Spacer()
                    Text("After")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ReferenceTheme.button, in: Capsule())
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(11)
                .frame(maxHeight: .infinity, alignment: .bottom)

                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .offset(x: max(0, min(geometry.size.width - 2, split - 1)))

                Image(systemName: "arrow.left.and.right.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white, .black.opacity(0.78))
                    .offset(
                        x: max(0, min(geometry.size.width - 30, split - 15)),
                        y: geometry.size.height / 2 - 15
                    )

                Text(state.configuration.resolution == .uhd8K ? "8K" : "4K")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.80), in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(9)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        reveal = max(0, min(1, value.location.x / max(1, geometry.size.width)))
                    }
            )
        }
        .frame(height: 205)
        .padding(.horizontal, 15)
    }

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button {
                guard let player else { return }
                if isPlaying {
                    player.pause()
                } else {
                    player.play()
                }
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("00:00")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

            Slider(value: $reveal, in: 0...1)
                .tint(.cyan)

            Text(state.assetInfo?.durationText ?? "00:15")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 17)
        .frame(height: 36)
    }

    private var settingsPanel: some View {
        ReferencePanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Enhancement Settings")
                    .font(.system(size: 14, weight: .semibold))

                VStack(alignment: .leading, spacing: 7) {
                    Text("Target Resolution")
                        .font(.system(size: 11, weight: .medium))
                    HStack(spacing: 0) {
                        referenceSegment("Original", selected: false, enabled: false) {}
                        referenceSegment("4K", selected: state.configuration.resolution == .uhd4K) {
                            state.configuration.resolution = .uhd4K
                        }
                        referenceSegment("8K", selected: state.configuration.resolution == .uhd8K) {
                            state.configuration.resolution = .uhd8K
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Enhancement Mode")
                        .font(.system(size: 11, weight: .medium))
                    HStack(spacing: 0) {
                        referenceSegment("Balanced", selected: state.configuration.mode == .fast) {
                            state.configuration.applyPreset(
                                .fast,
                                temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
                            )
                        }
                        referenceSegment("Quality", selected: state.configuration.mode == .quality) {
                            state.configuration.applyPreset(
                                .quality,
                                temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
                            )
                        }
                        referenceSegment(
                            "Ultra",
                            selected: [.restore, .anime, .dlss5].contains(state.configuration.mode)
                        ) {
                            let mode: EnhancementMode =
                                IOSNeuralHeadService.bundledModelURL() != nil ? .dlss5 : .restore
                            state.configuration.applyPreset(
                                mode,
                                temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
                            )
                        }
                    }
                }

                HStack {
                    Text("AI Super Resolution")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { aiSuperResolution },
                        set: { enabled in
                            aiSuperResolution = enabled
                            state.configuration.applyPreset(
                                enabled ? .quality : .fast,
                                temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
                            )
                        }
                    ))
                    .labelsHidden()
                    .tint(.cyan)
                }

                referenceSlider("Denoise", value: Binding(
                    get: { state.configuration.denoise },
                    set: { state.configuration.denoise = $0 }
                ))

                referenceSlider("Detail Recovery", value: Binding(
                    get: { state.configuration.detailRecovery },
                    set: { state.configuration.detailRecovery = $0 }
                ))

                referenceSlider("Sharpening", value: Binding(
                    get: { state.configuration.sharpening },
                    set: { state.configuration.sharpening = $0 }
                ))
            }
        }
        .padding(.horizontal, 15)
    }

    private func referenceSegment(
        _ title: String,
        selected: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.48))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    selected
                        ? AnyShapeStyle(ReferenceTheme.button)
                        : AnyShapeStyle(Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func referenceSlider(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 92, alignment: .leading)
            Slider(value: value, in: 0...1)
                .tint(.cyan)
            Text("\(Int((value.wrappedValue * 100).rounded()))")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.70))
                .frame(width: 28, alignment: .trailing)
        }
    }
}

struct ReferenceExportView: View {
    @Environment(AppState.self) private var state
    @State private var quality = 1
    @State private var alsoSaveToFiles = false

    var body: some View {
        ZStack {
            ReferenceBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ReferenceHeader(
                        title: "Export",
                        onBack: { state.route = .editor },
                        trailingSymbol: "magnifyingglass"
                    )

                    summaryCard

                    exportSettings

                    Button {
                        state.beginExport()
                    } label: {
                        Text("Start Export")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 0.02, green: 0.04, blue: 0.10))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                ReferenceTheme.button,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 15)

                    Text("Processing will continue in the background.\nYou’ll be notified when it’s done.")
                        .font(.system(size: 9.5, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.48))
                        .padding(.horizontal, 24)

                    HStack(spacing: 11) {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(Color.blue.opacity(0.16))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Image(systemName: "camera.aperture")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.blue)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Powered. On Device.")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Your privacy stays with you.")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        ReferenceTheme.panel,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .padding(.horizontal, 15)
                }
                .padding(.bottom, 22)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
    }

    private var summaryCard: some View {
        HStack(spacing: 12) {
            Group {
                if let mountain = ReferenceArt.mountain {
                    Image(uiImage: mountain)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(Color.blue.opacity(0.20))
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("My Video")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(state.assetInfo?.durationText ?? "2:15") · \(state.configuration.resolution == .uhd8K ? "8K" : "4K") · \(state.configuration.codec.rawValue)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))

                if let info = state.assetInfo {
                    Text("~ " + ByteCountFormatter.string(
                        fromByteCount: StorageEstimator.estimatedOutputBytes(info: info, configuration: state.configuration),
                        countStyle: .file
                    ) + " estimated")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            ReferenceTheme.panel,
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .padding(.horizontal, 15)
    }

    private var exportSettings: some View {
        ReferencePanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Export Settings")
                    .font(.system(size: 14, weight: .semibold))

                VStack(alignment: .leading, spacing: 7) {
                    Text("Format")
                        .font(.system(size: 11, weight: .medium))

                    HStack(spacing: 0) {
                        referenceOption("HEVC (H.265)", selected: state.configuration.codec == .hevc) {
                            state.configuration.codec = .hevc
                        }
                        referenceOption("ProRes", selected: false) {
                            state.errorMessage = "ProRes is not enabled in this processing backend yet."
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Quality")
                        .font(.system(size: 11, weight: .medium))

                    HStack(spacing: 0) {
                        referenceOption("Standard", selected: quality == 0) {
                            setQuality(0)
                        }
                        referenceOption("High", selected: quality == 1) {
                            setQuality(1)
                        }
                        referenceOption("Maximum", selected: quality == 2) {
                            setQuality(2)
                        }
                    }
                }

                Toggle(
                    "Preserve HDR (when available)",
                    isOn: Binding(
                        get: { state.configuration.hdrBehavior == .preserve },
                        set: { state.configuration.hdrBehavior = $0 ? .preserve : .convertToSDR }
                    )
                )
                .font(.system(size: 11.5, weight: .medium))
                .tint(.cyan)

                Toggle(
                    "Save to Photos",
                    isOn: Binding(
                        get: { state.saveToPhotosAfterExport },
                        set: { state.saveToPhotosAfterExport = $0 }
                    )
                )
                .font(.system(size: 11.5, weight: .medium))
                .tint(.cyan)

                Toggle("Also Save to Files", isOn: $alsoSaveToFiles)
                    .font(.system(size: 11.5, weight: .medium))
                    .tint(.cyan)
            }
        }
        .padding(.horizontal, 15)
    }

    private func referenceOption(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    selected
                        ? AnyShapeStyle(ReferenceTheme.button)
                        : AnyShapeStyle(Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }

    private func setQuality(_ value: Int) {
        quality = value
        let values = state.configuration.resolution == .uhd8K
            ? [100, 160, 220]
            : [35, 65, 100]
        state.configuration.bitrateMbps = values[value]
    }
}
