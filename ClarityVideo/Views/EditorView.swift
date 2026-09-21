import SwiftUI
import AVKit
import Combine

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
            if let url = state.importedURL {
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
                Text("Enhancement Mode").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.82))
                Picker("Enhancement mode", selection: $state.configuration.mode) {
                    ForEach(EnhancementMode.allCases) { Text(shortModeName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: state.configuration.mode) { _, mode in
                    state.configuration.applyPreset(mode, temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable)
                }
                Text(modeDescription(state.configuration.mode)).font(.caption).foregroundStyle(.white.opacity(0.50))
            }

            HStack(spacing: 10) {
                Image(systemName: state.capabilities.fullSuperResolutionAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(state.capabilities.fullSuperResolutionAvailable ? .cyan : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Super Resolution").font(.subheadline.bold())
                    Text(currentPipelinePlan?.disclosure ?? "No compatible enhancement route for this source.")
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

            Button { state.beginExport() } label: {
                HStack {
                    Text("Start Processing")
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
            .disabled(!state.capabilities.fullSuperResolutionAvailable && !state.capabilities.lowLatencySuperResolutionAvailable)
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
            target: state.configuration.resolution, mode: state.configuration.mode,
            capabilities: state.capabilities, lowLatencyFactorsForSource: factors
        )
    }

    private func shortModeName(_ mode: EnhancementMode) -> String {
        switch mode {
        case .fast: "Fast"
        case .quality: "Quality"
        case .restore: "Restore"
        case .anime: "Anime"
        }
    }

    private func modeDescription(_ mode: EnhancementMode) -> String {
        switch mode {
        case .fast: "Faster enhancement with a lighter processing path."
        case .quality: "Best supported detail and clarity for most videos."
        case .restore: "Stronger cleanup for old, compressed, or noisy footage."
        case .anime: "Crisp edges and controlled sharpening for animation and gameplay."
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

    var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.018, blue: 0.034).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    Circle().stroke(Color.blue.opacity(0.18), lineWidth: 13).frame(width: 150, height: 150)
                    Circle().trim(from: 0, to: state.activeJob?.progress ?? 0)
                        .stroke(LinearGradient(colors: [.purple, .blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 150, height: 150)
                    VStack(spacing: 4) {
                        Text("\(Int((state.activeJob?.progress ?? 0) * 100))%").font(.system(size: 35, weight: .bold, design: .rounded))
                        Text("ENHANCING").font(.caption2.bold()).tracking(1.5).foregroundStyle(.white.opacity(0.45))
                    }
                }
                Text("\(state.activeJob?.configuration.mode.rawValue ?? "Enhancing") · \(state.activeJob?.configuration.resolution.rawValue ?? "")")
                    .font(.title2.bold())
                if let job = state.activeJob {
                    VStack(spacing: 7) {
                        if job.segmentCount > 1 { Text("Segment \(max(1, job.currentSegment)) of \(job.segmentCount)") }
                        Text("\(job.processedFrames) / \(job.totalFrames) frames")
                        Text(ByteCountFormatter.string(fromByteCount: state.outputBytesSoFar, countStyle: .file) + " written")
                        if job.processedFrames > 0 {
                            Text(String(format: "%.1f FPS", Double(job.processedFrames) / max(0.1, Date().timeIntervalSince(job.createdAt))))
                        }
                    }.font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.58))
                }
                Label("AI processing stays on this iPhone", systemImage: "lock.fill")
                    .font(.subheadline).foregroundStyle(.cyan)
                Text(thermalLabel).font(.caption).foregroundStyle(.white.opacity(0.48))
                Spacer()
                HStack(spacing: 12) {
                    Button { state.pauseExport() } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(.blue)
                    Button(role: .destructive) { state.cancelExport() } label: { Label("Cancel", systemImage: "xmark").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }.controlSize(.large)
            }.padding(22)
        }.navigationBarBackButtonHidden()
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

    var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.018, blue: 0.034).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 17) {
                    HStack {
                        Button { state.route = .home } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text("Export").font(.headline)
                        Spacer()
                        Image(systemName: "magnifyingglass").opacity(0.7)
                    }
                    if let job = state.activeJob, let url = job.outputURL {
                        HStack(spacing: 13) {
                            RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [.indigo, .blue], startPoint: .top, endPoint: .bottom))
                                .frame(width: 78, height: 78)
                                .overlay(Image(systemName: "mountain.2.fill").font(.title).foregroundStyle(.white.opacity(0.8)))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(job.assetInfo.fileName).font(.headline).lineLimit(1)
                                Text("\(job.assetInfo.durationText) · \(job.configuration.resolution.rawValue) · \(job.outputCodec ?? "HEVC")")
                                    .font(.caption).foregroundStyle(.white.opacity(0.58))
                                if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                                        .font(.caption).foregroundStyle(.white.opacity(0.45))
                                }
                            }
                            Spacer()
                        }
                        .padding(14).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))

                        ComparisonPlaybackView(beforeURL: job.sourceURL, afterURL: url)

                        VStack(alignment: .leading, spacing: 15) {
                            Text("Export Complete").font(.headline)
                            LabeledContent("Format", value: job.outputCodec ?? "HEVC")
                            LabeledContent("Resolution", value: job.configuration.resolution.rawValue)
                            if let d = job.denoiseMethod { LabeledContent("Denoise", value: d) }
                            if let duration = job.processingDuration {
                                LabeledContent("Processing", value: String(format: "%.1f min", duration / 60))
                            }
                        }
                        .font(.subheadline)
                        .padding(16).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))

                        Button {
                            saving = true
                            Task {
                                defer { saving = false }
                                do { try await PhotosExportService.save(url) }
                                catch { state.errorMessage = error.localizedDescription }
                            }
                        } label: {
                            HStack { Spacer(); Image(systemName: "photo.badge.arrow.down"); Text(saving ? "Saving…" : "Save to Photos"); Spacer() }
                                .font(.headline).padding(.vertical, 16)
                                .background(LinearGradient(colors: [.purple, .blue, .cyan], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 17))
                                .foregroundStyle(.white)
                        }.buttonStyle(.plain).disabled(saving)

                        ShareLink(item: url) {
                            Label("Save to Files or Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).controlSize(.large)

                        HStack(spacing: 11) {
                            Image(systemName: "lock.shield.fill").foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Powered. On Device.").font(.subheadline.bold())
                                Text("Your privacy stays with you.").font(.caption).foregroundStyle(.white.opacity(0.46))
                            }
                            Spacer()
                        }
                        .padding(15).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))

                        Button("Enhance Another Video") { state.route = .home }.font(.subheadline.bold())
                        Button(role: .destructive) { state.deleteActiveOutput() } label: { Label("Delete Output", systemImage: "trash") }
                    }
                }.padding(17).padding(.bottom, 20)
            }
        }.navigationBarBackButtonHidden().preferredColorScheme(.dark)
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
