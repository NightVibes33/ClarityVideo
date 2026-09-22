import SwiftUI
import Photos
import AVFoundation
import AVKit
import UniformTypeIdentifiers
import UIKit

// App Store release-candidate UI surface.

enum ClarityNativeTheme {
    static let background = Color(red: 0.001, green: 0.008, blue: 0.021)
    static let panel = Color(red: 0.010, green: 0.030, blue: 0.070)
    static let muted = Color.white.opacity(0.60)
    static let subtle = Color.white.opacity(0.40)

    static let brand = LinearGradient(
        colors: [
            Color(red: 0.58, green: 0.27, blue: 1.0),
            Color(red: 0.12, green: 0.48, blue: 1.0),
            Color(red: 0.05, green: 0.79, blue: 1.0)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let card = LinearGradient(
        colors: [
            Color(red: 0.025, green: 0.22, blue: 0.47),
            Color(red: 0.018, green: 0.105, blue: 0.255),
            Color(red: 0.010, green: 0.040, blue: 0.105)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let surface = LinearGradient(
        colors: [
            Color(red: 0.020, green: 0.070, blue: 0.135).opacity(0.98),
            Color(red: 0.008, green: 0.022, blue: 0.052).opacity(0.98)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let border = LinearGradient(
        colors: [
            Color.cyan.opacity(0.72),
            Color.blue.opacity(0.55),
            Color.purple.opacity(0.46)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct ClarityScreenBackdrop: View {
    var body: some View {
        ZStack {
            ClarityNativeTheme.background
            RadialGradient(
                colors: [
                    Color.blue.opacity(0.24),
                    Color(red: 0.05, green: 0.23, blue: 0.52).opacity(0.12),
                    .clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color(red: 0.02, green: 0.25, blue: 0.62).opacity(0.13),
                    Color.purple.opacity(0.055),
                    .clear
                ],
                center: UnitPoint(x: 0.50, y: 0.72),
                startRadius: 10,
                endRadius: 430
            )

            LinearGradient(
                colors: [.clear, Color.purple.opacity(0.045), .clear],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
        .ignoresSafeArea()
    }
}

struct ClarityIconTile: View {
    let icon: String
    var size: CGFloat = 58
    var iconSize: CGFloat = 24
    var destructive = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(
                destructive
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.red.opacity(0.72), Color.pink.opacity(0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.02, green: 0.55, blue: 1.0),
                                Color(red: 0.12, green: 0.32, blue: 0.95),
                                Color(red: 0.48, green: 0.16, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(destructive ? Color.white : Color(red: 0.62, green: 0.92, blue: 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
            .shadow(color: destructive ? Color.red.opacity(0.18) : Color.blue.opacity(0.24), radius: 10)
    }
}

private enum ClarityArt {
    static let mountain = UIImage(named: "MountainReference")
}

struct NativePanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(ClarityNativeTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(ClarityNativeTheme.border, lineWidth: 0.85)
                    )
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                            .frame(height: 0.8)
                            .padding(.horizontal, 24)
                    }
                    .shadow(color: Color.blue.opacity(0.13), radius: 20, y: 10)
            )
    }
}

struct ClarityPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.985

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

struct ClarityPillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.48, green: 0.88, blue: 1.0))
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.02, green: 0.22, blue: 0.48),
                                    Color(red: 0.07, green: 0.10, blue: 0.28),
                                    Color.purple.opacity(0.30)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(Capsule().stroke(ClarityNativeTheme.border, lineWidth: 0.9))
                        .shadow(color: Color.blue.opacity(0.24), radius: 10)
                )
        }
        .buttonStyle(.plain)
    }
}

struct ClaritySwitchControl: View {
    @Binding var isOn: Bool
    var accessibilityLabel: String

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        isOn
                            ? AnyShapeStyle(ClarityNativeTheme.brand)
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.11),
                                        Color.white.opacity(0.055)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .frame(width: 52, height: 30)
                    .overlay(
                        Capsule()
                            .stroke(
                                isOn
                                    ? Color.cyan.opacity(0.52)
                                    : Color.white.opacity(0.10),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(
                        color: isOn ? Color.cyan.opacity(0.20) : .clear,
                        radius: 6
                    )

                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.cyan.opacity(isOn ? 0.22 : 0.08), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.30), radius: 3, y: 1)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

struct ClarityStorageDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let breakdown: StorageEstimateBreakdown
    let availableBytes: Int64?

    var body: some View {
        ZStack {
            ClarityScreenBackdrop()

            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Storage Estimate")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(
                            breakdown.usesCheckpoints
                                ? "Checkpointed export"
                                : "Streaming export"
                        )
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.cyan.opacity(0.76))
                    }

                    Spacer()

                    ClarityPillButton(title: "Done") { dismiss() }
                }

                NativePanel {
                    VStack(spacing: 0) {
                        storageRow(
                            icon: "film.fill",
                            title: "Final video",
                            detail: "Estimated encoded output",
                            bytes: breakdown.finalOutputBytes
                        )

                        rowDivider

                        storageRow(
                            icon: breakdown.usesCheckpoints ? "rectangle.stack.fill" : "arrow.triangle.2.circlepath",
                            title: breakdown.usesCheckpoints ? "Working checkpoints" : "Temporary working copy",
                            detail: breakdown.usesCheckpoints
                                ? "Completed segments + current 5-second pair"
                                : "One encoded video track while audio is remuxed",
                            bytes: breakdown.workingBytes
                        )

                        rowDivider

                        storageRow(
                            icon: "shield.fill",
                            title: "Safety reserve",
                            detail: "Prevents an export from filling the device",
                            bytes: breakdown.safetyBytes
                        )

                        rowDivider

                        HStack {
                            Text("Total temporary requirement")
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Spacer()

                            Text(fileSize(breakdown.requiredBytes))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.cyan)
                        }
                        .padding(.vertical, 13)
                    }
                    .padding(.horizontal, 14)
                }

                HStack(spacing: 10) {
                    Image(systemName: "internaldrive.fill")
                        .foregroundStyle(.cyan)

                    Text("Available")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.70))

                    Spacer()

                    Text(availableBytes.map(fileSize) ?? "Unknown")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 4)

                Text("Clarity never budgets raw uncompressed video frames on disk. Short exports stream frames and keep only the encoded output plus one working movie.")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.height(470)])
        .presentationDragIndicator(.visible)
    }

    private func storageRow(
        icon: String,
        title: String,
        detail: String,
        bytes: Int64
    ) -> some View {
        HStack(spacing: 12) {
            ClarityIconTile(icon: icon, size: 40, iconSize: 15)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(detail)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(fileSize(bytes))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.vertical, 10)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.7)
            .padding(.leading, 52)
    }

    private func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct ClarityConfirmationCard: View {
    let icon: String
    let title: String
    let message: String
    let destructiveTitle: String
    let cancelTitle: String
    let destructiveAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ClarityIconTile(
                icon: icon,
                size: 58,
                iconSize: 23,
                destructive: true
            )

            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: destructiveAction) {
                Text(destructiveTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.red.opacity(0.92),
                                Color.pink.opacity(0.62)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.red.opacity(0.42), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)

            Button(action: cancelAction) {
                Text(cancelTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Color.white.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: 330)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.018, green: 0.075, blue: 0.16),
                            Color(red: 0.010, green: 0.025, blue: 0.065)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(ClarityNativeTheme.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.52), radius: 34, y: 18)
        )
        .padding(.horizontal, 26)
    }
}

struct ClarityWaveDecoration: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                wave(
                    width: width,
                    height: height,
                    crest: height * 0.28,
                    trough: height * 0.70,
                    end: height * 0.34
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.02),
                            Color.blue.opacity(0.38),
                            Color.purple.opacity(0.18),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    wave(
                        width: width,
                        height: height,
                        crest: height * 0.28,
                        trough: height * 0.70,
                        end: height * 0.34
                    )
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.12), Color.cyan.opacity(0.72), Color.purple.opacity(0.60)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.1
                    )
                )

                wave(
                    width: width,
                    height: height,
                    crest: height * 0.46,
                    trough: height * 0.78,
                    end: height * 0.50
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.blue.opacity(0.18),
                            Color.purple.opacity(0.20),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func wave(
        width: CGFloat,
        height: CGFloat,
        crest: CGFloat,
        trough: CGFloat,
        end: CGFloat
    ) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: crest))
            path.addCurve(
                to: CGPoint(x: width * 0.52, y: trough),
                control1: CGPoint(x: width * 0.20, y: crest - height * 0.02),
                control2: CGPoint(x: width * 0.31, y: trough + height * 0.05)
            )
            path.addCurve(
                to: CGPoint(x: width, y: end),
                control1: CGPoint(x: width * 0.72, y: trough - height * 0.03),
                control2: CGPoint(x: width * 0.86, y: end - height * 0.15)
            )
            path.addLine(to: CGPoint(x: width, y: height))
            path.addLine(to: CGPoint(x: 0, y: height))
            path.closeSubpath()
        }
    }
}

struct NativeHeader: View {
    let title: String
    var showsBack = true
    var circularBack = false
    var trailingIcon: String? = nil
    var onBack: (() -> Void)? = nil
    var onTrailing: (() -> Void)? = nil

    var body: some View {
        HStack {
            Group {
                if showsBack {
                    Button { onBack?() } label: {
                        ZStack {
                            if circularBack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.02, green: 0.13, blue: 0.29),
                                                Color.black.opacity(0.78)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.blue.opacity(0.34), lineWidth: 0.8)
                                    )
                            }

                            Image(systemName: "chevron.left")
                                .font(.system(size: circularBack ? 20 : 22, weight: .bold))
                                .foregroundStyle(Color(red: 0.34, green: 0.70, blue: 1.0))
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }

            Spacer()

            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Group {
                if let trailingIcon {
                    Button { onTrailing?() } label: {
                        Circle()
                            .fill(Color.white.opacity(0.055))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: trailingIcon)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.cyan)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(onTrailing == nil)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
        }
        .foregroundStyle(.white)
    }
}

private struct NativeWordmark: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Clarity").foregroundStyle(.white)
            Text("Video").foregroundStyle(ClarityNativeTheme.brand)
        }
        .font(.system(size: 32, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.85)
        .lineLimit(1)
    }
}

private struct NativeActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ClarityIconTile(icon: icon, size: 60, iconSize: 25)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.50))
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        }
        .buttonStyle(ClarityPressStyle(pressedScale: 0.992))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(ClarityNativeTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(ClarityNativeTheme.border, lineWidth: 1)
                )
                .shadow(color: Color.blue.opacity(0.18), radius: 18, y: 8)
        )
    }
}

struct ReferenceHomeView: View {
    @Environment(AppState.self) private var state
    @State private var showingSettings = false
    @State private var showingProjects = false
    @State private var showingQuality = false

    var body: some View {
        ZStack {
            ClarityScreenBackdrop()

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                    HStack {
                        roundTopButton(icon: "gearshape.fill", accessibility: "Settings") {
                            showingSettings = true
                        }

                        Spacer()

                        roundTopButton(icon: "crown.fill", accessibility: "Quality Settings", usesBrand: true) {
                            showingQuality = true
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    NativeWordmark()
                        .padding(.top, 10)

                    Text("Sharper.  Clearer.  Better.")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.top, 5)

                    VStack(spacing: 12) {
                        NativeActionCard(
                            icon: "video.fill",
                            title: "Enhance Video",
                            subtitle: "Import from Photos, Files or Camera"
                        ) {
                            state.route = .importVideo
                        }

                        NativeActionCard(
                            icon: "clock.fill",
                            title: "Recent Projects",
                            subtitle: "Continue your work"
                        ) {
                            showingProjects = true
                        }

                        NativeActionCard(
                            icon: "gearshape.fill",
                            title: "Settings",
                            subtitle: "Quality, export and advanced options"
                        ) {
                            showingSettings = true
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 22)

                    ZStack(alignment: .bottom) {
                        if let mountain = ClarityArt.mountain {
                            Image(uiImage: mountain)
                                .resizable()
                                .scaledToFill()
                        } else {
                            LinearGradient(
                                colors: [Color.blue.opacity(0.60), Color.black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .overlay(
                                Image(systemName: "mountain.2.fill")
                                    .font(.system(size: 72))
                                    .foregroundStyle(.white.opacity(0.16))
                            )
                        }

                        LinearGradient(
                            colors: [
                                .clear,
                                ClarityNativeTheme.background.opacity(0.10),
                                ClarityNativeTheme.background.opacity(0.94)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        Text("TURN GOOD FOOTAGE\nINTO GREAT MEMORIES.")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .tracking(3.5)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.94))
                            .padding(.bottom, 38)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 255)
                    .clipped()
                    .padding(.top, 16)
                    }
                    // A vertical ScrollView otherwise lets padded children choose
                    // an oversized ideal width. Pinning the content to the viewport
                    // keeps the top controls and cards inside the physical display.
                    .frame(width: proxy.size.width)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { homeTabBar }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
                .environment(state)
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showingProjects) {
            ClarityProjectsView()
                .environment(state)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingQuality) {
            ClarityQualitySheet()
                .environment(state)
                .preferredColorScheme(.dark)
        }
    }

    private func roundTopButton(
        icon: String,
        accessibility: String,
        usesBrand: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.13, blue: 0.29),
                            Color(red: 0.01, green: 0.03, blue: 0.09)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)
                .overlay(
                    Circle()
                        .stroke(
                            usesBrand
                                ? AnyShapeStyle(ClarityNativeTheme.brand)
                                : AnyShapeStyle(Color.cyan.opacity(0.34)),
                            lineWidth: 0.9
                        )
                )
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(
                            usesBrand
                                ? AnyShapeStyle(ClarityNativeTheme.brand)
                                : AnyShapeStyle(Color(red: 0.66, green: 0.91, blue: 1.0))
                        )
                )
                .shadow(
                    color: usesBrand ? Color.purple.opacity(0.30) : Color.cyan.opacity(0.18),
                    radius: 10
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private var homeTabBar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.005, green: 0.025, blue: 0.065).opacity(0.99),
                            ClarityNativeTheme.background.opacity(0.99)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.28), Color.purple.opacity(0.18)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 0.8
                        )
                )

            HStack(spacing: 0) {
                tab(icon: "house.fill", title: "Home", selected: true) {}
                tab(icon: "folder.fill", title: "Projects") { showingProjects = true }
                Color.clear.frame(width: 84)
                tab(icon: "bolt.fill", title: "Tools") { state.showDiagnostics = true }
                tab(icon: "gearshape.fill", title: "Settings") { showingSettings = true }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 7)

            Button { state.route = .importVideo } label: {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.33, blue: 0.86),
                                Color(red: 0.26, green: 0.12, blue: 0.76)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                    .overlay(Circle().stroke(Color.cyan.opacity(0.95), lineWidth: 2))
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Color(red: 0.70, green: 0.91, blue: 1.0))
                    )
                    .shadow(color: .blue.opacity(0.65), radius: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Enhance Video")
            .offset(y: -15)
        }
        .frame(height: 82)
        .padding(.horizontal, 1)
    }

    private func tab(
        icon: String,
        title: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(selected ? Color.cyan : Color.white.opacity(0.56))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private enum ImportSource: String, CaseIterable, Identifiable {
    case photos = "Photos", files = "Files", camera = "Camera"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .photos: "photo.on.rectangle"
        case .files: "doc.fill"
        case .camera: "camera.fill"
        }
    }
}

private enum ImportFilter: String, CaseIterable, Identifiable {
    case all = "All", videos = "Videos", favorites = "Favorites", recents = "Recents"
    var id: String { rawValue }
}

struct ClarityQualitySheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ClarityScreenBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Quality")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Your default enhancement setup")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundStyle(ClarityNativeTheme.muted)
                        }

                        Spacer()

                        ClarityPillButton(title: "Done") { dismiss() }
                    }

                    NativePanel {
                        VStack(spacing: 0) {
                            qualityRow(
                                icon: "sparkles",
                                title: "Enhancement Mode",
                                options: QualityPreset.allCases.map(\.rawValue),
                                selected: state.configuration.qualityPreset.rawValue
                            ) { value in
                                guard let preset = QualityPreset(rawValue: value) else { return }
                                state.configuration.applyPreset(
                                    preset,
                                    temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
                                )
                            }

                            divider

                            qualityRow(
                                icon: "4k.tv.fill",
                                title: "Target Resolution",
                                options: state.capabilities.supports8KHEVCEncode ? ["4K", "8K"] : ["4K"],
                                selected: state.configuration.resolution == .uhd8K ? "8K" : "4K"
                            ) { value in
                                state.configuration.resolution = value == "8K" ? .uhd8K : .uhd4K
                                if state.configuration.resolution == .uhd8K {
                                    state.configuration.codec = .hevc
                                }
                                state.configuration.clampBitrateToSupportedRange()
                            }

                            divider

                            qualityRow(
                                icon: "brain.head.profile",
                                title: "AI Upscaler",
                                options: IOSNeuralHeadService.bundledModelURL() == nil
                                    ? ["Apple SR"]
                                    : ["Apple SR", "DLSS 5"],
                                selected: state.configuration.upscaler == .dlss5 ? "DLSS 5" : "Apple SR"
                            ) { value in
                                state.configuration.upscaler = value == "DLSS 5" ? .dlss5 : .appleSR
                            }
                        }
                        .padding(.horizontal, 14)
                    }

                    HStack(spacing: 12) {
                        ClarityIconTile(icon: "lock.shield.fill", size: 42, iconSize: 16)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Applied to new enhancements")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("You can still change these controls for each video in Enhance.")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(ClarityNativeTheme.muted)
                        }
                    }
                }
                .padding(20)
            }
        }
        .presentationDetents([.height(430), .medium])
        .presentationDragIndicator(.visible)
    }

    private func qualityRow(
        icon: String,
        title: String,
        options: [String],
        selected: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                ClarityIconTile(icon: icon, size: 38, iconSize: 15)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            NativeChoiceRow(options: options, selected: selected, select: onSelect)
        }
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.7)
    }
}

struct ClarityProjectsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ClarityScreenBackdrop()

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recent Projects")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.80)
                        .lineLimit(1)

                    Spacer(minLength: 14)

                    ClarityPillButton(title: "Done") { dismiss() }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                if state.recentJobs.isEmpty {
                    ZStack {
                        VStack {
                            Spacer()
                            ClarityWaveDecoration()
                                .frame(height: 250)
                        }
                        .ignoresSafeArea(edges: .bottom)

                        VStack(spacing: 18) {
                            Spacer()

                            ClarityIconTile(icon: "film.fill", size: 96, iconSize: 40)

                            Text("No recent projects")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Spacer()
                            Spacer()
                        }
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 11) {
                            ForEach(state.recentJobs) { job in
                                Button {
                                    if job.status == .paused {
                                        state.resume(job)
                                    } else if job.status == .completed, job.outputURL != nil {
                                        state.activeJob = job
                                        state.route = .results
                                    }
                                    dismiss()
                                } label: {
                                    HStack(spacing: 14) {
                                        ClarityIconTile(
                                            icon: job.status == .paused ? "pause.fill" : "film.fill",
                                            size: 56,
                                            iconSize: 21
                                        )

                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(job.assetInfo.fileName)
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)

                                            Text(
                                                (job.configuration.resolution == .uhd8K ? "8K" : "4K")
                                                + " · "
                                                + (job.configuration.upscaler == .dlss5 ? "DLSS 5" : "Apple SR")
                                                + " · "
                                                + job.status.rawValue.capitalized
                                            )
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(ClarityNativeTheme.muted)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white.opacity(0.40))
                                    }
                                    .padding(14)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        state.deleteRecentJob(job)
                                    } label: {
                                        Label("Delete Project", systemImage: "trash")
                                    }
                                }
                                .accessibilityAction(named: "Delete Project") {
                                    state.deleteRecentJob(job)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(ClarityNativeTheme.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(ClarityNativeTheme.border, lineWidth: 0.8)
                                        )
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 28)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#if targetEnvironment(simulator)
struct ReferenceImportSnapshotView: View {
    @Environment(AppState.self) private var state
    @State private var selection = 4

    private let grid = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        ZStack {
            ClarityScreenBackdrop()

            VStack(spacing: 12) {
                NativeHeader(title: "Import Video", onBack: { state.route = .home })
                    .padding(.horizontal, 14)

                HStack(spacing: 8) {
                    snapshotSource("Photos", icon: "photo.on.rectangle.angled", selected: true)
                    snapshotSource("Files", icon: "doc.fill", selected: false)
                    snapshotSource("Camera", icon: "camera.fill", selected: false)
                }
                .padding(5)
                .background(
                    Color.white.opacity(0.025),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .padding(.horizontal, 16)

                HStack(spacing: 7) {
                    snapshotFilter("All", selected: true)
                    snapshotFilter("Videos", selected: false)
                    snapshotFilter("Favorites", selected: false)
                    snapshotFilter("Recents", selected: false)
                }
                .padding(.horizontal, 16)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: grid, spacing: 6) {
                        ForEach(Array(NativeSnapshotVideo.samples.enumerated()), id: \.offset) { index, item in
                            Button { selection = index } label: {
                                NativeSnapshotVideoThumbnail(item: item, selected: selection == index)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                let item = NativeSnapshotVideo.samples[selection]

                NativePanel {
                    HStack(spacing: 12) {
                        NativeSnapshotVideoThumbnail(item: item, selected: false)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("1 video selected")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Text(item.duration + " total")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(ClarityNativeTheme.muted)
                        }

                        Spacer()

                        Text("Clear")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.18))
                                    .overlay(Capsule().stroke(Color.blue.opacity(0.42), lineWidth: 0.8))
                            )
                    }
                    .padding(12)
                }
                .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    ClarityNativeTheme.brand,
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .shadow(color: Color.blue.opacity(0.25), radius: 15, y: 6)
                .padding(.horizontal, 16)
            }
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(ClarityNativeTheme.background.opacity(0.97))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.cyan.opacity(0.10)).frame(height: 0.7)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func snapshotSource(_ title: String, icon: String, selected: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                selected
                    ? AnyShapeStyle(ClarityNativeTheme.brand)
                    : AnyShapeStyle(Color.white.opacity(0.055)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected ? Color.cyan.opacity(0.65) : Color.white.opacity(0.06),
                        lineWidth: 0.8
                    )
            )
    }

    private func snapshotFilter(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                selected
                    ? AnyShapeStyle(ClarityNativeTheme.brand)
                    : AnyShapeStyle(Color.white.opacity(0.05)),
                in: Capsule()
            )
    }
}
#endif

struct ReferenceImportVideoView: View {
    @Environment(AppState.self) private var state
    @State private var source: ImportSource = .photos
    @State private var filter: ImportFilter = .all
    @State private var assets: [PHAsset] = []
    @State private var selectedAsset: PHAsset?
    @State private var showingFiles = false
    @State private var showingCamera = false
    @State private var authorizationDenied = false
    private let grid = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        ZStack {
            ClarityScreenBackdrop()
            VStack(spacing: 12) {
                NativeHeader(title: "Import Video", onBack: { state.route = .home })
                    .padding(.horizontal, 14)

                sourceSelector.padding(.horizontal, 16)
                filterSelector.padding(.horizontal, 16)

                if authorizationDenied {
                    Spacer(minLength: 18)
                    importStateCard(
                        icon: "photo.badge.exclamationmark",
                        title: "Photos Access Needed",
                        detail: "Allow Photos access in Settings, or import a video from Files or Camera.",
                        actionTitle: "Open Settings"
                    ) {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .padding(.horizontal, 18)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        if filteredAssets.isEmpty {
                            importStateCard(
                                icon: "film.stack",
                                title: emptyLibraryTitle,
                                detail: emptyLibraryDetail,
                                actionTitle: "Choose from Files"
                            ) {
                                source = .files
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 28)
                        } else {
                            LazyVGrid(columns: grid, spacing: 6) {
                                ForEach(filteredAssets, id: \.localIdentifier) { asset in
                                    Button { selectedAsset = asset } label: {
                                        NativeVideoThumbnail(
                                            asset: asset,
                                            selected: selectedAsset?.localIdentifier == asset.localIdentifier
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { selectionFooter }
        .preferredColorScheme(.dark)
        .task {
            await loadPhotoAssets()
        }
        .onChange(of: source) { _, newValue in
            if newValue == .files { showingFiles = true }
            if newValue == .camera { showingCamera = true }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.movie]) { result in
            source = .photos
            switch result {
            case .success(let url): Task { await state.importVideo(from: url, sourceLabel: "Files video") }
            case .failure(let error): state.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingCamera, onDismiss: { source = .photos }) {
            NativeVideoCameraPicker { url in
                showingCamera = false
                Task { await state.importVideo(from: url, sourceLabel: "Camera video") }
            } onCancel: {
                showingCamera = false
            }
            .ignoresSafeArea()
        }
        .overlay {
            if state.isImporting {
                ZStack {
                    Color.black.opacity(0.66)
                        .ignoresSafeArea()

                    NativePanel {
                        VStack(spacing: 14) {
                            ClarityIconTile(
                                icon: "arrow.down.circle.fill",
                                size: 54,
                                iconSize: 22
                            )

                            VStack(spacing: 5) {
                                Text("Preparing Video")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)

                                Text(state.importStatus ?? "Importing video…")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(ClarityNativeTheme.muted)
                                    .multilineTextAlignment(.center)
                            }

                            ProgressView()
                                .controlSize(.regular)
                                .tint(.cyan)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 22)
                    }
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 24)
                }
                .transition(.opacity)
                .zIndex(80)
            }
        }
    }

    private var sourceSelector: some View {
        HStack(spacing: 8) {
            ForEach(ImportSource.allCases) { item in
                Button { source = item } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            item == source
                                ? AnyShapeStyle(ClarityNativeTheme.brand)
                                : AnyShapeStyle(Color.white.opacity(0.055)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    item == source
                                        ? AnyShapeStyle(Color.cyan.opacity(0.65))
                                        : AnyShapeStyle(Color.white.opacity(0.06)),
                                    lineWidth: 0.8
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            Color.white.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
    }

    private var filterSelector: some View {
        HStack(spacing: 7) {
            ForEach(ImportFilter.allCases) { item in
                Button { filter = item } label: {
                    Text(item.rawValue)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            item == filter
                                ? AnyShapeStyle(ClarityNativeTheme.brand)
                                : AnyShapeStyle(Color.white.opacity(0.05)),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func importStateCard(
        icon: String,
        title: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        NativePanel {
            VStack(spacing: 14) {
                ClarityIconTile(icon: icon, size: 62, iconSize: 25)

                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(detail)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(ClarityNativeTheme.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            ClarityNativeTheme.brand,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
        }
    }

    private var emptyLibraryTitle: String {
        switch filter {
        case .favorites: "No Favorite Videos"
        case .recents: "No Recent Videos"
        case .all, .videos: "No Videos Found"
        }
    }

    private var emptyLibraryDetail: String {
        switch filter {
        case .favorites:
            "Favorite a video in Photos or choose one from Files."
        case .recents:
            "No videos from the last 30 days are available in Photos."
        case .all, .videos:
            "Your Photos library has no videos available to Clarity."
        }
    }

    private var filteredAssets: [PHAsset] {
        switch filter {
        case .favorites:
            return assets.filter(\.isFavorite)
        case .recents:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            return assets.filter { ($0.creationDate ?? .distantPast) >= cutoff }
        case .all, .videos:
            return assets
        }
    }

    private var selectionFooter: some View {
        VStack(spacing: 10) {
            if let selectedAsset {
                NativePanel {
                    HStack(spacing: 12) {
                        NativeVideoThumbnail(asset: selectedAsset, selected: false)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("1 Video Selected")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text(durationText(selectedAsset.duration) + " · Ready to enhance")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(ClarityNativeTheme.muted)
                        }

                        Spacer()

                        Button("Clear") {
                            self.selectedAsset = nil
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.18))
                                .overlay(Capsule().stroke(Color.blue.opacity(0.42), lineWidth: 0.8))
                        )
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                }
                .padding(.horizontal, 16)
            }

            Button {
                guard let selectedAsset else { return }
                Task {
                    do {
                        let url = try await NativePhotoAssetResolver.videoURL(for: selectedAsset)
                        await state.importVideo(from: url, sourceLabel: "Photos video")
                    } catch {
                        state.errorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    ClarityNativeTheme.brand,
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .shadow(color: Color.blue.opacity(0.25), radius: 15, y: 6)
                .opacity(selectedAsset != nil ? 1 : 0.42)
            }
            .buttonStyle(.plain)
            .disabled(selectedAsset == nil || state.isImporting)
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(ClarityNativeTheme.background.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.cyan.opacity(0.10)).frame(height: 0.7)
        }
    }

    @MainActor
    private func loadPhotoAssets() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            authorizationDenied = true
            return
        }
        authorizationDenied = false
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 90
        let result = PHAsset.fetchAssets(with: .video, options: options)
        var loaded: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in loaded.append(asset) }
        assets = loaded
    }

    private func durationText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#if targetEnvironment(simulator)
private struct NativeSnapshotVideo {
    let duration: String
    let symbol: String
    let accent: Color
    let mountain: Bool

    static let samples: [NativeSnapshotVideo] = [
        .init(duration: "0:12", symbol: "cloud.sun.fill", accent: .blue, mountain: true),
        .init(duration: "0:34", symbol: "building.2.fill", accent: .orange, mountain: false),
        .init(duration: "1:20", symbol: "water.waves", accent: .cyan, mountain: true),
        .init(duration: "0:08", symbol: "pawprint.fill", accent: .brown, mountain: false),
        .init(duration: "2:15", symbol: "mountain.2.fill", accent: .indigo, mountain: true),
        .init(duration: "0:45", symbol: "leaf.fill", accent: .green, mountain: false),
        .init(duration: "1:03", symbol: "figure.run", accent: .green, mountain: false),
        .init(duration: "0:27", symbol: "mountain.2.fill", accent: .yellow, mountain: true),
        .init(duration: "0:16", symbol: "sparkles", accent: .orange, mountain: false),
        .init(duration: "3:21", symbol: "building.columns.fill", accent: .blue, mountain: false),
        .init(duration: "0:39", symbol: "figure.equestrian.sports", accent: .brown, mountain: false),
        .init(duration: "1:17", symbol: "water.waves", accent: .cyan, mountain: true)
    ]
}

private struct NativeSnapshotVideoThumbnail: View {
    let item: NativeSnapshotVideo
    let selected: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if item.mountain, let mountain = ClarityArt.mountain {
                Image(uiImage: mountain)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [item.accent.opacity(0.70), Color.black.opacity(0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: item.symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                )
            }

            Text(item.duration)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(5)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.cyan, .blue)
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(selected ? Color.cyan : Color.white.opacity(0.08), lineWidth: selected ? 2 : 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Snapshot video, \(item.duration)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}
#endif

private struct NativeVideoThumbnail: View {
    let asset: PHAsset
    let selected: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(Color.white.opacity(0.06))
                        .overlay(ProgressView().tint(.cyan))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .clipped()

            Text(durationText(asset.duration))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(5)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.cyan, .blue)
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.cyan : Color.white.opacity(0.08), lineWidth: selected ? 2 : 1))
        .task(id: asset.localIdentifier) { await loadImage() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Video, \(durationText(asset.duration))")
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    @MainActor
    private func loadImage() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 360, height: 360),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result { image = result }
        }
    }

    private func durationText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private enum NativePhotoAssetResolver {
    static func videoURL(for asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(throwing: AppError.importFailedReason("Photos could not provide a local video file."))
                    return
                }
                continuation.resume(returning: urlAsset.url)
            }
        }
    }
}

struct ReferenceEditorView: View {
    @Environment(AppState.self) private var state
    @State private var beforePlayer: AVPlayer?
    @State private var afterPlayer: AVPlayer?
    @State private var reveal = 0.5
    @State private var isPlaying = false
    @State private var previewRefreshTask: Task<Void, Never>?
    @State private var showingStorageDetails = false

    var body: some View {
        ZStack {
            ClarityScreenBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 9) {
                    NativeHeader(title: "Enhance", onBack: { state.route = .importVideo })

                    previewShell

                    storageStatusCard

                    NativePanel {
                        VStack(alignment: .leading, spacing: 8) {
                            settingRow(title: "Target Resolution") {
                                resolutionControl
                            }

                            settingRow(title: "Enhancement Mode") {
                                qualityControl
                            }

                            settingRow(title: "AI Upscaler") {
                                upscalerControl
                            }

                            Divider().overlay(Color.white.opacity(0.06))

                            NativeValueSlider(
                                title: "Denoise",
                                value: Binding(
                                    get: { state.configuration.denoise },
                                    set: { state.configuration.denoise = $0 }
                                )
                            )

                            NativeValueSlider(
                                title: "Detail Recovery",
                                value: Binding(
                                    get: { state.configuration.detailRecovery },
                                    set: { state.configuration.detailRecovery = $0 }
                                )
                            )

                            NativeValueSlider(
                                title: "Sharpen",
                                value: Binding(
                                    get: { state.configuration.sharpening },
                                    set: { state.configuration.sharpening = $0 }
                                )
                            )
                        }
                        .padding(13)
                    }

                    if !canEnhance {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(capabilityMessage)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(Color.orange.opacity(0.22), lineWidth: 0.7)
                        )
                    }

                    Button {
                        pausePlayers()
                        state.route = .exportSetup
                    } label: {
                        HStack(spacing: 10) {
                            Text("Continue")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            canEnhance
                                ? AnyShapeStyle(ClarityNativeTheme.brand)
                                : AnyShapeStyle(Color.white.opacity(0.07)),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .shadow(color: canEnhance ? Color.blue.opacity(0.30) : .clear, radius: 16, y: 8)
                    }
                    .buttonStyle(ClarityPressStyle(pressedScale: 0.992))
                    .disabled(!canEnhance)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { configurePlayersAndPreview() }
        .onChange(of: state.comparisonPreview?.id) { _, _ in
            configurePlayersAndPreview()
        }
        .onChange(of: state.configuration) { _, _ in
            scheduleRealPreviewRefresh()
        }
        .onDisappear {
            previewRefreshTask?.cancel()
            pausePlayers()
        }
        .sheet(isPresented: $showingStorageDetails) {
            if let info = state.assetInfo {
                ClarityStorageDetailSheet(
                    breakdown: StorageEstimator.breakdown(
                        info: info,
                        configuration: state.configuration
                    ),
                    availableBytes: storageEstimate.available
                )
            }
        }
    }

    private var previewShell: some View {
        VStack(spacing: 0) {
            comparisonCanvas
                .frame(height: 205)

            playbackBar
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(Color.black.opacity(0.28))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ClarityNativeTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.blue.opacity(0.20), radius: 18, y: 9)
    }

    private var comparisonCanvas: some View {
        GeometryReader { geometry in
            let split = geometry.size.width * reveal

            ZStack(alignment: .leading) {
                comparisonLayer(player: afterPlayer ?? beforePlayer)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                comparisonLayer(player: beforePlayer)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(1, split))
                    }
                    .overlay(Color.black.opacity(0.12))

                Rectangle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 2)
                    .offset(x: split - 1)

                Circle()
                    .fill(Color(red: 0.03, green: 0.18, blue: 0.42))
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(Color.cyan.opacity(0.92), lineWidth: 1.5))
                    .overlay(
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.cyan)
                    )
                    .offset(x: split - 19, y: geometry.size.height / 2 - 19)

                VStack {
                    HStack {
                        Spacer()
                        Text(state.configuration.resolution == .uhd8K ? "8K" : "4K")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 9))
                    }
                    Spacer()
                }
                .padding(.top, 10)
                .padding(.trailing, 12)
                .allowsHitTesting(false)

                if state.isGeneratingPreview {
                    VStack(spacing: 9) {
                        ProgressView(value: state.previewProgress)
                            .tint(.cyan)
                            .frame(width: 150)
                        Text("Generating AI preview…")
                            .font(.caption.bold())
                    }
                    .padding(14)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let previewError = state.previewErrorMessage, !state.isGeneratingPreview {
                    Label("Preview unavailable", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .accessibilityLabel("Preview unavailable. " + previewError)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        reveal = max(0.05, min(0.95, value.location.x / max(1, geometry.size.width)))
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Before and after comparison")
            .accessibilityValue(String(Int((reveal * 100).rounded())) + " percent before")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: reveal = min(0.95, reveal + 0.10)
                case .decrement: reveal = max(0.05, reveal - 0.10)
                @unknown default: break
                }
            }
        }
    }

    @ViewBuilder
    private func comparisonLayer(player: AVPlayer?) -> some View {
        if let player {
            VideoPlayer(player: player).allowsHitTesting(false)
        } else if let mountain = ClarityArt.mountain {
            Image(uiImage: mountain).resizable().scaledToFill()
        } else {
            Rectangle().fill(Color.indigo.opacity(0.35))
        }
    }

    private var playbackBar: some View {
        HStack(spacing: 10) {
            Button {
                if isPlaying {
                    pausePlayers()
                } else {
                    beforePlayer?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                    afterPlayer?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                    beforePlayer?.play()
                    afterPlayer?.play()
                    isPlaying = true
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause preview" : "Play preview")

            Text("00:00")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))

            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.cyan)
                        .frame(width: 44, height: 4)
                }

            Text(
                state.comparisonPreview.map { durationLabel($0.selectedDurationSeconds) }
                ?? state.assetInfo?.durationText
                ?? "00:00"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.72))

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76))
        }
        .foregroundStyle(.white)
    }

    private var storageStatusCard: some View {
        let estimate = storageEstimate
        let enough = estimate.available.map { $0 >= estimate.required } ?? true

        return Button {
            showingStorageDetails = true
        } label: {
            HStack(spacing: 13) {
                Circle()
                    .fill(enough ? Color.green.opacity(0.78) : Color.orange.opacity(0.82))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: enough ? "checkmark" : "exclamationmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated temporary storage")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))

                    Text(storageDetail(required: estimate.required, available: estimate.available))
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.52))
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                (enough ? Color.green : Color.orange).opacity(0.18),
                                Color(red: 0.01, green: 0.05, blue: 0.09).opacity(0.98)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke((enough ? Color.green : Color.orange).opacity(0.50), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Storage estimate")
        .accessibilityValue(storageDetail(required: estimate.required, available: estimate.available))
        .accessibilityHint("Shows how the temporary storage estimate is calculated")
    }

    private var storageEstimate: (required: Int64, available: Int64?) {
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["CLARITY_UI_SNAPSHOT"] == "1",
           let info = state.assetInfo {
            return (
                StorageEstimator.requiredBytes(info: info, configuration: state.configuration),
                583_200_000
            )
        }
#endif
        guard let info = state.assetInfo else {
            return (0, try? StorageEstimator.availableBytes())
        }
        return (
            StorageEstimator.requiredBytes(info: info, configuration: state.configuration),
            try? StorageEstimator.availableBytes()
        )
    }

    private func storageDetail(required: Int64, available: Int64?) -> String {
        let requiredText = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
        guard let available else { return requiredText + " estimated" }
        return requiredText + " • Available "
            + ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
    }

    @ViewBuilder
    private func settingRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.80))
                .frame(width: 126, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            content()
        }
    }

    private var resolutionControl: some View {
        NativeChoiceRow(
            options: state.capabilities.supports8KHEVCEncode ? ["4K", "8K"] : ["4K"],
            selected: state.configuration.resolution == .uhd8K ? "8K" : "4K"
        ) { value in
            let next: OutputResolution = value == "8K" ? .uhd8K : .uhd4K
            state.configuration.resolution = next
            if next == .uhd8K, state.configuration.bitrateMbps < 55 {
                state.configuration.bitrateMbps = 70
                state.configuration.codec = .hevc
            } else if next == .uhd4K, state.configuration.bitrateMbps > 55 {
                state.configuration.bitrateMbps = 40
            }
        }
    }

    private var qualityControl: some View {
        NativeChoiceRow(
            options: QualityPreset.allCases.map(\.rawValue),
            selected: state.configuration.qualityPreset.rawValue
        ) { value in
            guard let preset = QualityPreset(rawValue: value) else { return }
            state.configuration.applyPreset(
                preset,
                temporalDenoiseAvailable: state.capabilities.temporalNoiseFilteringAvailable
            )
        }
    }

    private var upscalerControl: some View {
        NativeChoiceRow(
            options: IOSNeuralHeadService.bundledModelURL() == nil
                ? ["Apple SR"]
                : ["Apple SR", "DLSS 5"],
            selected: state.configuration.upscaler == .dlss5 ? "DLSS 5" : "Apple SR"
        ) { value in
            state.configuration.upscaler = value == "DLSS 5" ? .dlss5 : .appleSR
        }
    }

    private var canEnhance: Bool {
        let upscalerAvailable: Bool
        switch state.configuration.upscaler {
        case .appleSR:
            upscalerAvailable = state.capabilities.fullSuperResolutionAvailable
                || state.capabilities.lowLatencySuperResolutionAvailable
        case .dlss5:
            upscalerAvailable = IOSNeuralHeadService.bundledModelURL() != nil
        }

        let outputAvailable = state.configuration.resolution == .uhd8K
            ? state.capabilities.supports8KHEVCEncode
            : true

        return upscalerAvailable && outputAvailable
    }

    private var capabilityMessage: String {
        if state.configuration.resolution == .uhd8K,
           !state.capabilities.supports8KHEVCEncode {
            return "8K is unavailable on this device. Choose 4K to continue."
        }

        if state.configuration.upscaler == .dlss5,
           IOSNeuralHeadService.bundledModelURL() == nil {
            return "DLSS 5 is not installed in this build. Choose Apple SR."
        }

        return "Apple Super Resolution is unavailable on this device."
    }

    private func configurePlayersAndPreview() {
        pausePlayers()

        if let preview = state.comparisonPreview {
            beforePlayer = AVPlayer(url: preview.sourceURL)
            afterPlayer = AVPlayer(url: preview.enhancedURL)
            return
        }

        if let source = state.importedURL {
            beforePlayer = AVPlayer(url: source)
            afterPlayer = nil
            if !state.isGeneratingPreview {
                state.generateComparisonPreview()
            }
        } else {
            beforePlayer = nil
            afterPlayer = nil
        }
    }

    private func scheduleRealPreviewRefresh(immediate: Bool = false) {
        guard state.importedURL != nil else { return }

        previewRefreshTask?.cancel()
        state.cancelComparisonPreview()
        state.comparisonPreview = nil
        afterPlayer?.pause()
        afterPlayer = nil

        previewRefreshTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard !Task.isCancelled else { return }
            state.generateComparisonPreview()
        }
    }

    private func pausePlayers() {
        beforePlayer?.pause()
        afterPlayer?.pause()
        isPlaying = false
    }

    private func durationLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct NativeChoiceRow: View {
    let options: [String]
    let selected: String
    let select: (String) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(options, id: \.self) { option in
                Button { select(option) } label: {
                    Text(option)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            option == selected
                                ? AnyShapeStyle(ClarityNativeTheme.brand)
                                : AnyShapeStyle(Color.white.opacity(0.055)),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    option == selected
                                        ? Color.cyan.opacity(0.42)
                                        : Color.white.opacity(0.035),
                                    lineWidth: 0.7
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Color.black.opacity(0.22),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
    }
}

private struct NativeValueSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 104, alignment: .leading)

            GeometryReader { geometry in
                let width = max(1, geometry.size.width)
                let clamped = max(0, min(1, value))
                let thumbX = max(7, min(width - 7, width * clamped))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 4)

                    Capsule()
                        .fill(ClarityNativeTheme.brand)
                        .frame(width: max(4, width * clamped), height: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.cyan.opacity(0.35), lineWidth: 0.8))
                        .shadow(color: .cyan.opacity(0.32), radius: 5)
                        .position(x: thumbX, y: 17)
                }
                .frame(height: 34)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            value = max(0, min(1, drag.location.x / width))
                        }
                )
                .accessibilityElement()
                .accessibilityLabel(title)
                .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: value = min(1, value + 0.05)
                    case .decrement: value = max(0, value - 0.05)
                    @unknown default: break
                    }
                }
            }
            .frame(height: 34)

            Text("\(Int((value * 100).rounded()))")
                .font(.caption.monospacedDigit())
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(minHeight: 36)
    }
}

struct ReferenceExportView: View {
    @Environment(AppState.self) private var state
    @State private var qualityIndex = 1
    @State private var showingStorageDetails = false

    var body: some View {
        ZStack {
            ClarityScreenBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    NativeHeader(title: "Export", onBack: { state.route = .editor })

                    videoSummary
                    storageStatus
                    exportSettings

                    Button { state.beginExport() } label: {
                        HStack(spacing: 10) {
                            Text(hasEnoughStorage ? "Start Export" : "More Storage Needed")
                            Image(systemName: hasEnoughStorage ? "arrow.right" : "internaldrive.fill.badge.exclamationmark")
                        }
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            hasEnoughStorage
                                ? AnyShapeStyle(ClarityNativeTheme.brand)
                                : AnyShapeStyle(Color.orange.opacity(0.18)),
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(
                                    hasEnoughStorage ? Color.cyan.opacity(0.20) : Color.orange.opacity(0.34),
                                    lineWidth: 0.8
                                )
                        )
                        .shadow(color: hasEnoughStorage ? Color.blue.opacity(0.28) : .clear, radius: 15, y: 7)
                    }
                    .buttonStyle(ClarityPressStyle(pressedScale: 0.992))
                    .disabled(!hasEnoughStorage)

                    Text("Keep Clarity open for fastest processing. Long exports keep checkpoints if iOS pauses them.")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 18)

                    NativePanel {
                        HStack(spacing: 13) {
                            ClarityIconTile(icon: "lock.shield.fill", size: 44, iconSize: 18)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("AI Powered. On Device.")
                                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                Text("Your original and enhanced video stay local unless you share them.")
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(ClarityNativeTheme.muted)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(13)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            state.configuration.clampBitrateToSupportedRange()
            qualityIndex = closestQualityIndex()
        }
        .sheet(isPresented: $showingStorageDetails) {
            if let info = state.assetInfo {
                ClarityStorageDetailSheet(
                    breakdown: StorageEstimator.breakdown(
                        info: info,
                        configuration: state.configuration
                    ),
                    availableBytes: try? StorageEstimator.availableBytes()
                )
            }
        }
    }

    private var hasEnoughStorage: Bool {
        guard let info = state.assetInfo else { return false }
        guard let available = try? StorageEstimator.availableBytes() else { return true }
        return available >= StorageEstimator.requiredBytes(
            info: info,
            configuration: state.configuration
        )
    }

    private var videoSummary: some View {
        let filename = state.assetInfo?.fileName ?? "My Video"
        let duration = state.assetInfo?.durationText ?? "00:00"
        let resolution = state.configuration.resolution == .uhd8K ? "8K" : "4K"
        let engine = state.configuration.upscaler == .dlss5 ? "DLSS 5" : "Apple SR"
        let metadata = duration + " · " + resolution + " · " + engine
        let finalSizeText: String? = state.assetInfo.map { info in
            let bytes = StorageEstimator.estimatedOutputBytes(
                info: info,
                configuration: state.configuration
            )
            return "~ "
                + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                + " final video"
        }

        return NativePanel {
            HStack(spacing: 13) {
                Group {
                    if let mountain = ClarityArt.mountain {
                        Image(uiImage: mountain)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(.indigo.opacity(0.3))
                    }
                }
                .frame(width: 78, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(filename)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)

                    Text(metadata)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.60))

                    if let finalSizeText {
                        Text(finalSizeText)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.cyan.opacity(0.76))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(13)
        }
    }

    private var storageStatus: some View {
        let required = state.assetInfo.map {
            StorageEstimator.requiredBytes(info: $0, configuration: state.configuration)
        } ?? 0
        let available = try? StorageEstimator.availableBytes()
        let enough = available.map { $0 >= required } ?? true

        return Button {
            showingStorageDetails = true
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(enough ? Color.green.opacity(0.78) : Color.orange.opacity(0.82))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: enough ? "checkmark" : "exclamationmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Temporary export storage")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))

                    Text(storageText(required: required, available: available))
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.50))
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                (enough ? Color.green : Color.orange).opacity(0.16),
                                Color(red: 0.01, green: 0.05, blue: 0.09).opacity(0.98)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke((enough ? Color.green : Color.orange).opacity(0.48), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Temporary export storage")
        .accessibilityValue(storageText(required: required, available: available))
        .accessibilityHint("Shows how the storage estimate is calculated")
    }

    private var exportSettings: some View {
        NativePanel {
            VStack(alignment: .leading, spacing: 13) {
                Text("Export Settings")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Divider().overlay(Color.white.opacity(0.07))

                settingLabel("Format")
                HStack(spacing: 5) {
                    exportChoice("HEVC (H.265)", selected: state.configuration.codec == .hevc) {
                        state.configuration.codec = .hevc
                    }

                    exportChoice(
                        "H.264",
                        selected: state.configuration.codec == .h264,
                        enabled: state.configuration.resolution == .uhd4K
                            && !(state.assetInfo?.isHDR ?? false)
                    ) {
                        state.configuration.codec = .h264
                    }
                }

                settingLabel("Quality")
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        let labels = ["Standard", "High", "Maximum"]
                        exportChoice(labels[index], selected: index == qualityIndex) {
                            setQuality(index)
                        }
                    }
                }

                nativeToggle(
                    "Preserve HDR when available",
                    isOn: Binding(
                        get: { state.configuration.hdrBehavior == .preserve },
                        set: {
                            state.configuration.hdrBehavior = $0 ? .preserve : .convertToSDR
                        }
                    )
                )

                nativeToggle(
                    "Save to Photos when finished",
                    isOn: Bindable(state).saveToPhotosAfterExport
                )
            }
            .padding(15)
        }
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
    }

    private func exportChoice(
        _ title: String,
        selected: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(enabled ? .white : .white.opacity(0.42))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    selected
                        ? AnyShapeStyle(ClarityNativeTheme.brand)
                        : AnyShapeStyle(Color.white.opacity(0.055)),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            selected ? Color.cyan.opacity(0.42) : Color.white.opacity(0.04),
                            lineWidth: 0.7
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func nativeToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            ClaritySwitchControl(isOn: isOn, accessibilityLabel: title)
        }
        .padding(.vertical, 2)
    }

    private func setQuality(_ index: Int) {
        qualityIndex = index
        let values = state.configuration.exportBitrateOptionsMbps
        guard values.indices.contains(index) else { return }
        state.configuration.bitrateMbps = values[index]
    }

    private func closestQualityIndex() -> Int {
        let values = state.configuration.exportBitrateOptionsMbps
        return values.enumerated().min {
            abs($0.element - state.configuration.bitrateMbps)
                < abs($1.element - state.configuration.bitrateMbps)
        }?.offset ?? 1
    }

    private func storageText(required: Int64, available: Int64?) -> String {
        let requiredText = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
        guard let available else { return requiredText + " estimated" }
        return requiredText
            + " • Available "
            + ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
    }
}

private struct NativeVideoCameraPicker: UIViewControllerRepresentable {
    let onResult: @MainActor (URL) -> Void
    let onCancel: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onResult: @MainActor (URL) -> Void
        let onCancel: @MainActor () -> Void

        init(onResult: @escaping @MainActor (URL) -> Void, onCancel: @escaping @MainActor () -> Void) {
            self.onResult = onResult
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in onCancel() }
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let url = info[.mediaURL] as? URL else {
                Task { @MainActor in onCancel() }
                return
            }
            Task { @MainActor in onResult(url) }
        }
    }
}
