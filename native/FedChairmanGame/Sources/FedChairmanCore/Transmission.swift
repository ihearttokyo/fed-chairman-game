import Foundation

public enum TransmissionTrend: String, Codable, Equatable, Sendable {
    case cooling
    case heating
    case stabilizing
    case stress
}

public struct TransmissionStep: Equatable, Sendable, Identifiable {
    public var id: String {
        month
    }

    public var month: String
    public var channel: String
    public var title: String
    public var stance: String
    public var intensity: Int
    public var intensityLabel: String
    public var driver: String
    public var value: String
    public var comparison: String
    public var basis: String
    public var detail: String
    public var trend: TransmissionTrend
    public var evidence: [String]
    public var signals: [String]
    public var traceInputs: [String]
}

public struct TransmissionReceipt: Equatable, Sendable {
    public var headline: String
    public var verdict: String
    public var policyEcho: String
    public var nextWatch: String
    public var tone: TransmissionTrend
}

public struct TransmissionDecisionMemo: Equatable, Sendable {
    public var headline: String
    public var assessment: String
    public var tradeoff: String
    public var risk: String
    public var nextBias: String
    public var tone: TransmissionTrend
}

public struct TransmissionCausalLink: Equatable, Sendable, Identifiable {
    public var id: String {
        label
    }

    public var label: String
    public var text: String
    public var tone: TransmissionTrend
}

public struct TransmissionChange: Equatable, Sendable, Identifiable {
    public var id: String {
        label
    }

    public var label: String
    public var previous: String
    public var current: String
    public var delta: String
    public var reason: String
    public var tone: TransmissionTrend
}

public struct TransmissionBriefing: Equatable, Sendable {
    public var receipt: TransmissionReceipt
    public var decisionMemo: TransmissionDecisionMemo
    public var summary: String
    public var path: [String]
    public var causalChain: [TransmissionCausalLink]
    public var changes: [TransmissionChange]
    public var steps: [TransmissionStep]
}

public func buildTransmissionBriefing(session: GameSession, scenario: ScenarioConfig = classicScenario) -> TransmissionBriefing? {
    guard
        let trace = session.traces.last,
        let decision = session.decisions.last,
        session.history.count >= 2
    else {
        return nil
    }
    let previous = session.history[session.history.count - 2]
    let current = session.current
    return TransmissionBriefing(
        receipt: transmissionReceipt(previous: previous, current: current, decision: decision, trace: trace, scenario: scenario),
        decisionMemo: decisionMemo(previous: previous, current: current, decision: decision, trace: trace, scenario: scenario),
        summary: transmissionSummary(decision: decision, previous: previous, current: current, trace: trace),
        path: transmissionPath(decision: decision, previous: previous, current: current, trace: trace),
        causalChain: causalChain(decision: decision, previous: previous, current: current, trace: trace, scenario: scenario),
        changes: transmissionChanges(previous: previous, current: current, decision: decision, trace: trace),
        steps: [
            rateTransmission(decision: decision, trace: trace, scenario: scenario),
            demandTransmission(previous: previous, current: current, trace: trace),
            mandateTransmission(previous: previous, current: current, trace: trace, scenario: scenario),
        ],
    )
}

public func buildTransmissionSteps(session: GameSession, scenario: ScenarioConfig = classicScenario) -> [TransmissionStep] {
    buildTransmissionBriefing(session: session, scenario: scenario)?.steps ?? []
}

private let shockLabels = [
    "demand": "demand",
    "supply": "supply chain",
    "financial": "financial stress",
    "labor": "labor market",
    "energy": "energy prices",
    "confidence": "confidence",
]

private func formatPercent(_ value: Double, digits: Int = 2) -> String {
    "\(String(format: "%.\(digits)f", value))%"
}

private func formatSigned(_ value: Double, digits: Int = 2) -> String {
    "\(value >= 0 ? "+" : "")\(String(format: "%.\(digits)f", value))"
}

private func clampIntensity(_ value: Double) -> Int {
    Int(min(100, max(8, value.rounded())))
}

private func formatMagnitude(_ value: Double) -> String {
    String(format: "%.2f", abs(value))
}

private func traceShockChannels(_ trace: EngineTrace) -> ShockChannels {
    shockChannels(traceContributions: trace.shockContrib)
}

private func dominantShockLabel(_ trace: EngineTrace) -> String {
    guard let dominant = trace.shockContrib.max(by: { abs($0.value) < abs($1.value) }), abs(dominant.value) > 0.05 else {
        return "none"
    }
    return "\(shockLabels[dominant.key] ?? dominant.key) \(formatSigned(dominant.value))"
}

private func rateTransmission(decision: PolicyDecision, trace: EngineTrace, scenario: ScenarioConfig) -> TransmissionStep {
    let neutralGap = decision.resultingFedFundsRate - trace.neutralRate
    let absChange = abs(decision.rateChange)
    let previousRate = decision.resultingFedFundsRate - decision.rateChange
    let trend: TransmissionTrend = if decision.rateChange > 0 {
        .cooling
    } else if decision.rateChange < 0 {
        .heating
    } else if abs(neutralGap) < 0.35 {
        .stabilizing
    } else if neutralGap > 0 {
        .cooling
    } else {
        .heating
    }
    let action = if decision.rateChange > 0 {
        "Rate hike committed"
    } else if decision.rateChange < 0 {
        "Rate cut committed"
    } else {
        "Target rate held"
    }
    let stance = if decision.rateChange > 0 {
        "Restrictive signal"
    } else if decision.rateChange < 0 {
        "Easier signal"
    } else if abs(neutralGap) < 0.35 {
        "Neutral hold"
    } else if neutralGap > 0 {
        "Restrictive hold"
    } else {
        "Easy hold"
    }
    let force = absChange >= 0.5 ? "a strong signal" : absChange > 0 ? "a measured signal" : "a wait-and-watch signal"
    return TransmissionStep(
        month: "Month 1",
        channel: "Decision",
        title: action,
        stance: stance,
        intensity: clampIntensity(max(absChange / 0.75, abs(neutralGap) / 1.25) * 100),
        intensityLabel: absChange > 0 ? "Policy signal strength" : "Neutral-gap pressure",
        driver: "Policy impulse: \(formatSigned(decision.rateChange)) pp move, \(formatSigned(neutralGap)) pp versus neutral",
        value: "\(formatPercent(decision.resultingFedFundsRate)) target",
        comparison: "Fed funds: \(formatPercent(previousRate)) -> \(formatPercent(decision.resultingFedFundsRate))",
        basis: "Uses the committed rate decision and this quarter's neutral-rate trace.",
        detail: "The desk sends \(force); neutral is near \(formatPercent(trace.neutralRate)) against the \(formatPercent(scenario.targets.inflation, digits: 1)) inflation mandate.",
        trend: trend,
        evidence: [
            "Previous rate \(formatPercent(previousRate))",
            "New rate \(formatPercent(decision.resultingFedFundsRate))",
            "Neutral \(formatPercent(trace.neutralRate))",
        ],
        signals: [
            "Move: \(formatSigned(decision.rateChange)) pp",
            "Gap: \(formatSigned(neutralGap)) pp",
        ],
        traceInputs: ["latest PolicyDecision", "EngineTrace.neutralRate", "scenario inflation target"],
    )
}

private func demandTransmission(previous: MacroState, current: MacroState, trace: EngineTrace) -> TransmissionStep {
    let channels = traceShockChannels(trace)
    let shockIntensity = channels.totalIntensity
    let trend: TransmissionTrend = if trace.laggedPolicyGap > 0.35 {
        .cooling
    } else if trace.laggedPolicyGap < -0.35 {
        .heating
    } else if shockIntensity > 0.35 {
        .stress
    } else {
        .stabilizing
    }
    let channel = if trace.laggedPolicyGap > 0.35 {
        "Credit conditions lean tighter"
    } else if trace.laggedPolicyGap < -0.35 {
        "Credit conditions lean easier"
    } else {
        "Momentum leads the quarter"
    }
    let shockLine = shockChannelSummary(channels)
    return TransmissionStep(
        month: "Month 2",
        channel: "Demand lag",
        title: channel,
        stance: trace.laggedPolicyGap > 0.35 ? "Demand cooling" : trace.laggedPolicyGap < -0.35 ? "Demand heating" : shockIntensity > 0.35 ? "Shock led" : "Momentum steady",
        intensity: clampIntensity(max(abs(trace.laggedPolicyGap) / 1.1, shockIntensity / 1.2) * 100),
        intensityLabel: shockIntensity > abs(trace.laggedPolicyGap) ? "Shock intensity" : "Lag pressure",
        driver: "Transmission driver: lag \(formatSigned(trace.laggedPolicyGap)) pp; \(shockLine)",
        value: "\(formatSigned(trace.laggedPolicyGap)) pp lag",
        comparison: "Output gap: \(formatSigned(previous.outputGap)) -> \(formatSigned(current.outputGap)) pp",
        basis: "Uses the prior quarter, current quarter, lagged policy gap, and shock contribution trace.",
        detail: "Policy works through the lagged gap while the separate shock channels shift prices, output, or hiring.",
        trend: trend,
        evidence: [
            "Output \(formatSigned(current.outputGap - previous.outputGap)) pp",
            "GDP \(formatSigned(trace.gdpDelta)) pp",
            "Shock intensity \(formatMagnitude(shockIntensity))",
        ],
        signals: [
            trace.laggedPolicyGap > 0.35 ? "Lag: restrictive" : trace.laggedPolicyGap < -0.35 ? "Lag: easy" : "Lag: near neutral",
            "Dominant: \(dominantShockLabel(trace))",
        ],
        traceInputs: ["previous MacroState", "current MacroState", "EngineTrace.laggedPolicyGap", "EngineTrace.shockContrib"],
    )
}

private func mandateTransmission(previous: MacroState, current: MacroState, trace: EngineTrace, scenario: ScenarioConfig) -> TransmissionStep {
    let inflationGap = current.inflation - scenario.targets.inflation
    let unemploymentGap = current.unemployment - scenario.targets.unemployment
    let previousMiss = abs(previous.inflation - scenario.targets.inflation) + abs(previous.unemployment - scenario.targets.unemployment)
    let combinedMiss = abs(inflationGap) + abs(unemploymentGap)
    let mandateMove = combinedMiss - previousMiss
    let trend: TransmissionTrend = if mandateMove < -0.05 {
        .stabilizing
    } else if trace.inflationDelta > 0.15 || trace.unemploymentDelta > 0.2 {
        .stress
    } else if trace.inflationDelta < -0.1 {
        .cooling
    } else {
        .heating
    }
    return TransmissionStep(
        month: "Month 3",
        channel: "Mandate close",
        title: combinedMiss < previousMiss ? "Mandate distance narrowed" : "Mandate distance widened",
        stance: mandateMove < -0.05 ? "Mandate improving" : mandateMove > 0.05 ? "Mandate slipping" : "Mandate steady",
        intensity: clampIntensity(max(abs(mandateMove) / 0.8, combinedMiss / 3.2) * 100),
        intensityLabel: mandateMove < 0 ? "Progress toward mandate" : "Mandate pressure",
        driver: "Mandate driver: inflation gap \(formatSigned(inflationGap)) pp, jobs gap \(formatSigned(unemploymentGap)) pp",
        value: "\(formatSigned(current.inflation - previous.inflation)) / \(formatSigned(current.unemployment - previous.unemployment)) pp",
        comparison: "Inflation \(formatPercent(previous.inflation)) -> \(formatPercent(current.inflation)); unemployment \(formatPercent(previous.unemployment)) -> \(formatPercent(current.unemployment))",
        basis: "Uses the closing mandate metrics and engine deltas from the completed quarter.",
        detail: "Inflation is \(formatSigned(inflationGap)) pp from target; unemployment is \(formatSigned(unemploymentGap)) pp from target.",
        trend: trend,
        evidence: [
            "Inflation \(formatSigned(current.inflation - previous.inflation)) pp",
            "Unemployment \(formatSigned(current.unemployment - previous.unemployment)) pp",
            "Credibility \(formatSigned(current.credibility - previous.credibility)) pts",
        ],
        signals: [
            "Distance: \(formatSigned(mandateMove)) pp",
            "Inflation: \(formatSigned(trace.inflationDelta)) pp",
            "Jobs: \(formatSigned(trace.unemploymentDelta)) pp",
        ],
        traceInputs: ["previous MacroState", "current MacroState", "EngineTrace.inflationDelta", "EngineTrace.unemploymentDelta", "scenario mandate targets"],
    )
}

private func transmissionSummary(decision: PolicyDecision, previous: MacroState, current: MacroState, trace: EngineTrace) -> String {
    let action = if decision.rateChange > 0 {
        "raising rates \(formatSigned(decision.rateChange)) pp"
    } else if decision.rateChange < 0 {
        "cutting rates \(formatSigned(decision.rateChange)) pp"
    } else {
        "holding rates steady"
    }
    let lagStance = trace.laggedPolicyGap > 0.35 ? "restrictive lag" : trace.laggedPolicyGap < -0.35 ? "easy lag" : "near-neutral lag"
    return "After \(action), the quarter closed with inflation \(formatSigned(current.inflation - previous.inflation)) pp, unemployment \(formatSigned(current.unemployment - previous.unemployment)) pp, and output gap \(formatSigned(current.outputGap - previous.outputGap)) pp as the \(lagStance) reached the economy."
}

private func transmissionPath(decision: PolicyDecision, previous: MacroState, current: MacroState, trace: EngineTrace) -> [String] {
    let policyLeg = if decision.rateChange > 0 {
        "Higher target \(formatSigned(decision.rateChange)) pp"
    } else if decision.rateChange < 0 {
        "Lower target \(formatSigned(decision.rateChange)) pp"
    } else {
        "Hold at \(formatPercent(decision.resultingFedFundsRate))"
    }
    let demandLeg = trace.laggedPolicyGap > 0.35 ? "Tighter lag \(formatSigned(trace.laggedPolicyGap)) pp" : trace.laggedPolicyGap < -0.35 ? "Easier lag \(formatSigned(trace.laggedPolicyGap)) pp" : "Neutral lag \(formatSigned(trace.laggedPolicyGap)) pp"
    let mandateLeg = "Inflation \(formatSigned(current.inflation - previous.inflation)) pp, jobs \(formatSigned(current.unemployment - previous.unemployment)) pp"
    return [policyLeg, demandLeg, mandateLeg]
}

private func causalChain(
    decision: PolicyDecision,
    previous: MacroState,
    current: MacroState,
    trace: EngineTrace,
    scenario: ScenarioConfig,
) -> [TransmissionCausalLink] {
    let neutralGap = decision.resultingFedFundsRate - trace.neutralRate
    let channels = traceShockChannels(trace)
    let shockIntensity = channels.totalIntensity
    let outputDelta = current.outputGap - previous.outputGap
    let inflationGap = current.inflation - scenario.targets.inflation
    let unemploymentGap = current.unemployment - scenario.targets.unemployment
    let previousMiss = abs(previous.inflation - scenario.targets.inflation) + abs(previous.unemployment - scenario.targets.unemployment)
    let currentMiss = abs(inflationGap) + abs(unemploymentGap)
    let mandateDelta = currentMiss - previousMiss
    return [
        TransmissionCausalLink(
            label: "Decision impulse",
            text: "The move leaves policy \(formatSigned(neutralGap)) pp from neutral, setting the signal that markets absorb first.",
            tone: decision.rateChange > 0 || neutralGap > 0.35 ? .cooling : decision.rateChange < 0 || neutralGap < -0.35 ? .heating : .stabilizing,
        ),
        TransmissionCausalLink(
            label: "Lag plus shocks",
            text: "That signal meets a \(formatSigned(trace.laggedPolicyGap)) pp lag and \(shockChannelSummary(channels)), moving output \(formatSigned(outputDelta)) pp.",
            tone: shockIntensity > abs(trace.laggedPolicyGap) && shockIntensity > 0.25 ? .stress : outputDelta > 0.05 ? .heating : outputDelta < -0.05 ? .cooling : .stabilizing,
        ),
        TransmissionCausalLink(
            label: "Mandate read-through",
            text: "The combined inflation and labor miss moved \(formatSigned(mandateDelta)) pp, ending \(formatSigned(inflationGap)) pp on inflation and \(formatSigned(unemploymentGap)) pp on jobs.",
            tone: mandateDelta < -0.05 ? .stabilizing : mandateDelta > 0.05 ? .stress : .stabilizing,
        ),
    ]
}

private func transmissionChanges(previous: MacroState, current: MacroState, decision: PolicyDecision, trace: EngineTrace) -> [TransmissionChange] {
    let inflationDelta = current.inflation - previous.inflation
    let unemploymentDelta = current.unemployment - previous.unemployment
    let outputDelta = current.outputGap - previous.outputGap
    let credibilityDelta = current.credibility - previous.credibility
    let expectationsDelta = current.expectedInflation - previous.expectedInflation
    let channels = traceShockChannels(trace)
    return [
        TransmissionChange(
            label: "Inflation",
            previous: formatPercent(previous.inflation),
            current: formatPercent(current.inflation),
            delta: "\(formatSigned(inflationDelta)) pp",
            reason: "Engine delta \(formatSigned(trace.inflationDelta)) pp; expectations \(formatSigned(expectationsDelta)) pp.",
            tone: inflationDelta > 0.05 ? .heating : inflationDelta < -0.05 ? .cooling : .stabilizing,
        ),
        TransmissionChange(
            label: "Unemployment",
            previous: formatPercent(previous.unemployment),
            current: formatPercent(current.unemployment),
            delta: "\(formatSigned(unemploymentDelta)) pp",
            reason: "Labor delta \(formatSigned(trace.unemploymentDelta)) pp; output \(formatSigned(outputDelta)) pp.",
            tone: unemploymentDelta > 0.05 ? .stress : .stabilizing,
        ),
        TransmissionChange(
            label: "Output gap",
            previous: "\(formatSigned(previous.outputGap)) pp",
            current: "\(formatSigned(current.outputGap)) pp",
            delta: "\(formatSigned(outputDelta)) pp",
            reason: "Lagged policy gap \(formatSigned(trace.laggedPolicyGap)) pp; \(shockChannelSummary(channels)).",
            tone: outputDelta > 0.05 ? .heating : outputDelta < -0.05 ? .cooling : .stabilizing,
        ),
        TransmissionChange(
            label: "Credibility",
            previous: String(format: "%.0f", previous.credibility),
            current: String(format: "%.0f", current.credibility),
            delta: "\(formatSigned(credibilityDelta)) pts",
            reason: "Policy move \(formatSigned(decision.rateChange)) pp; expectations \(formatSigned(expectationsDelta)) pp.",
            tone: credibilityDelta < -0.05 ? .stress : .stabilizing,
        ),
    ]
}

private func transmissionReceipt(
    previous: MacroState,
    current: MacroState,
    decision: PolicyDecision,
    trace: EngineTrace,
    scenario: ScenarioConfig,
) -> TransmissionReceipt {
    let inflationGap = current.inflation - scenario.targets.inflation
    let laborGap = current.unemployment - scenario.targets.unemployment
    let previousMiss = abs(previous.inflation - scenario.targets.inflation) + abs(previous.unemployment - scenario.targets.unemployment)
    let currentMiss = abs(inflationGap) + abs(laborGap)
    let mandateMove = currentMiss - previousMiss
    let channels = traceShockChannels(trace)
    let shockIntensity = channels.totalIntensity
    let tone: TransmissionTrend = if mandateMove < -0.08 {
        .stabilizing
    } else if mandateMove > 0.08 || shockIntensity > 0.65 {
        .stress
    } else if trace.laggedPolicyGap > 0.35 {
        .cooling
    } else if trace.laggedPolicyGap < -0.35 {
        .heating
    } else {
        .stabilizing
    }
    let headline = mandateMove < -0.08 ? "Mandate gap narrowed" : mandateMove > 0.08 ? "Mandate gap widened" : "Mandate gap held steady"
    let verdict = mandateMove < -0.08
        ? "The combined inflation and labor miss improved \(formatMagnitude(mandateMove)) pp this quarter."
        : mandateMove > 0.08
        ? "The combined inflation and labor miss deteriorated \(formatSigned(mandateMove)) pp this quarter."
        : "The combined inflation and labor miss moved only \(formatSigned(mandateMove)) pp this quarter."
    let policyDirection = decision.rateChange > 0 ? "hike" : decision.rateChange < 0 ? "cut" : "hold"
    let policyEcho = policyDirection == "hold"
        ? "The hold kept the target at \(formatPercent(decision.resultingFedFundsRate)) while the lag registered \(formatSigned(trace.laggedPolicyGap)) pp."
        : "The \(policyDirection) moved \(formatSigned(decision.rateChange)) pp to \(formatPercent(decision.resultingFedFundsRate)); the current lag registered \(formatSigned(trace.laggedPolicyGap)) pp."
    let nextWatch = if shockIntensity > abs(trace.laggedPolicyGap), shockIntensity > 0.25 {
        "Watch shock channels next: \(shockChannelSummary(channels))."
    } else if abs(decision.rateChange) >= 0.75 {
        "Watch for overshoot risk: a large move can keep transmitting into the next quarter."
    } else if abs(inflationGap) > abs(laborGap) {
        "Watch inflation gap next: \(formatSigned(inflationGap)) pp from target."
    } else {
        "Watch labor gap next: \(formatSigned(laborGap)) pp from target."
    }
    return TransmissionReceipt(headline: headline, verdict: verdict, policyEcho: policyEcho, nextWatch: nextWatch, tone: tone)
}

private func decisionMemo(
    previous: MacroState,
    current: MacroState,
    decision: PolicyDecision,
    trace: EngineTrace,
    scenario: ScenarioConfig,
) -> TransmissionDecisionMemo {
    let previousInflationGap = previous.inflation - scenario.targets.inflation
    let previousLaborGap = previous.unemployment - scenario.targets.unemployment
    let currentInflationGap = current.inflation - scenario.targets.inflation
    let currentLaborGap = current.unemployment - scenario.targets.unemployment
    let outputDelta = current.outputGap - previous.outputGap
    let channels = traceShockChannels(trace)
    let shockIntensity = channels.totalIntensity
    let needsCooling = previousInflationGap > 0.15 || previousLaborGap < -0.25
    let needsHeating = previousInflationGap < -0.15 || previousLaborGap > 0.25
    let pressureTone: TransmissionTrend = needsCooling ? .cooling : needsHeating ? .heating : .stabilizing
    let actionTone: TransmissionTrend = decision.rateChange > 0 ? .cooling : decision.rateChange < 0 ? .heating : .stabilizing
    let aligned = (pressureTone == .cooling && decision.rateChange > 0) || (pressureTone == .heating && decision.rateChange < 0) || (pressureTone == .stabilizing && decision.rateChange == 0)
    let contrarian = (pressureTone == .cooling && decision.rateChange < 0) || (pressureTone == .heating && decision.rateChange > 0)
    let actionLabel = decision.rateChange > 0 ? "tightening" : decision.rateChange < 0 ? "easing" : "holding"
    let pressureLabel = pressureTone == .cooling ? "cooling pressure" : pressureTone == .heating ? "support pressure" : "balanced pressure"
    let headline = "\(aligned ? "Aligned" : contrarian ? "Contrarian" : "Cautious") \(actionLabel) against \(pressureLabel)"
    let tradeoff = decision.rateChange == 0
        ? "The hold let the \(formatSigned(trace.laggedPolicyGap)) pp lag carry the quarter while output moved \(formatSigned(outputDelta)) pp."
        : "The \(actionLabel) impulse met a \(formatSigned(trace.laggedPolicyGap)) pp policy lag while output moved \(formatSigned(outputDelta)) pp."
    let risk = if shockIntensity > abs(trace.laggedPolicyGap) && shockIntensity > 0.25 {
        "Main risk: \(shockChannelSummary(channels)) can swamp the latest rate signal."
    } else if abs(currentInflationGap) >= abs(currentLaborGap) {
        "Main risk: inflation remains \(formatSigned(currentInflationGap)) pp from target after the decision."
    } else {
        "Main risk: labor remains \(formatSigned(currentLaborGap)) pp from target after the decision."
    }
    let nextBias = if currentInflationGap > 0.25 || currentLaborGap < -0.3 {
        "Next bias: lean tighter unless the mandate gap cools."
    } else if currentInflationGap < -0.25 || currentLaborGap > 0.3 {
        "Next bias: lean easier unless activity firms."
    } else {
        "Next bias: stay data-dependent near the mandate corridor."
    }
    return TransmissionDecisionMemo(
        headline: headline,
        assessment: "Before the vote: inflation \(formatSigned(previousInflationGap)) pp from target, labor \(formatSigned(previousLaborGap)) pp from target.",
        tradeoff: tradeoff,
        risk: risk,
        nextBias: nextBias,
        tone: contrarian ? .stress : actionTone,
    )
}
