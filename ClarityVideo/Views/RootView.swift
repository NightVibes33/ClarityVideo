import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers
import UIKit

struct VideoPhotosPicker: UIViewControllerRepresentable {
    let onResult: @MainActor @Sendable (Result<URL, AppError>) -> Void
    let onCancel: @MainActor @Sendable () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onResult: @MainActor @Sendable (Result<URL, AppError>) -> Void
        private let onCancel: @MainActor @Sendable () -> Void

        init(onResult: @escaping @MainActor @Sendable (Result<URL, AppError>) -> Void, onCancel: @escaping @MainActor @Sendable () -> Void) {
            self.onResult = onResult
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { onCancel(); return }
            guard provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                onResult(.failure(AppError.importFailedReason("Photos did not provide a movie file.")))
                return
            }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [onResult] url, error in
                let result: Result<URL, AppError>
                do {
                    if let error { throw error }
                    guard let url else {
                        throw AppError.importFailedReason("Photos returned an empty video file.")
                    }
                    let name = url.lastPathComponent.isEmpty ? "PhotosVideo.mov" : url.lastPathComponent
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + "-" + name)
                    try FileManager.default.copyItem(at: url, to: destination)
                    result = .success(destination)
                } catch {
                    result = .failure(error as? AppError ?? .importFailedReason(error.localizedDescription))
                }
                Task { @MainActor in onResult(result) }
            }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        NavigationStack {
            Group {
                switch state.route {
                case .home: HomeView()
                case .editor: EditorView()
                case .processing: ProcessingView()
                case .results: ResultsView()
                }
            }
            .navigationDestination(isPresented: Bindable(state).showDiagnostics) {
                DiagnosticsView()
            }
            .alert("Clarity Video AI", isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )) {
                Button("OK") { state.errorMessage = nil }
            } message: {
                Text(state.errorMessage ?? "")
            }
        }
        .tint(.cyan)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            state.handleMemoryPressure()
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            state.recordThermalTransition()
        }
    }
}

struct HomeView: View {
    @Environment(AppState.self) private var state
    @State private var showingPhotos = false
    @State private var showingFiles = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(.cyan)
                    Text("Clarity Video AI").font(.largeTitle.bold())
                    Text("Private on-device video enhancement")
                        .foregroundStyle(.secondary)
                }.padding(.top, 42)

                VStack(spacing: 12) {
                    Button { showingPhotos = true } label: {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(state.isImporting)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    Button { showingFiles = true } label: {
                        Label("Choose from Files", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(state.isImporting)
                    .buttonStyle(.bordered).controlSize(.large)
                }

                PrivacyCard()

                HStack {
                    Text("Recent").font(.title2.bold())
                    Spacer()
                    Button("Diagnostics") { state.showDiagnostics = true }
                }
                if state.recentJobs.isEmpty {
                    ContentUnavailableView("No exports yet", systemImage: "film.stack", description: Text("Completed and paused jobs appear here."))
                } else {
                    ForEach(state.recentJobs) { job in
                        HStack {
                            Image(systemName: job.status == .completed ? "checkmark.circle.fill" : "pause.circle")
                                .foregroundStyle(job.status == .completed ? .green : .orange)
                            VStack(alignment: .leading) {
                                Text(job.assetInfo.fileName).lineLimit(1)
                                Text("\(job.configuration.resolution.rawValue) \u{00B7} \(job.status.rawValue.capitalized)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if job.status == .paused { Button("Resume") { state.resume(job) }.buttonStyle(.borderedProminent) }
                            Spacer()
                        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }.padding()
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingPhotos) {
            VideoPhotosPicker { result in
                showingPhotos = false
                switch result {
                case .success(let url):
                    state.isImporting = true
                    state.importStatus = "Copying the selected Photos video..."
                    Task { await state.importVideo(from: url, sourceLabel: "Photos video") }
                case .failure(let error):
                    state.lastImportError = error.localizedDescription
                    state.errorMessage = error.localizedDescription
                }
            } onCancel: {
                showingPhotos = false
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.video]) { result in
            if case let .success(url) = result {
                state.isImporting = true
                state.importStatus = "Opening the selected Files video..."
                Task { await state.importVideo(from: url, sourceLabel: "Files video") }
            }
            if case let .failure(error) = result { state.lastImportError = error.localizedDescription; state.errorMessage = error.localizedDescription }
        }
        .overlay {
            if state.isImporting {
                ProgressView(state.importStatus ?? "Importing video...")
                    .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

struct PrivacyCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Always private").font(.headline)
                Text("No account, uploads, cloud credits, analytics, or server processing. Your source stays on this device.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
