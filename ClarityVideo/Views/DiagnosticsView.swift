import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Environment(AppState.self) private var state
    @State private var exportURL: URL?
    @State private var isRunning = false
    var body: some View {
        List {
            Section("Video Engine Diagnostics") {
                DiagnosticRow("OS", state.capabilities.osVersion)
                DiagnosticRow("Device", state.capabilities.deviceModel)
                DiagnosticRow("Full SR API", yesNo(state.capabilities.fullSuperResolutionAvailable))
                DiagnosticRow("Low-latency SR", yesNo(state.capabilities.lowLatencySuperResolutionAvailable))
                DiagnosticRow("Temporal denoise", yesNo(state.capabilities.temporalNoiseFilteringAvailable))
                DiagnosticRow("4K encoder", passFail(state.capabilities.supports4KHEVCEncode))
                DiagnosticRow("8K encoder", passFail(state.capabilities.supports8KHEVCEncode))
                DiagnosticRow("Main10", passFail(state.capabilities.supportsMain10))
                DiagnosticRow("Model state", state.capabilities.modelReadiness.rawValue)
                DiagnosticRow("Model progress", String(Int(state.capabilities.modelDownloadProgress * 100)) + "%")
                DiagnosticRow("Full scales", state.capabilities.supportedFullScaleFactors.map(String.init).joined(separator: ", "))
                DiagnosticRow("720p low-latency scales", state.capabilities.supportedLowLatencyScaleFactors.map { String($0) }.joined(separator: ", "))
                DiagnosticRow("Revisions", state.capabilities.supportedProcessorRevisions.map(String.init).joined(separator: ", "))
                DiagnosticRow("Source pixel formats", state.capabilities.sourcePixelFormats.map { String(format: "0x%08X", $0) }.joined(separator: ", "))
                DiagnosticRow("Destination formats", state.capabilities.destinationPixelFormats.map { String(format: "0x%08X", $0) }.joined(separator: ", "))
                DiagnosticRow("Maximum tested input", state.capabilities.maximumSafeInputSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "Unknown")
                DiagnosticRow("Maximum encoder output", state.capabilities.maximumSafeOutputSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "Unknown")
            }
            Section("Actions") {
                Button {
                    isRunning = true
                    Task { await state.refreshCapabilities(); isRunning = false }
                } label: { Label(isRunning ? "Running probes..." : "Run capability probes", systemImage: "gauge.with.dots.needle.50percent") }
                    .disabled(isRunning)
                Button { Task { await state.prepareModelAndRunSelfTest() } } label: {
                    Label(state.isPreparingModel ? "Preparing and testing..." : "Prepare model and run one-frame AI test", systemImage: "sparkles.tv")
                }.disabled(state.isPreparingModel || !state.capabilities.fullSuperResolutionAvailable)
                Text(state.diagnosticStatus).font(.footnote).foregroundStyle(.secondary)
                Button(role: .destructive) { state.clearProcessingCache() } label: { Label("Clear processing cache", systemImage: "trash") }
                Button { exportReport() } label: { Label("Prepare diagnostic JSON", systemImage: "doc.badge.gearshape") }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Export diagnostic JSON", systemImage: "square.and.arrow.up") }
                }
            }
            Section("What this proves") {
                Text("Encoder probes create and prepare hardware-required VideoToolbox sessions at the requested dimensions. Frame-processor and model tests must run on a physical iOS 26 device; simulator and CI results are never presented as device proof.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Diagnostics")
        .task { await state.refreshCapabilities() }
    }

    private func yesNo(_ value: Bool) -> String { value ? "Available" : "Unavailable" }
    private func passFail(_ value: Bool) -> String { value ? "Passed" : "Failed" }
    private func exportReport() {
        let report = DiagnosticReport(
            capabilities: state.capabilities,
            configurationAttempts: ["4K HEVC hardware session", "8K HEVC hardware session", "Main10 profile"],
            exactErrors: state.capabilities.lastProbeError.map { [$0] } ?? [],
            processorRevision: state.capabilities.defaultProcessorRevision.map(String.init),
            modelStatus: state.capabilities.modelReadiness.rawValue,
            encoderResults: ["4K": state.capabilities.supports4KHEVCEncode, "8K": state.capabilities.supports8KHEVCEncode, "Main10": state.capabilities.supportsMain10],
            peakMemoryBytes: 0,
            thermalTransitions: [],
            processingFPS: nil
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
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View { LabeledContent(label, value: value) }
}
