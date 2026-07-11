import Foundation

public enum SemanticState: String, Codable, Equatable, Sendable {
    case neutral
    case onTrack
    case atRisk
    case critical
    case disabled
}

public struct LatestMetrics: Equatable, Sendable {
    public var inflation: Double
    public var unemployment: Double
    public var fedFundsRate: Double
    public var expectedInflation: Double
    public var credibility: Double
    public var inflationGap: Double
    public var laborGap: Double
    public var mandateGap: Double

    public init(current: MacroState, targets: MandateTargets = classicScenario.targets) {
        inflation = current.inflation
        unemployment = current.unemployment
        fedFundsRate = current.fedFundsRate
        expectedInflation = current.expectedInflation
        credibility = current.credibility
        inflationGap = roundSnapshotValue(current.inflation - targets.inflation)
        laborGap = roundSnapshotValue(current.unemployment - targets.unemployment)
        mandateGap = roundSnapshotValue(abs(inflationGap) + abs(laborGap))
    }
}

public struct RiskDriver: Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case inflationGap
        case laborGap
        case credibility
        case laggedPolicy
        case activeShocks
    }

    public var id: Kind {
        kind
    }

    public var kind: Kind
    public var state: SemanticState
    public var score: Double
    public var title: String
    public var detail: String

    public init(kind: Kind, state: SemanticState, score: Double, title: String, detail: String) {
        self.kind = kind
        self.state = state
        self.score = roundSnapshotValue(score)
        self.title = title
        self.detail = detail
    }
}

public struct TermSnapshot: Equatable, Sendable {
    public var sourceSessionId: String
    public var status: CareerStatus
    public var termNumber: Int
    public var currentTermQuarter: Int
    public var totalCareerQuarters: Int
    public var boardWatch: BoardWatch
    public var briefing: CockpitBriefing
    public var decisionFeedback: DecisionFeedback
    public var chartInspection: ChartInspection?
    public var semanticState: SemanticState
    public var riskDrivers: [RiskDriver]
    public var latestMetrics: LatestMetrics

    public init(session: GameSession, scenario: ScenarioConfig = classicScenario) {
        let latestMetrics = LatestMetrics(current: session.current, targets: scenario.targets)
        let riskDrivers = buildRiskDrivers(session: session, latestMetrics: latestMetrics)

        sourceSessionId = session.sessionId
        status = session.status
        termNumber = session.termNumber
        currentTermQuarter = session.currentTermQuarter
        totalCareerQuarters = session.totalCareerQuarters
        boardWatch = buildBoardWatch(session: session, scenario: scenario)
        briefing = buildCockpitBriefing(session: session, scenario: scenario)
        decisionFeedback = buildDecisionFeedback(session: session, scenario: scenario)
        chartInspection = buildChartInspection(
            history: session.careerHistory,
            decisions: session.completedTerms.flatMap(\.decisions) + session.decisions,
            termQuarters: scenario.termQuarters,
        )
        semanticState = deriveSemanticState(session: session, latestMetrics: latestMetrics, riskDrivers: riskDrivers)
        self.riskDrivers = riskDrivers
        self.latestMetrics = latestMetrics
    }
}

public func buildTermSnapshot(session: GameSession, scenario: ScenarioConfig = classicScenario) -> TermSnapshot {
    TermSnapshot(session: session, scenario: scenario)
}

public func buildRiskDrivers(session: GameSession, scenario: ScenarioConfig = classicScenario) -> [RiskDriver] {
    buildRiskDrivers(session: session, latestMetrics: LatestMetrics(current: session.current, targets: scenario.targets))
}

private func buildRiskDrivers(session: GameSession, latestMetrics: LatestMetrics) -> [RiskDriver] {
    let laggedPolicyGap = session.traces.last?.laggedPolicyGap
    let shockPressure = session.activeShocks.reduce(0) { partial, shock in
        partial + abs(shock.magnitude) * Double(max(1, shock.remaining))
    }
    let activeShockDetail = activeShockSummary(session.activeShocks)

    let drivers = [
        RiskDriver(
            kind: .inflationGap,
            state: riskState(score: abs(latestMetrics.inflationGap), warning: 0.8, critical: 1.4),
            score: 20 + abs(latestMetrics.inflationGap) * 100,
            title: latestMetrics.inflationGap >= 0 ? "Inflation above target" : "Inflation below target",
            detail: "Inflation gap \(formatSnapshotSigned(latestMetrics.inflationGap)) pp versus target.",
        ),
        RiskDriver(
            kind: .laborGap,
            state: riskState(score: abs(latestMetrics.laborGap), warning: 1.0, critical: 2.0),
            score: abs(latestMetrics.laborGap) * 92,
            title: latestMetrics.laborGap >= 0 ? "Labor slack above target" : "Labor market running tight",
            detail: "Unemployment gap \(formatSnapshotSigned(latestMetrics.laborGap)) pp versus target.",
        ),
        RiskDriver(
            kind: .credibility,
            state: credibilityRiskState(latestMetrics.credibility),
            score: max(0, 75 - latestMetrics.credibility) * 4,
            title: "Credibility buffer",
            detail: "Credibility at \(formatSnapshotNumber(latestMetrics.credibility, digits: 0)); lower buffers narrow policy room.",
        ),
        RiskDriver(
            kind: .laggedPolicy,
            state: laggedPolicyGap.map { riskState(score: abs($0), warning: 0.55, critical: 1.1) } ?? .neutral,
            score: laggedPolicyGap.map { 10 + abs($0) * 120 } ?? 0,
            title: "Lagged policy pressure",
            detail: laggedPolicyGap.map { "Latest trace shows \(formatSnapshotSigned($0)) pp of lagged policy pressure." } ?? "No lagged policy trace is available yet.",
        ),
        RiskDriver(
            kind: .activeShocks,
            state: riskState(score: shockPressure, warning: 0.8, critical: 1.8),
            score: shockPressure * 70,
            title: "Active shock pressure",
            detail: activeShockDetail,
        ),
    ]

    return drivers.sorted { lhs, rhs in
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return riskDriverTieBreak(lhs.kind) < riskDriverTieBreak(rhs.kind)
    }
}

private func deriveSemanticState(session: GameSession, latestMetrics: LatestMetrics, riskDrivers: [RiskDriver]) -> SemanticState {
    switch session.status {
    case .notStarted, .retired:
        return .disabled
    case .notReappointed:
        return .critical
    case .termDebrief:
        return session.score.reappointed ? .onTrack : .critical
    case .inProgress:
        if riskDrivers.contains(where: { $0.state == .critical }) || session.score.score < 60 {
            return .critical
        }
        if riskDrivers.contains(where: { $0.state == .atRisk }) || latestMetrics.mandateGap >= 1.2 || session.score.score < 70 {
            return .atRisk
        }
        if latestMetrics.mandateGap <= 0.75, latestMetrics.credibility >= 70, session.activeShocks.isEmpty {
            return .onTrack
        }
        return .neutral
    }
}

private func riskState(score: Double, warning: Double, critical: Double) -> SemanticState {
    if score >= critical {
        return .critical
    }
    if score >= warning {
        return .atRisk
    }
    return .neutral
}

private func credibilityRiskState(_ credibility: Double) -> SemanticState {
    if credibility < 45 {
        return .critical
    }
    if credibility < 65 {
        return .atRisk
    }
    if credibility >= 80 {
        return .onTrack
    }
    return .neutral
}

private func activeShockSummary(_ activeShocks: [ActiveShock]) -> String {
    guard !activeShocks.isEmpty else {
        return "No active shocks are carrying into this quarter."
    }
    let ordered = activeShocks.sorted { lhs, rhs in
        if abs(lhs.magnitude) != abs(rhs.magnitude) {
            return abs(lhs.magnitude) > abs(rhs.magnitude)
        }
        return lhs.id < rhs.id
    }
    let first = ordered[0]
    let suffix = ordered.count == 1 ? "" : " plus \(ordered.count - 1) more"
    let futureQuarters = max(0, first.remaining - 1)
    if futureQuarters == 0 {
        return "\(first.type.rawValue.capitalized) shock \(formatSnapshotSigned(first.magnitude)) is dissipating before next quarter\(suffix)."
    }
    return "\(first.type.rawValue.capitalized) shock \(formatSnapshotSigned(first.magnitude)) with \(futureQuarters) future qtr remaining\(suffix)."
}

private func riskDriverTieBreak(_ kind: RiskDriver.Kind) -> Int {
    switch kind {
    case .inflationGap:
        0
    case .laborGap:
        1
    case .credibility:
        2
    case .laggedPolicy:
        3
    case .activeShocks:
        4
    }
}

private func roundSnapshotValue(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}

private func formatSnapshotSigned(_ value: Double) -> String {
    "\(value >= 0 ? "+" : "")\(formatSnapshotNumber(value, digits: 2))"
}

private func formatSnapshotNumber(_ value: Double, digits: Int) -> String {
    String(format: "%.\(digits)f", value)
}
