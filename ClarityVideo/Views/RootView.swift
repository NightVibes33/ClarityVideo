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
            if let snapshotRoute = ProcessInfo.processInfo.environment["CLARITY_UI_ROUTE"] {
                switch snapshotRoute {
                case "settings":
                    SettingsView()
                case "diagnostics":
                    NavigationStack { DiagnosticsView() }
                case "projects":
                    ClarityProjectsView()
                default:
                    appNavigation
                }
            } else if hasCompletedOnboarding {
                appNavigation
            } else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        hasCompletedOnboarding = true
                    }
                }
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
                case .home: ReferenceHomeView()
                case .importVideo: ReferenceImportVideoView()
                case .editor: ReferenceEditorView()
                case .exportSetup: ReferenceExportView()
                case .processing: ProcessingView()
                case .results: ResultsView()
                }
            }
            .navigationDestination(isPresented: Bindable(state).showDiagnostics) { DiagnosticsView() }
            .overlay {
                if let message = state.errorMessage {
                    ClarityNoticeOverlay(
                        title: alertTitle,
                        message: message,
                        dismiss: { state.errorMessage = nil }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(50)
                }
            }
            .animation(.easeOut(duration: 0.18), value: state.errorMessage != nil)
        }
    }

    private var alertTitle: String {
        guard let message = state.errorMessage else { return "ClarityVideo" }
        if message.localizedCaseInsensitiveContains("storage") {
            return "Not Enough Storage"
        }
        if message.localizedCaseInsensitiveContains("HDR") {
            return "HDR Setting Needs Attention"
        }
        if message.localizedCaseInsensitiveContains("encoder") {
            return "Export Not Supported"
        }
        return "Unable to Continue"
    }
}

private struct ClarityNoticeOverlay: View {
    let title: String
    let message: String
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.42), Color.purple.opacity(0.26)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 46, height: 46)
                        Image(systemName: noticeIcon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.cyan)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("ClarityVideo")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    Spacer()
                }

                Text(message)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(4)
                    .padding(.top, 16)

                Button(action: dismiss) {
                    Text("Got it")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(ClarityNativeTheme.brand, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
            }
            .padding(20)
            .frame(maxWidth: 350)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(ClarityNativeTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.cyan.opacity(0.56), Color.blue.opacity(0.30), Color.purple.opacity(0.24)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.blue.opacity(0.20), radius: 30)
                    .shadow(color: .black.opacity(0.65), radius: 34, y: 18)
            )
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .contain)
    }

    private var noticeIcon: String {
        if message.localizedCaseInsensitiveContains("storage") { return "internaldrive.fill" }
        if message.localizedCaseInsensitiveContains("HDR") { return "sun.max.trianglebadge.exclamationmark.fill" }
        if message.localizedCaseInsensitiveContains("encoder") { return "video.badge.exclamationmark" }
        return "exclamationmark.triangle.fill"
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
            if let mountain = ClarityMountainArt.mountain {
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

private enum ClarityMountainArt {
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
                OnboardingFeature(symbol: "hare.fill", title: "Balanced", detail: "A lighter enhancement pass for faster processing."),
                OnboardingFeature(symbol: "diamond.fill", title: "Quality", detail: "Balanced cleanup and detail recovery for most footage."),
                OnboardingFeature(symbol: "sparkles", title: "Ultra", detail: "The strongest cleanup, detail recovery, and sharpening preset.")
            ]
        ),
        OnboardingPage(
            symbol: "checkmark.seal.fill", eyebrow: "READY WHEN YOU ARE",
            title: "Preview, enhance, enjoy",
            detail: "Clarity checks storage and device support, keeps you informed, and makes the finished video easy to save or share.",
            accent: .orange,
            features: [
                OnboardingFeature(symbol: "play.rectangle.on.rectangle", title: "Before and after", detail: "Generate a short real enhancement preview before committing to a full export."),
                OnboardingFeature(symbol: "pause.circle.fill", title: "Pause and resume", detail: "Long jobs use checkpoints so completed work can be resumed."),
                OnboardingFeature(symbol: "square.and.arrow.up", title: "Save anywhere", detail: "Save to Photos, Files, or share with your favorite apps.")
            ]
        )
    ]

    var body: some View {
        ZStack {
            ClarityScreenBackdrop()

            RadialGradient(
                colors: [pages[page].accent.opacity(0.16), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 0) {
                        Text("Clarity").foregroundStyle(.white)
                        Text("Video").foregroundStyle(ClarityNativeTheme.brand)
                    }
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                    Spacer()

                    if page < pages.count - 1 {
                        Button("Skip") { onComplete() }
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.045), in: Capsule())
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageView(page: pages[index]).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(
                                index == page
                                    ? AnyShapeStyle(ClarityNativeTheme.brand)
                                    : AnyShapeStyle(Color.white.opacity(0.18))
                            )
                            .frame(width: index == page ? 30 : 8, height: 7)
                            .animation(.spring(response: 0.35), value: page)
                    }
                }
                .padding(.bottom, 15)

                Button {
                    if page == pages.count - 1 {
                        onComplete()
                    } else {
                        withAnimation(.easeInOut(duration: 0.24)) { page += 1 }
                    }
                } label: {
                    HStack(spacing: 9) {
                        Text(page == pages.count - 1 ? "Start Enhancing" : "Continue")
                        Image(systemName: page == pages.count - 1 ? "sparkles" : "arrow.right")
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        ClarityNativeTheme.brand,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                    .shadow(color: Color.blue.opacity(0.28), radius: 16, y: 7)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Spacer(minLength: 8)

                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(ClarityNativeTheme.card)
                        .frame(width: 106, height: 106)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(ClarityNativeTheme.border, lineWidth: 1)
                        )
                        .shadow(color: page.accent.opacity(0.22), radius: 18)

                    Image(systemName: page.symbol)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(page.accent)
                }

                VStack(spacing: 8) {
                    Text(page.eyebrow)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(page.accent)

                    Text(page.title)
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)

                    Text(page.detail)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    ForEach(page.features.indices, id: \.self) { index in
                        let feature = page.features[index]

                        NativePanel {
                            HStack(alignment: .top, spacing: 13) {
                                ClarityIconTile(
                                    icon: feature.symbol,
                                    size: 44,
                                    iconSize: 18
                                )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(feature.title)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text(feature.detail)
                                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(13)
                        }
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 22)
        }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage("clarity.onboarding.completed") private var hasCompletedOnboarding = true

    var body: some View {
        NavigationStack {
            ZStack {
                ClarityScreenBackdrop()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header

                        settingsSection("Enhancement defaults") {
                            VStack(alignment: .leading, spacing: 10) {
                                settingTitle("Target Resolution")
                                SettingsChoiceRow(
                                    options: state.capabilities.supports8KHEVCEncode
                                        ? ["4K", "8K"]
                                        : ["4K"],
                                    selected: state.configuration.resolution == .uhd8K ? "8K" : "4K"
                                ) { value in
                                    state.configuration.resolution = value == "8K" ? .uhd8K : .uhd4K
                                    if state.configuration.resolution == .uhd8K {
                                        state.configuration.codec = .hevc
                                    }
                                    state.configuration.clampBitrateToSupportedRange()
                                }
                            }
                            .padding(.vertical, 13)

                            divider

                            VStack(alignment: .leading, spacing: 10) {
                                settingTitle("AI Upscaler")
                                SettingsChoiceRow(
                                    options: IOSNeuralHeadService.bundledModelURL() == nil
                                        ? ["Apple SR"]
                                        : ["Apple SR", "DLSS 5"],
                                    selected: state.configuration.upscaler == .dlss5 ? "DLSS 5" : "Apple SR"
                                ) { value in
                                    state.configuration.upscaler = value == "DLSS 5" ? .dlss5 : .appleSR
                                }
                            }
                            .padding(.vertical, 13)

                            divider

                            VStack(alignment: .leading, spacing: 10) {
                                settingTitle("Enhancement Mode")
                                SettingsChoiceRow(
                                    options: QualityPreset.allCases.map(\.rawValue),
                                    selected: state.configuration.qualityPreset.rawValue
                                ) { value in
                                    guard let preset = QualityPreset(rawValue: value) else { return }
                                    state.configuration.applyPreset(
                                        preset,
                                        temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
                                    )
                                }
                            }
                            .padding(.vertical, 13)
                        }

                        settingsSection("Fine tune defaults") {
                            settingsSlider(
                                title: "Denoise",
                                value: Binding(
                                    get: { state.configuration.denoise },
                                    set: { state.configuration.denoise = $0 }
                                ),
                                enabled: state.capabilities.temporalNoiseFilteringAvailable
                            )

                            divider

                            settingsSlider(
                                title: "Detail Recovery",
                                value: Binding(
                                    get: { state.configuration.detailRecovery },
                                    set: { state.configuration.detailRecovery = $0 }
                                )
                            )

                            divider

                            settingsSlider(
                                title: "Sharpen",
                                value: Binding(
                                    get: { state.configuration.sharpening },
                                    set: { state.configuration.sharpening = $0 }
                                )
                            )
                        }

                        settingsSection("Export defaults") {
                            VStack(alignment: .leading, spacing: 10) {
                                settingTitle("Format")
                                SettingsChoiceRow(
                                    options: state.configuration.resolution == .uhd8K
                                        ? ["HEVC"]
                                        : ["HEVC", "H.264"],
                                    selected: state.configuration.codec == .hevc ? "HEVC" : "H.264"
                                ) { value in
                                    state.configuration.codec = value == "H.264" ? .h264 : .hevc
                                }
                            }
                            .padding(.vertical, 13)

                            divider

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    settingTitle("Output Quality")
                                    Spacer()
                                    Text("\(state.configuration.bitrateMbps) Mbps")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.cyan.opacity(0.78))
                                }

                                SettingsChoiceRow(
                                    options: ["Standard", "High", "Maximum"],
                                    selected: bitrateQualityLabel
                                ) { value in
                                    let index = ["Standard", "High", "Maximum"].firstIndex(of: value) ?? 1
                                    let values = state.configuration.exportBitrateOptionsMbps
                                    if values.indices.contains(index) {
                                        state.configuration.bitrateMbps = values[index]
                                    }
                                }
                            }
                            .padding(.vertical, 13)

                            divider

                            settingsToggle(
                                icon: "gauge.with.dots.needle.50percent",
                                title: "Preserve source frame rate",
                                isOn: Binding(
                                    get: { state.configuration.preserveFrameRate },
                                    set: { state.configuration.preserveFrameRate = $0 }
                                )
                            )

                            divider

                            settingsToggle(
                                icon: "photo.on.rectangle.angled",
                                title: "Save to Photos after export",
                                isOn: Binding(
                                    get: { state.saveToPhotosAfterExport },
                                    set: { state.saveToPhotosAfterExport = $0 }
                                )
                            )

                            divider

                            settingsToggle(
                                icon: "folder.fill",
                                title: "Open Files export after completion",
                                isOn: Binding(
                                    get: { state.saveToFilesAfterExport },
                                    set: { state.saveToFilesAfterExport = $0 }
                                )
                            )
                        }

                        settingsSection("About Clarity") {
                            infoRow(
                                icon: "info.circle.fill",
                                title: "Version",
                                value: appVersion
                            )
                            divider
                            infoRow(
                                icon: "cpu.fill",
                                title: "Processing",
                                value: "On-device"
                            )
                            divider
                            infoRow(
                                icon: "person.fill",
                                title: "Account",
                                value: "Not required"
                            )
                        }

                        Text("Clarity enhances video locally using Apple media and machine-learning technologies supported by your device.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineSpacing(4)
                            .padding(.horizontal, 10)

                        settingsSection("Your privacy") {
                            featureRow(icon: "icloud.slash.fill", title: "No cloud uploads")
                            divider
                            featureRow(icon: "eye.slash.fill", title: "No analytics or tracking")
                            divider
                            featureRow(icon: "person.crop.circle.badge.xmark", title: "No account or cloud credits")
                        }

                        settingsSection("Help and learning") {
                            Button {
                                hasCompletedOnboarding = false
                                dismiss()
                            } label: {
                                actionRow(icon: "play.circle.fill", title: "Replay introduction")
                            }
                            .buttonStyle(.plain)

                            divider.padding(.leading, 62)

                            NavigationLink {
                                DiagnosticsView()
                            } label: {
                                actionRow(
                                    icon: "stethoscope",
                                    title: "Video engine diagnostics",
                                    showsChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Good to know")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.68))
                                .padding(.leading, 8)

                            NativePanel {
                                HStack(alignment: .top, spacing: 16) {
                                    ClarityIconTile(icon: "lightbulb.fill", size: 56, iconSize: 22)

                                    Text("Long exports and 8K video can use significant storage, power, and time. Clarity monitors temperature, creates checkpoints where appropriate, and never replaces your original video.")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.62))
                                        .lineSpacing(4)

                                    Spacer(minLength: 0)
                                }
                                .padding(16)
                            }
                        }

                        NativePanel {
                            VStack(spacing: 0) {
                                HStack {
                                    Label("Free storage", systemImage: "externaldrive.fill")
                                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(freeStorageText)
                                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.cyan.opacity(0.80))
                                }
                                .padding(.vertical, 13)

                                divider

                                Button {
                                    state.clearProcessingCache()
                                } label: {
                                    HStack {
                                        Label("Clear processing cache", systemImage: "trash.fill")
                                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.red)
                                        Spacer()
                                    }
                                    .padding(.vertical, 13)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 15)
                        }

                        Text("Processing stays on this iPhone unless you explicitly share an exported file.")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.34))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 12)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Settings")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 12)

            Button("Done") { dismiss() }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.cyan)
                .padding(.horizontal, 19)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.055))
                        .overlay(Capsule().stroke(ClarityNativeTheme.border, lineWidth: 0.8))
                )
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .padding(.leading, 8)

            NativePanel {
                VStack(spacing: 0) {
                    content()
                }
                .padding(.horizontal, 15)
            }
        }
    }

    private func settingTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
    }

    private func settingsSlider(
        title: String,
        value: Binding<Double>,
        enabled: Bool = true
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(enabled ? .white : .white.opacity(0.38))

                Spacer()

                Text("\(Int((value.wrappedValue * 100).rounded()))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(enabled ? .cyan.opacity(0.78) : .white.opacity(0.28))
            }

            Slider(value: value, in: 0...1)
                .tint(.cyan)
                .disabled(!enabled)
        }
        .padding(.vertical, 12)
    }

    private func settingsToggle(
        icon: String,
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 13) {
            ClarityIconTile(icon: icon, size: 40, iconSize: 16)

            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.cyan)
        }
        .padding(.vertical, 10)
    }

    private var bitrateQualityLabel: String {
        let values = state.configuration.exportBitrateOptionsMbps
        guard let index = values.enumerated().min(by: {
            abs($0.element - state.configuration.bitrateMbps)
                < abs($1.element - state.configuration.bitrateMbps)
        })?.offset else {
            return "High"
        }
        return ["Standard", "High", "Maximum"][min(index, 2)]
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            ClarityIconTile(icon: icon, size: 42, iconSize: 17)

            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(.vertical, 11)
    }

    private func featureRow(icon: String, title: String) -> some View {
        HStack(spacing: 14) {
            ClarityIconTile(icon: icon, size: 42, iconSize: 17)

            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.68))
        }
        .padding(.vertical, 11)
    }

    private func actionRow(
        icon: String,
        title: String,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            ClarityIconTile(icon: icon, size: 42, iconSize: 17)

            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.40))
            }
        }
        .padding(.vertical, 11)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.7)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var freeStorageText: String {
        guard let bytes = try? StorageEstimator.availableBytes() else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct SettingsChoiceRow: View {
    let options: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(options, id: \.self) { option in
                Button { onSelect(option) } label: {
                    Text(option)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            option == selected
                                ? AnyShapeStyle(ClarityNativeTheme.brand)
                                : AnyShapeStyle(Color.white.opacity(0.055)),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 0.7)
        )
    }
}
