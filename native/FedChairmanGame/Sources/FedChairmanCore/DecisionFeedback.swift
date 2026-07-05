import Foundation

public struct DecisionFeedback: Equatable, Sendable {
    public var headline: String
    public var moveLabel: String
    public var ratePath: String
    public var mandateLine: String
    public var credibilityLine: String
    public var traceLine: String
    public var tone: TransmissionTrend
    public var intensity: Int
}

public func buildDecisionFeedback(session: GameSession, scenario: ScenarioConfig = classicScenario) -> DecisionFeedback {
    guard
        let decision = session.decisions.last,
        let trace = session.traces.last,
        session.history.count >= 2
    else {
        return openingDecisionFeedback(current: session.current, scenario: scenario)
    }

    let previous = session.history[session.history.count - 2]
    let current = session.current
    let previousMandateGap = mandateDistance(previous, scenario: scenario)
    let currentMandateGap = mandateDistance(current, scenario: scenario)
    let mandateDelta = currentMandateGap - previousMandateGap
    let credibilityDelta = current.credibility - previous.credibility
    let tone = decisionFeedbackTone(mandateDelta: mandateDelta, credibilityDelta: credibilityDelta)

    return DecisionFeedback(
        headline: mandateDelta <= 0 ? "Mandate gap improved" : "Mandate gap widened",
        moveLabel: policyMoveText(decision),
        ratePath: "\(formatDecisionPercent(decision.resultingFedFundsRate - decision.rateChange)) -> \(formatDecisionPercent(decision.resultingFedFundsRate))",
        mandateLine: "\(formatSignedDecision(mandateDelta)) pp total miss; inflation \(formatSignedDecision(current.inflation - scenario.targets.inflation)) pp, labor \(formatSignedDecision(current.unemployment - scenario.targets.unemployment)) pp",
        credibilityLine: "Credibility \(formatSignedDecision(credibilityDelta)) pts; base \(formatSignedDecision(trace.credibilityBaseDrift ?? 0)), rate cost \(formatSignedDecision(trace.credibilityRateMoveCost ?? 0)), grace \(formatSignedDecision(trace.credibilityReappointmentGrace ?? 0))",
        traceLine: "Lag \(formatSignedDecision(trace.laggedPolicyGap)) pp, shocks \(formatSignedDecision(trace.shockContrib.values.reduce(0, +))) pp, neutral \(formatDecisionPercent(trace.neutralRate))",
        tone: tone,
        intensity: decisionFeedbackIntensity(mandateDelta: mandateDelta, credibilityDelta: credibilityDelta, trace: trace),
    )
}

public func shouldPlayCockpitSound(ui: UiState) -> Bool {
    ui.soundEnabled && !ui.reducedNoise && ui.soundVolume > 0
}

public func cockpitSoundVolume(ui: UiState) -> Double {
    min(1, max(0, ui.soundVolume))
}

private func openingDecisionFeedback(current: MacroState, scenario: ScenarioConfig) -> DecisionFeedback {
    DecisionFeedback(
        headline: "Awaiting first vote",
        moveLabel: "Choose rate move",
        ratePath: "Fed funds \(formatDecisionPercent(current.fedFundsRate))",
        mandateLine: "Inflation \(formatSignedDecision(current.inflation - scenario.targets.inflation)) pp, labor \(formatSignedDecision(current.unemployment - scenario.targets.unemployment)) pp",
        credibilityLine: "Credibility \(String(format: "%.0f", current.credibility)); keep inflation anchored to build trust",
        traceLine: "Preview a move, then commit to advance one quarter and write the trace.",
        tone: .stabilizing,
        intensity: 0,
    )
}

private func mandateDistance(_ state: MacroState, scenario: ScenarioConfig) -> Double {
    abs(state.inflation - scenario.targets.inflation) + abs(state.unemployment - scenario.targets.unemployment)
}

private func policyMoveText(_ decision: PolicyDecision) -> String {
    if decision.rateChange == 0 {
        return "Hold"
    }
    let bps = Int((decision.rateChange * 100).rounded())
    return "\(bps > 0 ? "+" : "")\(bps) bps"
}

private func decisionFeedbackTone(mandateDelta: Double, credibilityDelta: Double) -> TransmissionTrend {
    if mandateDelta <= -0.05 {
        return .stabilizing
    }
    if credibilityDelta < -1 || mandateDelta > 0.45 {
        return .stress
    }
    return mandateDelta > 0 ? .heating : .cooling
}

private func decisionFeedbackIntensity(mandateDelta: Double, credibilityDelta: Double, trace: EngineTrace) -> Int {
    let raw = abs(mandateDelta) * 42 + max(0, -credibilityDelta) * 8 + abs(trace.laggedPolicyGap) * 18 + abs(trace.shockContrib.values.reduce(0, +)) * 14
    return Int(min(100, max(0, raw.rounded())))
}

private func formatDecisionPercent(_ value: Double) -> String {
    "\(String(format: "%.2f", value))%"
}

private func formatSignedDecision(_ value: Double) -> String {
    "\(value >= 0 ? "+" : "")\(String(format: "%.2f", value))"
}
