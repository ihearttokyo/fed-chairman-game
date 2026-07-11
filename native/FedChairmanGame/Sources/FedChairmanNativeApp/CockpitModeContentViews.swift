import FedChairmanCore
import SwiftUI

struct PriorityRiskPanel: View {
    var snapshot: TermSnapshot
    var maxDrivers = 3

    var body: some View {
        CommandPanel(tone: .instrument) {
            VStack(alignment: .leading, spacing: 12) {
                ModePanelHeader(
                    eyebrow: "Priority Risk",
                    title: primaryDriver?.title ?? snapshot.boardWatch.headline,
                    detail: snapshot.boardWatch.riskLabel,
                    state: snapshot.semanticState,
                )

                VStack(spacing: 8) {
                    ForEach(Array(snapshot.riskDrivers.prefix(maxDrivers).enumerated()), id: \.element.id) { index, driver in
                        RiskDriverRow(rank: index + 1, driver: driver)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("priority-risk-panel")
    }

    private var primaryDriver: RiskDriver? {
        snapshot.riskDrivers.first
    }
}

struct MandateFocusContainer<Content: View>: View {
    var snapshot: TermSnapshot
    var title: String = "Mandate Focus"
    @ViewBuilder var content: Content

    var body: some View {
        CommandPanel(tone: .monitor) {
            VStack(alignment: .leading, spacing: 12) {
                ModePanelHeader(
                    eyebrow: "Mandate",
                    title: title,
                    detail: "Inflation \(percent(snapshot.latestMetrics.inflation)) | Unemployment \(percent(snapshot.latestMetrics.unemployment)) | Fed funds \(percent(snapshot.latestMetrics.fedFundsRate))",
                    state: snapshot.semanticState,
                )

                HStack(alignment: .top, spacing: 10) {
                    MandateFocusMetric(
                        label: "Inflation gap",
                        value: signedPoints(snapshot.latestMetrics.inflationGap),
                        state: gapState(snapshot.latestMetrics.inflationGap, warning: 0.8, critical: 1.4),
                    )
                    MandateFocusMetric(
                        label: "Labor gap",
                        value: signedPoints(snapshot.latestMetrics.laborGap),
                        state: gapState(snapshot.latestMetrics.laborGap, warning: 1.0, critical: 2.0),
                    )
                    MandateFocusMetric(
                        label: "Credibility",
                        value: String(format: "%.0f", snapshot.latestMetrics.credibility),
                        state: snapshot.latestMetrics.credibility >= 70 ? .onTrack : .atRisk,
                    )
                }

                content
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mandate-focus-container")
    }
}

struct TermHistorySummaryView: View {
    var snapshot: TermSnapshot

    var body: some View {
        CommandPanel(tone: .glass) {
            VStack(alignment: .leading, spacing: 12) {
                ModePanelHeader(
                    eyebrow: "History",
                    title: historyTitle,
                    detail: "Term \(snapshot.termNumber) | Q\(snapshot.currentTermQuarter) | Career Q\(snapshot.totalCareerQuarters)",
                    state: snapshot.semanticState,
                )

                VStack(alignment: .leading, spacing: 7) {
                    LabeledModeLine(label: "Board", text: "\(snapshot.boardWatch.scoreDetail); \(snapshot.boardWatch.gateLabel)", tint: stateColor(snapshot.semanticState))
                    LabeledModeLine(label: "Latest vote", text: "\(snapshot.decisionFeedback.moveLabel), \(snapshot.decisionFeedback.ratePath)", tint: decisionToneColor(snapshot.decisionFeedback.tone))
                    LabeledModeLine(label: "Mandate", text: snapshot.decisionFeedback.mandateLine, tint: .blue)
                    LabeledModeLine(label: "Trace", text: snapshot.decisionFeedback.traceLine, tint: .cyan)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("term-history-summary")
    }

    private var historyTitle: String {
        switch snapshot.status {
        case .termDebrief, .retired, .notReappointed:
            snapshot.boardWatch.headline
        case .notStarted, .inProgress:
            "Active term summary"
        }
    }
}

private struct ModePanelHeader: View {
    var eyebrow: String
    var title: String
    var detail: String
    var state: SemanticState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(stateColor(state))
                .frame(width: 5, height: 56)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(stateColor(state))
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }
        }
    }
}

private struct RiskDriverRow: View {
    var rank: Int
    var driver: RiskDriver

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(rank)")
                .font(.caption.monospacedDigit().weight(.black))
                .foregroundStyle(.black.opacity(0.72))
                .frame(width: 20, height: 20)
                .background(stateColor(driver.state), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(driver.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(driver.state.rawValue.uppercased())
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(stateColor(driver.state))
                }
                Text(driver.detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(stateColor(driver.state).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(stateColor(driver.state).opacity(0.18)))
    }
}

private struct LabeledModeLine: View {
    var label: String
    var text: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(tint)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MandateFocusMetric: View {
    var label: String
    var value: String
    var state: SemanticState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(stateColor(state))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(stateColor(state).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(stateColor(state).opacity(0.16)))
    }
}

private func semanticState(for severity: BriefingSeverity) -> SemanticState {
    switch severity {
    case .normal:
        .neutral
    case .watch:
        .onTrack
    case .warning:
        .atRisk
    case .critical:
        .critical
    }
}

private func gapState(_ gap: Double, warning: Double, critical: Double) -> SemanticState {
    let distance = abs(gap)
    if distance >= critical {
        return .critical
    }
    if distance >= warning {
        return .atRisk
    }
    return .onTrack
}

private func decisionToneColor(_ tone: TransmissionTrend) -> Color {
    switch tone {
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

private func stateColor(_ state: SemanticState) -> Color {
    switch state {
    case .neutral:
        .white.opacity(0.58)
    case .onTrack:
        .green
    case .atRisk:
        .orange
    case .critical:
        .red
    case .disabled:
        .gray
    }
}

private func percent(_ value: Double) -> String {
    "\(String(format: "%.2f", value))%"
}

private func signedPoints(_ value: Double) -> String {
    "\(value >= 0 ? "+" : "")\(String(format: "%.2f", value)) pp"
}
