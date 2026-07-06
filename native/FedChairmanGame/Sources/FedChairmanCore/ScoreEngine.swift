import Foundation

private func gradeFor(score: Double) -> Grade {
    if score >= 90 {
        return .a
    }
    if score >= 80 {
        return .b
    }
    if score >= 70 {
        return .c
    }
    if score >= 60 {
        return .d
    }
    return .f
}

public let reappointmentInflationUpperBound = 4.0

public func evaluateScore(
    history: [MacroState],
    scenario: ScenarioConfig,
    inflationUpperBound: Double = reappointmentInflationUpperBound,
) -> ScoreState {
    let played = Array(history.dropFirst())
    let scored = played.isEmpty ? history : played
    let inflationGaps = scored.map { $0.inflation - scenario.targets.inflation }
    let unemploymentGaps = scored.map { $0.unemployment - scenario.targets.unemployment }
    let volatilityIndex = mean(Array(scored.dropFirst()).enumerated().map { index, state in
        let previous = scored[index]
        return abs(state.inflation - previous.inflation) + abs(state.unemployment - previous.unemployment)
    })
    let recessionQuarterShare = Double(scored.count(where: { $0.outputGap < -2 || $0.unemployment > 7 })) / Double(max(1, scored.count))
    let averageCredibility = mean(scored.map(\.credibility))
    let credibilityBonus = clamp((averageCredibility - 70) / 6, 0, 5)
    let meanAbsInflationGap = meanAbs(inflationGaps)
    let meanAbsUnemploymentGap = meanAbs(unemploymentGaps)
    let rawScore = 100 -
        10 * meanAbsInflationGap -
        8 * meanAbsUnemploymentGap -
        5 * volatilityIndex -
        12 * recessionQuarterShare +
        credibilityBonus
    let score = roundTo(clamp(rawScore, 0, 100), digits: 1)
    let final = history.last ?? scenario.startingState
    let reappointed = score >= 70 && final.inflation <= inflationUpperBound && final.unemployment <= 7
    let misses = [
        ("inflation drift", meanAbsInflationGap),
        ("unemployment gap", meanAbsUnemploymentGap),
        ("quarter-to-quarter volatility", volatilityIndex),
        ("recession risk", recessionQuarterShare * 2),
    ].sorted { $0.1 > $1.1 }
    let biggestMiss = misses.first?.0 ?? "none"
    let takeaway = switch biggestMiss {
    case "inflation drift":
        "Inflation responds with a lag, so waiting too long can require sharper later moves."
    case "unemployment gap":
        "Tight policy can stabilize prices but may overshoot into a weaker labor market."
    case "recession risk":
        "A successful term balances price stability against avoidable downturns."
    default:
        "Moderate, steady decisions usually work better than chasing each quarter of data."
    }

    return ScoreState(
        score: score,
        grade: gradeFor(score: score),
        reappointed: reappointed,
        meanAbsInflationGap: roundTo(meanAbsInflationGap),
        meanAbsUnemploymentGap: roundTo(meanAbsUnemploymentGap),
        volatilityIndex: roundTo(volatilityIndex),
        recessionQuarterShare: roundTo(recessionQuarterShare),
        credibilityBonus: roundTo(credibilityBonus),
        biggestMiss: biggestMiss,
        takeaway: takeaway,
    )
}
