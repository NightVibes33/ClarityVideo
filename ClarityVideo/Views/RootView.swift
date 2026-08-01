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
    @AppStorage("clarity.onboarding.completed") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                appNavigation
                    .transition(.opacity)
            } else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.35)) { hasCompletedOnboarding = true }
                }
                .transition(.opacity)
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

    private var appNavigation: some View {
        NavigationStack {
            Group {
                switch state.route {
                case .home: HomeView()
                case .editor: EditorView()
                case .processing: ProcessingView()
                case .results: ResultsView()
                }
            }
            .navigationDestination(isPresented: Bindable(state).showDiagnostics) { DiagnosticsView() }
            .alert("Something needs your attention", isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )) {
                Button("Got it") { state.errorMessage = nil }
            } message: {
                Text(state.errorMessage ?? "")
            }
        }
    }
}

struct HomeView: View {
    @Environment(AppState.self) private var state
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles.tv.fill")
                            .font(.title2).foregroundStyle(.cyan)
                        Text("Clarity").font(.title2.bold())
                    }
                    Spacer()
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                            .background(.thinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Settings")
                }.padding(.top, 12)

                VStack(spacing: 18) {
                    ZStack {
                        Circle().fill(.cyan.opacity(0.16)).frame(width: 108, height: 108)
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(.cyan)
                    }
                    Text("Make every frame feel new")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text("Restore detail, reduce noise, and create beautiful 4K or 8K video - privately on your iPhone.")
                        .font(.title3).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [.cyan.opacity(0.18), .blue.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28)
                )

                HStack(spacing: 8) {
                    HomeBenefit(symbol: "4k.tv.fill", title: "4K & 8K")
                    HomeBenefit(symbol: "iphone.gen3", title: "On-device")
                    HomeBenefit(symbol: "lock.fill", title: "Always private")
                }

                VStack(spacing: 12) {
                    Button { showingPhotos = true } label: {
                        Label("Choose a video", systemImage: "photo.on.rectangle.angled")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .disabled(state.isImporting)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    Button { showingFiles = true } label: {
                        Label("Browse Files", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(state.isImporting)
                    .buttonStyle(.bordered).controlSize(.large)
                }

                PrivacyCard()

                HStack {
                    Text("Your videos").font(.title2.bold())
                    Spacer()
                }
                if state.recentJobs.isEmpty {
                    VStack(spacing: 10) { Image(systemName: "film.stack").font(.largeTitle).foregroundStyle(.secondary); Text("Your enhanced videos will appear here").font(.headline); Text("Choose a video above to create your first enhancement.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(.vertical, 34).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
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
                            Spacer()
                            if job.status == .paused {
                                Button("Resume") { state.resume(job) }.buttonStyle(.borderedProminent)
                            } else if job.status == .completed {
                                Button("View") {
                                    state.activeJob = job
                                    state.route = .results
                                }.buttonStyle(.bordered)
                            }
                        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }.padding()
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingSettings) { SettingsView() }
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

struct HomeBenefit: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.cyan)
            Text(title).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct OnboardingFeature {
    let symbol: String
    let title: String
    let detail: String
}

struct OnboardingPage {
    let symbol: String
    let eyebrow: String
    let title: String
    let detail: String
    let accent: Color
    let features: [OnboardingFeature]
}

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var page = 0

    private let pages = [
        OnboardingPage(
            symbol: "sparkles.tv.fill", eyebrow: "WELCOME TO CLARITY",
            title: "Make every frame feel new",
            detail: "Turn soft, noisy, or aging footage into a cleaner video made for today's screens.",
            accent: .cyan,
            features: [
                OnboardingFeature(symbol: "4k.tv.fill", title: "True UHD output", detail: "Create standard 4K or 8K video when your device supports it."),
                OnboardingFeature(symbol: "wand.and.stars", title: "Intelligent enhancement", detail: "Apple on-device processing restores detail frame by frame."),
                OnboardingFeature(symbol: "rectangle.split.2x1", title: "See the difference", detail: "Preview a short range with a draggable before-and-after comparison.")
            ]
        ),
        OnboardingPage(
            symbol: "lock.shield.fill", eyebrow: "PRIVATE BY DESIGN",
            title: "Your videos stay yours",
            detail: "Every frame is processed locally. Clarity has no account, cloud upload, credits, or tracking.",
            accent: .green,
            features: [
                OnboardingFeature(symbol: "iphone", title: "Fully on-device", detail: "Enhancement and export happen on your iPhone or iPad."),
                OnboardingFeature(symbol: "wifi.slash", title: "No upload required", detail: "Your source video never needs to leave your device."),
                OnboardingFeature(symbol: "person.crop.circle.badge.xmark", title: "No account", detail: "Start enhancing immediately without a sign-up or subscription.")
            ]
        ),
        OnboardingPage(
            symbol: "slider.horizontal.3", eyebrow: "MADE FOR YOUR FOOTAGE",
            title: "Choose the look you want",
            detail: "Start with a thoughtful preset, then fine-tune noise reduction, detail, sharpness, codec, and quality.",
            accent: .purple,
            features: [
                OnboardingFeature(symbol: "hare.fill", title: "Fast", detail: "A lighter path for quick, efficient enhancement."),
                OnboardingFeature(symbol: "diamond.fill", title: "Quality", detail: "Prioritizes detail and the best supported Apple processing route."),
                OnboardingFeature(symbol: "clock.arrow.circlepath", title: "Restore and Anime", detail: "Tailored controls for older footage, animation, and gameplay.")
            ]
        ),
        OnboardingPage(
            symbol: "checkmark.seal.fill", eyebrow: "READY WHEN YOU ARE",
            title: "Preview, enhance, enjoy",
            detail: "Clarity checks storage and device support, keeps you informed, and makes the finished video easy to save or share.",
            accent: .orange,
            features: [
                OnboardingFeature(symbol: "play.rectangle.on.rectangle", title: "Before and after", detail: "Inspect detail at 100, 200, or 400 percent before a full export."),
                OnboardingFeature(symbol: "pause.circle.fill", title: "Pause and resume", detail: "Long jobs use checkpoints so completed work can be resumed."),
                OnboardingFeature(symbol: "square.and.arrow.up", title: "Save anywhere", detail: "Save to Photos, Files, or share with your favorite apps.")
            ]
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [pages[page].accent.opacity(0.20), Color.black, Color.black],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("CLARITY").font(.subheadline.bold()).tracking(2).foregroundStyle(.secondary)
                    Spacer()
                    if page < pages.count - 1 {
                        Button("Skip") { onComplete() }.foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 24).padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageView(page: pages[index]).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? pages[page].accent : Color.secondary.opacity(0.28))
                            .frame(width: index == page ? 28 : 8, height: 8)
                            .animation(.spring(response: 0.35), value: page)
                    }
                }.padding(.bottom, 20)

                Button {
                    if page == pages.count - 1 { onComplete() }
                    else { withAnimation { page += 1 } }
                } label: {
                    HStack {
                        Text(page == pages.count - 1 ? "Start enhancing" : "Continue")
                        Image(systemName: page == pages.count - 1 ? "sparkles" : "arrow.right")
                    }
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(pages[page].accent)
                .padding(.horizontal, 24).padding(.bottom, 16)
            }
        }
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 16)
                ZStack {
                    Circle().fill(page.accent.opacity(0.17)).frame(width: 118, height: 118)
                    Circle().stroke(page.accent.opacity(0.28), lineWidth: 1).frame(width: 92, height: 92)
                    Image(systemName: page.symbol)
                        .font(.system(size: 47, weight: .semibold)).foregroundStyle(page.accent)
                }
                VStack(spacing: 10) {
                    Text(page.eyebrow).font(.caption.bold()).tracking(1.8).foregroundStyle(page.accent)
                    Text(page.title).font(.system(size: 34, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(page.detail).font(.title3).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 12) {
                    ForEach(page.features.indices, id: \.self) { index in
                        let feature = page.features[index]
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: feature.symbol)
                                .font(.headline).foregroundStyle(page.accent)
                                .frame(width: 38, height: 38)
                                .background(page.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(feature.title).font(.headline)
                                Text(feature.detail).font(.subheadline).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
                    }
                }
                Spacer(minLength: 8)
            }.padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("clarity.onboarding.completed") private var hasCompletedOnboarding = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    LabeledContent("Processing", value: "On-device")
                    LabeledContent("Account", value: "Not required")
                } header: { Text("About Clarity") } footer: {
                    Text("Clarity enhances video locally using Apple media and machine-learning technologies supported by your device.")
                }

                Section("Your privacy") {
                    Label("No cloud uploads", systemImage: "icloud.slash")
                    Label("No analytics or tracking", systemImage: "eye.slash")
                    Label("No account or cloud credits", systemImage: "person.crop.circle.badge.xmark")
                }

                Section("Help and learning") {
                    Button {
                        hasCompletedOnboarding = false
                        dismiss()
                    } label: { Label("Replay introduction", systemImage: "play.circle") }
                    NavigationLink { DiagnosticsView() } label: {
                        Label("Video engine diagnostics", systemImage: "stethoscope")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Long exports and 8K video can use significant storage, power, and time. Clarity monitors temperature, creates checkpoints where appropriate, and never replaces your original video.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                } header: { Text("Good to know") }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
