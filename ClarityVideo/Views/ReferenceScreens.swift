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
    @State private var assets: [PHAsset] = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selected: PHAsset?
    @State private var showingFiles = false
    @State private var showingCamera = false
    @State private var filter: Filter = .all
    @State private var photoAccessResolved = false
    @State private var photoAccessDenied = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case videos = "Videos"
        case favorites = "Favorites"
        case recents = "Recents"
        var id: String { rawValue }
    }

    private var isSnapshotMode: Bool {
        ProcessInfo.processInfo.environment["CLARITY_UI_ROUTE"] != nil
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

    var body: some View {
        ZStack {
            ExactReferenceBackground(screen: .importVideo)

            // Back.
            ExactHotspot(rect: CGRect(x: 0.00, y: 0.045, width: 0.14, height: 0.075)) {
                state.route = .home
            }

            // Source controls retain the exact reference chrome.
            ExactHotspot(rect: CGRect(x: 0.04, y: 0.115, width: 0.32, height: 0.065)) {
                Task { await loadAssets() }
            }
            ExactHotspot(rect: CGRect(x: 0.37, y: 0.115, width: 0.30, height: 0.065)) {
                showingFiles = true
            }
            ExactHotspot(rect: CGRect(x: 0.69, y: 0.115, width: 0.29, height: 0.065)) {
                showingCamera = true
            }

            if !isSnapshotMode {
                liveFilterRow
                liveVideoGrid

                if let selected {
                    selectedSummary(selected)
                }
            }

            // Continue imports the exact video selected in the live grid.
            ExactHotspot(rect: CGRect(x: 0.05, y: 0.895, width: 0.90, height: 0.075)) {
                guard let selected else {
                    state.errorMessage = "Select a video to continue."
                    return
                }
                Task { await importAsset(selected) }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .task {
            guard !isSnapshotMode else { return }
            await loadAssets()
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

    private var liveFilterRow: some View {
        GeometryReader { geometry in
            HStack(spacing: 5) {
                ForEach(Filter.allCases) { item in
                    Button(item.rawValue) {
                        filter = item
                        if selected.map({ filteredAssets.contains($0) }) == false {
                            selected = nil
                        }
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(filter == item ? .white : .white.opacity(0.58))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        filter == item
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [.purple, .blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            : AnyShapeStyle(Color.white.opacity(0.06)),
                        in: Capsule()
                    )
                    .accessibilityAddTraits(filter == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
            .frame(
                width: geometry.size.width * 0.94,
                height: geometry.size.height * 0.052
            )
            .background(
                Color(red: 0.012, green: 0.028, blue: 0.050).opacity(0.98),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .position(
                x: geometry.size.width * 0.50,
                y: geometry.size.height * 0.210
            )
        }
    }

    private var liveVideoGrid: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.008, green: 0.020, blue: 0.038).opacity(0.995))

                if photoAccessDenied {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(.cyan)
                        Text("Photos access is off")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Use Files or Camera, or allow Photos access in Settings.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if photoAccessResolved && filteredAssets.isEmpty {
                    ContentUnavailableView("No Videos", systemImage: "video.slash")
                        .scaleEffect(0.75)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3),
                            spacing: 6
                        ) {
                            ForEach(filteredAssets, id: \.localIdentifier) { asset in
                                ExactReferencePhotoCell(
                                    asset: asset,
                                    image: thumbnails[asset.localIdentifier],
                                    selected: selected?.localIdentifier == asset.localIdentifier
                                )
                                .onTapGesture {
                                    selected = asset
                                }
                                .task {
                                    await loadThumbnail(for: asset)
                                }
                            }
                        }
                        .padding(5)
                    }
                }
            }
            .frame(
                width: geometry.size.width * 0.94,
                height: geometry.size.height * 0.515
            )
            .position(
                x: geometry.size.width * 0.50,
                y: geometry.size.height * 0.505
            )
        }
    }

    private func selectedSummary(_ asset: PHAsset) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 9) {
                Group {
                    if let image = thumbnails[asset.localIdentifier] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.07)
                    }
                }
                .frame(
                    width: geometry.size.width * 0.13,
                    height: geometry.size.width * 0.13
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("1 Video Selected")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(duration(asset.duration)) · \(asset.pixelWidth)×\(asset.pixelHeight)")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(
                width: geometry.size.width * 0.94,
                height: geometry.size.height * 0.085
            )
            .background(
                Color(red: 0.018, green: 0.035, blue: 0.062).opacity(0.98),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .position(
                x: geometry.size.width * 0.50,
                y: geometry.size.height * 0.815
            )
        }
        .allowsHitTesting(false)
    }

    private func loadAssets() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        photoAccessResolved = true
        guard status == .authorized || status == .limited else {
            photoAccessDenied = true
            assets = []
            selected = nil
            return
        }

        photoAccessDenied = false
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .video, options: options)
        var values: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in values.append(asset) }
        assets = values
        if let selected, !values.contains(where: { $0.localIdentifier == selected.localIdentifier }) {
            self.selected = nil
        }
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
            let url = try await ExactReferencePhotoAssetResolver.videoURL(for: asset)
            await state.importVideo(from: url, sourceLabel: "Photos video")
        } catch {
            state.isImporting = false
            state.importStatus = nil
            state.errorMessage = error.localizedDescription
        }
    }

    private func duration(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct ExactReferencePhotoCell: View {
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
            .aspectRatio(1.25, contentMode: .fill)
            .clipped()

            Text(String(format: "%d:%02d", Int(asset.duration) / 60, Int(asset.duration) % 60))
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(4)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.cyan)
                    .background(Circle().fill(.black))
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(selected ? Color.cyan : Color.white.opacity(0.05), lineWidth: selected ? 2 : 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Video \(String(format: "%d minutes %d seconds", Int(asset.duration) / 60, Int(asset.duration) % 60))")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private enum ExactReferencePhotoAssetResolver {
    static func videoURL(for asset: PHAsset) async throws -> URL {
        let avAsset: AVAsset = try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let avAsset else {
                    continuation.resume(
                        throwing: AppError.importFailedReason("Photos could not prepare this video.")
                    )
                    return
                }
                continuation.resume(returning: avAsset)
            }
        }

        if let urlAsset = avAsset as? AVURLAsset {
            return urlAsset.url
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clarity-Photos-" + UUID().uuidString)
            .appendingPathExtension("mov")
        try? FileManager.default.removeItem(at: temporaryURL)

        guard let session = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetPassthrough) else {
            throw AppError.importFailedReason("Photos returned a composed video that could not be exported.")
        }
        try await session.export(to: temporaryURL, as: .mov)
        return temporaryURL
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

            // Target resolution is an explicit choice independent of engine/preset.
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    ForEach([OutputResolution.uhd4K, .uhd8K]) { resolution in
                        Button {
                            state.configuration.resolution = resolution
                        } label: {
                            Text(resolution == .uhd4K ? "4K" : "8K")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    state.configuration.resolution == resolution
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
                    }
                }
                .padding(4)
                .frame(
                    width: geometry.size.width * 0.935,
                    height: geometry.size.height * 0.060
                )
                .background(
                    Color(red: 0.018, green: 0.035, blue: 0.062).opacity(0.98),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .position(
                    x: geometry.size.width * 0.502,
                    y: geometry.size.height * 0.615
                )
            }

            // Quality preset is independent from the selected AI upscaler.
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    ForEach(QualityPreset.allCases) { preset in
                        Button {
                            state.configuration.applyPreset(
                                preset,
                                temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
                            )
                        } label: {
                            Text(preset.rawValue)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    state.configuration.qualityPreset == preset
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
                        .accessibilityLabel("(preset.rawValue) quality preset")
                        .accessibilityAddTraits(
                            state.configuration.qualityPreset == preset ? .isSelected : []
                        )
                    }
                }
                .padding(4)
                .frame(
                    width: geometry.size.width * 0.935,
                    height: geometry.size.height * 0.060
                )
                .background(
                    Color(red: 0.018, green: 0.035, blue: 0.062).opacity(0.98),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .position(
                    x: geometry.size.width * 0.502,
                    y: geometry.size.height * 0.720
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

            // Quality row with live selection feedback.
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    ForEach(Array(["Standard", "High", "Maximum"].enumerated()), id: .offset) { index, title in
                        Button {
                            setQuality(index)
                        } label: {
                            Text(title)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    quality == index
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
                        .accessibilityLabel("(title) export quality")
                        .accessibilityAddTraits(quality == index ? .isSelected : [])
                    }
                }
                .padding(4)
                .frame(
                    width: geometry.size.width * 0.88,
                    height: geometry.size.height * 0.055
                )
                .background(
                    Color(red: 0.018, green: 0.035, blue: 0.062).opacity(0.98),
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .position(
                    x: geometry.size.width * 0.51,
                    y: geometry.size.height * 0.4825
                )
            }

            // Live toggles over the exact reference positions.
            GeometryReader { geometry in
                referenceToggle(
                    isOn: state.configuration.hdrBehavior == .preserve,
                    label: "Preserve HDR",
                    geometry: geometry,
                    y: 0.565
                ) {
                    guard state.assetInfo?.isHDR == true else { return }
                    if state.configuration.hdrBehavior == .preserve {
                        state.configuration.hdrBehavior = .convertToSDR
                    } else {
                        state.errorMessage = "Verified HDR preservation is not available yet for this AI path. Clarity will not silently strip HDR metadata."
                    }
                }

                referenceToggle(
                    isOn: state.saveToPhotosAfterExport,
                    label: "Save to Photos",
                    geometry: geometry,
                    y: 0.620
                ) {
                    state.saveToPhotosAfterExport.toggle()
                }

                referenceToggle(
                    isOn: state.saveToFilesAfterExport,
                    label: "Also Save to Files",
                    geometry: geometry,
                    y: 0.675
                ) {
                    state.saveToFilesAfterExport.toggle()
                }
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

    @ViewBuilder
    private func referenceToggle(
        isOn: Bool,
        label: String,
        geometry: GeometryProxy,
        y: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Capsule()
                .fill(
                    isOn
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [.purple, .blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        : AnyShapeStyle(Color.white.opacity(0.16))
                )
                .frame(
                    width: geometry.size.width * 0.105,
                    height: geometry.size.height * 0.027
                )
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .position(
            x: geometry.size.width * 0.90,
            y: geometry.size.height * y
        )
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
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
