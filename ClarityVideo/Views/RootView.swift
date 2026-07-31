import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers
import CoreTransferable
import UIKit

struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let originalName = received.file.lastPathComponent.isEmpty ? "PhotosVideo.mov" : received.file.lastPathComponent
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "-" + originalName)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
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
    @State private var photoItem: PhotosPickerItem?
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
                    PhotosPicker(selection: $photoItem, matching: .videos) {
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
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.video]) { result in
            if case let .success(url) = result { Task { await state.importVideo(from: url, sourceLabel: "file") } }
            if case let .failure(error) = result { state.lastImportError = error.localizedDescription; state.errorMessage = error.localizedDescription }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            state.isImporting = true
            state.importStatus = "Requesting the selected Photos video..."
            Task { @MainActor in
                defer {
                    photoItem = nil
                    if state.route != .editor {
                        state.isImporting = false
                        state.importStatus = nil
                    }
                }
                do {
                    guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                        throw AppError.importFailedReason("Photos did not provide a transferable movie file.")
                    }
                    await state.importVideo(from: movie.url, sourceLabel: "Photos video")
                } catch {
                    state.lastImportError = error.localizedDescription
                    state.errorMessage = error.localizedDescription
                }
            }
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
