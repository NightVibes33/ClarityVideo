import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var isRunning = false

    var body: some View {
        ZStack {
            ClarityNativeTheme.background.ignoresSafeArea()
            LinearGradient(
                colors: [Color.blue.opacity(0.055), .clear, Color.purple.opacity(0.03)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    NativeHeader(title: "Diagnostics", onBack: { dismiss() })

                    diagnosticSection("DEVICE & ENGINE") {
                        DiagnosticRow("App", appIdentity)
                        DiagnosticRow("Source", sourceIdentity)
                        DiagnosticRow("OS", state.capabilities.osVersion)
                        DiagnosticRow("Device", state.capabilities.deviceModel)
                        DiagnosticRow("Apple SR", yesNo(state.capabilities.fullSuperResolutionAvailable))
                        DiagnosticRow("Low-latency SR", yesNo(state.capabilities.lowLatencySuperResolutionAvailable))
                        DiagnosticRow("Temporal denoise", yesNo(state.capabilities.temporalNoiseFilteringAvailable))
                        DiagnosticRow("4K encoder", passFail(state.capabilities.supports4KHEVCEncode))
                        DiagnosticRow("8K encoder", passFail(state.capabilities.supports8KHEVCEncode))
                        DiagnosticRow("Main10", passFail(state.capabilities.supportsMain10))
                    }

                    diagnosticSection("MODEL") {
                        DiagnosticRow("Apple model", state.capabilities.modelReadiness.rawValue)
                        DiagnosticRow("DLSS 5 model", IOSNeuralHeadService.bundledModelURL() == nil ? "Missing" : "Bundled")
                        DiagnosticRow("Last self-test", state.lastSuccessfulSelfTest?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                        DiagnosticRow("Maximum tile", "960 × 540")
                        DiagnosticRow(
                            "Maximum output",
                            state.capabilities.maximumSafeOutputSize.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "Unknown"
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("ACTIONS")
                        NativePanel {
                            VStack(spacing: 0) {
                                diagnosticButton(
                                    icon: "gauge.with.dots.needle.50percent",
                                    title: isRunning ? "Running capability probes…" : "Run capability probes",
                                    enabled: !isRunning
                                ) {
                                    isRunning = true
                                    Task { await state.refreshCapabilities(); isRunning = false }
                                }

                                rowDivider
                                diagnosticButton(
                                    icon: "sparkles.tv.fill",
                                    title: state.isPreparingModel ? "Preparing Apple model…" : "Run Apple SR one-frame test",
                                    enabled: !state.isPreparingModel && state.capabilities.fullSuperResolutionAvailable
                                ) {
                                    Task { await state.prepareModelAndRunSelfTest() }
                                }

                                rowDivider
                                diagnosticButton(
                                    icon: "brain.head.profile",
                                    title: state.isPreparingModel ? "Running DLSS 5 test…" : "Run DLSS 5 device test",
                                    enabled: !state.isPreparingModel && IOSNeuralHeadService.bundledModelURL() != nil
                                ) {
                                    Task { await state.runRecoveredNeuralHeadSelfTest() }
                                }

                                rowDivider
                                diagnosticButton(
                                    icon: "4k.tv.fill",
                                    title: state.isRunningFiveSecondTest ? "Running 4K test…" : "Run five-second 4K test",
                                    enabled: !state.isRunningFiveSecondTest && state.importedURL != nil && state.capabilities.fullSuperResolutionAvailable
                                ) {
                                    state.runFiveSecondDiagnostic()
                                }

                                if state.capabilities.supports8KHEVCEncode {
                                    rowDivider
                                    diagnosticButton(
                                        icon: "8.circle.fill",
                                        title: "Run five-second 8K test",
                                        enabled: !state.isRunningFiveSecondTest && state.importedURL != nil
                                    ) {
                                        state.runFiveSecondDiagnostic(resolution: .uhd8K)
                                    }
                                }

                                rowDivider
                                diagnosticButton(icon: "trash.fill", title: "Clear processing cache", destructive: true) {
                                    state.clearProcessingCache()
                                }

                                rowDivider
                                diagnosticButton(icon: "doc.badge.gearshape.fill", title: "Prepare diagnostic JSON") {
                                    exportReport()
                                }
                            }
                            .padding(.horizontal, 14)
                        }

                        if state.importedURL == nil {
                            Text("Import a video first to enable the 4K/8K video tests.")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(ClarityNativeTheme.muted)
                                .padding(.horizontal, 3)
                        }

                        if state.diagnosticStatus != "Not run" {
                            Text(state.diagnosticStatus)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(ClarityNativeTheme.muted)
                                .padding(.horizontal, 3)
                        }
                    }

                    if let still = state.diagnosticStillURL {
                        ShareLink(item: still) {
                            shareRow("Export enhanced test still", icon: "photo.fill")
                        }
                    }
                    if let output = state.diagnosticTestOutputURL {
                        ShareLink(item: output) {
                            shareRow("Export five-second test video", icon: "square.and.arrow.up")
                        }
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            shareRow("Export diagnostic JSON", icon: "doc.fill")
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("WHAT THIS PROVES")
                        NativePanel {
                            Text("Encoder checks use hardware VideoToolbox sessions. Apple SR and DLSS 5 inference tests are labeled separately, and device-only results are never inferred from simulator or CI runs.")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.60))
                                .lineSpacing(4)
                                .padding(15)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .task { await state.refreshCapabilities() }
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
        enabled: Bool = true,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(destructive ? .red : .cyan)
                    .frame(width: 30)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(enabled ? (destructive ? Color.red : Color.white) : Color.white.opacity(0.32))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(enabled ? 0.28 : 0.12))
            }
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func shareRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.cyan)
            Text(title)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.30))
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(ClarityNativeTheme.panel)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(ClarityNativeTheme.stroke, lineWidth: 0.8))
        )
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.7)
            .padding(.leading, 42)
    }

    private var appIdentity: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return version + " (" + build + ")"
    }

    private var sourceIdentity: String {
        let revision = Bundle.main.object(forInfoDictionaryKey: "ClaritySourceRevision") as? String ?? "development"
        return String(revision.prefix(12))
    }

    private func yesNo(_ value: Bool) -> String { value ? "Available" : "Unavailable" }
    private func passFail(_ value: Bool) -> String { value ? "Passed" : "Failed" }

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
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.50))
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
