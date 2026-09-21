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
        ZStack {
            ClarityBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    brandHeader
                    hero
                    quickActions
                    featureStrip
                    projects
                    privacyFooter
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 34)
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarHidden(true)
        .sheet(isPresented: $showingSettings) { SettingsView().preferredColorScheme(.dark) }
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
            } onCancel: { showingPhotos = false }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.video]) { result in
            switch result {
            case .success(let url):
                state.isImporting = true
                state.importStatus = "Opening the selected Files video..."
                Task { await state.importVideo(from: url, sourceLabel: "Files video") }
            case .failure(let error):
                state.lastImportError = error.localizedDescription
                state.errorMessage = error.localizedDescription
            }
        }
        .overlay {
            if state.isImporting {
                ZStack {
                    Color.black.opacity(0.46).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(.cyan)
                        Text(state.importStatus ?? "Importing video...")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .padding(26)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            ClarityMark(size: 42)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("Clarity").foregroundStyle(.white)
                    Text("Video").foregroundStyle(ClarityTheme.brandGradient)
                }
                .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("ENHANCE  ·  RESTORE  ·  CREATE")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.7)
                    .foregroundStyle(.white.opacity(0.46))
            }
            Spacer()
            Button { state.showDiagnostics = true } label: {
                Image(systemName: "waveform.path.ecg")
                    .frame(width: 42, height: 42)
                    .background(ClarityTheme.panel, in: Circle())
            }
            .accessibilityLabel("Diagnostics")
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .frame(width: 42, height: 42)
                    .background(ClarityTheme.panel, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Sharper. Cleaner. Better.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Bring detail back to every frame with private, on-device enhancement.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.67))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(ClarityTheme.brandGradient)
                    .padding(15)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Button { showingPhotos = true } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(ClarityTheme.brandGradient)
                            .frame(width: 48, height: 48)
                        Image(systemName: "play.rectangle.fill").font(.title3.bold()).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enhance Video").font(.headline)
                        Text("Import from Photos and start enhancing").font(.caption).foregroundStyle(.white.opacity(0.62))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(.white.opacity(0.65))
                }
                .padding(14)
                .background(
                    LinearGradient(colors: [Color.blue.opacity(0.30), Color.indigo.opacity(0.18)], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.cyan.opacity(0.24), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(state.isImporting)
        }
        .padding(20)
        .background(ClarityTheme.heroPanel, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 1))
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            ClarityAction(symbol: "photo.on.rectangle.angled", title: "Photos", tint: .blue) { showingPhotos = true }
            ClarityAction(symbol: "folder.fill", title: "Files", tint: .indigo) { showingFiles = true }
            ClarityAction(symbol: "slider.horizontal.3", title: "Settings", tint: .purple) { showingSettings = true }
        }
    }

    private var featureStrip: some View {
        HStack(spacing: 8) {
            HomeBenefit(symbol: "4k.tv.fill", title: "4K / 8K")
            HomeBenefit(symbol: "sparkles", title: "AI Enhance")
            HomeBenefit(symbol: "bolt.fill", title: "On-device")
            HomeBenefit(symbol: "lock.fill", title: "Private")
        }
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Projects").font(.title3.bold())
                Spacer()
                Text("\(state.recentJobs.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.cyan.opacity(0.10), in: Capsule())
            }

            if state.recentJobs.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "film.stack.fill")
                        .font(.title2)
                        .foregroundStyle(ClarityTheme.brandGradient)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No projects yet").font(.headline)
                        Text("Import a video to create your first enhancement.")
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(15)
                .background(ClarityTheme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(state.recentJobs.prefix(6)) { job in
                    HStack(spacing: 13) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.055)).frame(width: 54, height: 54)
                            Image(systemName: job.status == .completed ? "checkmark.seal.fill" : "film.fill")
                                .foregroundStyle(job.status == .completed ? Color.cyan : Color.purple)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.assetInfo.fileName).font(.subheadline.bold()).lineLimit(1)
                            Text("\(job.configuration.resolution.rawValue)  ·  \(job.status.rawValue.capitalized)")
                                .font(.caption).foregroundStyle(.white.opacity(0.52))
                        }
                        Spacer()
                        if job.status == .paused {
                            Button("Resume") { state.resume(job) }.buttonStyle(.borderedProminent).tint(.blue)
                        } else if job.status == .completed {
                            Button {
                                state.activeJob = job
                                state.route = .results
                            } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(13)
                    .background(ClarityTheme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }

    private var privacyFooter: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill").foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Powered. On Device.").font(.subheadline.bold())
                Text("Your source video stays with you.").font(.caption).foregroundStyle(.white.opacity(0.48))
            }
            Spacer()
        }
        .padding(15)
        .background(ClarityTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private enum ClarityTheme {
    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.20, green: 0.72, blue: 1.0), Color(red: 0.42, green: 0.42, blue: 1.0), Color(red: 0.68, green: 0.30, blue: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let panel = Color(red: 0.055, green: 0.085, blue: 0.13).opacity(0.94)
    static let heroPanel = LinearGradient(
        colors: [Color(red: 0.04, green: 0.10, blue: 0.18), Color(red: 0.04, green: 0.06, blue: 0.10)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

private struct ClarityBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.015, green: 0.025, blue: 0.045)
            RadialGradient(colors: [Color.blue.opacity(0.20), .clear], center: .topLeading, startRadius: 0, endRadius: 430)
            RadialGradient(colors: [Color.purple.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 400)
        }
        .ignoresSafeArea()
    }
}

private struct ClarityMark: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(Color(red: 0.025, green: 0.05, blue: 0.10))
            Circle()
                .stroke(ClarityTheme.brandGradient, lineWidth: max(2, size * 0.075))
                .padding(size * 0.18)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.29, weight: .bold))
                .foregroundStyle(ClarityTheme.brandGradient)
                .offset(x: size * 0.025)
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.27).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
        .shadow(color: .blue.opacity(0.30), radius: 10)
    }
}

private struct ClarityAction: View {
    let symbol: String
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title3).foregroundStyle(tint)
                Text(title).font(.caption.bold()).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(ClarityTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
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
