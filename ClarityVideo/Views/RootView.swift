import SwiftUI
import AVKit
import UIKit

struct RootView: View {
    @AppStorage("clarity.onboarding.completed") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
#if targetEnvironment(simulator)
            if let snapshotRoute = ProcessInfo.processInfo.environment["CLARITY_UI_ROUTE"] {
                switch snapshotRoute {
                case "settings":
                    SettingsView()
                case "diagnostics", "diagnostics-actions", "diagnostics-confirm":
                    NavigationStack { DiagnosticsView() }
                case "projects":
                    ClarityProjectsView()
                case "onboarding":
                    OnboardingView { }
                case "import":
                    ReferenceImportSnapshotView()
                case "storage":
                    ClarityStorageDetailSheet(
                        breakdown: StorageEstimateBreakdown(
                            finalOutputBytes: 95_000_000,
                            workingBytes: 95_000_000,
                            safetyBytes: 96_000_000,
                            usesCheckpoints: false
                        ),
                        availableBytes: 583_200_000
                    )
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
#else
            if hasCompletedOnboarding {
                appNavigation
            } else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        hasCompletedOnboarding = true
                    }
                }
            }
#endif
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
                            .font(.system(size: 20.5, weight: .bold, design: .rounded))
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
    @State private var showsCompactHeader = false

    var body: some View {
        NavigationStack {
            ZStack {
                ClarityScreenBackdrop()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 15) {
                        header

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
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineSpacing(2)
                            .padding(.horizontal, 8)

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
                                .font(.system(size: 20.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.68))
                                .padding(.leading, 8)

                            NativePanel {
                                HStack(alignment: .top, spacing: 16) {
                                    ClarityIconTile(icon: "lightbulb.fill", size: 48, iconSize: 19)

                                    Text("Long exports and 8K video can use significant storage, power, and time. Clarity monitors temperature, creates checkpoints where appropriate, and never replaces your original video.")
                                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.62))
                                        .lineSpacing(2)

                                    Spacer(minLength: 0)
                                }
                                .padding(13)
                            }
                        }

                        Text("Processing stays on this iPhone unless you explicitly share an exported file.")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.34))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 12)
                    }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 22)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y > 92
                } action: { _, scrolled in
                    withAnimation(.easeOut(duration: 0.16)) {
                        showsCompactHeader = scrolled
                    }
                }
            }
            .overlay(alignment: .top) {
                if showsCompactHeader {
                    compactHeader
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(20)
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }

    private var compactHeader: some View {
        HStack {
            Color.clear.frame(width: 78, height: 44)

            Spacer()

            Text("Settings")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            ClarityPillButton(title: "Done") { dismiss() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.008, green: 0.040, blue: 0.095).opacity(0.98),
                            ClarityNativeTheme.background.opacity(0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ClarityNativeTheme.border)
                        .frame(height: 0.8)
                        .opacity(0.42)
                }
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Settings")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 12)

            ClarityPillButton(title: "Done") { dismiss() }
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 20.5, weight: .bold, design: .rounded))
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

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            ClarityIconTile(icon: icon, size: 44, iconSize: 17)

            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(.vertical, 10)
    }

    private func featureRow(icon: String, title: String) -> some View {
        HStack(spacing: 14) {
            ClarityIconTile(icon: icon, size: 44, iconSize: 17)

            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.vertical, 10)
    }

    private func actionRow(
        icon: String,
        title: String,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            ClarityIconTile(icon: icon, size: 44, iconSize: 17)

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
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.7)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

}
