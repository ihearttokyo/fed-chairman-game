import Foundation

public struct ChartInspection: Equatable, Sendable, Identifiable {
    public var id: Int {
        careerIndex
    }

    public var careerIndex: Int
    public var primaryLabel: String
    public var secondaryLabel: String
    public var inflation: String
    public var unemployment: String
    public var fedFunds: String
    public var expectations: String
    public var credibility: String
    public var policy: String
    public var movement: String
}

public struct MandateChartFocus: Equatable, Sendable {
    public var railItems: [MandateChartRailItem]
    public var insightHeadline: String
    public var insightDetail: String
    public var accessibilityLabel: String
}

public struct MandateChartRailItem: Equatable, Sendable, Identifiable {
    public enum Metric: String, Codable, Equatable, Sendable {
        case inflation
        case unemployment
        case fedFunds
        case credibility
    }

    public var id: Metric {
        metric
    }

    public var metric: Metric
    public var label: String
    public var value: String
    public var target: String
    public var gap: String
    public var state: SemanticState
}

public func buildChartInspection(
    history: [MacroState],
    decisions: [PolicyDecision] = [],
    selectedIndex: Int? = nil,
    termQuarters: Int = classicScenario.termQuarters,
) -> ChartInspection? {
    guard !history.isEmpty else {
        return nil
    }
    let index = min(max(selectedIndex ?? history.count - 1, 0), history.count - 1)
    let state = history[index]
    let previous = index > 0 ? history[index - 1] : nil
    let matchingDecision = decisions.last { $0.careerQuarterIndex == index }

    return ChartInspection(
        careerIndex: index,
        primaryLabel: primaryChartLabel(for: index, termQuarters: termQuarters),
        secondaryLabel: secondaryChartLabel(for: index, termQuarters: termQuarters),
        inflation: formatPercent(state.inflation),
        unemployment: formatPercent(state.unemployment),
        fedFunds: formatPercent(state.fedFundsRate),
        expectations: formatPercent(state.expectedInflation),
        credibility: String(format: "%.0f", state.credibility),
        policy: matchingDecision.map(formatPolicyDecision) ?? (index == 0 ? "Starting economy" : "No logged decision"),
        movement: previous.map { formatMovement(from: $0, to: state) } ?? "Opening snapshot before the first vote.",
    )
}

public func buildMandateChartFocus(snapshot: TermSnapshot, scenario: ScenarioConfig = classicScenario) -> MandateChartFocus {
    let metrics = snapshot.latestMetrics
    let inflationGap = metrics.inflation - scenario.targets.inflation
    let laborGap = metrics.unemployment - scenario.targets.unemployment
    let topDriver = snapshot.riskDrivers.first
    let railItems = [
        MandateChartRailItem(
            metric: .inflation,
            label: "Inflation",
            value: formatPercent(metrics.inflation),
            target: "Target \(formatPercent(scenario.targets.inflation, digits: 1))",
            gap: "\(formatDelta(inflationGap)) pp",
            state: riskState(forGap: abs(inflationGap), warning: 0.8, critical: 1.4),
        ),
        MandateChartRailItem(
            metric: .unemployment,
            label: "Unemployment",
            value: formatPercent(metrics.unemployment),
            target: "Target \(formatPercent(scenario.targets.unemployment, digits: 1))",
            gap: "\(formatDelta(laborGap)) pp",
            state: riskState(forGap: abs(laborGap), warning: 1.0, critical: 2.0),
        ),
        MandateChartRailItem(
            metric: .fedFunds,
            label: "Fed funds",
            value: formatPercent(metrics.fedFundsRate),
            target: "Policy rate",
            gap: "latest setting",
            state: .neutral,
        ),
    ]
    let insightHeadline = topDriver?.title ?? "Mandate stable"
    let insightDetail = topDriver?.detail ?? "No dominant risk driver is pulling the mandate away from target."

    return MandateChartFocus(
        railItems: railItems,
        insightHeadline: insightHeadline,
        insightDetail: insightDetail,
        accessibilityLabel: chartFocusAccessibilityLabel(
            railItems: railItems,
            insightHeadline: insightHeadline,
            insightDetail: insightDetail,
        ),
    )
}

public func chartInspectionAccessibilityLabel(_ inspection: ChartInspection) -> String {
    "\(inspection.primaryLabel), \(inspection.secondaryLabel). Inflation \(inspection.inflation), unemployment \(inspection.unemployment), fed funds \(inspection.fedFunds), expectations \(inspection.expectations), credibility \(inspection.credibility). Policy: \(inspection.policy). \(inspection.movement)"
}

private func chartFocusAccessibilityLabel(
    railItems: [MandateChartRailItem],
    insightHeadline: String,
    insightDetail: String,
) -> String {
    let items = railItems.map { "\($0.label) \($0.value), \($0.target), gap \($0.gap)" }.joined(separator: ". ")
    return "\(insightHeadline). \(insightDetail). \(items)."
}

private func primaryChartLabel(for index: Int, termQuarters: Int) -> String {
    guard index > 0 else {
        return "Career start"
    }
    let term = ((index - 1) / max(1, termQuarters)) + 1
    let quarter = ((index - 1) % max(1, termQuarters)) + 1
    return "T\(term) Q\(quarter)"
}

private func secondaryChartLabel(for index: Int, termQuarters: Int) -> String {
    guard index > 0 else {
        return "Before Term 1"
    }
    let quarter = ((index - 1) % max(1, termQuarters)) + 1
    let remaining = max(0, termQuarters - quarter)
    return "Career Q\(index) | \(remaining) left in term"
}

private func formatPercent(_ value: Double, digits: Int = 2) -> String {
    String(format: "%.\(digits)f%%", value)
}

private func formatPolicyDecision(_ decision: PolicyDecision) -> String {
    let bps = Int((decision.rateChange * 100).rounded())
    guard bps != 0 else {
        return "Hold"
    }
    return "\(bps > 0 ? "+" : "")\(bps) bps"
}

private func formatMovement(from previous: MacroState, to current: MacroState) -> String {
    "Since prior: inflation \(formatDelta(current.inflation - previous.inflation)) pp, labor \(formatDelta(current.unemployment - previous.unemployment)) pp, rate \(formatDelta(current.fedFundsRate - previous.fedFundsRate)) pp."
}

private func formatDelta(_ value: Double) -> String {
    String(format: "%+.2f", value)
}

private func riskState(forGap gap: Double, warning: Double, critical: Double) -> SemanticState {
    if gap >= critical {
        return .critical
    }
    if gap >= warning {
        return .atRisk
    }
    return .onTrack
}
