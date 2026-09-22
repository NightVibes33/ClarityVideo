import SwiftUI
import AVKit
import UIKit

struct RootView: View {
    @Environment(AppState.self) private var state
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
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            HStack(alignment: .top, spacing: 13) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: noticeColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: noticeIcon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 16.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(message)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(ClarityNativeTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(ClarityNativeTheme.border, lineWidth: 0.9)
                    )
                    .shadow(color: Color.blue.opacity(0.20), radius: 22, y: 10)
                    .shadow(color: .black.opacity(0.55), radius: 28, y: 14)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .accessibilityElement(children: .contain)
    }

    private var noticeIcon: String {
        if message.localizedCaseInsensitiveContains("storage") { return "internaldrive.fill" }
        if message.localizedCaseInsensitiveContains("HDR") { return "sun.max.trianglebadge.exclamationmark.fill" }
        if message.localizedCaseInsensitiveContains("encoder") { return "video.badge.exclamationmark" }
        return "exclamationmark.triangle.fill"
    }

    private var noticeColors: [Color] {
        if message.localizedCaseInsensitiveContains("storage") {
            return [Color.orange.opacity(0.85), Color.red.opacity(0.52)]
        }
        return [Color.blue.opacity(0.80), Color.purple.opacity(0.58)]
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
                            infoRow(icon: "info.circle.fill", title: "Version", value: appVersion)
                            divider
                            infoRow(icon: "cpu.fill", title: "Processing", value: "On-device")
                            divider
                            infoRow(icon: "person.fill", title: "Account", value: "Not required")
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

                            divider.padding(.leading, 58)

                            NavigationLink {
                                DiagnosticsView()
                                    .environment(state)
                            } label: {
                                actionRow(icon: "stethoscope", title: "Video engine diagnostics", showsChevron: true)
                            }
                            .buttonStyle(.plain)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Good to know")
                                .font(.system(size: 20.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.68))
                                .padding(.leading, 8)

                            NativePanel {
                                HStack(alignment: .top, spacing: 14) {
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

                        settingsSection("Enhancement defaults") {
                            choiceBlock(
                                icon: "4k.tv.fill",
                                title: "Target Resolution",
                                options: state.capabilities.supports8KHEVCEncode ? ["4K", "8K"] : ["4K"],
                                selected: state.configuration.resolution == .uhd8K ? "8K" : "4K"
                            ) { value in
                                state.configuration.resolution = value == "8K" ? .uhd8K : .uhd4K
                                if state.configuration.resolution == .uhd8K {
                                    state.configuration.codec = .hevc
                                }
                                state.configuration.clampBitrateToSupportedRange()
                            }

                            divider

                            choiceBlock(
                                icon: "sparkles",
                                title: "Enhancement Mode",
                                options: QualityPreset.allCases.map(\.rawValue),
                                selected: state.configuration.qualityPreset.rawValue
                            ) { value in
                                guard let preset = QualityPreset(rawValue: value) else { return }
                                state.configuration.applyPreset(
                                    preset,
                                    temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
                                )
                            }

                            divider

                            choiceBlock(
                                icon: "brain.head.profile",
                                title: "AI Upscaler",
                                options: IOSNeuralHeadService.bundledModelURL() == nil
                                    ? ["Apple SR"]
                                    : ["Apple SR", "DLSS 5"],
                                selected: state.configuration.upscaler == .dlss5 ? "DLSS 5" : "Apple SR"
                            ) { value in
                                state.configuration.upscaler = value == "DLSS 5" ? .dlss5 : .appleSR
                            }

                            divider

                            brandedSlider(
                                icon: "waveform.path",
                                title: "Denoise",
                                value: Binding(
                                    get: { state.configuration.denoise },
                                    set: { state.configuration.denoise = $0 }
                                ),
                                enabled: state.capabilities.temporalNoiseFilteringAvailable
                            )

                            divider

                            brandedSlider(
                                icon: "wand.and.stars",
                                title: "Detail Recovery",
                                value: Binding(
                                    get: { state.configuration.detailRecovery },
                                    set: { state.configuration.detailRecovery = $0 }
                                )
                            )

                            divider

                            brandedSlider(
                                icon: "triangle.lefthalf.filled",
                                title: "Sharpen",
                                value: Binding(
                                    get: { state.configuration.sharpening },
                                    set: { state.configuration.sharpening = $0 }
                                )
                            )
                        }

                        settingsSection("Export defaults") {
                            choiceBlock(
                                icon: "film.fill",
                                title: "Format",
                                options: state.configuration.resolution == .uhd8K ? ["HEVC"] : ["HEVC", "H.264"],
                                selected: state.configuration.codec == .hevc ? "HEVC" : "H.264"
                            ) { value in
                                state.configuration.codec = value == "H.264" ? .h264 : .hevc
                            }

                            divider

                            choiceBlock(
                                icon: "gauge.with.dots.needle.67percent",
                                title: "Quality",
                                options: ["Standard", "High", "Maximum"],
                                selected: bitrateQualityLabel
                            ) { value in
                                let index = ["Standard", "High", "Maximum"].firstIndex(of: value) ?? 1
                                let values = state.configuration.exportBitrateOptionsMbps
                                if values.indices.contains(index) {
                                    state.configuration.bitrateMbps = values[index]
                                }
                            }

                            divider

                            brandedToggle(
                                icon: "gauge.with.dots.needle.50percent",
                                title: "Preserve source frame rate",
                                isOn: Binding(
                                    get: { state.configuration.preserveFrameRate },
                                    set: { state.configuration.preserveFrameRate = $0 }
                                )
                            )

                            divider

                            brandedToggle(
                                icon: "photo.on.rectangle.angled",
                                title: "Save to Photos after export",
                                isOn: Binding(
                                    get: { state.saveToPhotosAfterExport },
                                    set: { state.saveToPhotosAfterExport = $0 }
                                )
                            )

                            divider

                            brandedToggle(
                                icon: "folder.fill",
                                title: "Offer Files export when finished",
                                isOn: Binding(
                                    get: { state.saveToFilesAfterExport },
                                    set: { state.saveToFilesAfterExport = $0 }
                                )
                            )
                        }

                        NativePanel {
                            VStack(spacing: 0) {
                                HStack(spacing: 13) {
                                    ClarityIconTile(icon: "externaldrive.fill", size: 40, iconSize: 16)

                                    Text("Free storage")
                                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)

                                    Spacer()

                                    Text(freeStorageText)
                                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.cyan.opacity(0.82))
                                }
                                .padding(.vertical, 10)

                                divider

                                Button {
                                    state.clearProcessingCache()
                                } label: {
                                    HStack(spacing: 13) {
                                        ClarityIconTile(icon: "trash.fill", size: 40, iconSize: 16, destructive: true)
                                        Text("Clear processing cache")
                                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.red)
                                        Spacer()
                                    }
                                    .padding(.vertical, 10)
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

    private func actionRow(icon: String, title: String, showsChevron: Bool = false) -> some View {
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

    private func choiceBlock(
        icon: String,
        title: String,
        options: [String],
        selected: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ClarityIconTile(icon: icon, size: 40, iconSize: 16)
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            onSelect(option)
                        }
                    } label: {
                        Text(option)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                option == selected
                                    ? AnyShapeStyle(ClarityNativeTheme.brand)
                                    : AnyShapeStyle(Color.black.opacity(0.22)),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        option == selected ? Color.cyan.opacity(0.46) : Color.white.opacity(0.06),
                                        lineWidth: 0.8
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .padding(.vertical, 10)
    }

    private func brandedSlider(
        icon: String,
        title: String,
        value: Binding<Double>,
        enabled: Bool = true
    ) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                ClarityIconTile(icon: icon, size: 40, iconSize: 16)

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(enabled ? .white : .white.opacity(0.38))

                Spacer()

                Text("\(Int((value.wrappedValue * 100).rounded()))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(enabled ? .cyan.opacity(0.86) : .white.opacity(0.28))
                    .frame(minWidth: 28, alignment: .trailing)
            }

            GeometryReader { geometry in
                let width = max(1, geometry.size.width)
                let clamped = max(0, min(1, value.wrappedValue))
                let knobX = max(10, min(width - 10, width * clamped))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.075))
                        .frame(height: 5)

                    Capsule()
                        .fill(ClarityNativeTheme.brand)
                        .frame(width: max(5, width * clamped), height: 5)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.cyan.opacity(0.42), lineWidth: 0.8))
                        .shadow(color: Color.cyan.opacity(0.30), radius: 6)
                        .position(x: knobX, y: 13)
                }
                .frame(height: 26)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard enabled else { return }
                            value.wrappedValue = max(0, min(1, drag.location.x / width))
                        }
                )
                .accessibilityElement()
                .accessibilityLabel(title)
                .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
                .accessibilityAdjustableAction { direction in
                    guard enabled else { return }
                    switch direction {
                    case .increment:
                        value.wrappedValue = min(1, value.wrappedValue + 0.05)
                    case .decrement:
                        value.wrappedValue = max(0, value.wrappedValue - 0.05)
                    @unknown default:
                        break
                    }
                }
            }
            .frame(height: 26)
            .opacity(enabled ? 1 : 0.35)
        }
        .padding(.vertical, 10)
    }

    private func brandedToggle(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ClarityIconTile(icon: icon, size: 40, iconSize: 16)

            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isOn.wrappedValue.toggle()
                }
            } label: {
                ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                    Capsule()
                        .fill(
                            isOn.wrappedValue
                                ? AnyShapeStyle(ClarityNativeTheme.brand)
                                : AnyShapeStyle(Color.white.opacity(0.09))
                        )
                        .frame(width: 50, height: 29)
                        .overlay(
                            Capsule()
                                .stroke(
                                    isOn.wrappedValue
                                        ? Color.cyan.opacity(0.40)
                                        : Color.white.opacity(0.08),
                                    lineWidth: 0.8
                                )
                        )

                    Circle()
                        .fill(Color.white)
                        .frame(width: 23, height: 23)
                        .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                        .padding(3)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
        }
        .padding(.vertical, 10)
    }

    private var bitrateQualityLabel: String {
        let values = state.configuration.exportBitrateOptionsMbps
        guard let index = values.enumerated().min(by: {
            abs($0.element - state.configuration.bitrateMbps)
                < abs($1.element - state.configuration.bitrateMbps)
        })?.offset else { return "High" }
        return ["Standard", "High", "Maximum"][min(index, 2)]
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.7)
    }

    private var freeStorageText: String {
        guard let bytes = try? StorageEstimator.availableBytes() else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
