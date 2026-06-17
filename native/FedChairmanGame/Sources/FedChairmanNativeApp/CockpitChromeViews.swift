import AppKit
import FedChairmanCore
import SwiftUI

struct CommandDeskBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.029, blue: 0.036),
                    Color(red: 0.038, green: 0.051, blue: 0.058),
                    Color(red: 0.018, green: 0.024, blue: 0.025),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
            LinearGradient(
                colors: [
                    Color(red: 0.28, green: 0.38, blue: 0.52).opacity(0.26),
                    .clear,
                    Color(red: 0.08, green: 0.30, blue: 0.25).opacity(0.18),
                ],
                startPoint: .top,
                endPoint: .bottomTrailing,
            )
            Rectangle()
                .fill(.black.opacity(0.22))
                .blendMode(.multiply)
        }
        .ignoresSafeArea()
    }
}

enum CommandPanelTone {
    case glass
    case instrument
    case keyboard
    case monitor
}

func cockpitContentTopInset(_ layout: CockpitLayoutMetrics) -> Double {
    switch layout.mode {
    case .compact:
        62
    case .standard:
        94
    case .expanded:
        100
    }
}

func dockPanelTopInset(_ layout: CockpitLayoutMetrics) -> Double {
    switch layout.mode {
    case .compact:
        layout.panelPadding + 10
    case .standard, .expanded:
        layout.panelPadding + layout.dockButtonHeight + 8
    }
}

struct CommandPanel<Content: View>: View {
    var padding: CGFloat = 14
    var tone: CommandPanelTone = .glass
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .foregroundStyle(.white)
            .background(glassFill)
            .overlay(glassEdge)
            .shadow(color: .black.opacity(0.38), radius: 18, y: 10)
            .shadow(color: toneGlow.opacity(0.12), radius: 18, y: 3)
    }

    private var radius: CGFloat {
        tone == .keyboard ? 14 : 12
    }

    private var glassFill: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .fill(
                        LinearGradient(
                            colors: panelColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        ),
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.18),
                                .white.opacity(0.035),
                                .black.opacity(0.20),
                            ],
                            startPoint: .top,
                            endPoint: .bottom,
                        ),
                    )
            }
    }

    private var glassEdge: some View {
        RoundedRectangle(cornerRadius: radius)
            .stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(0.34),
                        toneGlow.opacity(0.20),
                        .white.opacity(0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                ),
                lineWidth: 1,
            )
    }

    private var toneGlow: Color {
        switch tone {
        case .glass:
            Color.cyan
        case .instrument:
            Color.mint
        case .keyboard:
            Color.green
        case .monitor:
            Color.blue
        }
    }

    private var panelColors: [Color] {
        switch tone {
        case .glass:
            [
                Color(red: 0.18, green: 0.22, blue: 0.25).opacity(0.40),
                Color(red: 0.035, green: 0.052, blue: 0.058).opacity(0.82),
            ]
        case .instrument:
            [
                Color(red: 0.16, green: 0.18, blue: 0.19).opacity(0.46),
                Color(red: 0.024, green: 0.036, blue: 0.040).opacity(0.90),
            ]
        case .keyboard:
            [
                Color(red: 0.12, green: 0.18, blue: 0.16).opacity(0.52),
                Color(red: 0.020, green: 0.035, blue: 0.034).opacity(0.94),
            ]
        case .monitor:
            [
                Color(red: 0.13, green: 0.17, blue: 0.20).opacity(0.50),
                Color(red: 0.015, green: 0.025, blue: 0.030).opacity(0.94),
            ]
        }
    }
}

struct PolicyButtonStyle: ButtonStyle {
    var pulse: Bool
    var width: CGFloat
    var height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .black, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: width, height: height)
            .background(keyFill(configuration: configuration))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(configuration.isPressed ? 0.10 : 0.20))
                    .frame(height: max(3, height * 0.22))
                    .padding(.horizontal, 3)
                    .padding(.top, 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(configuration.isPressed ? 0.44 : 0.22)))
            .shadow(color: Color.green.opacity(configuration.isPressed ? 0.25 : 0.06), radius: configuration.isPressed ? 12 : 8, y: 4)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.20 : 0.42), radius: configuration.isPressed ? 2 : 8, y: configuration.isPressed ? 1 : 6)
            .scaleEffect(configuration.isPressed ? 0.92 : (pulse ? 1.025 : 1))
            .animation(.bouncy(duration: 0.22, extraBounce: 0.24), value: configuration.isPressed)
            .animation(.bouncy(duration: 0.28, extraBounce: 0.18), value: pulse)
    }

    private func keyFill(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: configuration.isPressed
                        ? [Color(red: 0.18, green: 0.42, blue: 0.30), Color(red: 0.030, green: 0.082, blue: 0.070)]
                        : [Color(red: 0.16, green: 0.18, blue: 0.18).opacity(0.92), Color(red: 0.030, green: 0.038, blue: 0.040).opacity(0.98)],
                    startPoint: .top,
                    endPoint: .bottom,
                ),
            )
    }
}

struct DockButtonStyle: ButtonStyle {
    var isOpen: Bool
    var width: CGFloat
    var height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [
                                .white.opacity(isOpen ? 0.30 : 0.18),
                                Color.cyan.opacity(isOpen ? 0.18 : 0.05),
                                Color.green.opacity(isOpen ? 0.16 : 0.04),
                                .black.opacity(0.20),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16)),
                    ),
            )
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(isOpen ? 0.48 : 0.22)))
            .shadow(color: Color.cyan.opacity(isOpen ? 0.22 : 0.04), radius: isOpen ? 18 : 8, y: 4)
            .shadow(color: .black.opacity(0.28), radius: 8, y: 5)
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .animation(.bouncy(duration: 0.28, extraBounce: 0.34), value: configuration.isPressed)
    }
}

struct DockIcon: View {
    var panel: CockpitDockPanel
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 0 : 7) {
            iconPlate
            if !compact {
                Text(panel.title)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: 82, height: 14)
                    .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
    }

    private var iconPlate: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [.white.opacity(0.46), .white.opacity(0.10), .black.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing,
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.3)))
                .shadow(color: .black.opacity(0.34), radius: 7, y: 4)

            if let image = NativeImageLoader.image(named: panel.iconName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 32 : 50, height: compact ? 32 : 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                    .accessibilityHidden(true)
            } else {
                Text(String(panel.rawValue.prefix(1)))
                    .font(.system(size: compact ? 18 : 24, weight: .black, design: .rounded))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: compact ? 38 : 58, height: compact ? 38 : 58)
    }
}

extension Double {
    var cg: CGFloat {
        CGFloat(self)
    }
}

enum NativeImageLoader {
    static func image(named name: String) -> NSImage? {
        if let image = NSImage(named: name) {
            return image
        }
        let candidateURLs = [
            Bundle.main.url(forResource: name, withExtension: "png"),
            Bundle.main.resourceURL?
                .appendingPathComponent("FedChairmanGame_FedChairmanNativeApp.bundle")
                .appendingPathComponent("\(name).png"),
            Bundle.main.bundleURL
                .appendingPathComponent("FedChairmanGame_FedChairmanNativeApp.bundle")
                .appendingPathComponent("\(name).png"),
        ].compactMap(\.self)
        #if SWIFT_PACKAGE
            if let packageURL = Bundle.module.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: packageURL)
            {
                return image
            }
        #endif
        return candidateURLs.lazy.compactMap(NSImage.init(contentsOf:)).first
    }
}
