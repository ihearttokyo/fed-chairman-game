import Foundation

private let shockTypes = ShockType.allCases
private let inflationCredibilityBand = 0.5
private let reappointmentGraceQuarters = 4
private let normalCredibilityRecovery = 0.6
private let outOfBandCredibilityDrift = -1.8
private let rateMoveCredibilityCost = 0.75
private let reappointmentGraceLimit = 2.4
private let laggedPolicyActiveThreshold = 0.35
private let trumpCheatMaxInflationTarget = 8.0
private let trumpCheatMinInflationTarget = 4.0
private let trumpCheatInflationDecayPerQuarter = 0.25

private func emptyShockContrib() -> [ShockType: Double] {
    Dictionary(uniqueKeysWithValues: shockTypes.map { ($0, 0) })
}

private func trumpCheatEffectiveInflationTarget(
    ui: UiState?,
    currentCareerQuarter: Int,
    normalTarget: Double,
) -> Double {
    guard let ui, let activatedQuarter = ui.trumpCheatActivatedCareerQuarter else {
        return normalTarget
    }
    let elapsedQuarters = max(0, currentCareerQuarter - activatedQuarter)
    let decayed = trumpCheatMaxInflationTarget - Double(elapsedQuarters) * trumpCheatInflationDecayPerQuarter
    return clamp(decayed, trumpCheatMinInflationTarget, trumpCheatMaxInflationTarget)
}

private func shouldTrigger(shock: Shock, quarterIndex: Int, seed: String) -> Bool {
    switch shock.quarter {
    case let .fixed(quarter):
        return quarter == quarterIndex
    case .random:
        var rng = SeededRng(seed: "\(seed):\(shock.id):\(quarterIndex)")
        return rng.next() > 0.78
    }
}

private func nextActiveShocks(
    scenario: ScenarioConfig,
    activeShocks: [ActiveShock],
    quarterIndex: Int,
    seed: String,
) -> (active: [ActiveShock], triggered: [Shock]) {
    let carried = activeShocks
        .map { shock -> ActiveShock in
            var next = shock
            next.remaining -= 1
            return next
        }
        .filter { $0.remaining > 0 }
    let triggered = scenario.shockDeck.filter { shouldTrigger(shock: $0, quarterIndex: quarterIndex, seed: seed) }
    let newActive = triggered.map { ActiveShock(shock: $0, startedQuarter: quarterIndex, remaining: $0.persistence) }
    return (carried + newActive, triggered)
}

private func shockContributions(activeShocks: [ActiveShock], scenario: ScenarioConfig) -> [ShockType: Double] {
    var contrib = emptyShockContrib()
    for shock in activeShocks {
        let age = shock.persistence - shock.remaining
        let decayed = shock.magnitude * pow(scenario.coefficients.shockDecay, Double(max(0, age)))
        contrib[shock.type, default: 0] += decayed
    }
    return contrib
}

private func laggedPolicyGap(history: [MacroState], scenario: ScenarioConfig) -> Double {
    let weights = [0.1, 0.25, 0.4, 0.25]
    let recent = history.suffix(4).reversed()
    guard !recent.isEmpty else {
        return 0
    }
    var weighted = 0.0
    var weightTotal = 0.0
    for (index, state) in recent.enumerated() {
        let weight = weights[index]
        let neutralRate = scenario.coefficients.realNeutralRate + state.expectedInflation
        weighted += (state.fedFundsRate - neutralRate) * weight
        weightTotal += weight
    }
    return weighted / weightTotal
}

public func advanceQuarter(
    history: [MacroState],
    decision: PolicyDecision,
    scenario: ScenarioConfig,
    activeShocks: [ActiveShock],
    seed: String,
    termNumber: Int = 1,
    ui: UiState? = nil,
    careerQuarterIndex: Int? = nil,
) throws -> AdvanceResult {
    guard let previous = history.last else {
        throw NativeEngineError.missingHistory
    }
    let quarterIndex = previous.quarterIndex + 1
    let targetCareerQuarter = careerQuarterIndex ?? quarterIndex
    let effectiveInflationTarget = trumpCheatEffectiveInflationTarget(
        ui: ui,
        currentCareerQuarter: targetCareerQuarter,
        normalTarget: scenario.targets.inflation,
    )
    let shockState = nextActiveShocks(scenario: scenario, activeShocks: activeShocks, quarterIndex: quarterIndex, seed: seed)
    let shocks = shockContributions(activeShocks: shockState.active, scenario: scenario)
    let coefficients = scenario.coefficients
    let neutralRate = coefficients.realNeutralRate + previous.expectedInflation
    let currentPolicyGap = decision.resultingFedFundsRate - neutralRate
    let laggedGap = laggedPolicyGap(history: history, scenario: scenario)
    let demandShock = (shocks[.demand] ?? 0) + 0.45 * (shocks[.confidence] ?? 0)
    let financialStress = abs(min(0, shocks[.financial] ?? 0)) * 0.8
    let supplyShock = (shocks[.supply] ?? 0) + (shocks[.energy] ?? 0) * 0.55
    let laborShock = max(0, shocks[.labor] ?? 0) * 0.35 + abs(min(0, shocks[.financial] ?? 0)) * 0.2
    let noise = deterministicNoise(seed: seed, quarterIndex: quarterIndex, salt: "macro", scale: coefficients.noiseScale)

    let outputGap = clamp(
        0.58 * previous.outputGap -
            coefficients.rateSensitivity * laggedGap +
            demandShock -
            financialStress +
            noise,
        -8,
        8,
    )
    let gdpGrowth = clamp(
        coefficients.trendGrowth + 0.65 * outputGap + demandShock * 0.35 - financialStress * 0.45,
        -9,
        9,
    )
    let unemployment = clamp(
        previous.unemployment - coefficients.okunCoefficient * (gdpGrowth - coefficients.trendGrowth) + laborShock,
        2,
        15,
    )
    let inflationGap = previous.inflation - effectiveInflationTarget
    let inflationInBand = previous.inflation <= effectiveInflationTarget + inflationCredibilityBand
    let credibilityBaseDrift = inflationInBand ? normalCredibilityRecovery : outOfBandCredibilityDrift
    let credibilityRateMoveCost = abs(decision.rateChange) * rateMoveCredibilityCost
    let rightDirectionForHighInflation =
        inflationGap > inflationCredibilityBand &&
        (decision.rateChange > 0 || (decision.rateChange == 0 && laggedGap > laggedPolicyActiveThreshold))
    let rightDirectionForLowInflation =
        inflationGap < -inflationCredibilityBand &&
        (decision.rateChange < 0 || (decision.rateChange == 0 && laggedGap < -laggedPolicyActiveThreshold))
    let eligibleForReappointmentGrace =
        termNumber > 1 &&
        quarterIndex <= reappointmentGraceQuarters &&
        !inflationInBand &&
        (rightDirectionForHighInflation || rightDirectionForLowInflation)
    let rawCredibilityDelta = credibilityBaseDrift - credibilityRateMoveCost
    let credibilityReappointmentGrace = eligibleForReappointmentGrace
        ? min(reappointmentGraceLimit, normalCredibilityRecovery - rawCredibilityDelta)
        : 0
    let credibilityDelta = min(normalCredibilityRecovery, rawCredibilityDelta + credibilityReappointmentGrace)
    let credibility = clamp(previous.credibility + credibilityDelta, 0, 100)
    let expectationsAnchor = effectiveInflationTarget + (100 - credibility) / 100
    let expectedInflation = clamp(
        0.72 * previous.expectedInflation + 0.18 * previous.inflation + 0.1 * expectationsAnchor,
        0,
        10,
    )
    let inflation = clamp(
        0.55 * previous.inflation +
            0.3 * expectedInflation +
            0.15 * effectiveInflationTarget +
            coefficients.phillipsSlope * previous.outputGap +
            supplyShock -
            coefficients.inflationRateSensitivity * laggedGap +
            noise,
        -2,
        20,
    )
    let nextState = MacroState(
        quarterIndex: quarterIndex,
        quartersRemaining: max(0, scenario.termQuarters - quarterIndex),
        inflation: roundTo(inflation),
        unemployment: roundTo(unemployment),
        fedFundsRate: roundTo(decision.resultingFedFundsRate),
        outputGap: roundTo(outputGap),
        gdpGrowth: roundTo(gdpGrowth),
        expectedInflation: roundTo(expectedInflation),
        credibility: roundTo(credibility),
    )
    let roundedShocks = Dictionary(uniqueKeysWithValues: shockTypes.map { ($0.rawValue, roundTo(shocks[$0] ?? 0)) })
    let explanation = if laggedGap > 0.35 {
        "Earlier restrictive policy is cooling demand, lowering inflation pressure while lifting unemployment risk."
    } else if laggedGap < -0.35 {
        "Earlier easier policy is supporting demand, improving labor conditions while adding inflation pressure."
    } else {
        "Policy is close to neutral, so shocks and momentum explain most of this quarter."
    }
    let trace = EngineTrace(
        neutralRate: roundTo(neutralRate),
        policyGap: roundTo(currentPolicyGap),
        laggedPolicyGap: roundTo(laggedGap),
        shockContrib: roundedShocks,
        credibilityBaseDrift: roundTo(credibilityBaseDrift),
        credibilityRateMoveCost: roundTo(credibilityRateMoveCost),
        credibilityReappointmentGrace: roundTo(credibilityReappointmentGrace),
        credibilityDelta: roundTo(nextState.credibility - previous.credibility),
        inflationDelta: roundTo(nextState.inflation - previous.inflation),
        unemploymentDelta: roundTo(nextState.unemployment - previous.unemployment),
        gdpDelta: roundTo(nextState.gdpGrowth - previous.gdpGrowth),
        explanation: explanation,
    )
    return AdvanceResult(nextState: nextState, trace: trace, activeShocks: shockState.active, triggeredShocks: shockState.triggered)
}
