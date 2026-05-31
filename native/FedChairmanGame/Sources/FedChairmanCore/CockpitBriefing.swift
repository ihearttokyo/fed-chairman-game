import Foundation

public enum BriefingSeverity: String, Codable, Equatable, Sendable {
    case normal
    case watch
    case warning
    case critical
}

public struct CockpitBriefing: Equatable, Sendable {
    public var kicker: String
    public var headline: String
    public var metadata: String
    public var severity: BriefingSeverity
    public var body: String
    public var policyImplication: String
    public var riskCalendar: String
}

public struct HelpTopic: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var body: String
    public var isPrimary: Bool = false
}

public func buildCockpitBriefing(session: GameSession, scenario: ScenarioConfig = classicScenario) -> CockpitBriefing {
    let state = session.current
    let inflationGap = state.inflation - scenario.targets.inflation
    let laborGap = state.unemployment - scenario.targets.unemployment
    let dominantShock = session.latestTriggeredShocks.first
    let severity = briefingSeverity(inflationGap: inflationGap, laborGap: laborGap, credibility: state.credibility, hasShock: dominantShock != nil)
    let pressure = abs(inflationGap) >= abs(laborGap) ? "inflation" : "labor"
    let direction = policyDirection(inflationGap: inflationGap, laborGap: laborGap)

    return CockpitBriefing(
        kicker: dominantShock == nil ? "Quarterly Briefing" : "\(dominantShock!.type.rawValue.capitalized) Shock",
        headline: briefingHeadline(inflationGap: inflationGap, laborGap: laborGap, credibility: state.credibility, pressure: pressure),
        metadata: "Term \(session.termNumber) | Q\(state.quarterIndex) | \(severity.rawValue.uppercased())",
        severity: severity,
        body: session.traces.last?.explanation ?? "Markets are reading the opening stance, current credibility, and early policy signal.",
        policyImplication: direction,
        riskCalendar: "Watch \(pressure), credibility \(String(format: "%.0f", state.credibility)), and lagged policy over the next quarter.",
    )
}

public func buildHelpTopics(session: GameSession, scenario: ScenarioConfig = classicScenario) -> [HelpTopic] {
    buildHelpTopics(current: session.current, scenario: scenario, trace: session.traces.last, activeShocks: session.activeShocks)
}

public func buildHelpTopics(current: MacroState, scenario: ScenarioConfig = classicScenario, trace: EngineTrace? = nil, activeShocks: [ActiveShock] = []) -> [HelpTopic] {
    let neutralRate = scenario.coefficients.realNeutralRate + current.expectedInflation
    let stance = if current.fedFundsRate > neutralRate + 0.5 {
        "restrictive"
    } else if current.fedFundsRate < neutralRate - 0.5 {
        "expansionary"
    } else {
        "near neutral"
    }

    var topics = [
        HelpTopic(
            id: "job",
            title: "Your Job",
            body: "Guide inflation toward \(String(format: "%.1f", scenario.targets.inflation))% while keeping unemployment near \(String(format: "%.1f", scenario.targets.unemployment))% over each 16-quarter term.",
            isPrimary: true,
        ),
        HelpTopic(
            id: "fed-funds-rate",
            title: "Federal Funds Rate",
            body: "The current rate is \(String(format: "%.2f", current.fedFundsRate))%. The model estimates neutral near \(String(format: "%.2f", neutralRate))%, so policy is \(stance).",
            isPrimary: true,
        ),
        HelpTopic(
            id: "dual-mandate",
            title: "Dual Mandate",
            body: "A good term balances price stability and maximum employment. Pushing one goal too hard can damage the other.",
        ),
        HelpTopic(
            id: "expansionary-policy",
            title: "Expansionary Policy",
            body: "Rate cuts tend to support spending, output, and hiring. If demand runs too hot, inflation can rise later.",
        ),
        HelpTopic(
            id: "contractionary-policy",
            title: "Contractionary Policy",
            body: "Rate hikes tend to cool spending and inflation. The tradeoff is a higher chance of weaker growth and unemployment.",
        ),
        HelpTopic(
            id: "policy-lags",
            title: "Policy Lags",
            body: "Your decisions work gradually. The strongest effect usually appears several quarters after the rate change.",
        ),
        HelpTopic(
            id: "policy-questions",
            title: "Policy Questions",
            body: "Before each vote, ask whether inflation is moving toward target, whether labor-market slack is becoming costly, and whether credibility gives you room to move gradually.",
        ),
        HelpTopic(
            id: "what-to-watch",
            title: "What To Watch",
            body: "Track unemployment, output gap, expectations, credibility, and lagged policy. These are reference concepts, not new incoming news.",
        ),
    ]

    if current.inflation > scenario.targets.inflation + 1 {
        topics.append(HelpTopic(
            id: "credibility-matters",
            title: "Why Credibility Matters",
            body: "When inflation stays high, expectations can drift up. Strong credibility makes it easier to return inflation to target without a deeper slowdown.",
        ))
    }
    if current.unemployment > scenario.targets.unemployment + 1.4 {
        topics.append(HelpTopic(
            id: "easing-with-care",
            title: "Easing With Care",
            body: "Cuts can support hiring, but their full effect arrives later. If inflation is still elevated, easing too quickly can create a stop-go cycle.",
        ))
    }
    if let trace, abs(trace.laggedPolicyGap) > 0.75 {
        topics.append(HelpTopic(
            id: "reading-old-decisions",
            title: "Reading Old Decisions",
            body: "A large lagged policy gap means today's data is still being shaped by earlier rate choices. Reacting only to the latest quarter can cause overcorrection.",
        ))
    }
    if !activeShocks.isEmpty {
        topics.append(HelpTopic(
            id: "temporary-shock-or-trend",
            title: "Temporary Shock Or Trend?",
            body: "A shock can move inflation and unemployment at the same time. The policy challenge is judging whether it will fade or change expectations.",
        ))
    }

    return topics
}

public func staticHelpTopics(scenario: ScenarioConfig = classicScenario) -> [HelpTopic] {
    buildHelpTopics(current: scenario.startingState, scenario: scenario)
}

private func briefingSeverity(inflationGap: Double, laborGap: Double, credibility: Double, hasShock: Bool) -> BriefingSeverity {
    if abs(inflationGap) >= 1.4 || laborGap >= 2.5 || credibility < 45 {
        return .critical
    }
    if abs(inflationGap) >= 0.8 || laborGap >= 1.4 || credibility < 60 {
        return .warning
    }
    if hasShock || abs(inflationGap) >= 0.35 || laborGap >= 0.6 {
        return .watch
    }
    return .normal
}

private func briefingHeadline(inflationGap: Double, laborGap: Double, credibility: Double, pressure: String) -> String {
    if credibility < 55 {
        return "Credibility is becoming the binding policy constraint"
    }
    if laborGap >= 1.4 {
        return "Labor-market weakness is becoming a reappointment risk"
    }
    if inflationGap >= 0.8 {
        return "Inflation pressure is testing the policy path"
    }
    if inflationGap <= -0.8 {
        return "Inflation is undershooting while demand cools"
    }
    return "The \(pressure) side of the mandate is setting the tone"
}

private func policyDirection(inflationGap: Double, laborGap: Double) -> String {
    if inflationGap >= 0.35, abs(inflationGap) >= abs(laborGap) {
        return "Bias tighter unless labor stress accelerates."
    }
    if laborGap >= 0.6 || inflationGap <= -0.35 {
        return "Bias easier unless inflation expectations re-accelerate."
    }
    return "Hold or move gradually; avoid creating a new mandate miss."
}
