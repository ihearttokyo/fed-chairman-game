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
    if session.ui.trumpCheatActivatedCareerQuarter != nil {
        let inflationCap = activeInflationUpperBound(ui: session.ui, currentCareerQuarter: session.totalCareerQuarters)
        return CockpitBriefing(
            kicker: "Cheat Event",
            headline: "Trump elected; Fed independence crisis hits the desk",
            metadata: "Term \(session.termNumber) | Q\(state.quarterIndex) | CRITICAL",
            severity: .critical,
            body: "A televised loyalty ceremony and fascistic salute controversy have shattered the normal mandate frame.",
            policyImplication: "Political pressure now tolerates inflation up to \(String(format: "%.2f", inflationCap))%, falling 0.25 pp each quarter.",
            riskCalendar: "Watch credibility, institutional stress, and the shrinking inflation cap.",
        )
    }
    let inflationGap = state.inflation - scenario.targets.inflation
    let laborGap = state.unemployment - scenario.targets.unemployment
    let dominantShock = session.latestTriggeredShocks.first
    let severity = briefingSeverity(inflationGap: inflationGap, laborGap: laborGap, credibility: state.credibility, hasShock: dominantShock != nil)
    let pressure = abs(inflationGap) >= abs(laborGap) ? "inflation" : "labor"
    let direction = policyDirection(inflationGap: inflationGap, laborGap: laborGap)
    let briefSeed = "\(session.seed):t\(session.termNumber):q\(state.quarterIndex):\(dominantShock?.headlineKey ?? "baseline")"

    return CockpitBriefing(
        kicker: briefingKicker(shock: dominantShock, seed: briefSeed),
        headline: briefingHeadline(inflationGap: inflationGap, laborGap: laborGap, credibility: state.credibility, pressure: pressure, seed: briefSeed),
        metadata: "Term \(session.termNumber) | Q\(state.quarterIndex) | \(severity.rawValue.uppercased())",
        severity: severity,
        body: briefingBody(
            traceExplanation: session.traces.last?.explanation,
            inflationGap: inflationGap,
            laborGap: laborGap,
            credibility: state.credibility,
            seed: briefSeed,
        ),
        policyImplication: direction,
        riskCalendar: briefingRiskCalendar(pressure: pressure, credibility: state.credibility, seed: briefSeed),
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

private func briefingKicker(shock: Shock?, seed: String) -> String {
    guard let shock else {
        return deterministicChoice([
            "Quarterly Briefing",
            "Desk Open",
            "Mandate Wire",
            "Policy Morning",
        ], seed: seed)
    }
    return deterministicChoice([
        "\(shock.type.rawValue.capitalized) Shock",
        "\(shock.type.rawValue.capitalized) Watch",
        "Incoming \(shock.type.rawValue.capitalized) Pressure",
    ], seed: seed)
}

private func briefingHeadline(inflationGap: Double, laborGap: Double, credibility: Double, pressure: String, seed: String) -> String {
    if credibility < 55 {
        return deterministicChoice([
            "Credibility is becoming the binding policy constraint",
            "Markets are marking down the policy reaction function",
            "The confidence buffer is thinning before the next vote",
        ], seed: seed)
    }
    if laborGap >= 1.4 {
        return deterministicChoice([
            "Labor-market weakness is becoming a reappointment risk",
            "Hiring slack is moving to the center of the mandate",
            "The labor side of the scorecard is flashing amber",
        ], seed: seed)
    }
    if inflationGap >= 0.8 {
        return deterministicChoice([
            "Inflation pressure is testing the policy path",
            "Price momentum is forcing a cleaner signal",
            "Inflation is asking whether the desk will lean in",
        ], seed: seed)
    }
    if inflationGap <= -0.8 {
        return deterministicChoice([
            "Inflation is undershooting while demand cools",
            "Soft prices give the desk room to protect labor",
            "The disinflation glide path may be turning too cold",
        ], seed: seed)
    }
    return deterministicChoice([
        "The \(pressure) side of the mandate is setting the tone",
        "The desk opens with a narrow but manageable mandate gap",
        "Markets see room for a measured first signal",
        "Both sides of the mandate are still in play",
    ], seed: seed)
}

private func briefingBody(traceExplanation: String?, inflationGap: Double, laborGap: Double, credibility: Double, seed: String) -> String {
    if let traceExplanation {
        return deterministicChoice([
            traceExplanation,
            "\(traceExplanation) The next vote should separate fresh data from lagged policy.",
            "\(traceExplanation) Watch whether credibility absorbs the move or amplifies it.",
        ], seed: seed)
    }
    let mandateLine = if abs(inflationGap) < 0.35, abs(laborGap) < 0.6 {
        "The opening economy is close enough to target that over-steering is the main rookie mistake."
    } else if abs(inflationGap) >= abs(laborGap) {
        "Inflation is the louder miss, but the labor buffer still matters for the reappointment gate."
    } else {
        "Labor slack is the louder miss, but easing too quickly can spend credibility."
    }
    return deterministicChoice([
        "\(mandateLine) Credibility starts near \(String(format: "%.0f", credibility)), giving you time to move gradually.",
        "\(mandateLine) Start by testing a small move and reading the transmission tape next quarter.",
        "\(mandateLine) The safest opening is a clear signal, not a dramatic one.",
    ], seed: seed)
}

private func briefingRiskCalendar(pressure: String, credibility: Double, seed: String) -> String {
    deterministicChoice([
        "Watch \(pressure), credibility \(String(format: "%.0f", credibility)), and lagged policy over the next quarter.",
        "Next read: \(pressure) trend, expectations, and whether credibility holds above \(String(format: "%.0f", credibility - 5)).",
        "Risk desk: separate temporary \(pressure) noise from the four-quarter policy lag.",
    ], seed: seed)
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

private func deterministicChoice(_ options: [String], seed: String) -> String {
    guard !options.isEmpty else {
        return ""
    }
    var hash = 5381
    for scalar in seed.unicodeScalars {
        hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
    }
    return options[abs(hash) % options.count]
}
