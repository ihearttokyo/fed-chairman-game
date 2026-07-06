import FedChairmanCore
import SwiftUI

struct CockpitModeRailView: View {
    @Binding var selectedMode: CockpitMode
    var layout: CockpitLayoutMetrics

    var body: some View {
        let compact = layout.mode == .compact
        let expanded = layout.mode == .expanded

        return Group {
            if compact {
                HStack(spacing: 5) {
                    modeButtons(compact: compact, expanded: expanded)
                }
            } else {
                VStack(spacing: 8) {
                    modeButtons(compact: compact, expanded: expanded)
                    Spacer(minLength: 0)
                }
                .frame(width: expanded ? 158 : 136, alignment: .top)
            }
        }
        .padding(5)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.11)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cockpit-mode-rail")
    }

    private func modeButtons(compact: Bool, expanded: Bool) -> some View {
        ForEach(CockpitMode.allCases) { mode in
            let isSelected = selectedMode == mode
            Button {
                selectedMode = mode
            } label: {
                CockpitModeRailLabel(
                    mode: mode,
                    isSelected: isSelected,
                    compact: compact,
                    expanded: expanded,
                )
            }
            .buttonStyle(CockpitModeButtonStyle(
                isSelected: isSelected,
                compact: compact,
            ))
            .accessibilityLabel(mode.selectionAccessibilityLabel)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityIdentifier(mode.accessibilityIdentifier)
        }
    }
}

private struct CockpitModeRailLabel: View {
    var mode: CockpitMode
    var isSelected: Bool
    var compact: Bool
    var expanded: Bool

    var body: some View {
        HStack(spacing: compact ? 4 : 7) {
            Image(systemName: mode.systemImageName)
                .font(.system(size: compact ? 12 : 14, weight: .bold))
                .frame(width: compact ? 12 : 16)
                .foregroundStyle(isSelected ? Color.green : .white.opacity(0.68))
            VStack(alignment: .leading, spacing: 2) {
                Text(compact ? mode.shortTitle : mode.title)
                    .font(.system(size: compact ? 11 : 12, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if expanded {
                    Text(mode.shortTitle)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(isSelected ? 0.68 : 0.42))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CockpitModeButtonStyle: ButtonStyle {
    var isSelected: Bool
    var compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
            .padding(.vertical, compact ? 6 : 7)
            .padding(.horizontal, compact ? 7 : 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.green.opacity(configuration.isPressed ? 0.28 : 0.18) : Color.white.opacity(configuration.isPressed ? 0.08 : 0.035)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.green.opacity(0.42) : Color.white.opacity(0.10)),
            )
    }
}

private extension CockpitMode {
    var systemImageName: String {
        switch self {
        case .desk:
            "gauge.with.dots.needle.67percent"
        case .charts:
            "chart.xyaxis.line"
        case .records:
            "clock.arrow.circlepath"
        }
    }
}
