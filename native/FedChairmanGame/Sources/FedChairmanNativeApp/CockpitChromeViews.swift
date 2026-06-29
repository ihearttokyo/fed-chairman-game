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
        10
    case .standard:
        24
    case .expanded:
        28
    }
}

func dockPanelTopInset(_ layout: CockpitLayoutMetrics) -> Double {
    switch layout.mode {
    case .compact:
        layout.panelPadding + 8
    case .standard, .expanded:
        layout.panelPadding + layout.dockButtonHeight + 6
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
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }

    private var radius: CGFloat {
        tone == .keyboard ? 16 : 18
    }

    private var glassFill: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(
                LinearGradient(
                    colors: [
                        panelColors[0],
                        panelColors[0].opacity(0.68),
                        panelColors[1],
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                ),
            )
    }

    private var glassEdge: some View {
        RoundedRectangle(cornerRadius: radius)
            .stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(0.22),
                        toneGlow.opacity(0.09),
                        .white.opacity(0.055),
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
                Color(red: 0.21, green: 0.24, blue: 0.27).opacity(0.30),
                Color(red: 0.042, green: 0.056, blue: 0.062).opacity(0.70),
            ]
        case .instrument:
            [
                Color(red: 0.18, green: 0.20, blue: 0.20).opacity(0.34),
                Color(red: 0.030, green: 0.040, blue: 0.043).opacity(0.78),
            ]
        case .keyboard:
            [
                Color(red: 0.14, green: 0.19, blue: 0.17).opacity(0.38),
                Color(red: 0.024, green: 0.038, blue: 0.037).opacity(0.82),
            ]
        case .monitor:
            [
                Color(red: 0.15, green: 0.18, blue: 0.21).opacity(0.36),
                Color(red: 0.020, green: 0.030, blue: 0.035).opacity(0.82),
            ]
        }
    }
}

struct PolicyButtonStyle: ButtonStyle {
    var pulse: Bool
    var selected: Bool = false
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
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.green.opacity(0.88) : .white.opacity(configuration.isPressed ? 0.44 : 0.22), lineWidth: selected ? 2 : 1))
            .shadow(color: Color.green.opacity(selected ? 0.24 : (configuration.isPressed ? 0.12 : 0.05)), radius: selected ? 8 : (configuration.isPressed ? 5 : 3), y: configuration.isPressed ? 2 : 2)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.18 : 0.26), radius: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.92 : (pulse ? 1.025 : 1))
            .animation(.bouncy(duration: 0.12, extraBounce: 0.06), value: configuration.isPressed)
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
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(isOpen ? 0.22 : 0.12),
                                Color.cyan.opacity(isOpen ? 0.14 : 0.04),
                                Color.green.opacity(isOpen ? 0.08 : 0.02),
                                .black.opacity(0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        ),
                    ),
            )
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(isOpen ? 0.34 : 0.14)))
            .shadow(color: Color.cyan.opacity(isOpen ? 0.10 : 0.015), radius: isOpen ? 6 : 3, y: 2)
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
    }
}

struct DockIcon: View {
    var panel: CockpitDockPanel
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            iconPlate
        }
        .accessibilityElement(children: .ignore)
    }

    private var iconPlate: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.20), .white.opacity(0.06), .black.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing,
                    ),
                )
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

            if let image = NativeImageLoader.image(named: panel.iconName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                    .accessibilityHidden(true)
            } else {
                Text(String(panel.rawValue.prefix(1)))
                    .font(.system(size: compact ? 18 : 20, weight: .black, design: .rounded))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: compact ? 36 : 42, height: compact ? 36 : 42)
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
        if let image = candidateURLs.lazy.compactMap(NSImage.init(contentsOf:)).first {
            return image
        }
        #if SWIFT_PACKAGE
            if let packageURL = Bundle.module.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: packageURL)
            {
                return image
            }
        #endif
        return nil
    }
}
