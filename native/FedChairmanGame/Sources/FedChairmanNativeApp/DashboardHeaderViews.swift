import FedChairmanCore
import SwiftUI

struct ChartInspectionStrip: View {
    var inspection: ChartInspection?
    var isInspecting: Bool
    var compact = false

    var body: some View {
        Group {
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

struct CompactDecisionPrompt: View {
    var feedback: DecisionFeedback

    var body: some View {
        HStack(spacing: 8) {
            Text(feedback.headline.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.green)
            Text(feedback.moveLabel)
                .font(.caption.weight(.black))
                .lineLimit(1)
            Text(feedback.mandateLine)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 30)
        .padding(.horizontal, 9)
        .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.green.opacity(0.22)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Decision prompt. \(feedback.headline). \(feedback.moveLabel). \(feedback.mandateLine).")
        .accessibilityIdentifier("decision-tape")
    }
}
