import Foundation

public struct CareerLedgerEntry: Equatable, Sendable, Identifiable {
    public var termNumber: Int
    public var label: String
    public var score: String
    public var outcome: String
    public var finalInflation: String
    public var finalUnemployment: String
    public var finalRate: String
    public var decisionMix: String

    public var id: Int {
        termNumber
    }
}

public struct TermHandoffMetric: Equatable, Sendable, Identifiable {
    public enum Tone: String, Equatable, Sendable {
        case better
        case worse
        case steady
    }

    public var label: String
    public var start: String
    public var end: String
    public var delta: String
    public var tone: Tone

    public var id: String {
        label
    }
}

public struct NativeDebrief: Equatable, Sendable {
    public var boardVerdict: String
    public var gateStatus: String
    public var gateChoice: String
    public var termStanding: String
    public var policyStyle: String
    public var bestStretch: String
    public var turningPoint: String
    public var mandateTrend: String
    public var decisionMix: String
    public var finalImpulse: String
    public var coachingFocus: String
    public var recommendation: String
    public var largestPolicyMove: String
    public var careerLedger: [CareerLedgerEntry]
    public var careerStanding: String
    public var carryoverBrief: String
    public var carryoverMetrics: [String]
    public var nextTermBrief: String
    public var retirementStatus: String
    public var termHandoff: String
    public var termHandoffMetrics: [TermHandoffMetric]
}

private struct DebriefScope {
    var termNumber: Int
    var history: [MacroState]
    var decisions: [PolicyDecision]
    var traces: [EngineTrace]
    var score: ScoreState
}

public func buildNativeDebrief(session: GameSession, scenario: ScenarioConfig = classicScenario) -> NativeDebrief {
    let scope = debriefScope(session)
    let played = Array(scope.history.dropFirst())
    let final = scope.history.last ?? session.current
    let previous = scope.history.dropLast().last ?? final
    let nearTargetCount = played.count(where: { nearTarget($0, scenario: scenario) })
    let bestStreak = longestNearTargetStreak(played, scenario: scenario)
    let biggestMove = played.enumerated()
        .map { index, state in
            let previous = scope.history[safe: index] ?? state
            return (quarter: state.quarterIndex, move: abs(state.inflation - previous.inflation) + abs(state.unemployment - previous.unemployment))
        }
        .sorted { $0.move > $1.move }
        .first
    let averageChange = scope.decisions.reduce(0) { $0 + abs($1.rateChange) } / Double(max(1, scope.decisions.count))
    let largestDecision = scope.decisions.sorted { abs($0.rateChange) > abs($1.rateChange) }.first
    let policyStyle = policyStyle(averageChange: averageChange, biggestMiss: scope.score.biggestMiss)
    let inflationDirection = directionWord(delta: final.inflation - previous.inflation, positive: "heated", negative: "cooled")
    let unemploymentDirection = directionWord(delta: final.unemployment - previous.unemployment, positive: "weakened", negative: "improved")
    let handoff = buildTermHandoff(scope: scope, scenario: scenario)

    return NativeDebrief(
        boardVerdict: buildBoardVerdict(session),
        gateStatus: buildGateStatus(session),
        gateChoice: buildGateChoice(session),
        termStanding: "Term \(scope.termNumber) scored \(formatFixed(scope.score.score, digits: 1)) (\(scope.score.grade.rawValue)) across \(scope.decisions.count) policy meetings; reappointment \(scope.score.reappointed ? "earned" : "missed").",
        policyStyle: policyStyle,
        bestStretch: bestStreak.length > 0
            ? "\(nearTargetCount) of \(played.count) quarters were close to target; longest run was Q\(bestStreak.start)-Q\(bestStreak.end)."
            : "0 of \(played.count) played quarters stayed close to both mandate targets.",
        turningPoint: biggestMove.map { "Q\($0.quarter) moved most: \(formatSigned($0.move)) total points across inflation and unemployment." } ?? "No major turning point yet.",
        mandateTrend: "Final quarter inflation \(inflationDirection) to \(formatFixed(final.inflation))%; unemployment \(unemploymentDirection) to \(formatFixed(final.unemployment))%.",
        decisionMix: buildDecisionMix(scope.decisions),
        finalImpulse: finalImpulse(scope.traces.last),
        coachingFocus: coachingFocus(biggestMiss: scope.score.biggestMiss),
        recommendation: scope.score.reappointed ? "Replay the same seed and try to win with fewer rate moves." : "Replay the same seed and respond earlier to the biggest miss identified in the scorecard.",
        largestPolicyMove: largestDecision.map { "Largest move: Q\($0.quarterIndex) \(policyDecisionLabel($0).lowercased()) (\(formatSigned($0.rateChange)) pp)." } ?? "No policy moves recorded.",
        careerLedger: buildCareerLedger(session),
        careerStanding: buildCareerStanding(session),
        carryoverBrief: buildCarryoverBrief(session),
        carryoverMetrics: buildCarryoverMetrics(session),
        nextTermBrief: buildNextTermBrief(session),
        retirementStatus: buildRetirementStatus(session),
        termHandoff: handoff.termHandoff,
        termHandoffMetrics: handoff.metrics,
    )
}

private func debriefScope(_ session: GameSession) -> DebriefScope {
    if session.status != .inProgress, let completedTerm = session.completedTerms.last {
        return DebriefScope(
            termNumber: completedTerm.termNumber,
            history: completedTerm.history,
            decisions: completedTerm.decisions,
            traces: completedTerm.traces,
            score: completedTerm.score,
        )
    }
    return DebriefScope(
        termNumber: session.termNumber,
        history: session.history,
        decisions: session.decisions,
        traces: session.traces,
        score: session.score,
    )
}

private func nearTarget(_ state: MacroState, scenario: ScenarioConfig) -> Bool {
    abs(state.inflation - scenario.targets.inflation) <= 0.6 && abs(state.unemployment - scenario.targets.unemployment) <= 0.8
}

private func longestNearTargetStreak(_ states: [MacroState], scenario: ScenarioConfig) -> (length: Int, start: Int, end: Int) {
    var currentLength = 0
    var currentStart = 0
    var best = (length: 0, start: 0, end: 0)
    for (index, state) in states.enumerated() {
        if nearTarget(state, scenario: scenario) {
            if currentLength == 0 {
                currentStart = index
            }
            currentLength += 1
            if currentLength > best.length {
                best = (currentLength, states[currentStart].quarterIndex, state.quarterIndex)
            }
        } else {
            currentLength = 0
        }
    }
    return best
}

private func buildDecisionMix(_ decisions: [PolicyDecision]) -> String {
    let hikes = decisions.count { $0.rateChange > 0 }
    let cuts = decisions.count { $0.rateChange < 0 }
    let holds = decisions.count { $0.rateChange == 0 }
    return "\(plural(hikes, "hike")), \(plural(cuts, "cut")), \(plural(holds, "hold")) across \(decisions.count) meetings."
}

private func compactDecisionMix(_ decisions: [PolicyDecision]) -> String {
    let hikes = decisions.count { $0.rateChange > 0 }
    let cuts = decisions.count { $0.rateChange < 0 }
    let holds = decisions.count { $0.rateChange == 0 }
    return "\(hikes)H / \(cuts)C / \(holds) hold"
}

private func finalImpulse(_ trace: EngineTrace?) -> String {
    guard let trace else {
        return "No final model trace was recorded."
    }
    let channels = shockChannels(traceContributions: trace.shockContrib)
    let policy = trace.laggedPolicyGap > 0.35
        ? "restrictive lag was cooling demand"
        : trace.laggedPolicyGap < -0.35
        ? "easy lag was supporting demand"
        : "policy lag was near neutral"
    return "Final quarter: \(policy); \(shockChannelSummary(channels))."
}

private func buildCareerLedger(_ session: GameSession) -> [CareerLedgerEntry] {
    session.completedTerms.map { term in
        CareerLedgerEntry(
            termNumber: term.termNumber,
            label: "Term \(term.termNumber)",
            score: "\(formatFixed(term.score.score, digits: 1)) (\(term.score.grade.rawValue))",
            outcome: term.reappointed ? "Reappointed" : "Not reappointed",
            finalInflation: "\(formatFixed(term.endingState.inflation))%",
            finalUnemployment: "\(formatFixed(term.endingState.unemployment))%",
            finalRate: "\(formatFixed(term.endingState.fedFundsRate))%",
            decisionMix: compactDecisionMix(term.decisions),
        )
    }
}

private func buildCareerStanding(_ session: GameSession) -> String {
    let completed = session.completedTerms.count
    if completed == 0 {
        return "No completed four-year terms yet."
    }
    let reappointments = session.completedTerms.count { $0.reappointed }
    return "\(completed) completed four-year \(completed == 1 ? "term" : "terms"); \(reappointments) \(reappointments == 1 ? "reappointment" : "reappointments") earned. Career score \(formatFixed(session.careerScore.score, digits: 1)) (\(session.careerScore.grade.rawValue))."
}

private func buildCarryoverBrief(_ session: GameSession) -> String {
    let final = session.history.last ?? session.current
    switch session.status {
    case .termDebrief:
        return "Carryover economy for Term \(session.termNumber + 1): \(formatFixed(final.inflation))% inflation, \(formatFixed(final.unemployment))% unemployment, \(formatFixed(final.fedFundsRate))% policy rate."
    case .retired:
        return "Retired after \(session.totalCareerQuarters) quarters with final inflation \(formatFixed(final.inflation))% and unemployment \(formatFixed(final.unemployment))%."
    case .notReappointed:
        return "The final economy ended at \(formatFixed(final.inflation))% inflation and \(formatFixed(final.unemployment))% unemployment, short of the reappointment bar."
    case .inProgress, .notStarted:
        return "Current economy: \(formatFixed(final.inflation))% inflation, \(formatFixed(final.unemployment))% unemployment, \(formatFixed(final.fedFundsRate))% policy rate."
    }
}

private func buildCarryoverMetrics(_ session: GameSession) -> [String] {
    let final = session.history.last ?? session.current
    return [
        "\(formatFixed(final.inflation))% inflation",
        "\(formatFixed(final.unemployment))% unemployment",
        "\(formatFixed(final.fedFundsRate))% policy rate",
        "\(formatFixed(final.gdpGrowth))% GDP growth",
    ]
}

private func buildBoardVerdict(_ session: GameSession) -> String {
    switch session.status {
    case .retired:
        "You retired after \(session.completedTerms.count) completed four-year terms with a \(session.careerScore.grade.rawValue) career grade."
    case .notReappointed:
        "The board ended the appointment after Term \(session.termNumber); the mandate score missed the reappointment threshold."
    case .termDebrief:
        "The board reappointed you for Term \(session.termNumber + 1); your next four years inherit this economy."
    case .inProgress, .notStarted:
        "The board will evaluate reappointment after the 16th quarter of the term."
    }
}

private func buildGateStatus(_ session: GameSession) -> String {
    switch session.status {
    case .retired:
        "Career score is final."
    case .notReappointed:
        "Career ended by board decision."
    case .termDebrief:
        session.completedTerms.count >= 2
            ? "Choose another four-year term or retire with a final career score."
            : "Retirement unlocks after completing one reappointment term; continue into Term 2 to build a career score."
    case .inProgress, .notStarted:
        "Finish the current four-year term to reach the reappointment gate."
    }
}

private func buildGateChoice(_ session: GameSession) -> String {
    switch session.status {
    case .retired:
        "Career ledger finalized."
    case .notReappointed:
        "Replay the same seed or start fresh from the opening economy."
    case .termDebrief:
        session.completedTerms.count >= 2
            ? "Your next click either starts another inherited four-year term or locks the career score."
            : "Your next click starts Term 2 immediately; retirement remains locked until that term is complete."
    case .inProgress, .notStarted:
        "The next gate appears only after Q16."
    }
}

private func buildRetirementStatus(_ session: GameSession) -> String {
    if session.status == .retired {
        return "Finalized after \(session.totalCareerQuarters) quarters."
    }
    if session.status != .termDebrief || !session.score.reappointed {
        return "Retirement is available only at a successful term-boundary debrief."
    }
    let completedTerms = max(session.completedTerms.count, session.status == .termDebrief ? session.termNumber : 0)
    let remaining = max(0, 2 - completedTerms)
    if remaining == 0 {
        return "Retirement is available now because you completed at least one reappointment term."
    }
    return "Retirement locked: complete \(remaining) more reappointed \(remaining == 1 ? "term" : "terms") first."
}

private func buildNextTermBrief(_ session: GameSession) -> String {
    let final = session.history.last ?? session.current
    guard session.status == .termDebrief, session.score.reappointed else {
        return "No next term is scheduled from this debrief."
    }
    let inflationRisk = final.inflation > 2.6 ? "inflation still above target" : final.inflation < 1.4 ? "inflation running soft" : "inflation near target"
    let laborRisk = final.unemployment > 5.8 ? "labor slack elevated" : final.unemployment < 4.2 ? "labor market tight" : "labor near balance"
    return "Term \(session.termNumber + 1) opens with \(inflationRisk) and \(laborRisk); inherited rate \(formatFixed(final.fedFundsRate))%."
}

private func buildTermHandoff(scope: DebriefScope, scenario: ScenarioConfig) -> (termHandoff: String, metrics: [TermHandoffMetric]) {
    guard let start = scope.history.first, let end = scope.history.last else {
        return ("No completed term handoff is available yet.", [])
    }
    let inflationStart = abs(start.inflation - scenario.targets.inflation)
    let inflationEnd = abs(end.inflation - scenario.targets.inflation)
    let laborStart = abs(start.unemployment - scenario.targets.unemployment)
    let laborEnd = abs(end.unemployment - scenario.targets.unemployment)
    let credibilityDelta = end.credibility - start.credibility
    let rateDelta = end.fedFundsRate - start.fedFundsRate
    let bias = if inflationEnd < inflationStart - 0.1, laborEnd < laborStart - 0.1 {
        "stronger on both sides of the mandate"
    } else if inflationEnd > inflationStart + 0.1, laborEnd > laborStart + 0.1 {
        "more strained on both sides of the mandate"
    } else if inflationEnd < inflationStart - 0.1 {
        "cleaner on inflation but still mixed for labor"
    } else if laborEnd < laborStart - 0.1 {
        "cleaner on labor but still mixed for inflation"
    } else {
        "broadly similar to the economy you inherited"
    }
    return (
        "You inherited \(formatFixed(start.inflation))% inflation, \(formatFixed(start.unemployment))% unemployment, and a \(formatFixed(start.fedFundsRate))% policy rate; the handoff is \(bias).",
        [
            TermHandoffMetric(label: "Inflation gap", start: "\(formatFixed(inflationStart)) pp", end: "\(formatFixed(inflationEnd)) pp", delta: formatSignedPercent(inflationEnd - inflationStart), tone: toneForGap(start: inflationStart, end: inflationEnd)),
            TermHandoffMetric(label: "Labor gap", start: "\(formatFixed(laborStart)) pp", end: "\(formatFixed(laborEnd)) pp", delta: formatSignedPercent(laborEnd - laborStart), tone: toneForGap(start: laborStart, end: laborEnd)),
            TermHandoffMetric(label: "Policy rate", start: "\(formatFixed(start.fedFundsRate))%", end: "\(formatFixed(end.fedFundsRate))%", delta: formatSignedPercent(rateDelta), tone: .steady),
            TermHandoffMetric(label: "Credibility", start: "\(formatFixed(start.credibility, digits: 0))", end: "\(formatFixed(end.credibility, digits: 0))", delta: "\(credibilityDelta > 0 ? "+" : "")\(formatFixed(credibilityDelta, digits: 0))", tone: credibilityDelta > 1 ? .better : credibilityDelta < -1 ? .worse : .steady),
        ],
    )
}

private func policyStyle(averageChange: Double, biggestMiss: String) -> String {
    if averageChange < 0.15 {
        return "Patient operator"
    }
    if averageChange > 0.42 {
        return "Forceful rate mover"
    }
    if biggestMiss == "inflation drift" {
        return "Inflation responder"
    }
    if biggestMiss == "unemployment gap" {
        return "Labor-market defender"
    }
    return "Balanced stabilizer"
}

private func coachingFocus(biggestMiss: String) -> String {
    switch biggestMiss {
    case "inflation drift":
        "Watch expected inflation and policy lag before inflation breaks far from target."
    case "unemployment gap":
        "Ease earlier when labor slack opens and inflation is already moving toward target."
    case "recession risk":
        "Use smaller steps when financial stress and unemployment are both rising."
    default:
        "Keep rate moves measured when both mandate gaps are closing."
    }
}

private func directionWord(delta: Double, positive: String, negative: String) -> String {
    if delta > 0.05 {
        return positive
    }
    if delta < -0.05 {
        return negative
    }
    return "held steady"
}

private func toneForGap(start: Double, end: Double, tolerance: Double = 0.05) -> TermHandoffMetric.Tone {
    if end < start - tolerance {
        return .better
    }
    if end > start + tolerance {
        return .worse
    }
    return .steady
}

private func plural(_ count: Int, _ label: String) -> String {
    "\(count) \(label)\(count == 1 ? "" : "s")"
}

private func formatSigned(_ value: Double) -> String {
    "\(value > 0 ? "+" : "")\(formatFixed(value))"
}

private func formatSignedPercent(_ value: Double) -> String {
    "\(formatSigned(value)) pp"
}

private func formatFixed(_ value: Double, digits: Int = 2) -> String {
    String(format: "%.\(digits)f", value)
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
