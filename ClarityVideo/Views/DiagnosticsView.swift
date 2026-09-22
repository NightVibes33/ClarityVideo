import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var isRunning = false

    private let grid = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack {
            ClarityNativeTheme.background.ignoresSafeArea()
            RadialGradient(
                colors: [Color.blue.opacity(0.20), Color.cyan.opacity(0.035), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 440
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    NativeHeader(title: "Tools", onBack: { dismiss() })
                        .padding(.horizontal, 2)

                    engineHero

                    LazyVGrid(columns: grid, spacing: 10) {
                        capabilityTile(
                            icon: "sparkles.tv.fill",
                            title: "Apple SR",
                            value: state.capabilities.fullSuperResolutionAvailable ? "Ready" : "Unavailable",
                            available: state.capabilities.fullSuperResolutionAvailable
                        )
                        capabilityTile(
                            icon: "4k.tv.fill",
                            title: "4K Encode",
                            value: state.capabilities.supports4KHEVCEncode ? "Passed" : "Unavailable",
                            available: state.capabilities.supports4KHEVCEncode
                        )
                        capabilityTile(
                            icon: "8.circle.fill",
                            title: "8K Encode",
                            value: state.capabilities.supports8KHEVCEncode ? "Passed" : "Unavailable",
                            available: state.capabilities.supports8KHEVCEncode
                        )
                        capabilityTile(
                            icon: "brain.head.profile",
                            title: "DLSS 5",
                            value: IOSNeuralHeadService.bundledModelURL() == nil ? "Not bundled" : "Bundled",
                            available: IOSNeuralHeadService.bundledModelURL() != nil
                        )
                    }

                    diagnosticSection("ENGINE DETAILS") {
                        DiagnosticRow("Device", state.capabilities.deviceModel)
                        DiagnosticRow("iOS", state.capabilities.osVersion)
                        DiagnosticRow("Low-latency SR", availability(state.capabilities.lowLatencySuperResolutionAvailable))
                        DiagnosticRow("Temporal denoise", availability(state.capabilities.temporalNoiseFilteringAvailable))
                        DiagnosticRow("Main10", state.capabilities.supportsMain10 ? "Passed" : "Unavailable")
                        DiagnosticRow("Apple model", state.capabilities.modelReadiness.rawValue)
                        DiagnosticRow(
                            "Maximum output",
                            state.capabilities.maximumSafeOutputSize.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "Unknown"
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("REAL DEVICE TESTS")
                        NativePanel {
                            VStack(spacing: 0) {
                                diagnosticButton(
                                    icon: "gauge.with.dots.needle.50percent",
                                    title: isRunning ? "Running capability probes…" : "Refresh device capabilities",
                                    subtitle: "Re-check Apple SR and hardware encode support",
                                    enabled: !isRunning
                                ) {
                                    isRunning = true
                                    Task {
                                        await state.refreshCapabilities()
                                        isRunning = false
                                    }
                                }

                                rowDivider

                                diagnosticButton(
                                    icon: "sparkles.tv.fill",
                                    title: state.isPreparingModel ? "Running Apple SR test…" : "Apple SR one-frame test",
                                    subtitle: "Runs the actual on-device frame processor",
                                    enabled: !state.isPreparingModel && state.capabilities.fullSuperResolutionAvailable
                                ) {
                                    Task { await state.prepareModelAndRunSelfTest() }
                                }

                                rowDivider

                                diagnosticButton(
                                    icon: "brain.head.profile",
                                    title: state.isPreparingModel ? "Running DLSS 5 test…" : "DLSS 5 neural-head test",
                                    subtitle: "Executes the bundled neural model on this iPhone",
                                    enabled: !state.isPreparingModel && IOSNeuralHeadService.bundledModelURL() != nil
                                ) {
                                    Task { await state.runRecoveredNeuralHeadSelfTest() }
                                }

                                rowDivider

                                diagnosticButton(
                                    icon: "4k.tv.fill",
                                    title: state.isRunningFiveSecondTest ? "Running 4K export…" : "Five-second 4K export",
                                    subtitle: state.importedURL == nil ? "Import a video first" : "Processes a real five-second source clip",
                                    enabled: !state.isRunningFiveSecondTest && state.importedURL != nil && state.capabilities.fullSuperResolutionAvailable
                                ) {
                                    state.runFiveSecondDiagnostic()
                                }

                                if state.capabilities.supports8KHEVCEncode {
                                    rowDivider
                                    diagnosticButton(
                                        icon: "8.circle.fill",
                                        title: "Five-second 8K export",
                                        subtitle: state.importedURL == nil ? "Import a video first" : "Validates the complete 8K pipeline",
                                        enabled: !state.isRunningFiveSecondTest && state.importedURL != nil
                                    ) {
                                        state.runFiveSecondDiagnostic(resolution: .uhd8K)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }

                    if state.diagnosticStatus != "Not run" {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("LAST RESULT")
                            NativePanel {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: state.diagnosticStatus.localizedCaseInsensitiveContains("fail") ? "xmark.octagon.fill" : "checkmark.circle.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(state.diagnosticStatus.localizedCaseInsensitiveContains("fail") ? Color.red : Color.cyan)
                                    Text(state.diagnosticStatus)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.76))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .padding(15)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("MAINTENANCE")
                        NativePanel {
                            VStack(spacing: 0) {
                                diagnosticButton(
                                    icon: "trash.fill",
                                    title: "Clear processing cache",
                                    subtitle: "Removes checkpoints and temporary preview data",
                                    destructive: true
                                ) {
                                    state.clearProcessingCache()
                                }
                                rowDivider
                                diagnosticButton(
                                    icon: "doc.badge.gearshape.fill",
                                    title: "Prepare diagnostic JSON",
                                    subtitle: "Exports capability and pipeline details"
                                ) {
                                    exportReport()
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }

                    outputLinks

                    Text("All tests above run against the real device APIs. Simulator and CI results are not presented as device capability results.")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineSpacing(3)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 10)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .task { await state.refreshCapabilities() }
    }

    private var engineHero: some View {
        NativePanel {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(ClarityNativeTheme.card)
                        .frame(width: 64, height: 64)
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(.cyan)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text("VIDEO ENGINE")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .tracking(1.35)
                            .foregroundStyle(.white.opacity(0.42))
                        Circle()
                            .fill(engineReady ? Color.cyan : Color.orange)
                            .frame(width: 6, height: 6)
                    }
                    Text(engineReady ? "Ready on this iPhone" : "Needs attention")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(engineSummary)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(ClarityNativeTheme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(15)
        }
    }

    private var engineReady: Bool {
        state.capabilities.fullSuperResolutionAvailable && state.capabilities.supports4KHEVCEncode
    }

    private var engineSummary: String {
        if engineReady {
            return state.capabilities.supports8KHEVCEncode
                ? "Apple SR, 4K and 8K hardware export paths are available."
                : "Apple SR and 4K hardware export are available."
        }
        return "Run capability probes to verify the available enhancement path."
    }

    private func capabilityTile(icon: String, title: String, value: String, available: Bool) -> some View {
        NativePanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(available ? Color.cyan : Color.white.opacity(0.34))
                    Spacer()
                    Image(systemName: available ? "checkmark.circle.fill" : "minus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(available ? Color.cyan.opacity(0.78) : Color.white.opacity(0.24))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(available ? Color.cyan.opacity(0.72) : Color.white.opacity(0.38))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
        }
    }

    @ViewBuilder
    private func diagnosticSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title)
            NativePanel {
                VStack(spacing: 0) {
                    content()
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.40))
            .padding(.leading, 3)
    }

    private func diagnosticButton(
        icon: String,
        title: String,
        subtitle: String,
        enabled: Bool = true,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((destructive ? Color.red : Color.cyan).opacity(0.10))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(destructive ? Color.red : Color.cyan)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(enabled ? (destructive ? Color.red : Color.white) : Color.white.opacity(0.32))
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(enabled ? 0.44 : 0.22))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(enabled ? 0.28 : 0.12))
            }
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    @ViewBuilder
    private var outputLinks: some View {
        if state.diagnosticStillURL != nil || state.diagnosticTestOutputURL != nil || exportURL != nil {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("OUTPUTS")
                if let still = state.diagnosticStillURL {
                    ShareLink(item: still) { shareRow("Enhanced test still", icon: "photo.fill") }
                }
                if let output = state.diagnosticTestOutputURL {
                    ShareLink(item: output) { shareRow("Five-second test video", icon: "square.and.arrow.up") }
                }
                if let exportURL {
                    ShareLink(item: exportURL) { shareRow("Diagnostic JSON", icon: "doc.fill") }
                }
            }
        }
    }

    private func shareRow(_ title: String, icon: String) -> some View {
        NativePanel {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.cyan)
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.30))
            }
            .foregroundStyle(.white)
            .padding(14)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.7)
            .padding(.leading, 50)
    }

    private func availability(_ value: Bool) -> String { value ? "Available" : "Unavailable" }

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
            enhancedStillCreated: state.diagnosticStillURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
            diagnosticVideoCreated: state.diagnosticTestOutputURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
            activeJobStatus: state.activeJob?.status.rawValue,
            activeJobError: state.activeJob?.errorMessage,
            activeJobDenoiseMethod: state.activeJob?.denoiseMethod,
            processingFPS: state.activeJob.flatMap { job in
                job.processingDuration.map { Double(job.processedFrames) / max(0.1, $0) }
            }
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ClarityVideo-Diagnostics.json")
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
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.cyan.opacity(0.70))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.055))
                .frame(height: 0.6)
        }
    }
}
