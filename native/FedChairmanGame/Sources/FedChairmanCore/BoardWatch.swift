import Foundation

public enum BoardWatchTone: String, Codable, Equatable, Sendable {
    case onTrack
    case watch
    case danger
    case complete
}

public struct BoardWatch: Equatable, Sendable {
    public var headline: String
    public var gateLabel: String
    public var scoreLabel: String
    public var scoreDetail: String
    public var inflationDetail: String
    public var laborDetail: String
    public var credibilityDetail: String
    public var riskLabel: String
    public var quartersRemaining: Int
    public var tone: BoardWatchTone

    public var accessibilityLabel: String {
        "Board Watch. \(headline). \(gateLabel). \(scoreDetail). \(inflationDetail). \(laborDetail). \(riskLabel)."
    }
}

public func buildBoardWatch(session: GameSession, scenario: ScenarioConfig = classicScenario) -> BoardWatch {
    let score = session.score
    let current = session.current
    let quartersRemaining = max(0, scenario.termQuarters - session.currentTermQuarter)
    let scorePass = score.score >= 70
    let inflationPass = current.inflation <= 4
    let laborPass = current.unemployment <= 7
    let gatesPassed = [scorePass, inflationPass, laborPass].count { $0 }
    let tone = boardWatchTone(
        status: session.status,
        score: score,
        current: current,
        gatesPassed: gatesPassed,
        quartersRemaining: quartersRemaining,
    )

    return BoardWatch(
        headline: boardWatchHeadline(status: session.status, tone: tone, quartersRemaining: quartersRemaining),
        gateLabel: "\(gatesPassed)/3 gates",
        scoreLabel: "\(formatBoardNumber(score.score, digits: 1)) \(score.grade.rawValue)",
        scoreDetail: "Score \(formatBoardNumber(score.score, digits: 1)) (\(score.grade.rawValue)), needs 70",
        inflationDetail: "Inflation \(formatBoardPercent(current.inflation)), cap 4.00%",
        laborDetail: "Unemployment \(formatBoardPercent(current.unemployment)), cap 7.00%",
        credibilityDetail: "Credibility \(formatBoardNumber(current.credibility, digits: 0))",
        riskLabel: boardWatchRiskLabel(
            scorePass: scorePass,
            inflationPass: inflationPass,
            laborPass: laborPass,
            credibility: current.credibility,
            quartersRemaining: quartersRemaining,
        ),
        quartersRemaining: quartersRemaining,
        tone: tone,
    )
}

private func boardWatchTone(
    status: CareerStatus,
    score: ScoreState,
    current: MacroState,
    gatesPassed: Int,
    quartersRemaining: Int,
) -> BoardWatchTone {
    switch status {
    case .retired, .termDebrief:
        return .complete
    case .notReappointed:
        return .danger
    case .notStarted, .inProgress:
        if gatesPassed == 3 {
            return quartersRemaining <= 4 ? .watch : .onTrack
        }
        if gatesPassed <= 1 || score.score < 60 || current.inflation > 4.75 || current.unemployment > 7.75 {
            return .danger
        }
        return .watch
    }
}

private func boardWatchHeadline(status: CareerStatus, tone: BoardWatchTone, quartersRemaining: Int) -> String {
    switch status {
    case .termDebrief:
        "Renewal earned"
    case .retired:
        "Career closed"
    case .notReappointed:
        "Renewal missed"
    case .notStarted:
        "Board watching"
    case .inProgress:
        switch tone {
        case .onTrack:
            "On track for renewal"
        case .watch:
            quartersRemaining <= 4 ? "Final-year watch" : "Board watch"
        case .danger:
            "Renewal at risk"
        case .complete:
            "Renewal earned"
        }
    }
}

private func boardWatchRiskLabel(
    scorePass: Bool,
    inflationPass: Bool,
    laborPass: Bool,
    credibility: Double,
    quartersRemaining: Int,
) -> String {
    if !scorePass {
        return "Raise score above 70"
    }
    if !inflationPass {
        return "Cool inflation below 4.0%"
    }
    if !laborPass {
        return "Ease labor stress below 7.0%"
    }
    if credibility < 70 {
        return "Rebuild credibility cushion"
    }
    if quartersRemaining <= 4 {
        return "Protect the landing"
    }
    return "Protect the glide path"
}

private func formatBoardPercent(_ value: Double) -> String {
    "\(formatBoardNumber(value, digits: 2))%"
}

private func formatBoardNumber(_ value: Double, digits: Int) -> String {
    String(format: "%.\(digits)f", value)
}
