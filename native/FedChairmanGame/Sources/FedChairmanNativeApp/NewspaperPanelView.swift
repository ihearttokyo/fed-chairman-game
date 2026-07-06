import FedChairmanCore
import SwiftUI

private let drawerCornerRadius: CGFloat = 18

struct NewspaperPanelView: View {
    var briefing: CockpitBriefing
    var layout: CockpitLayoutMetrics

    var body: some View {
        HStack(spacing: layout.mode == .compact ? 12 : 18) {
            Text("THE MANDATE DESK")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
            if layout.mode != .compact {
                mastheadTile
            }
            briefingContent
            Spacer(minLength: 0)
            riskStack
        }
        .padding(layout.mode == .compact ? 10 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.26)))
        .shadow(color: .black.opacity(0.24), radius: 10, y: 6)
    }

    private var panelFill: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.19, green: 0.22, blue: 0.25).opacity(0.74),
                        Color(red: 0.14, green: 0.12, blue: 0.08).opacity(0.42),
                        Color(red: 0.05, green: 0.06, blue: 0.07),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                ),
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
                Text("THE MANDATE DESK")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.orange)
                Text(briefing.metadata)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.54))
            }
            .lineLimit(1)
            Text(briefing.headline)
                .font(.system(size: layout.mode == .compact ? 15 : 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(layout.mode == .compact ? 2 : 3)
                .minimumScaleFactor(0.82)
            if layout.mode != .compact {
                Text(briefing.body)
                    .font(.caption.weight(.semibold))
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
            if layout.mode == .expanded {
                briefingChip("Watch", "Labor, credibility, lagged policy")
            }
        }
        .frame(width: layout.mode == .compact ? 360 : 390, alignment: .topLeading)
    }

    private func briefingChip(_ label: String, _ body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.52))
            Text(body)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
        }
        .padding(layout.mode == .compact ? 9 : 11)
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

    private var secondaryColumnCount: Int {
        layout.isCompactNotebookLayout ? 1 : 3
    }

    private var primaryTopicColumns: Int {
        layout.isCompactNotebookLayout ? 1 : 3
    }

    var body: some View {
        Group {
            if layout.mode == .compact {
                compactBody
            } else if layout.isCompactNotebookLayout {
                compactDensityBody
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    drawerHeader(
                        systemName: "questionmark.circle.fill",
                        eyebrow: "Policy Guide",
                        title: "Policy Notebook",
                        caption: "Read the economy, pick a stance, then watch the lags.",
                        tint: .green,
                    )

                    HStack(alignment: .top, spacing: 8) {
                        ForEach(primaryTopics.prefix(3)) { topic in
                            HelpPrimaryTopicTile(topic: topic, compact: false)
                        }
                    }

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: secondaryColumnCount),
                        alignment: .leading,
                        spacing: 8,
                    ) {
                        ForEach(secondaryTopics.prefix(6)) { topic in
                            HelpTopicRow(topic: topic, compact: false)
                        }
                    }
                }
            }
        }
        .padding(layout.mode == .compact ? 10 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(drawerPanelFill(tint: .green))
        .clipShape(RoundedRectangle(cornerRadius: drawerCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: drawerCornerRadius).stroke(.white.opacity(0.24)))
        .shadow(color: .black.opacity(0.24), radius: 10, y: 6)
    }

    private var compactBody: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 9) {
                drawerHeader(
                    systemName: "questionmark.circle.fill",
                    eyebrow: "Policy Guide",
                    title: "Policy Notebook",
                    caption: "Balance inflation, labor, and policy lags.",
                    tint: .green,
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8, alignment: .top),
                        GridItem(.flexible(), spacing: 8, alignment: .top),
                    ],
                    alignment: .leading,
                    spacing: 8,
                ) {
                    ForEach(primaryTopics.prefix(2)) { topic in
                        HelpPrimaryTopicTile(topic: topic, compact: true)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(secondaryTopics.prefix(6)) { topic in
                        HelpTopicRow(topic: topic, compact: false)
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var compactDensityBody: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                drawerHeader(
                    systemName: "questionmark.circle.fill",
                    eyebrow: "Policy Guide",
                    title: "Policy Notebook",
                    caption: "Read the economy, pick a stance, then watch the lags.",
                    tint: .green,
                )

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: primaryTopicColumns),
                    alignment: .leading,
                    spacing: 10,
                ) {
                    ForEach(primaryTopics.prefix(4)) { topic in
                        HelpPrimaryTopicTile(topic: topic, compact: false)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(secondaryTopics.prefix(8)) { topic in
                        HelpTopicRow(topic: topic, compact: false)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.never)
    }
}

struct SettingsDrawerView: View {
    @Binding var fastCommit: Bool
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
        content
            .padding(layout.mode == .compact ? 10 : 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white)
            .background(drawerPanelFill(tint: .cyan))
            .clipShape(RoundedRectangle(cornerRadius: drawerCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: drawerCornerRadius).stroke(.white.opacity(0.24)))
            .shadow(color: .black.opacity(0.24), radius: 10, y: 6)
    }

    @ViewBuilder
    private var content: some View {
        if layout.mode == .compact {
            compactContent
        } else {
            fullContent
        }
    }

    private var compactContent: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PREFERENCES")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.cyan)
                Text("Preferences")
                    .font(.headline.weight(.black))
                if let panelMessage {
                    Text(panelMessage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }
            }
            .frame(width: 112, alignment: .leading)

            HStack(spacing: 7) {
                compactToggle("Fast commit", isOn: $fastCommit)
                compactToggle("Motion", isOn: $reducedMotion)
                compactToggle("Sound", isOn: $soundEnabled)
                compactToggle("Noise", isOn: $reducedNoise)
            }

            HStack(spacing: 6) {
                drawerActionButton("Save", systemName: "square.and.arrow.down", action: save)
                drawerActionButton("Load", systemName: "folder", action: load)
                drawerActionButton("CSV", systemName: "tablecells", action: exportCsv)
                drawerActionButton("JSON", systemName: "curlybraces", action: exportJson)
                drawerActionButton("Markdown", systemName: "doc.plaintext", action: exportMarkdown)
            }
            .buttonStyle(.plain)
            .controlSize(.small)
        }
    }

    private var fullContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            drawerHeader(
                systemName: "slider.horizontal.3",
                eyebrow: "Preferences",
                title: "Preferences",
                caption: "Tune feel, audio, and portable records without leaving the cockpit.",
                tint: .cyan,
            )

            HStack(alignment: .top, spacing: 8) {
                SettingsToggleTile(
                    title: "Fast commit",
                    subtitle: "Numbers commit",
                    systemName: "return",
                    tint: .green,
                    isOn: $fastCommit,
                )
                SettingsToggleTile(
                    title: "Motion",
                    subtitle: "Quieter transitions",
                    systemName: "figure.walk.motion",
                    tint: .cyan,
                    isOn: $reducedMotion,
                )
                SettingsToggleTile(
                    title: "Sound",
                    subtitle: "Cockpit cues",
                    systemName: "speaker.wave.2.fill",
                    tint: .orange,
                    isOn: $soundEnabled,
                )
                SettingsToggleTile(
                    title: "Noise",
                    subtitle: "Reduced texture",
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
                    drawerActionButton("Markdown", systemName: "doc.plaintext", action: exportMarkdown)
                }
            }
            .buttonStyle(.plain)

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
    }

    private func compactToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.82))
            .accessibilityLabel(title)
            .accessibilityIdentifier("settings-toggle-\(settingsIdentifierSlug(title))")
    }
}

private struct HelpPrimaryTopicTile: View {
    var topic: HelpTopic
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topic.title)
                .font(.caption.weight(.black))
                .foregroundStyle(.green)
                .lineLimit(2)
            Text(topic.body)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(compact ? 4 : 3)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.green.opacity(0.18)))
    }
}

private struct HelpTopicRow: View {
    var topic: HelpTopic
    var compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(.white.opacity(0.42))
                .frame(width: 5, height: 5)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                Text(topic.body)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(compact ? 2 : 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct SettingsToggleTile: View {
    var title: String
    var subtitle: String
    var systemName: String
    var tint: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 7) {
                Image(systemName: systemName)
                    .font(.caption.weight(.black))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.54))
                        .lineLimit(1)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.10)))
        .accessibilityLabel(title)
        .accessibilityIdentifier("settings-toggle-\(settingsIdentifierSlug(title))")
    }
}

private func settingsIdentifierSlug(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: " ", with: "-")
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
        .fill(
            LinearGradient(
                colors: [
                    .white.opacity(0.12),
                    tint.opacity(0.12),
                    Color(red: 0.04, green: 0.06, blue: 0.07),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            ),
        )
}

private func drawerActionButton(_ title: String, systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Label(title, systemImage: systemName)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.86))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(.white.opacity(0.060), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.10)))
    }
}
