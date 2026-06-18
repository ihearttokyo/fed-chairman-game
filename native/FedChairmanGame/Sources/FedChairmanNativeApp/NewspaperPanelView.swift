import FedChairmanCore
import SwiftUI

private let drawerCornerRadius: CGFloat = 18

struct NewspaperPanelView: View {
    var briefing: CockpitBriefing
    var layout: CockpitLayoutMetrics

    var body: some View {
        HStack(spacing: layout.mode == .compact ? 12 : 16) {
            if layout.mode != .compact {
                mastheadTile
            }
            briefingContent
            Spacer(minLength: 0)
            riskStack
        }
        .padding(layout.mode == .compact ? 10 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.26)))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }

    private var panelFill: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.15),
                        Color(red: 0.18, green: 0.16, blue: 0.12).opacity(0.24),
                        Color.black.opacity(0.18),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                )
                .clipShape(RoundedRectangle(cornerRadius: 18)),
            )
    }

    private var mastheadTile: some View {
        ZStack {
            if let image = NativeImageLoader.image(named: "newspaper-panel") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(0.72)
                    .brightness(-0.04)
                    .contrast(0.92)
                    .accessibilityHidden(true)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Spacer()
                Text("MANDATE")
                Text("DESK")
            }
            .font(.system(size: layout.mode == .compact ? 15 : 18, weight: .black, design: .serif))
            .foregroundStyle(.white.opacity(0.88))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(width: layout.mode == .compact ? 116 : 144)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }

    private var briefingContent: some View {
        VStack(alignment: .leading, spacing: layout.mode == .compact ? 6 : 8) {
            HStack(spacing: 8) {
                Text(layout.mode == .compact ? "Briefing" : "Latest Briefing")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.orange)
                Text(briefing.metadata)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.54))
            }
            .lineLimit(1)
            Text(briefing.headline)
                .font(.system(size: layout.mode == .compact ? 15 : 25, weight: .black, design: .rounded))
                .lineLimit(layout.mode == .compact ? 1 : 2)
                .minimumScaleFactor(0.82)
            if layout.mode != .compact {
                Text(briefing.body)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var riskStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            briefingChip("Risk", briefing.riskCalendar)
            briefingChip("Policy", briefing.policyImplication)
            if layout.mode != .compact {
                briefingChip("Watch", "Labor, credibility, lagged policy")
            }
        }
        .frame(width: layout.mode == .compact ? 300 : 310, alignment: .topLeading)
    }

    private func briefingChip(_ label: String, _ body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.52))
            Text(body)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(layout.mode == .compact ? 1 : 2)
        }
        .padding(layout.mode == .compact ? 7 : 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.10)))
    }
}

struct HelpDrawerView: View {
    var topics: [HelpTopic]
    var layout: CockpitLayoutMetrics

    private var primaryTopics: [HelpTopic] {
        topics.filter(\.isPrimary)
    }

    private var secondaryTopics: [HelpTopic] {
        topics.filter { !$0.isPrimary }
    }

    var body: some View {
        HStack(alignment: .center, spacing: layout.mode == .compact ? 10 : 14) {
            drawerHeader(
                systemName: "questionmark.circle.fill",
                eyebrow: "Policy Guide",
                title: "Chair's Notes",
                caption: "Economy, stance, lags.",
                tint: .green,
            )
            .frame(width: layout.mode == .compact ? 224 : 292, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(primaryTopics.prefix(3)) { topic in
                    SlimHelpChip(topic: topic, tint: .green)
                }
            }

            if layout.mode != .compact {
                HStack(spacing: 8) {
                    ForEach(secondaryTopics.prefix(3)) { topic in
                        SlimHelpChip(topic: topic, tint: .white.opacity(0.70))
                    }
                }
            }
        }
        .padding(.vertical, layout.mode == .compact ? 8 : 10)
        .padding(.horizontal, layout.mode == .compact ? 10 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(drawerPanelFill(tint: .green))
        .clipShape(RoundedRectangle(cornerRadius: drawerCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: drawerCornerRadius).stroke(.white.opacity(0.24)))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }
}

struct SettingsDrawerView: View {
    @Binding var reducedMotion: Bool
    @Binding var soundEnabled: Bool
    @Binding var reducedNoise: Bool

    var panelMessage: String?
    var layout: CockpitLayoutMetrics
    var save: () -> Void
    var load: () -> Void
    var exportCsv: () -> Void
    var exportJson: () -> Void
    var exportMarkdown: () -> Void

    private var exportColumnCount: Int {
        layout.mode == .compact ? 5 : 5
    }

    var body: some View {
        HStack(alignment: .center, spacing: layout.mode == .compact ? 10 : 12) {
            drawerHeader(
                systemName: "slider.horizontal.3",
                eyebrow: "Preferences",
                title: "Desk Setup",
                caption: "Feel, audio, records.",
                tint: .cyan,
            )
            .frame(width: layout.mode == .compact ? 218 : 276, alignment: .leading)

            HStack(spacing: 8) {
                SlimSettingsToggle(
                    title: "Motion",
                    systemName: "figure.walk.motion",
                    tint: .cyan,
                    isOn: $reducedMotion,
                )
                SlimSettingsToggle(
                    title: "Sound",
                    systemName: "speaker.wave.2.fill",
                    tint: .orange,
                    isOn: $soundEnabled,
                )
                SlimSettingsToggle(
                    title: "Noise",
                    systemName: "dial.low.fill",
                    tint: .mint,
                    isOn: $reducedNoise,
                )
            }

            HStack(spacing: 8) {
                drawerActionButton("Save", systemName: "square.and.arrow.down", action: save)
                drawerActionButton("Load", systemName: "folder", action: load)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: exportColumnCount - 2),
                    alignment: .leading,
                    spacing: 6,
                ) {
                    drawerActionButton("CSV", systemName: "tablecells", action: exportCsv)
                    drawerActionButton("JSON", systemName: "curlybraces", action: exportJson)
                    drawerActionButton("MD", systemName: "doc.plaintext", action: exportMarkdown)
                }
            }

            if let panelMessage {
                Label(panelMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .padding(.vertical, layout.mode == .compact ? 8 : 10)
        .padding(.horizontal, layout.mode == .compact ? 10 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(drawerPanelFill(tint: .cyan))
        .clipShape(RoundedRectangle(cornerRadius: drawerCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: drawerCornerRadius).stroke(.white.opacity(0.24)))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }
}

private struct SlimHelpChip: View {
    var topic: HelpTopic
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(topic.title)
                .font(.caption.weight(.black))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(topic.body)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(2)
                .minimumScaleFactor(0.84)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.16)))
    }
}

private struct SlimSettingsToggle: View {
    var title: String
    var systemName: String
    var tint: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.caption.weight(.black))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.14)))
    }
}

private func drawerHeader(systemName: String, eyebrow: String, title: String, caption: String, tint: Color) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 9) {
        Image(systemName: systemName)
            .font(.title3.weight(.bold))
            .foregroundStyle(tint)
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(tint.opacity(0.92))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
    }
}

private func drawerPanelFill(tint: Color) -> some View {
    RoundedRectangle(cornerRadius: drawerCornerRadius)
        .fill(.ultraThinMaterial)
        .overlay(
            LinearGradient(
                colors: [
                    .white.opacity(0.13),
                    tint.opacity(0.08),
                    .black.opacity(0.20),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
            .clipShape(RoundedRectangle(cornerRadius: drawerCornerRadius)),
        )
}

@MainActor
private func drawerActionButton(_ title: String, systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Label(title, systemImage: systemName)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.86))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.13)))
    }
    .buttonStyle(.plain)
}
