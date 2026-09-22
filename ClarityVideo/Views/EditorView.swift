import SwiftUI
import AVKit
import Combine
import UIKit

struct ProcessingView: View {
    @Environment(AppState.self) private var state
    @State private var showCancelConfirmation: Bool = {
#if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["CLARITY_UI_ROUTE"] == "processing-confirm"
#else
        false
#endif
    }()

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
        .overlay {
            if showCancelConfirmation {
                ZStack {
                    Color.black.opacity(0.64)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.16)) {
                                showCancelConfirmation = false
                            }
                        }

                    ClarityConfirmationCard(
                        icon: "xmark.circle.fill",
                        title: "Cancel enhancement?",
                        message: "The current export will stop. Completed checkpoints are kept when this job supports resumable processing.",
                        destructiveTitle: "Cancel Enhancement",
                        cancelTitle: "Keep Processing",
                        destructiveAction: {
                            state.cancelExport()
                            withAnimation(.easeOut(duration: 0.16)) {
                                showCancelConfirmation = false
                            }
                        },
                        cancelAction: {
                            withAnimation(.easeOut(duration: 0.16)) {
                                showCancelConfirmation = false
                            }
                        }
                    )
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
                .zIndex(100)
            }
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
    @State private var showDeleteConfirmation: Bool = {
#if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["CLARITY_UI_ROUTE"] == "results-confirm"
#else
        false
#endif
    }()

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
        .overlay {
            if showDeleteConfirmation {
                ZStack {
                    Color.black.opacity(0.64)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.16)) {
                                showDeleteConfirmation = false
                            }
                        }

                    ClarityConfirmationCard(
                        icon: "trash.fill",
                        title: "Delete enhanced video?",
                        message: "This deletes the enhanced export from Clarity. Your original video is not changed.",
                        destructiveTitle: "Delete Output",
                        cancelTitle: "Cancel",
                        destructiveAction: {
                            state.deleteActiveOutput()
                            withAnimation(.easeOut(duration: 0.16)) {
                                showDeleteConfirmation = false
                            }
                        },
                        cancelAction: {
                            withAnimation(.easeOut(duration: 0.16)) {
                                showDeleteConfirmation = false
                            }
                        }
                    )
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
                .zIndex(100)
            }
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
