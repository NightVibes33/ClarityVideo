import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var isRunning = false
    @State private var showClearCacheConfirmation = ProcessInfo.processInfo.environment["CLARITY_UI_ROUTE"] == "diagnostics-confirm"
    @State private var showsCompactHeader = false

    var body: some View {
        ZStack {
            ClarityScreenBackdrop()

            ScrollViewReader { diagnosticsProxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                    NativeHeader(title: "Diagnostics", circularBack: true, onBack: { dismiss() })

                    hero

                    NativePanel {
                        VStack(spacing: 0) {
                            DiagnosticRow("App", appIdentity)
                            DiagnosticRow("Source", sourceIdentity)
                            DiagnosticRow("OS", state.capabilities.osVersion)
                            DiagnosticRow("Device", state.capabilities.deviceModel)
                            DiagnosticRow("Apple SR API", availability(state.capabilities.fullSuperResolutionAvailable))
                            DiagnosticRow("Low-latency SR", availability(state.capabilities.lowLatencySuperResolutionAvailable))
                            DiagnosticRow("Temporal denoise", availability(state.capabilities.temporalNoiseFilteringAvailable))
                            DiagnosticRow("4K encoder", state.capabilities.supports4KHEVCEncode ? "Passed" : "Unavailable")
                            DiagnosticRow("8K encoder", state.capabilities.supports8KHEVCEncode ? "Passed" : "Unavailable")
                            DiagnosticRow("Main10", state.capabilities.supportsMain10 ? "Passed" : "Unavailable")
                            DiagnosticRow("Model state", state.capabilities.modelReadiness.rawValue)
                        }
                        .padding(.horizontal, 13)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Actions")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Run diagnostic tests to verify capabilities and performance.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(ClarityNativeTheme.muted)

                        NativePanel {
                            VStack(spacing: 0) {
                                actionButton(
                                    icon: "gauge.with.dots.needle.50percent",
                                    title: isRunning ? "Running capability probes…" : "Run capability probes",
                                    subtitle: "Check hardware and software capabilities",
                                    enabled: !isRunning
                                ) {
                                    isRunning = true
                                    Task {
                                        await state.refreshCapabilities()
                                        isRunning = false
                                    }
                                }

                                divider

                                actionButton(
                                    icon: "sparkles.tv.fill",
                                    title: state.isPreparingModel ? "Running Apple SR test…" : "Run Apple SR one-frame test",
                                    subtitle: "Validate Apple Super Resolution",
                                    enabled: !state.isPreparingModel && state.capabilities.fullSuperResolutionAvailable
                                ) {
                                    Task { await state.prepareModelAndRunSelfTest() }
                                }

                                divider

                                actionButton(
                                    icon: "brain.head.profile",
                                    title: state.isPreparingModel ? "Running DLSS 5 test…" : "Run DLSS 5 device test",
                                    subtitle: "Validate the experimental neural upscaler",
                                    enabled: !state.isPreparingModel && neuralDeviceTestAvailable
                                ) {
                                    Task { await state.runRecoveredNeuralHeadSelfTest() }
                                }

                                divider

                                actionButton(
                                    icon: nil,
                                    badgeText: "4K",
                                    title: state.isRunningFiveSecondTest ? "Running 4K test…" : "Run five-second 4K test",
                                    subtitle: state.importedURL == nil ? "Import a video first" : "Encode a real 5-second 4K sample",
                                    enabled: !state.isRunningFiveSecondTest
                                        && state.importedURL != nil
                                        && state.capabilities.fullSuperResolutionAvailable
                                ) {
                                    state.runFiveSecondDiagnostic()
                                }

                                divider

                                actionButton(
                                    icon: nil,
                                    badgeText: "8K",
                                    title: "Run five-second 8K test",
                                    subtitle: state.importedURL == nil ? "Import a video first" : "Encode a real 5-second 8K sample",
                                    enabled: !state.isRunningFiveSecondTest
                                        && state.importedURL != nil
                                        && state.capabilities.supports8KHEVCEncode
                                ) {
                                    state.runFiveSecondDiagnostic(resolution: .uhd8K)
                                }

                                divider

                                actionButton(
                                    icon: "trash.fill",
                                    title: "Clear processing cache",
                                    subtitle: "Remove temporary files and cached data",
                                    destructive: true
                                ) {
                                    showClearCacheConfirmation = true
                                }

                                divider

                                actionButton(
                                    icon: "doc.badge.gearshape.fill",
                                    title: "Prepare diagnostic JSON",
                                    subtitle: "Generate a diagnostic report"
                                ) {
                                    exportReport()
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .id("diagnostics-actions")

                    if state.diagnosticStatus != "Not run" {
                        NativePanel {
                            HStack(alignment: .top, spacing: 12) {
                                Image(
                                    systemName: state.diagnosticStatus.localizedCaseInsensitiveContains("fail")
                                        ? "xmark.octagon.fill"
                                        : "checkmark.circle.fill"
                                )
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(
                                    state.diagnosticStatus.localizedCaseInsensitiveContains("fail")
                                        ? Color.red
                                        : Color.cyan
                                )

                                Text(state.diagnosticStatus)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 0)
                            }
                            .padding(15)
                        }
                    }

                    if let still = state.diagnosticStillURL {
                        ShareLink(item: still) {
                            shareRow("Enhanced test still", icon: "photo.fill")
                        }
                    }

                    if let output = state.diagnosticTestOutputURL {
                        ShareLink(item: output) {
                            shareRow("Five-second test video", icon: "square.and.arrow.up")
                        }
                    }

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            shareRow("Diagnostic JSON", icon: "doc.fill")
                        }
                    }

                    Text("Device tests above run against the real on-device APIs. Simulator and CI results are not presented as device capability results.")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                        .lineSpacing(3)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 10)
                }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 88
                } action: { _, scrolled in
                    withAnimation(.easeOut(duration: 0.16)) {
                        showsCompactHeader = scrolled
                    }
                }
                .task {
#if targetEnvironment(simulator)
                    if ProcessInfo.processInfo.environment["CLARITY_UI_ROUTE"] == "diagnostics-actions" {
                        try? await Task.sleep(for: .milliseconds(250))
                        withAnimation(.none) {
                            diagnosticsProxy.scrollTo("diagnostics-actions", anchor: .top)
                        }
                    }
#endif
                }
            }
        }
        .overlay(alignment: .top) {
            if showsCompactHeader {
                NativeHeader(
                    title: "Diagnostics",
                    circularBack: true,
                    onBack: { dismiss() }
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    Rectangle()
                        .fill(ClarityNativeTheme.background.opacity(0.90))
                        .background(.ultraThinMaterial)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.cyan.opacity(0.10))
                                .frame(height: 0.7)
                        }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                .zIndex(20)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .overlay {
            if showClearCacheConfirmation {
                ZStack {
                    Color.black.opacity(0.62)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.16)) {
                                showClearCacheConfirmation = false
                            }
                        }

                    ClarityConfirmationCard(
                        icon: "trash.fill",
                        title: "Clear processing cache?",
                        message: "This removes previews, checkpoints, and other disposable processing files. Completed exports are not deleted.",
                        destructiveTitle: "Clear Cache",
                        cancelTitle: "Cancel",
                        destructiveAction: {
                            state.clearProcessingCache()
                            withAnimation(.easeOut(duration: 0.16)) {
                                showClearCacheConfirmation = false
                            }
                        },
                        cancelAction: {
                            withAnimation(.easeOut(duration: 0.16)) {
                                showClearCacheConfirmation = false
                            }
                        }
                    )
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
                .zIndex(100)
            }
        }
        .task {
#if targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["CLARITY_UI_SNAPSHOT"] != "1" {
                await state.refreshCapabilities()
            }
#else
            await state.refreshCapabilities()
#endif
        }
    }

    private var neuralDeviceTestAvailable: Bool {
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["CLARITY_UI_SNAPSHOT"] == "1" {
            return true
        }
#endif
        return IOSNeuralHeadService.bundledModelURL() != nil
    }

    private var hero: some View {
        HStack(spacing: 12) {
            ClarityIconTile(icon: "waveform.path.ecg", size: 56, iconSize: 25)

            VStack(alignment: .leading, spacing: 5) {
                Text("Video Engine Diagnostics")
                    .font(.system(size: 21.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Hardware.  Performance.  Clarity.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.56))
            }

            Spacer(minLength: 0)
        }
    }

    private func actionButton(
        icon: String?,
        badgeText: String? = nil,
        title: String,
        subtitle: String,
        enabled: Bool = true,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                diagnosticActionTile(
                    icon: icon,
                    badgeText: badgeText,
                    destructive: destructive
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            enabled
                                ? (destructive ? Color.red : Color.white)
                                : Color.white.opacity(0.34)
                        )

                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(enabled ? 0.52 : 0.25))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(enabled ? 0.34 : 0.14))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    @ViewBuilder
    private func diagnosticActionTile(
        icon: String?,
        badgeText: String?,
        destructive: Bool
    ) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                destructive
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.red.opacity(0.72), Color.pink.opacity(0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.03, green: 0.43, blue: 0.95),
                                Color(red: 0.24, green: 0.18, blue: 0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .frame(width: 46, height: 46)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        destructive ? Color.red.opacity(0.42) : Color.cyan.opacity(0.38),
                        lineWidth: 0.8
                    )
            )
            .overlay {
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.white, Color.cyan.opacity(0.82)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(destructive ? Color.white : Color(red: 0.66, green: 0.92, blue: 1.0))
                }
            }
            .shadow(
                color: destructive ? Color.red.opacity(0.16) : Color.blue.opacity(0.22),
                radius: 8
            )
    }

    private func shareRow(_ title: String, icon: String) -> some View {
        NativePanel {
            HStack(spacing: 12) {
                ClarityIconTile(icon: icon, size: 40, iconSize: 16)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.34))
            }
            .foregroundStyle(.white)
            .padding(13)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.7)
            .padding(.leading, 48)
    }

    private func availability(_ value: Bool) -> String {
        value ? "Available" : "Unavailable"
    }

    private var appIdentity: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return version + " (" + build + ")"
    }

    private var sourceIdentity: String {
        state.assetInfo?.fileName ?? "—"
    }

    private func exportReport() {
        let report = DiagnosticReport(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            sourceRevision: Bundle.main.object(forInfoDictionaryKey: "ClaritySourceRevision") as? String ?? "development",
            capabilities: state.capabilities,
            configurationAttempts: ["4K HEVC hardware session", "8K HEVC hardware session", "Main10 profile"],
            exactErrors: [state.capabilities.lastProbeError, state.lastImportError].compactMap { $0 },
            processorRevision: state.capabilities.defaultProcessorRevision.map(String.init),
            modelStatus: state.capabilities.modelReadiness.rawValue,
            encoderResults: [
                "4K": state.capabilities.supports4KHEVCEncode,
                "8K": state.capabilities.supports8KHEVCEncode,
                "Main10": state.capabilities.supportsMain10
            ],
            peakMemoryBytes: ProcessMemory.peakResidentBytes(),
            thermalTransitions: state.thermalTransitions,
            diagnosticStatus: state.diagnosticStatus,
            lastSuccessfulSelfTest: state.lastSuccessfulSelfTest,
            lastImportedSummary: state.lastImportedSummary,
            enhancedStillCreated: state.diagnosticStillURL.map {
                FileManager.default.fileExists(atPath: $0.path)
            } ?? false,
            diagnosticVideoCreated: state.diagnosticTestOutputURL.map {
                FileManager.default.fileExists(atPath: $0.path)
            } ?? false,
            activeJobStatus: state.activeJob?.status.rawValue,
            activeJobError: state.activeJob?.errorMessage,
            activeJobDenoiseMethod: state.activeJob?.denoiseMethod,
            processingFPS: state.activeJob.flatMap { job in
                job.processingDuration.map {
                    Double(job.processedFrames) / max(0.1, $0)
                }
            }
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClarityVideo-Diagnostics.json")
            try encoder.encode(report).write(to: url, options: .atomic)
            exportURL = url
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}

struct DiagnosticRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.6)
        }
    }
}
