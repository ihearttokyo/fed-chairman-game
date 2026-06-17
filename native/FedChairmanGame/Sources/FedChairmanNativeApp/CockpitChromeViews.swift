import AppKit
import FedChairmanCore
import SwiftUI

struct CommandDeskBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.030, green: 0.034, blue: 0.034),
                Color(red: 0.070, green: 0.044, blue: 0.030),
                Color(red: 0.018, green: 0.030, blue: 0.030),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
        .ignoresSafeArea()
        .overlay {
            RadialGradient(colors: [Color.orange.opacity(0.16), .clear], center: .topLeading, startRadius: 30, endRadius: 540)
                .ignoresSafeArea()
        }
        .overlay {
            RadialGradient(colors: [Color.green.opacity(0.08), .clear], center: .bottomTrailing, startRadius: 80, endRadius: 760)
                .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.075, blue: 0.050).opacity(0.24),
                            Color(red: 0.022, green: 0.032, blue: 0.030).opacity(0.70),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .frame(height: 190)
                .blur(radius: 18)
                .ignoresSafeArea()
        }
    }
}

enum CommandPanelTone {
    case glass
    case instrument
    case keyboard
    case monitor
}

struct CommandPanel<Content: View>: View {
    var padding: CGFloat = 14
    var tone: CommandPanelTone = .glass
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: panelColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        ),
                    )
                    .overlay(
                        LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 8)),
                    ),
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.16)))
            .shadow(color: .black.opacity(0.30), radius: 10, y: 6)
    }

    private var panelColors: [Color] {
        switch tone {
        case .glass:
            [
                Color(red: 0.082, green: 0.060, blue: 0.046).opacity(0.94),
                Color(red: 0.022, green: 0.030, blue: 0.030).opacity(0.99),
            ]
        case .instrument:
            [
                Color(red: 0.070, green: 0.062, blue: 0.052).opacity(0.95),
                Color(red: 0.020, green: 0.028, blue: 0.028).opacity(1),
            ]
        case .keyboard:
            [
                Color(red: 0.078, green: 0.058, blue: 0.044).opacity(0.97),
                Color(red: 0.018, green: 0.026, blue: 0.026).opacity(1),
            ]
        case .monitor:
            [
                Color(red: 0.060, green: 0.056, blue: 0.050).opacity(0.96),
                Color(red: 0.012, green: 0.020, blue: 0.022).opacity(1),
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
                    .fill(.white.opacity(configuration.isPressed ? 0.06 : 0.12))
                    .frame(height: max(3, height * 0.22))
                    .padding(.horizontal, 3)
                    .padding(.top, 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(configuration.isPressed ? 0.30 : 0.16)))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.20 : 0.46), radius: configuration.isPressed ? 2 : 8, y: configuration.isPressed ? 1 : 6)
            .scaleEffect(configuration.isPressed ? 0.92 : (pulse ? 1.025 : 1))
            .animation(.bouncy(duration: 0.22, extraBounce: 0.24), value: configuration.isPressed)
            .animation(.bouncy(duration: 0.28, extraBounce: 0.18), value: pulse)
    }

    private func keyFill(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: configuration.isPressed
                        ? [Color(red: 0.10, green: 0.32, blue: 0.18), Color(red: 0.025, green: 0.060, blue: 0.045)]
                        : [Color(red: 0.095, green: 0.102, blue: 0.095), Color(red: 0.018, green: 0.020, blue: 0.020)],
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
                    .fill(Color(red: 0.032, green: 0.045, blue: 0.040).opacity(0.94))
                    .overlay(
                        LinearGradient(
                            colors: [
                                .white.opacity(isOpen ? 0.20 : 0.10),
                                Color.green.opacity(isOpen ? 0.16 : 0.04),
                                .black.opacity(0.18),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16)),
                    ),
            )
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(isOpen ? 0.30 : 0.14)))
            .shadow(color: Color.green.opacity(isOpen ? 0.18 : 0.03), radius: isOpen ? 12 : 5, y: 4)
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
                        colors: [.white.opacity(0.35), .white.opacity(0.08), .black.opacity(0.2)],
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
