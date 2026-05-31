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

public func chartInspectionAccessibilityLabel(_ inspection: ChartInspection) -> String {
    "\(inspection.primaryLabel), \(inspection.secondaryLabel). Inflation \(inspection.inflation), unemployment \(inspection.unemployment), fed funds \(inspection.fedFunds), expectations \(inspection.expectations), credibility \(inspection.credibility). Policy: \(inspection.policy). \(inspection.movement)"
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

private func formatPercent(_ value: Double) -> String {
    String(format: "%.2f%%", value)
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
