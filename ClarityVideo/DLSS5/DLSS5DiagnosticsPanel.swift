import SwiftUI

struct DLSS5DiagnosticsPanel: View {
    let sourceURL: URL?
    let requestedSeconds: Double

    @State private var isCapturing = false
    @State private var captureURL: URL?
    @State private var status = "No reference frame captured yet."

    var body: some View {
        Section("DLSS 5 Port") {
            let runtime = DLSS5RuntimeProbe.current
            DiagnosticRow("Runtime", runtime.available ? "Available" : "Not linked")
            DiagnosticRow("Execution backend", runtime.executionBackend)
            DiagnosticRow("Color contract", "RGBA16F linear")
            DiagnosticRow("Depth contract", "R32F reversed-Z")
            DiagnosticRow("Motion contract", "RG16F pixels")
            DiagnosticRow("Video history", "Reset each frame")
            DiagnosticRow("Video motion", "Zero vectors")

            if let reason = runtime.reason, !runtime.available {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                guard let sourceURL else { return }
                isCapturing = true
                status = "Preparing linear color, depth and motion planes..."
                Task { @MainActor in
                    defer { isCapturing = false }
                    do {
                        let result = try await DLSS5ReferenceCaptureCoordinator().captureVideoFrame(
                            sourceURL: sourceURL,
                            requestedSeconds: requestedSeconds
                        )
                        captureURL = result.packageURL
                        status = "Captured \(result.width)x\(result.height) feeder frame at "
                            + String(format: "%.3f s", result.frameTimestampSeconds)
                            + ". Packet self-validation passed."
                    } catch {
                        status = "DLSS 5 feeder capture failed: \(error.localizedDescription)"
                    }
                }
            } label: {
                Label(
                    isCapturing ? "Building DLSS 5 reference packet..." : "Build DLSS 5 reference packet",
                    systemImage: "shippingbox.and.arrow.backward"
                )
            }
            .disabled(isCapturing || sourceURL == nil)

            if sourceURL == nil {
                Text("Import a video first to capture its DLSS 5 feeder resources.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let captureURL {
                ShareLink(item: captureURL) {
                    Label("Export .cvdlss5 reference packet", systemImage: "square.and.arrow.up")
                }
            }
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
