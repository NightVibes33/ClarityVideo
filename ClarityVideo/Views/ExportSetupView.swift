import SwiftUI
import AVFoundation

struct ExportSetupView: View {
    @Environment(AppState.self) private var state
    @State private var quality = 1

    var body: some View {
        @Bindable var state = state
        ZStack {
            Color(red: 0.008, green: 0.018, blue: 0.034).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if let info = state.assetInfo {
                        HStack(spacing: 12) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 36)).foregroundStyle(.cyan)
                                .frame(width: 76, height: 76)
                                .background(.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(info.fileName).font(.headline).lineLimit(1)
                                Text("\(info.durationText) · \(state.configuration.resolution.rawValue) · \(state.configuration.codec.rawValue)")
                                Text(ByteCountFormatter.string(fromByteCount: StorageEstimator.estimatedOutputBytes(info: info, configuration: state.configuration), countStyle: .file) + " estimated")
                            }.font(.caption).foregroundStyle(.white.opacity(0.72))
                            Spacer(minLength: 0)
                        }.padding(12).background(panel)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Export Settings").font(.headline)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Format").font(.caption)
                            Picker("Format", selection: $state.configuration.codec) {
                                Text("HEVC (H.265)").tag(OutputCodec.hevc)
                                if state.configuration.resolution == .uhd4K && state.assetInfo?.isHDR == false {
                                    Text("H.264").tag(OutputCodec.h264)
                                }
                            }.pickerStyle(.segmented)
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Quality").font(.caption)
                            Picker("Quality", selection: $quality) {
                                Text("Standard").tag(0)
                                Text("High").tag(1)
                                Text("Maximum").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: quality) { _, value in
                                state.configuration.bitrateMbps = (state.configuration.resolution == .uhd8K ? [100, 160, 220] : [35, 65, 100])[value]
                            }
                        }
                        if state.assetInfo?.isHDR == true {
                            Text("HDR will be converted to SDR for supported 4K exports.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        Toggle("Save to Photos when finished", isOn: $state.saveToPhotosAfterExport)
                    }
                    .font(.subheadline)
                    .tint(.cyan)
                    .padding(16).background(panel)

                    Button { state.beginExport() } label: {
                        Text("Start Export").font(.headline).frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(Color(red: 0.02, green: 0.04, blue: 0.12))
                            .background(LinearGradient(colors: [.purple, .blue, .cyan], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                    Text("Processing runs on your iPhone. Keep Clarity open for long exports.")
                        .font(.caption).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
                    Label("Your video stays on this device", systemImage: "lock.shield.fill")
                        .font(.caption).foregroundStyle(.cyan)
                        .frame(maxWidth: .infinity).padding(15).background(panel)
                }.padding(16)
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) {
            Button { state.route = .editor } label: { Image(systemName: "chevron.left") }
        } }
        .navigationBarBackButtonHidden()
        .preferredColorScheme(.dark)
    }

    private var panel: some ShapeStyle { Color(red: 0.065, green: 0.09, blue: 0.135) }
}
