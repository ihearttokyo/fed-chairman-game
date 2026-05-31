import Foundation

private struct TimelinePoint {
    var termNumber: Int
    var termQuarter: Int
    var careerQuarter: Int?
    var label: String
    var isTermStart: Bool
    var state: MacroState
    var decision: PolicyDecision?
}

private struct DecisionRow {
    var termNumber: Int
    var termQuarter: Int
    var careerQuarter: Int
    var action: String
    var resultingFedFundsRate: Double
    var inflation: Double?
    var unemployment: Double?
}

private func escapeCsv(_ value: String) -> String {
    if value.contains(",") || value.contains("\n") || value.contains("\"") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
}

private func formatNumber(_ value: Double?) -> String {
    guard let value else {
        return ""
    }
    return String(format: "%.2f", value)
}

private func buildCareerTimeline(_ session: GameSession) -> [TimelinePoint] {
    let completed = session.completedTerms.flatMap { term in
        term.history.enumerated().map { index, state in
            let isStart = index == 0
            return TimelinePoint(
                termNumber: term.termNumber,
                termQuarter: index,
                careerQuarter: isStart ? nil : (term.termNumber - 1) * 16 + index,
                label: isStart ? "T\(term.termNumber) start" : "T\(term.termNumber) Q\(index)",
                isTermStart: isStart,
                state: state,
                decision: isStart ? nil : term.decisions[safe: index - 1],
            )
        }
    }

    let includeActiveTerm = session.status == .inProgress || session.status == .notStarted
    let active: [TimelinePoint] = includeActiveTerm
        ? session.history.enumerated().map { index, state in
            let isStart = index == 0
            return TimelinePoint(
                termNumber: session.termNumber,
                termQuarter: index,
                careerQuarter: isStart ? nil : session.totalCareerQuarters - session.currentTermQuarter + index,
                label: isStart ? "T\(session.termNumber) start" : "T\(session.termNumber) Q\(index)",
                isTermStart: isStart,
                state: state,
                decision: isStart ? nil : session.decisions[safe: index - 1],
            )
        }
        : []

    return completed + active
}

private func buildDecisionRows(_ session: GameSession) -> [DecisionRow] {
    let completed = session.completedTerms.flatMap { term in
        term.decisions.enumerated().map { index, decision in
            let state = term.history[safe: index + 1]
            return DecisionRow(
                termNumber: term.termNumber,
                termQuarter: decision.quarterIndex,
                careerQuarter: decision.careerQuarterIndex ?? (term.termNumber - 1) * 16 + decision.quarterIndex,
                action: policyDecisionLabel(decision),
                resultingFedFundsRate: decision.resultingFedFundsRate,
                inflation: state?.inflation,
                unemployment: state?.unemployment,
            )
        }
    }

    let active: [DecisionRow] = (session.status == .inProgress || session.status == .notStarted)
        ? session.decisions.enumerated().map { index, decision in
            let state = session.history[safe: index + 1]
            return DecisionRow(
                termNumber: session.termNumber,
                termQuarter: decision.quarterIndex,
                careerQuarter: decision.careerQuarterIndex ?? (session.termNumber - 1) * 16 + decision.quarterIndex,
                action: policyDecisionLabel(decision),
                resultingFedFundsRate: decision.resultingFedFundsRate,
                inflation: state?.inflation,
                unemployment: state?.unemployment,
            )
        }
        : []

    return completed + active
}

public func sessionToCsv(_ session: GameSession) -> String {
    let header = [
        "term",
        "quarter",
        "careerQuarter",
        "label",
        "boundary",
        "policyAction",
        "policyRateChange",
        "inflation",
        "unemployment",
        "fedFundsRate",
        "outputGap",
        "gdpGrowth",
        "expectedInflation",
        "credibility",
    ]

    let rows = buildCareerTimeline(session).map { point in
        [
            "\(point.termNumber)",
            "\(point.termQuarter)",
            point.careerQuarter.map(String.init) ?? "",
            point.label,
            point.isTermStart ? "term start" : "",
            point.decision.map(policyDecisionLabel) ?? "",
            point.isTermStart ? "" : formatNumber(point.decision?.rateChange),
            formatNumber(point.state.inflation),
            formatNumber(point.state.unemployment),
            formatNumber(point.state.fedFundsRate),
            formatNumber(point.state.outputGap),
            formatNumber(point.state.gdpGrowth),
            formatNumber(point.state.expectedInflation),
            formatNumber(point.state.credibility),
        ]
    }

    return ([header] + rows).map { row in
        row.map(escapeCsv).joined(separator: ",")
    }.joined(separator: "\n")
}

public func sessionToJson(_ session: GameSession) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(session)
    return String(data: data, encoding: .utf8) ?? "{}"
}

public func sessionToMarkdown(_ session: GameSession) -> String {
    let final = session.careerHistory.last
    let termBoundaries = buildCareerTimeline(session)
        .filter(\.isTermStart)
        .map { point in
            "- \(point.label): \(point.careerQuarter.map { "career Q\($0)" } ?? "term boundary"), \(String(format: "%.2f", point.state.inflation))% inflation, \(String(format: "%.2f", point.state.unemployment))% unemployment, \(String(format: "%.2f", point.state.fedFundsRate))% policy rate."
        }
    let decisions = buildDecisionRows(session).map { decision in
        "| T\(decision.termNumber) Q\(decision.termQuarter) | Q\(decision.careerQuarter) | \(decision.action) | \(String(format: "%.2f", decision.resultingFedFundsRate))% | \(formatNumber(decision.inflation).emptyFallback("-"))% | \(formatNumber(decision.unemployment).emptyFallback("-"))% |"
    }
    let finalTrace = session.traces.last
    let result = session.status == .retired ? "Retired" : session.score.reappointed ? "Reappointed" : "Not reappointed"

    return [
        "# Classic Monetary Policy Debrief",
        "",
        "- Scenario: \(session.scenarioId)",
        "- Seed: \(session.seed)",
        "- Terms completed: \(session.completedTerms.count)",
        "- Quarters played: \(session.totalCareerQuarters)",
        "- Career score: \(String(format: "%.0f", session.careerScore.score)) (\(session.careerScore.grade.rawValue))",
        "- Current term score: \(String(format: "%.0f", session.score.score)) (\(session.score.grade.rawValue))",
        "- Result: \(result)",
        final.map { "- Final inflation: \(String(format: "%.2f", $0.inflation))%" } ?? "",
        final.map { "- Final unemployment: \(String(format: "%.2f", $0.unemployment))%" } ?? "",
        final.map { "- Final fed funds rate: \(String(format: "%.2f", $0.fedFundsRate))%" } ?? "",
        "- Biggest miss: \(session.score.biggestMiss)",
        "- Takeaway: \(session.score.takeaway)",
        finalTrace.map { "- Final model readout: \($0.explanation)" } ?? "",
        "",
        "## Term Boundaries",
        "",
        termBoundaries.joined(separator: "\n"),
        "",
        "## Score Components",
        "",
        "- Mean inflation miss: \(String(format: "%.2f", session.score.meanAbsInflationGap))",
        "- Mean unemployment miss: \(String(format: "%.2f", session.score.meanAbsUnemploymentGap))",
        "- Volatility index: \(String(format: "%.2f", session.score.volatilityIndex))",
        "- Recession quarter share: \(String(format: "%.0f", session.score.recessionQuarterShare * 100))%",
        "- Credibility bonus: \(String(format: "%.2f", session.score.credibilityBonus))",
        "",
        "## Decision Log",
        "",
        "| Term quarter | Career quarter | Decision | Resulting rate | Inflation | Unemployment |",
        "| --- | ---: | --- | ---: | ---: | ---: |",
        decisions.joined(separator: "\n"),
    ]
    .filter { !$0.isEmpty }
    .joined(separator: "\n")
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    func emptyFallback(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
