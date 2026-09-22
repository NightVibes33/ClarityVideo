import SwiftUI
import AVKit
import Combine
import UIKit

struct EditorView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        ZStack {
            Color(red: 0.015, green: 0.025, blue: 0.045).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    previewCard
                    if let info = state.assetInfo { compactSourceInfo(info) }
                    enhancementCard
                    fineTuneCard
                    exportCard
                    actionBar
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 34)
            }
        }
        .preferredColorScheme(.dark)
        .tint(.cyan)
        .sheet(item: $state.comparisonPreview) { preview in
            NavigationStack {
                ZStack {
                    Color(red: 0.015, green: 0.025, blue: 0.045).ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: 16) {
                            ComparisonPlaybackView(beforeURL: preview.sourceURL, afterURL: preview.enhancedURL)
                            VStack(spacing: 10) {
                                LabeledContent("Selected range", value: "\(durationLabel(preview.selectedStartSeconds)) · \(Int(preview.selectedDurationSeconds.rounded())) sec")
                                LabeledContent("Preview processing", value: String(format: "%.1f sec", preview.previewProcessingDuration))
                                LabeledContent("Estimated full export", value: String(format: "%.1f min", preview.estimatedFullDuration / 60))
                                LabeledContent("Estimated output", value: ByteCountFormatter.string(fromByteCount: preview.estimatedOutputBytes, countStyle: .file))
                            }
                            .padding(16)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
                        }.padding()
                    }
                }
                .navigationTitle("Before / After")
                .navigationBarTitleDisplayMode(.inline)
            }
            .preferredColorScheme(.dark)
        }
        .navigationTitle("Enhance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { state.route = .home } label: { Image(systemName: "chevron.left") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let plan = currentPipelinePlan {
                    Text(String(format: "%.1fx AI", plan.aiScaleFactor))
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                }
            }
        }
    }

    private var previewCard: some View {
        VStack(spacing: 0) {
            if let comparison = state.comparisonPreview {
                ComparisonPlaybackView(beforeURL: comparison.sourceURL, afterURL: comparison.enhancedURL)
                    .frame(height: 260)
            } else if let url = state.importedURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 225)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Text(state.configuration.resolution == .uhd8K ? "8K" : "4K")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.72), in: Capsule())
                            .padding(10)
                    }
            }
        }
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func compactSourceInfo(_ info: VideoAssetInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "film.fill").foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.fileName).font(.subheadline.bold()).lineLimit(1)
                Text("\(info.resolutionText)  ·  \(String(format: "%.0f", info.frameRate)) fps  ·  \(info.codec)")
                    .font(.caption).foregroundStyle(.white.opacity(0.52))
            }
            Spacer()
            Text(info.durationText).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.65))
        }
        .padding(14)
        .background(Color(red: 0.055, green: 0.085, blue: 0.13), in: RoundedRectangle(cornerRadius: 18))
    }

    private var enhancementCard: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 16) {
            Label("Enhancement Settings", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("Target Resolution").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.82))
                Picker("Target resolution", selection: $state.configuration.resolution) {
                    Text("4K").tag(OutputResolution.uhd4K)
                    if state.capabilities.supports8KHEVCEncode { Text("8K").tag(OutputResolution.uhd8K) }
                }
                .pickerStyle(.segmented)
                .onChange(of: state.configuration.resolution) { _, resolution in
                    if resolution == .uhd8K && state.configuration.codec == .h264 { state.configuration.codec = .hevc }
                    if resolution == .uhd8K && state.configuration.bitrateMbps == 55 { state.configuration.bitrateMbps = 160 }
                    if resolution == .uhd4K && state.configuration.bitrateMbps > 110 { state.configuration.bitrateMbps = 65 }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Quality Preset").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.82))
                Picker("Quality preset", selection: $state.configuration.qualityPreset) {
                    ForEach(QualityPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: state.configuration.qualityPreset) { _, preset in
                    state.configuration.applyPreset(
                        preset,
                        temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
                    )
                }
                Text(presetDescription(state.configuration.qualityPreset))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.50))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("AI Upscaler").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.82))
                Picker("AI upscaler", selection: $state.configuration.upscaler) {
                    Text("Apple SR").tag(UpscalerEngine.appleSR)
                    if IOSNeuralHeadService.bundledModelURL() != nil {
                        Text("DLSS 5").tag(UpscalerEngine.dlss5)
                    }
                }
                .pickerStyle(.segmented)
                Text(state.configuration.upscaler == .dlss5
                     ? "Experimental recovered DLSS 5 neural prepass followed by the selected 4K/8K output route."
                     : "Apple Super Resolution provides the neural scaling stage.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 10) {
                Image(systemName: state.capabilities.fullSuperResolutionAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(state.capabilities.fullSuperResolutionAvailable ? .cyan : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Super Resolution").font(.subheadline.bold())
                    Text(currentPipelinePlan?.disclosure ?? "Spatial 4K/8K upscaling is available; Apple AI Super Resolution is unavailable for this source.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.48)).lineLimit(2)
                }
                Spacer()
            }
        }
        .padding(17)
        .background(Color(red: 0.045, green: 0.07, blue: 0.11), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.blue.opacity(0.16), lineWidth: 1))
    }

    private var fineTuneCard: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 17) {
            Text("Fine Tune").font(.headline)
            ClaritySlider(title: "Denoise", value: $state.configuration.denoise)
            ClaritySlider(title: "Detail Recovery", value: $state.configuration.detailRecovery)
            ClaritySlider(title: "Sharpen", value: $state.configuration.sharpening)
            if usesSpatialDenoiseFallback {
                Label("Spatial noise reduction will be used for this source.", systemImage: "info.circle.fill")
                    .font(.caption).foregroundStyle(.white.opacity(0.52))
            }
        }
        .padding(17)
        .background(Color(red: 0.045, green: 0.07, blue: 0.11), in: RoundedRectangle(cornerRadius: 22))
    }

    private var exportCard: some View {
        @Bindable var state = state
        return DisclosureGroup {
            VStack(spacing: 14) {
                Picker("Color", selection: $state.configuration.hdrBehavior) {
                    ForEach(HDRBehavior.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Format", selection: $state.configuration.codec) {
                    ForEach(OutputCodec.allCases.filter { codec in
                        codec == .hevc || (state.configuration.resolution == .uhd4K && state.assetInfo?.isHDR == false)
                    }) { Text($0.rawValue).tag($0) }
                }
                Stepper("Bitrate  ·  \(state.configuration.bitrateMbps) Mbps", value: $state.configuration.bitrateMbps, in: 20...300, step: 5)
                if let info = state.assetInfo {
                    HStack {
                        Text("Estimated output").foregroundStyle(.white.opacity(0.60))
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: StorageEstimator.estimatedOutputBytes(info: info, configuration: state.configuration), countStyle: .file)).bold()
                    }
                }
            }
            .font(.subheadline)
            .padding(.top, 14)
        } label: {
            Label("Export Settings", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
        .padding(17)
        .background(Color(red: 0.045, green: 0.07, blue: 0.11), in: RoundedRectangle(cornerRadius: 22))
    }

    private var actionBar: some View {
        VStack(spacing: 11) {
            Button { state.generateComparisonPreview() } label: {
                HStack {
                    Image(systemName: "rectangle.split.2x1")
                    Text(state.isGeneratingPreview ? "Building Preview  \(Int(state.previewProgress * 100))%" : "Preview Before / After")
                }
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(state.isGeneratingPreview || (!state.capabilities.fullSuperResolutionAvailable && !state.capabilities.lowLatencySuperResolutionAvailable))

            Button { state.route = .exportSetup } label: {
                HStack {
                    Text("Start Export")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Color(red: 0.66, green: 0.36, blue: 1), Color(red: 0.20, green: 0.64, blue: 1), .cyan], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var usesSpatialDenoiseFallback: Bool {
        guard state.configuration.denoise > 0, let info = state.assetInfo,
              let plan = currentPipelinePlan, plan.requiresTiling else { return false }
        return !TemporalNoiseFilterService.supports(
            width: info.encodedWidth, height: info.encodedHeight,
            pixelFormat: kCVPixelFormatType_32BGRA
        )
    }

    private var currentPipelinePlan: PipelinePlan? {
        guard let info = state.assetInfo else { return nil }
        let factors = info.encodedWidth <= 1280 && info.encodedHeight <= 720
            ? state.capabilities.supportedLowLatencyScaleFactors
            : state.capabilities.supportedLowLatency1080pScaleFactors
        return try? PipelinePlanner.plan(
            sourceWidth: info.encodedWidth, sourceHeight: info.encodedHeight,
            target: state.configuration.resolution, qualityPreset: state.configuration.qualityPreset,
            capabilities: state.capabilities, lowLatencyFactorsForSource: factors
        )
    }

    private func presetDescription(_ preset: QualityPreset) -> String {
        switch preset {
        case .balanced: "Faster enhancement with lighter denoise, detail recovery, and sharpening."
        case .quality: "Higher detail recovery and balanced cleanup for most videos."
        case .ultra: "Maximum cleanup, detail recovery, and sharpening independent of the selected upscaler."
        }
    }

    private func durationLabel(_ seconds: Double) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct ClaritySlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline).frame(width: 112, alignment: .leading)
            Slider(value: $value, in: 0...1)
            Text("\(Int((value * 100).rounded()))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 28, alignment: .trailing)
        }
    }
}

struct AnalysisCard: View {
    let info: VideoAssetInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Original").font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow { Label(info.resolutionText, systemImage: "rectangle.inset.filled"); Text(String(format: "%.2f FPS", info.frameRate)) }
                GridRow { Label(info.codec.uppercased(), systemImage: "film"); Text(info.isHDR ? "HDR" : "SDR") }
                GridRow { Label(info.durationText, systemImage: "clock"); Text(info.isPortrait ? "Portrait" : "Landscape") }
            }.font(.subheadline)
            Text(info.fileName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ProcessingView: View {
    @Environment(AppState.self) private var state
    @State private var showCancelConfirmation = false

    var body: some View {
        ZStack {
            ClarityScreenBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    NativeHeader(title: "Processing", showsBack: false)
                        .padding(.horizontal, 2)

                    if let job = state.activeJob {
                        progressHero(job)
                        jobSummary(job)
                        stats(job)
                        thermalCard
                    }

                    actionBar
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
        .navigationBarBackButtonHidden()
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Cancel enhancement?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Enhancement", role: .destructive) {
                state.cancelExport()
            }
            Button("Keep Processing", role: .cancel) {}
        } message: {
            Text("The current export will stop. Completed checkpoints are kept when the job supports resumable processing.")
        }
    }

    private func progressHero(_ job: ProcessingJob) -> some View {
        NativePanel {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.07), lineWidth: 11)
                        .frame(width: 136, height: 136)

                    Circle()
                        .trim(from: 0, to: max(0, min(1, job.progress)))
                        .stroke(
                            ClarityNativeTheme.brand,
                            style: StrokeStyle(lineWidth: 11, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 136, height: 136)
                        .shadow(color: Color.cyan.opacity(0.22), radius: 12)

                    VStack(spacing: 3) {
                        Text("\(Int((job.progress * 100).rounded()))%")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("ENHANCING")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }

                VStack(spacing: 5) {
                    Text(job.assetInfo.fileName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text("\(job.configuration.upscaler == .dlss5 ? "DLSS 5" : "Apple SR")  •  \(job.configuration.qualityPreset.rawValue)  •  \(job.configuration.resolution == .uhd8K ? "8K" : "4K")")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.cyan.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
        }
    }

    private func jobSummary(_ job: ProcessingJob) -> some View {
        NativePanel {
            VStack(spacing: 0) {
                processingRow(
                    icon: "film.fill",
                    title: "Frames",
                    value: "\(job.processedFrames) / \(job.totalFrames)"
                )
                rowDivider
                processingRow(
                    icon: "externaldrive.fill",
                    title: "Written",
                    value: ByteCountFormatter.string(fromByteCount: state.outputBytesSoFar, countStyle: .file)
                )
                if job.segmentCount > 1 {
                    rowDivider
                    processingRow(
                        icon: "rectangle.stack.fill",
                        title: "Checkpoint",
                        value: "\(max(1, job.currentSegment)) / \(job.segmentCount)"
                    )
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func stats(_ job: ProcessingJob) -> some View {
        HStack(spacing: 10) {
            statTile(
                title: "Speed",
                value: job.processedFrames > 0
                    ? String(format: "%.1f FPS", Double(job.processedFrames) / max(0.1, Date().timeIntervalSince(job.createdAt)))
                    : "Starting"
            )
            statTile(title: "Output", value: job.configuration.resolution == .uhd8K ? "8K" : "4K")
            statTile(title: "Engine", value: job.configuration.upscaler == .dlss5 ? "DLSS 5" : "Apple SR")
        }
    }

    private func statTile(title: String, value: String) -> some View {
        NativePanel {
            VStack(spacing: 5) {
                Text(value)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 6)
        }
    }

    private var thermalCard: some View {
        HStack(spacing: 10) {
            Image(systemName: ProcessInfo.processInfo.thermalState == .critical ? "thermometer.high" : "iphone")
                .foregroundStyle(ProcessInfo.processInfo.thermalState == .critical ? Color.orange : Color.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(thermalLabel)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                Text("Processing stays on this iPhone.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(ClarityNativeTheme.muted)
            }
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.65))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ClarityNativeTheme.surface,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ClarityNativeTheme.border, lineWidth: 0.7)
        )
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button { state.pauseExport() } label: {
                Label("Pause", systemImage: "pause.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.72), Color.cyan.opacity(0.42)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
            }
            .buttonStyle(.plain)

            Button(role: .destructive) { showCancelConfirmation = true } label: {
                Label("Cancel", systemImage: "xmark")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.red.opacity(0.18), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func processingRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 26)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.vertical, 11)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.7)
            .padding(.leading, 37)
    }

    private var thermalLabel: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Temperature normal"
        case .fair: "Device is warm"
        case .serious: "Device is hot · processing may slow"
        case .critical: "Critical temperature · processing paused"
        default: "Temperature unavailable"
        }
    }
}

struct ResultsView: View {
    @Environment(AppState.self) private var state
    @State private var saving = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            ClarityScreenBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    NativeHeader(title: "Complete", onBack: { state.leaveCompletedResult() })
                        .padding(.horizontal, 2)

                    if let job = state.activeJob, let url = job.outputURL {
                        completionHero(job, url: url)

                        if isSnapshotMode {
                            snapshotOutputPreview
                        } else if FileManager.default.fileExists(atPath: job.sourceURL.path) {
                            ComparisonPlaybackView(beforeURL: job.sourceURL, afterURL: url)
                        } else {
                            outputPreview(url)
                        }

                        exportDetails(job, url: url)
                        saveActions(url)
                        privacyCard

                        Button {
                            state.leaveCompletedResult(startAnother: true)
                        } label: {
                            Label("Enhance Another Video", systemImage: "plus")
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    ClarityNativeTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(ClarityNativeTheme.border, lineWidth: 0.7)
                                )
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Output", systemImage: "trash")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
        .navigationBarBackButtonHidden()
        .preferredColorScheme(.dark)
        .sheet(
            isPresented: Binding(
                get: { state.pendingFilesExportURL != nil },
                set: { presented in
                    if !presented { state.pendingFilesExportURL = nil }
                }
            )
        ) {
            if let url = state.pendingFilesExportURL {
                NativeFilesExportPicker(url: url) {
                    state.pendingFilesExportURL = nil
                }
            }
        }
        .confirmationDialog(
            "Delete enhanced video?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Output", role: .destructive) {
                state.deleteActiveOutput()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the enhanced export from Clarity. Your original video is not changed.")
        }
    }

    private var isSnapshotMode: Bool {
#if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["CLARITY_UI_SNAPSHOT"] == "1"
#else
        false
#endif
    }

    private var snapshotOutputPreview: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = UIImage(named: "MountainReference") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.blue.opacity(0.58), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.74)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.cyan)
                Text("Enhanced preview")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(12)
        }
        .frame(height: 220)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ClarityNativeTheme.border, lineWidth: 0.8)
        )
    }

    private func completionHero(_ job: ProcessingJob, url: URL) -> some View {
        NativePanel {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(ClarityNativeTheme.brand)
                        .frame(width: 62, height: 62)
                        .opacity(0.18)
                    Circle()
                        .stroke(Color.cyan.opacity(0.34), lineWidth: 1)
                        .frame(width: 62, height: 62)
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.cyan)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Export Complete")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(job.assetInfo.fileName)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(ClarityNativeTheme.muted)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        resultChip(job.configuration.resolution == .uhd8K ? "8K" : "4K")
                        resultChip(job.configuration.upscaler == .dlss5 ? "DLSS 5" : "Apple SR")
                        if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            resultChip(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(15)
        }
    }

    private func outputPreview(_ url: URL) -> some View {
        VideoPlayer(player: AVPlayer(url: url))
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func exportDetails(_ job: ProcessingJob, url: URL) -> some View {
        NativePanel {
            VStack(spacing: 0) {
                resultRow("Format", value: job.outputCodec ?? "HEVC")
                rowDivider
                resultRow("Resolution", value: job.configuration.resolution.rawValue)
                rowDivider
                resultRow("Duration", value: job.assetInfo.durationText)
                if let denoise = job.denoiseMethod {
                    rowDivider
                    resultRow("Denoise", value: denoise)
                }
                if let duration = job.processingDuration {
                    rowDivider
                    resultRow("Processing", value: String(format: "%.1f min", duration / 60))
                }
                if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    rowDivider
                    resultRow("File size", value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func saveActions(_ url: URL) -> some View {
        VStack(spacing: 10) {
            Button {
                saving = true
                Task {
                    defer { saving = false }
                    do { try await PhotosExportService.save(url) }
                    catch { state.errorMessage = error.localizedDescription }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "photo.badge.arrow.down")
                    Text(saving ? "Saving…" : "Save to Photos")
                }
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(ClarityNativeTheme.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(saving)

            ShareLink(item: url) {
                HStack(spacing: 9) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Save to Files or Share")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    ClarityNativeTheme.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(ClarityNativeTheme.border, lineWidth: 0.8)
                )
            }
        }
    }

    private var privacyCard: some View {
        NativePanel {
            HStack(spacing: 12) {
                ClarityIconTile(icon: "lock.shield.fill", size: 42, iconSize: 16)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Processed on this iPhone")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("No upload or cloud processing was used.")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(ClarityNativeTheme.muted)
                }

                Spacer()
            }
            .padding(13)
        }
    }

    private func resultChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.cyan)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.cyan.opacity(0.08), in: Capsule())
    }

    private func resultRow(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.70))
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.cyan.opacity(0.72))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 11)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.7)
    }
}
private struct NativeFilesExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish()
        }
    }
}

struct ComparisonPlaybackView: View {
    @State private var beforePlayer: AVPlayer
    @State private var afterPlayer: AVPlayer
    @State private var reveal = 0.5
    @State private var zoom = 1.0
    @State private var cropAnchor = UnitPoint.center
    private let syncTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    init(beforeURL: URL, afterURL: URL) {
        let before = AVPlayer(url: beforeURL)
        before.isMuted = true
        _beforePlayer = State(initialValue: before)
        _afterPlayer = State(initialValue: AVPlayer(url: afterURL))
    }

    var body: some View {
        NativePanel {
            VStack(spacing: 12) {
                comparisonCanvas
                    .frame(height: 230)

                revealControl

                VStack(spacing: 9) {
                    comparisonOptionRow(
                        title: "Zoom",
                        options: [
                            ("100%", zoom == 1.0, { zoom = 1.0 }),
                            ("200%", zoom == 2.0, { zoom = 2.0 }),
                            ("400%", zoom == 4.0, { zoom = 4.0 })
                        ]
                    )

                    comparisonOptionRow(
                        title: "Detail",
                        options: [
                            ("Top", cropAnchor == .top, { cropAnchor = .top }),
                            ("Center", cropAnchor == .center, { cropAnchor = .center }),
                            ("Bottom", cropAnchor == .bottom, { cropAnchor = .bottom })
                        ]
                    )
                }
            }
            .padding(12)
        }
        .onAppear {
            beforePlayer.seek(to: .zero)
            afterPlayer.seek(to: .zero)
            beforePlayer.play()
            afterPlayer.play()
        }
        .onReceive(syncTimer) { _ in
            let reference = afterPlayer.currentTime()
            let drift = abs(beforePlayer.currentTime().seconds - reference.seconds)
            if drift.isFinite, drift > 0.06 {
                beforePlayer.seek(to: reference, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: afterPlayer.currentItem)) { _ in
            beforePlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            afterPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            beforePlayer.play()
            afterPlayer.play()
        }
        .onDisappear {
            beforePlayer.pause()
            afterPlayer.pause()
        }
    }

    private var comparisonCanvas: some View {
        GeometryReader { geometry in
            let splitX = max(0, min(geometry.size.width, geometry.size.width * reveal))

            ZStack(alignment: .leading) {
                VideoPlayer(player: afterPlayer)
                    .scaleEffect(zoom, anchor: cropAnchor)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                VideoPlayer(player: beforePlayer)
                    .scaleEffect(zoom, anchor: cropAnchor)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(1, splitX))
                    }

                HStack {
                    comparisonBadge("BEFORE")
                    Spacer()
                    comparisonBadge("AFTER")
                }
                .padding(10)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

                Rectangle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 2)
                    .shadow(color: .black.opacity(0.65), radius: 2)
                    .offset(x: max(0, min(geometry.size.width - 2, splitX - 1)))
                    .allowsHitTesting(false)

                Circle()
                    .fill(Color(red: 0.03, green: 0.18, blue: 0.42))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.cyan.opacity(0.92), lineWidth: 1.4))
                    .overlay(
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.cyan)
                    )
                    .shadow(color: Color.cyan.opacity(0.18), radius: 7)
                    .offset(
                        x: max(0, min(geometry.size.width - 36, splitX - 18)),
                        y: geometry.size.height / 2 - 18
                    )
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ClarityNativeTheme.border, lineWidth: 0.8)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        reveal = max(0, min(1, value.location.x / max(1, geometry.size.width)))
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Before and after quality comparison")
            .accessibilityValue("Before \(Int(reveal * 100)) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    reveal = min(1, reveal + 0.05)
                case .decrement:
                    reveal = max(0, reveal - 0.05)
                @unknown default:
                    break
                }
            }
        }
    }

    private var revealControl: some View {
        HStack(spacing: 10) {
            Text("Before")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))

            GeometryReader { geometry in
                let width = max(1, geometry.size.width)
                let thumbX = max(8, min(width - 8, width * reveal))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.09))
                        .frame(height: 5)

                    Capsule()
                        .fill(ClarityNativeTheme.brand)
                        .frame(width: max(5, width * reveal), height: 5)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.cyan.opacity(0.38), lineWidth: 0.8))
                        .shadow(color: Color.cyan.opacity(0.26), radius: 5)
                        .position(x: thumbX, y: 12)
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            reveal = max(0, min(1, drag.location.x / width))
                        }
                )
            }
            .frame(height: 24)

            Text("After")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
        }
    }

    private func comparisonOptionRow(
        title: String,
        options: [(String, Bool, () -> Void)]
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.60))
                .frame(width: 42, alignment: .leading)

            HStack(spacing: 5) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button(action: option.2) {
                        Text(option.0)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                option.1
                                    ? AnyShapeStyle(ClarityNativeTheme.brand)
                                    : AnyShapeStyle(Color.white.opacity(0.055)),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(
                                        option.1 ? Color.cyan.opacity(0.42) : Color.white.opacity(0.04),
                                        lineWidth: 0.7
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                Color.black.opacity(0.20),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }

    private func comparisonBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.62), in: Capsule())
    }
}
