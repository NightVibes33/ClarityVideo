import SwiftUI
import AVKit

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
                    Stepper("Bitrate: \(state.configuration.bitrateMbps) Mbps", value: $state.configuration.bitrateMbps, in: 20...240, step: 5)
                    LabeledContent("Codec", value: "HEVC (hardware)")
                    if let info = state.assetInfo {
                        LabeledContent("Estimated output", value: ByteCountFormatter.string(fromByteCount: StorageEstimator.estimatedOutputBytes(info: info, configuration: state.configuration), countStyle: .file))
                    }
                }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                DisclosureGroup("How this export is produced") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(state.capabilities.fullSuperResolutionAvailable ? "Apple frame processor detected" : "Apple AI processor unavailable", systemImage: "cpu")
                        Text("Clarity queries the device before exposing AI modes. Exact 4K/8K sizing may supplement supported AI scaling with a high-quality final resize. 8K only appears after a hardware encoder probe passes.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                Button { state.generateComparisonPreview() } label: {
                    Label(state.isGeneratingPreview ? "Building preview \(Int(state.previewProgress * 100))%" : "Generate 3-second AI comparison", systemImage: "rectangle.split.2x1")
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
                    LabeledContent("Preview processing", value: String(format: "%.1f s", preview.previewProcessingDuration))
                    LabeledContent("Estimated full export", value: String(format: "%.1f min", preview.estimatedFullDuration / 60))
                }.padding().navigationTitle("AI Comparison")
            }
        }
        .navigationTitle("Video setup")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { state.route = .home } } }
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
                Text(ProcessInfo.processInfo.thermalState == .critical ? "Paused to protect your device" : "Temperature monitored automatically")
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
                        LabeledContent("Codec", value: "HEVC")
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

    init(beforeURL: URL, afterURL: URL) {
        let before = AVPlayer(url: beforeURL)
        before.isMuted = true
        _beforePlayer = State(initialValue: before)
        _afterPlayer = State(initialValue: AVPlayer(url: afterURL))
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    VideoPlayer(player: beforePlayer)
                    VideoPlayer(player: afterPlayer)
                        .frame(width: max(1, geometry.size.width * reveal), alignment: .leading)
                        .clipped()
                    Rectangle().fill(.white.opacity(0.9)).frame(width: 2)
                        .offset(x: geometry.size.width * reveal)
                }
                .scaleEffect(zoom)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .allowsHitTesting(false)
            }
            .frame(height: 230)
            HStack { Text("Before"); Slider(value: $reveal, in: 0...1); Text("After") }
                .font(.caption.bold())
            Picker("Zoom", selection: $zoom) {
                Text("100%").tag(1.0)
                Text("200%").tag(2.0)
                Text("400%").tag(4.0)
            }.pickerStyle(.segmented)
        }
        .onAppear {
            beforePlayer.seek(to: .zero)
            afterPlayer.seek(to: .zero)
            beforePlayer.play()
            afterPlayer.play()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: beforePlayer.currentItem)) { _ in
            beforePlayer.seek(to: .zero); beforePlayer.play()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: afterPlayer.currentItem)) { _ in
            afterPlayer.seek(to: .zero); afterPlayer.play()
        }
        .onDisappear {
            beforePlayer.pause()
            afterPlayer.pause()
        }
    }
}
