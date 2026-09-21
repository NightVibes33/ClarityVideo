import SwiftUI
import Photos
import AVFoundation
import UniformTypeIdentifiers
import UIKit

struct ImportVideoView: View {
    @Environment(AppState.self) private var state
    @State private var assets: [PHAsset] = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selected: PHAsset?
    @State private var showingFiles = false
    @State private var showingCamera = false
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable { case all = "All", videos = "Videos", favorites = "Favorites", recents = "Recents"; var id: String { rawValue } }

    var filteredAssets: [PHAsset] {
        switch filter {
        case .favorites: return assets.filter(\.isFavorite)
        case .recents:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            return assets.filter { ($0.creationDate ?? .distantPast) >= cutoff }
        case .all, .videos: return assets
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.018, blue: 0.034).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                sourceTabs
                filterTabs
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                        ForEach(filteredAssets, id: \.localIdentifier) { asset in
                            VideoAssetCell(asset: asset, image: thumbnails[asset.localIdentifier], selected: selected?.localIdentifier == asset.localIdentifier)
                                .onTapGesture { selected = asset }
                                .task { await loadThumbnail(for: asset) }
                        }
                    }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, selected == nil ? 30 : 130)
                }
                if let selected { selectionBar(selected) }
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden()
        .task { await loadAssets() }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.video]) { result in
            if case .success(let url) = result { Task { await state.importVideo(from: url, sourceLabel: "Files video") } }
            else if case .failure(let error) = result { state.errorMessage = error.localizedDescription }
        }
        .sheet(isPresented: $showingCamera) {
            VideoCameraPicker { url in
                showingCamera = false
                Task { await state.importVideo(from: url, sourceLabel: "Camera video") }
            } onCancel: { showingCamera = false }
            .ignoresSafeArea()
        }
        .overlay { if state.isImporting { importingOverlay } }
    }

    private var header: some View {
        HStack {
            Button { state.route = .home } label: { Image(systemName: "chevron.left").font(.headline) }
            Spacer()
            Text("Import Video").font(.headline)
            Spacer()
            Color.clear.frame(width: 18, height: 18)
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var sourceTabs: some View {
        HStack(spacing: 8) {
            sourceButton("Photos", "photo.on.rectangle", active: true) {}
            sourceButton("Files", "folder", active: false) { showingFiles = true }
            sourceButton("Camera", "camera", active: false) { showingCamera = true }
        }.padding(.horizontal, 16).padding(.bottom, 10)
    }

    private func sourceButton(_ title: String, _ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(active ? AnyShapeStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.white.opacity(0.07)), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private var filterTabs: some View {
        HStack(spacing: 7) {
            ForEach(Filter.allCases) { item in
                Button(item.rawValue) { filter = item }
                    .font(.caption.bold()).foregroundStyle(filter == item ? .white : .white.opacity(0.55))
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(filter == item ? Color.blue.opacity(0.9) : Color.white.opacity(0.055), in: Capsule())
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 16)
    }

    private func selectionBar(_ asset: PHAsset) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let image = thumbnails[asset.localIdentifier] {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 9))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("1 Video Selected").font(.subheadline.bold())
                    Text("\(duration(asset.duration)) · \(asset.pixelWidth)×\(asset.pixelHeight)").font(.caption).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }
            Button { Task { await importAsset(asset) } } label: {
                HStack { Spacer(); Text("Continue").font(.headline); Image(systemName: "arrow.right"); Spacer() }
                    .padding(.vertical, 15).background(LinearGradient(colors: [.purple, .blue, .cyan], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain)
        }.padding(14).background(.ultraThinMaterial)
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 12) { ProgressView().controlSize(.large).tint(.cyan); Text(state.importStatus ?? "Importing video…").font(.subheadline.bold()) }
                .padding(26).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
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
            manager.requestImage(for: asset, targetSize: CGSize(width: 360, height: 240), contentMode: .aspectFill, options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let requestError = info?[PHImageErrorKey] as? Error
                if (!degraded || cancelled || requestError != nil) && !resumed {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
        if let image { thumbnails[asset.localIdentifier] = image }
    }

    private func importAsset(_ asset: PHAsset) async {
        state.isImporting = true
        state.importStatus = "Preparing selected video…"
        do {
            let url = try await PhotoAssetResolver.videoURL(for: asset)
            await state.importVideo(from: url, sourceLabel: "Photos video")
        } catch {
            state.isImporting = false
            state.errorMessage = error.localizedDescription
        }
    }

    private func duration(_ value: Double) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}

private struct VideoAssetCell: View {
    let asset: PHAsset
    let image: UIImage?
    let selected: Bool
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Rectangle().fill(Color.white.opacity(0.06)).overlay(ProgressView().tint(.cyan)) }
            }
            .frame(height: 103).clipped()
            Text(String(format: "%d:%02d", Int(asset.duration) / 60, Int(asset.duration) % 60))
                .font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 3).background(.black.opacity(0.65), in: Capsule()).padding(5)
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan).background(Circle().fill(.black)).padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? Color.cyan : Color.white.opacity(0.05), lineWidth: selected ? 2 : 1))
    }
}

private enum PhotoAssetResolver {
    static func videoURL(for asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error { continuation.resume(throwing: error); return }
                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(throwing: AppError.importFailedReason("Photos could not provide a local video file."))
                    return
                }
                continuation.resume(returning: urlAsset.url)
            }
        }
    }
}

private struct VideoCameraPicker: UIViewControllerRepresentable {
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
        init(onResult: @escaping @MainActor (URL) -> Void, onCancel: @escaping @MainActor () -> Void) { self.onResult = onResult; self.onCancel = onCancel }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { Task { @MainActor in onCancel() } }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            guard let url = info[.mediaURL] as? URL else { Task { @MainActor in onCancel() }; return }
            Task { @MainActor in onResult(url) }
        }
    }
}
