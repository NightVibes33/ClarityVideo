import SwiftUI
import AVKit
import Combine

struct EditorView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var state = state
        ScrollView {
            VStack(spacing: 18) {
                if let url = state.importedURL {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 18))
                }
                if let info = state.assetInfo { AnalysisCard(info: info) }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Enhancement").font(.title2.bold())
                    Picker("Output", selection: $state.configuration.resolution) {
                        Text("4K UHD").tag(OutputResolution.uhd4K)
                        if state.capabilities.supports8KHEVCEncode {
                            Text("8K UHD \u{00B7} Experimental").tag(OutputResolution.uhd8K)
                        }
                    }.pickerStyle(.segmented)
                    .onChange(of: state.configuration.resolution) { _, resolution in
                        if resolution == .uhd8K && state.configuration.codec == .h264 { state.configuration.codec = .hevc }
                        if resolution == .uhd8K && state.configuration.bitrateMbps == 55 { state.configuration.bitrateMbps = 160 }
                        if resolution == .uhd4K && state.configuration.bitrateMbps > 110 { state.configuration.bitrateMbps = 65 }
                    }
                    Picker("Mode", selection: $state.configuration.mode) {
                        ForEach(EnhancementMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .onChange(of: state.configuration.mode) { _, mode in
                        state.configuration.applyPreset(mode, temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable)
                    }
                    LabeledContent("Denoise") { Slider(value: $state.configuration.denoise, in: 0...1).frame(width: 180).disabled(!state.capabilities.temporalNoiseFilteringAvailable) }
                    if !state.capabilities.temporalNoiseFilteringAvailable { Text("Apple temporal denoise is unavailable on this device.").font(.caption).foregroundStyle(.secondary) }
                    LabeledContent("Detail recovery") { Slider(value: $state.configuration.detailRecovery, in: 0...1).frame(width: 180) }
                    LabeledContent("Sharpening") { Slider(value: $state.configuration.sharpening, in: 0...1).frame(width: 180) }
                    Picker("HDR", selection: $state.configuration.hdrBehavior) {
                        ForEach(HDRBehavior.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Codec", selection: $state.configuration.codec) {
                        ForEach(OutputCodec.allCases.filter { codec in
                            codec == .hevc || (state.configuration.resolution == .uhd4K && state.assetInfo?.isHDR == false)
                        }) { Text($0.rawValue).tag($0) }
                    }
                    .onChange(of: state.configuration.codec) { _, codec in
                        if codec == .h264 && state.configuration.resolution == .uhd8K { state.configuration.codec = .hevc }
                    }
                    Stepper("Bitrate: \(state.configuration.bitrateMbps) Mbps", value: $state.configuration.bitrateMbps, in: 20...300, step: 5)
                    Toggle("Preserve source frame rate", isOn: $state.configuration.preserveFrameRate)
                        .disabled(true)
                    Text("Frame-rate conversion is not enabled; every export preserves source presentation timing.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let info = state.assetInfo {
                        LabeledContent("Estimated output", value: ByteCountFormatter.string(fromByteCount: StorageEstimator.estimatedOutputBytes(info: info, configuration: state.configuration), countStyle: .file))
                    }
                }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                DisclosureGroup("How this export is produced") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(state.capabilities.fullSuperResolutionAvailable ? "Apple frame processor detected" : "Apple AI processor unavailable", systemImage: "cpu")
                        if let plan = currentPipelinePlan {
                            LabeledContent("Apple AI scale", value: String(format: "%.1fx", plan.aiScaleFactor))
                            LabeledContent("Output", value: "\(plan.targetWidth) x \(plan.targetHeight)")
                            if plan.requiresTiling {
                                LabeledContent("Processing", value: "Overlapping tiles")
                            }
                            Text(plan.disclosure)
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("No compatible Apple super-resolution route is available for this source and output on this device.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("8K only appears after a real hardware encoder probe passes.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                if let info = state.assetInfo {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Comparison range").font(.headline)
                        LabeledContent("Start", value: durationLabel(state.previewStartSeconds))
                        Slider(
                            value: $state.previewStartSeconds,
                            in: 0...max(0.01, info.duration - state.previewDurationSeconds)
                        )
                        Stepper(
                            "Duration: \(Int(state.previewDurationSeconds.rounded())) seconds",
                            value: $state.previewDurationSeconds,
                            in: min(2, info.duration)...min(5, max(2, info.duration)),
                            step: 1
                        )
                        .disabled(info.duration < 2)
                        Text("Only this short range is enhanced for the preview. The full source remains untouched.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .onChange(of: state.previewDurationSeconds) { _, duration in
                        state.previewStartSeconds = min(state.previewStartSeconds, max(0, info.duration - duration))
                    }
                    .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }

                Button { state.generateComparisonPreview() } label: {
                    Label(state.isGeneratingPreview ? "Building preview \(Int(state.previewProgress * 100))%" : "Generate AI comparison", systemImage: "rectangle.split.2x1")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).controlSize(.large)
                    .disabled(state.isGeneratingPreview || (!state.capabilities.fullSuperResolutionAvailable && !state.capabilities.lowLatencySuperResolutionAvailable))
                Button { state.beginExport() } label: {
                    Label("Enhance on this device", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!state.capabilities.fullSuperResolutionAvailable && !state.capabilities.lowLatencySuperResolutionAvailable)
            }.padding()
        }
        .sheet(item: $state.comparisonPreview) { preview in
            NavigationStack {
                VStack {
                    ComparisonPlaybackView(beforeURL: preview.sourceURL, afterURL: preview.enhancedURL)
                    LabeledContent("Selected range", value: "\(durationLabel(preview.selectedStartSeconds)) for \(Int(preview.selectedDurationSeconds.rounded())) s")
                    LabeledContent("Preview processing", value: String(format: "%.1f s", preview.previewProcessingDuration))
                    LabeledContent("Estimated full export", value: String(format: "%.1f min", preview.estimatedFullDuration / 60))
                    LabeledContent("Estimated output", value: ByteCountFormatter.string(fromByteCount: preview.estimatedOutputBytes, countStyle: .file))
                }.padding().navigationTitle("AI Comparison")
            }
        }
        .navigationTitle("Video setup")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { state.route = .home } } }
    }

    private var currentPipelinePlan: PipelinePlan? {
        guard let info = state.assetInfo else { return nil }
        let factors = info.encodedWidth <= 1280 && info.encodedHeight <= 720
            ? state.capabilities.supportedLowLatencyScaleFactors
            : state.capabilities.supportedLowLatency1080pScaleFactors
        return try? PipelinePlanner.plan(
            sourceWidth: info.encodedWidth, sourceHeight: info.encodedHeight,
            target: state.configuration.resolution, mode: state.configuration.mode,
            capabilities: state.capabilities, lowLatencyFactorsForSource: factors
        )
    }

    private func durationLabel(_ seconds: Double) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
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
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "wand.and.rays").font(.system(size: 58)).foregroundStyle(.cyan).symbolEffect(.pulse)
            Text("\(state.activeJob?.configuration.mode.rawValue ?? "Enhancing") \(state.activeJob?.configuration.resolution.rawValue ?? "")")
                .font(.title.bold())
            let progress = state.activeJob?.progress ?? 0
            ProgressView(value: progress).progressViewStyle(.linear).padding(.horizontal, 32)
            Text("\(Int(progress * 100))%").font(.system(.largeTitle, design: .rounded).bold())
            if let job = state.activeJob {
                VStack(spacing: 4) {
                    if job.segmentCount > 1 { Text("Segment \(max(1, job.currentSegment)) of \(job.segmentCount)") }
                    Text("\(job.processedFrames) of \(job.totalFrames) frames")
                    Text("Output so far: \(ByteCountFormatter.string(fromByteCount: state.outputBytesSoFar, countStyle: .file))")
                    if job.processedFrames > 0 {
                        Text(String(format: "%.1f FPS", Double(job.processedFrames) / max(0.1, Date().timeIntervalSince(job.createdAt))))
                    }
                }.font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                Text("Processing remains on this device")
                Text("Temperature: \(thermalLabel)")
                Text(ProcessInfo.processInfo.thermalState == .critical ? "Paused to protect your device" : "Temperature monitored automatically")
                Text("If you leave the app, iOS may pause heavy processing. Completed segments are checkpointed for resume.")
                    .multilineTextAlignment(.center)
            }.font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button { state.pauseExport() } label: {
                    Label("Pause", systemImage: "pause.circle").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                Button(role: .destructive) { state.cancelExport() } label: {
                    Label("Cancel", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }.controlSize(.large).padding()
        }.navigationBarBackButtonHidden()
    }

    private var thermalLabel: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot - slowing down"
        case .critical: "Critical - pausing"
         default: "Unknown"
        }
    }
}

struct ResultsView: View {
    @Environment(AppState.self) private var state
    @State private var saving = false
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 68)).foregroundStyle(.green)
                Text("Enhancement complete").font(.largeTitle.bold())
                if let job = state.activeJob, let url = job.outputURL {
                    ComparisonPlaybackView(beforeURL: job.sourceURL, afterURL: url)
                    VStack {
                        LabeledContent("Resolution", value: job.configuration.resolution.rawValue)
                        LabeledContent("Codec", value: job.outputCodec ?? "HEVC")
                        LabeledContent("Frames", value: "\(job.processedFrames)")
                        if let duration = job.processingDuration {
                            LabeledContent("Processing time", value: String(format: "%.1f min", duration / 60))
                            LabeledContent("Average speed", value: String(format: "%.1f FPS", Double(job.processedFrames) / max(0.1, duration)))
                        }
                        if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            LabeledContent("Output size", value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                        }
                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    Button {
                        saving = true
                        Task {
                            defer { saving = false }
                            do { try await PhotosExportService.save(url) } catch { state.errorMessage = error.localizedDescription }
                        }
                    } label: { Label(saving ? "Saving\u{2026}" : "Save to Photos", systemImage: "photo.badge.arrow.down").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(saving)
                    ShareLink(item: url) { Label("Save to Files or Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).controlSize(.large)
                    Button(role: .destructive) { state.deleteActiveOutput() } label: {
                        Label("Delete output", systemImage: "trash").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).controlSize(.large)
                }
                Button("Enhance another video") { state.route = .home }
            }.padding()
        }.navigationBarBackButtonHidden()
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
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let splitX = max(0, min(geometry.size.width, geometry.size.width * reveal))
                ZStack(alignment: .leading) {
                    ZStack {
                        VideoPlayer(player: afterPlayer)
                            .scaleEffect(zoom, anchor: cropAnchor)
                        VideoPlayer(player: beforePlayer)
                            .scaleEffect(zoom, anchor: cropAnchor)
                            .mask(alignment: .leading) {
                                HStack(spacing: 0) {
                                    Rectangle().frame(width: max(1, splitX))
                                    Spacer(minLength: 0)
                                }
                            }
                    }
                    HStack {
                        Text("BEFORE")
                        Spacer()
                        Text("AFTER")
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(10)
                    .allowsHitTesting(false)
                    Rectangle()
                        .fill(.white)
                        .frame(width: 3)
                        .shadow(color: .black.opacity(0.65), radius: 2)
                        .offset(x: max(0, min(geometry.size.width - 3, splitX - 1.5)))
                        .allowsHitTesting(false)
                    Image(systemName: "arrow.left.and.right.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white, .black.opacity(0.72))
                        .offset(x: max(0, min(geometry.size.width - 30, splitX - 15)), y: geometry.size.height / 2 - 15)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    reveal = max(0, min(1, value.location.x / max(1, geometry.size.width)))
                })
                .accessibilityLabel("Before and after quality comparison")
                .accessibilityValue("Before \(Int(reveal * 100)) percent")
                .accessibilityAdjustableAction { direction in
                    reveal = max(0, min(1, reveal + (direction == .increment ? 0.05 : -0.05)))
                }
            }
            .frame(height: 230)
            HStack { Text("Before"); Slider(value: $reveal, in: 0...1); Text("After") }
                .font(.caption.bold())
            Picker("Zoom", selection: $zoom) {
                Text("100%").tag(1.0)
                Text("200%").tag(2.0)
                Text("400%").tag(4.0)
            }.pickerStyle(.segmented)
            Picker("Detail crop", selection: $cropAnchor) {
                Text("Top").tag(UnitPoint.top)
                Text("Center").tag(UnitPoint.center)
                Text("Bottom").tag(UnitPoint.bottom)
            }.pickerStyle(.segmented)
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
}
