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
        appNavigation
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
                case .home: ReferenceHomeView()
                case .importVideo: ReferenceImportVideoView()
                case .editor: ReferenceEditorView()
                case .exportSetup: ReferenceExportView()
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
    @State private var showingSettings = false
    @State private var showingProjects = false

    var body: some View {
        ZStack {
            ClarityBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    topBar
                    wordmark
                    primaryActions
                    recentProjects
                    Spacer(minLength: 6)
                    mountainPanel
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 88)
            }
            VStack { Spacer(); bottomBar }
        }
        .preferredColorScheme(.dark)
        .navigationBarHidden(true)
        .sheet(isPresented: $showingSettings) { SettingsView().preferredColorScheme(.dark) }
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
                        VStack(alignment: .leading, spacing: 5) {
                            Text(job.assetInfo.fileName).lineLimit(1)
                            Text("\(job.configuration.resolution.rawValue) · \(job.status.rawValue.capitalized)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .overlay { if state.recentJobs.isEmpty { ContentUnavailableView("No recent projects", systemImage: "film") } }
                .navigationTitle("Recent Projects")
                .toolbar { Button("Done") { showingProjects = false } }
            }.preferredColorScheme(.dark)
        }
        .overlay { if state.isImporting { importOverlay } }
    }

    private var topBar: some View {
        HStack {
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.title3).foregroundStyle(.cyan)
            }
            Spacer()
            Image(systemName: "crown.fill").font(.title3).foregroundStyle(.purple)
        }
        .padding(.horizontal, 4)
    }

    private var wordmark: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 19).fill(Color(red: 0.025, green: 0.04, blue: 0.09))
                    .frame(width: 74, height: 74)
                    .overlay(RoundedRectangle(cornerRadius: 19).stroke(ClarityTheme.brandGradient, lineWidth: 2))
                    .shadow(color: .blue.opacity(0.65), radius: 15)
                Circle().stroke(ClarityTheme.brandGradient, lineWidth: 4).frame(width: 50, height: 50)
                Image(systemName: "play.fill").font(.title2).foregroundStyle(.white)
            }.padding(.bottom, 2)
            HStack(spacing: 0) {
                Text("Clarity").foregroundStyle(.white)
                Text("Video").foregroundStyle(ClarityTheme.brandGradient)
            }
            .font(.system(size: 31, weight: .bold, design: .rounded))
            Text("Sharper. Clearer. Better.")
                .font(.caption.weight(.medium)).tracking(1).foregroundStyle(.white.opacity(0.65))
        }
        .padding(.vertical, 6)
    }

    private var featureStrip: some View {
        HStack(spacing: 8) {
            ReferenceFeature(symbol: "4k.tv.fill", title: "4K / 8K", subtitle: "Upscaling")
            ReferenceFeature(symbol: "sparkles", title: "AI", subtitle: "Enhancement")
            ReferenceFeature(symbol: "bolt.fill", title: "Fast", subtitle: "On-Device")
            ReferenceFeature(symbol: "lock.fill", title: "Private", subtitle: "Local Only")
        }.padding(.vertical, 4)
    }

    private var primaryActions: some View {
        VStack(spacing: 11) {
            HomeMenuButton(symbol: "video.fill", title: "Enhance Video", subtitle: "Import from Photos, Files or Camera") {
                state.route = .importVideo
            }
            HomeMenuButton(symbol: "clock.fill", title: "Recent Projects", subtitle: "Continue your work") { showingProjects = true }
            HomeMenuButton(symbol: "gearshape.fill", title: "Settings", subtitle: "Quality, export and advanced options") {
                showingSettings = true
            }
        }
    }

    private var recentProjects: some View {
        Group {
            if !state.recentJobs.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("RECENT").font(.caption2.bold()).tracking(1.8).foregroundStyle(.white.opacity(0.42))
                    ForEach(state.recentJobs.prefix(3)) { job in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12).fill(ClarityTheme.brandGradient).frame(width: 48, height: 48)
                                .overlay(Image(systemName: "film.fill").foregroundStyle(.white))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(job.assetInfo.fileName).font(.subheadline.bold()).lineLimit(1)
                                Text("\(job.configuration.resolution.rawValue) · \(job.status.rawValue.capitalized)")
                                    .font(.caption).foregroundStyle(.white.opacity(0.52))
                            }
                            Spacer()
                            if job.status == .paused {
                                Button("Resume") { state.resume(job) }.font(.caption.bold())
                            } else if job.status == .completed {
                                Button { state.activeJob = job; state.route = .results } label: { Image(systemName: "chevron.right") }
                            }
                        }
                        .padding(11)
                        .background(ClarityTheme.panel, in: RoundedRectangle(cornerRadius: 17))
                    }
                }
            }
        }
    }

    private var mountainPanel: some View {
        ZStack(alignment: .bottom) {
            if let mountain = ReferenceArtwork.mountain {
                Image(uiImage: mountain).resizable().scaledToFill().frame(height: 255).clipped()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
            VStack(spacing: 10) {
                Spacer()
                Text("TURN GOOD FOOTAGE\nINTO GREAT MEMORIES.")
                    .font(.caption2.bold()).tracking(2.5).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.76))
                    .padding(.bottom, 15)
            }
        }
        .frame(height: 255)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.blue.opacity(0.18)))
    }

    private var bottomBar: some View {
        HStack {
            BottomItem(symbol: "house.fill", title: "Home", selected: true) { }
            BottomItem(symbol: "folder.fill", title: "Projects") { showingProjects = true }
            Button { state.route = .importVideo } label: {
                ZStack {
                    Circle().fill(ClarityTheme.brandGradient).frame(width: 58, height: 58)
                    Circle().stroke(.cyan.opacity(0.85), lineWidth: 2).frame(width: 58, height: 58)
                    Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                }.shadow(color: .blue.opacity(0.7), radius: 12)
            }
            BottomItem(symbol: "bolt.fill", title: "Tools") { state.showDiagnostics = true }
            BottomItem(symbol: "gearshape.fill", title: "Settings") { showingSettings = true }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5) }
    }

    private var importOverlay: some View {
        ZStack {
            Color.black.opacity(0.56).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(.cyan)
                Text(state.importStatus ?? "Importing video...").font(.subheadline.bold())
            }
            .padding(28).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

private enum ReferenceArtwork {
    static let mountain = UIImage(named: "MountainReference")
}

private enum ClarityTheme {
    static let brandGradient = LinearGradient(colors: [
        Color(red: 0.16, green: 0.72, blue: 1.0),
        Color(red: 0.35, green: 0.42, blue: 1.0),
        Color(red: 0.70, green: 0.27, blue: 1.0)
    ], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let panel = Color(red: 0.045, green: 0.075, blue: 0.12).opacity(0.98)
}

private struct ClarityBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.018, blue: 0.034)
            RadialGradient(colors: [Color.blue.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 480)
            RadialGradient(colors: [Color.purple.opacity(0.10), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 420)
        }.ignoresSafeArea()
    }
}

private struct ReferenceFeature: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.045)).frame(width: 38, height: 38)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.45)))
                .overlay(Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(ClarityTheme.brandGradient))
            Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            Text(subtitle).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.46)).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }
}

private struct HomeMenuButton: View {
    let symbol: String
    let title: String
    let subtitle: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 13).fill(ClarityTheme.brandGradient).frame(width: 48, height: 48)
                    .overlay(Image(systemName: symbol).font(.title3.bold()).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(subtitle).font(.caption2).foregroundStyle(.white.opacity(0.52))
                }
                Spacer()
            }
            .padding(13)
            .background(LinearGradient(colors: [Color.blue.opacity(0.20), Color(red: 0.045, green: 0.075, blue: 0.12)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.blue.opacity(0.28), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

private struct BottomItem: View {
    let symbol: String
    let title: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(selected ? Color.cyan : Color.white.opacity(0.58))
            .frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
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
