import FedChairmanCore
import SwiftUI

struct BoardWatchRailView: View {
    var watch: BoardWatch
    var layout: CockpitLayoutMetrics

    var body: some View {
        HStack(spacing: layout.mode == .compact ? 6 : 9) {
            VStack(alignment: .leading, spacing: 1) {
                Text("BOARD WATCH")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(toneColor)
                Text(watch.headline)
                    .font(.caption2.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Divider()
                .frame(height: layout.mode == .compact ? 24 : 30)
                .overlay(.white.opacity(0.13))
            VStack(alignment: .leading, spacing: 1) {
                Text(watch.scoreLabel)
                    .font(.caption.weight(.black))
                    .monospacedDigit()
                Text(watch.gateLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
            }
            if layout.mode != .compact {
                Divider()
                    .frame(height: 30)
                    .overlay(.white.opacity(0.13))
                VStack(alignment: .leading, spacing: 1) {
                    Text(watch.riskLabel)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                    Text("\(watch.quartersRemaining) quarters to gate")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.50))
                }
                .frame(maxWidth: 180, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, layout.mode == .compact ? 8 : 10)
        .frame(width: layout.mode == .compact ? 214 : 390, alignment: .leading)
        .background(toneColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(toneColor.opacity(0.25)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(watch.accessibilityLabel)
        .accessibilityIdentifier("board-watch")
    }

    private var toneColor: Color {
        switch watch.tone {
        case .onTrack, .complete:
            .green
        case .watch:
            .orange
        case .danger:
            .red
        }
    }
}

struct ChartInspectionStrip: View {
    var inspection: ChartInspection?
    var isInspecting: Bool
    var compact = false

    var body: some View {
        if let inspection {
            VStack(alignment: .leading, spacing: compact ? 0 : 5) {
                HStack(spacing: 10) {
                    Text(isInspecting ? "INSPECTING" : "LATEST")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.green)
                    Text(inspection.primaryLabel)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .accessibilityIdentifier("chart-inspection-primary")
                    Text(inspection.secondaryLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    inspectionStat("INF", inspection.inflation, .orange)
                    inspectionStat("U", inspection.unemployment, .blue)
                    inspectionStat("FFR", inspection.fedFunds, .green)
                    inspectionStat("CRED", inspection.credibility, .yellow)
                }
                if !compact {
                    HStack(spacing: 10) {
                        Text(inspection.policy)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                            .accessibilityIdentifier("chart-inspection-policy")
                        Text(inspection.movement)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                } else {
                    Text(inspection.policy)
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .accessibilityIdentifier("chart-inspection-policy")
                }
            }
            .padding(.vertical, compact ? 5 : 8)
            .padding(.horizontal, compact ? 8 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.070), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.16)))
        }
    }

    private func inspectionStat(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.black))
                .foregroundStyle(color)
            Text(value)
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.78))
        }
    }
}

struct MandateInsightBand: View {
    var focus: MandateChartFocus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("CHART READ")
                .font(.caption2.weight(.black))
                .foregroundStyle(.green)
            Text(focus.insightHeadline)
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
            Text(focus.insightDetail)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("Targets: INF 2.0% | U 5.0%")
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(focus.accessibilityLabel)
        .accessibilityIdentifier("mandate-chart-insight-band")
    }
}

struct CurrentValueRailView: View {
    var focus: MandateChartFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT")
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.52))
            ForEach(focus.railItems) { item in
                railRow(item)
            }
        }
        .padding(10)
        .frame(width: 214, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("current-value-rail")
    }

    private func railRow(_ item: MandateChartRailItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.label.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(metricColor(item.metric))
                Spacer()
                Text(item.value)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.88))
                    .monospacedDigit()
            }
            HStack {
                Text(item.target)
                Spacer()
                Text(item.gap)
                    .foregroundStyle(stateColor(item.state))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.52))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(stateColor(item.state).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(stateColor(item.state).opacity(0.16)))
    }

    private func metricColor(_ metric: MandateChartRailItem.Metric) -> Color {
        switch metric {
        case .inflation:
            .orange
        case .unemployment:
            .blue
        case .fedFunds:
            .green
        case .credibility:
            .yellow
        }
    }

    private func stateColor(_ state: SemanticState) -> Color {
        switch state {
        case .onTrack:
            .green
        case .atRisk:
            .orange
        case .critical:
            .red
        case .disabled:
            .gray
        case .neutral:
            .white.opacity(0.55)
        }
    }
}

struct MandateBadge: View {
    var label: String
    var value: Double
    var target: Double
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(color)
            Text(value, format: .number.precision(.fractionLength(label == "Credibility" ? 0 : 2)))
                .font(.system(size: 18, weight: .black, design: .rounded))
            Text("Target \(target, format: .number.precision(.fractionLength(label == "Credibility" ? 0 : 1)))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(width: 104, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.22)))
        .shadow(color: color.opacity(0.08), radius: 10, y: 4)
    }
}

struct MandateMetricCard: View {
    var label: String
    var value: Double
    var target: String
    var suffix: String
    var color: Color
    var layout: CockpitLayoutMetrics

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                Text(target)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.40))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(value, format: .number.precision(.fractionLength(suffix.isEmpty ? 0 : 2)))\(suffix)")
                .font(.system(size: layout.mode == .compact ? 18 : 22, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: layout.mode == .compact ? 42 : 50, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.16)))
    }
}

struct CompactQuarterReview: View {
    var transmission: TransmissionBriefing

    var body: some View {
        HStack(spacing: 10) {
            Text("REVIEW")
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.58))
            Text(transmission.receipt.headline)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(toneColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Divider()
                .frame(height: 28)
                .overlay(.white.opacity(0.16))
            Text(transmission.summary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.70))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toneColor: Color {
        switch transmission.receipt.tone {
        case .cooling:
            .cyan
        case .heating:
            .orange
        case .stabilizing:
            .green
        case .stress:
            .red
        }
    }
}
