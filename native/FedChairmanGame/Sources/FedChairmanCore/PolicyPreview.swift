import Foundation

public enum PolicyPreviewPressure: String, Codable, Equatable, Sendable {
    case lower
    case steady
    case higher
}

public enum PolicyPreviewMandateGapDirection: String, Codable, Equatable, Sendable {
    case narrowing
    case mixed
    case widening
    case littleChanged = "little_changed"
}

public enum PolicyPreviewConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

public struct PolicyPreviewInput: Equatable, Sendable {
    public static let customBasisPointRange: ClosedRange<Int> = -150 ... 150

    public var action: PolicyAction
    public var customBasisPoints: Int?

    public init(action: PolicyAction, customBasisPoints: Int? = nil) {
        self.action = action
        self.customBasisPoints = customBasisPoints
    }

    public static func action(_ action: PolicyAction) -> PolicyPreviewInput {
        PolicyPreviewInput(action: action)
    }

    public static func customBasisPoints(_ basisPoints: Int) -> PolicyPreviewInput {
        PolicyPreviewInput(action: .custom, customBasisPoints: basisPoints)
    }

    public static func customRateChange(_ rateChange: Double) -> PolicyPreviewInput? {
        let basisPoints = Int((rateChange * 100).rounded())
        guard abs(rateChange * 100 - Double(basisPoints)) <= 0.000_000_001 else {
            return nil
        }
        return customBasisPoints(basisPoints)
    }

    public var rateChange: Double? {
        if action == .custom {
            guard let customBasisPoints, Self.customBasisPointRange.contains(customBasisPoints) else {
                return nil
            }
            return Double(customBasisPoints) / 100
        }
        return policyActions[action]?.delta
    }
}

public struct PolicyPreview: Equatable, Sendable {
    public var selectedMoveLabel: String {
        moveLabel
    }

    public var inflationPressure: Double {
        estimatedInflationPressureValue
    }

    public var unemploymentPressure: Double {
        estimatedUnemploymentPressureValue
    }

    public var moveLabel: String
    public var resultingFedFundsRate: Double
    public var estimatedInflationPressure: PolicyPreviewPressure
    public var estimatedUnemploymentPressure: PolicyPreviewPressure
    public var estimatedInflationPressureValue: Double
    public var estimatedUnemploymentPressureValue: Double
    public var credibilityCost: Double
    public var mandateGapDirection: PolicyPreviewMandateGapDirection
    public var confidence: PolicyPreviewConfidence
    public var primaryDriver: String

    public init(
        moveLabel: String,
        resultingFedFundsRate: Double,
        estimatedInflationPressure: PolicyPreviewPressure,
        estimatedUnemploymentPressure: PolicyPreviewPressure,
        estimatedInflationPressureValue: Double,
        estimatedUnemploymentPressureValue: Double,
        credibilityCost: Double,
        mandateGapDirection: PolicyPreviewMandateGapDirection,
        confidence: PolicyPreviewConfidence,
        primaryDriver: String,
    ) {
        self.moveLabel = moveLabel
        self.resultingFedFundsRate = resultingFedFundsRate
        self.estimatedInflationPressure = estimatedInflationPressure
        self.estimatedUnemploymentPressure = estimatedUnemploymentPressure
        self.estimatedInflationPressureValue = estimatedInflationPressureValue
        self.estimatedUnemploymentPressureValue = estimatedUnemploymentPressureValue
        self.credibilityCost = credibilityCost
        self.mandateGapDirection = mandateGapDirection
        self.confidence = confidence
        self.primaryDriver = primaryDriver
    }
}

public func buildPolicyPreview(session: GameSession, input: PolicyPreviewInput) -> PolicyPreview? {
    guard session.status == .inProgress, let rateChange = input.rateChange else {
        return nil
    }
    guard let scenario = try? getTermScenario(id: session.scenarioId, seed: session.seed, termNumber: session.termNumber) else {
        return nil
    }
    let current = session.current
    let resultingRate = roundTo(current.fedFundsRate + rateChange)
    guard resultingRate >= 0, resultingRate <= 20 else {
        return nil
    }

    let inflationGap = current.inflation - scenario.targets.inflation
    let unemploymentGap = current.unemployment - scenario.targets.unemployment
    let laggedGap = previewLaggedPolicyGap(history: session.history, scenario: scenario)
    let neutralRate = scenario.coefficients.realNeutralRate + current.expectedInflation
    let policyGap = resultingRate - neutralRate
    let shockPressure = previewShockPressure(activeShocks: session.activeShocks, scenario: scenario)
    let inflationImpulse = -scenario.coefficients.inflationRateSensitivity * rateChange -
        0.05 * laggedGap +
        0.18 * shockPressure.supply +
        0.08 * shockPressure.demand
    let unemploymentImpulse = scenario.coefficients.okunCoefficient * scenario.coefficients.rateSensitivity *
        rateChange +
        0.04 * laggedGap +
        0.14 * shockPressure.labor -
        0.06 * shockPressure.demand
    let credibilityCost = roundTo(abs(rateChange) * 0.75)
    let moveLabel = input.action == .custom
        ? "Custom \(formatRateChangeBps(rateChange))"
        : policyActions[input.action]?.label ?? formatRateChangeBps(rateChange)

    return PolicyPreview(
        moveLabel: moveLabel,
        resultingFedFundsRate: resultingRate,
        estimatedInflationPressure: previewPressure(inflationImpulse),
        estimatedUnemploymentPressure: previewPressure(unemploymentImpulse),
        estimatedInflationPressureValue: roundTo(inflationImpulse),
        estimatedUnemploymentPressureValue: roundTo(unemploymentImpulse),
        credibilityCost: credibilityCost,
        mandateGapDirection: previewMandateGapDirection(
            inflationGap: inflationGap,
            unemploymentGap: unemploymentGap,
            inflationImpulse: inflationImpulse,
            unemploymentImpulse: unemploymentImpulse,
        ),
        confidence: previewConfidence(laggedGap: laggedGap, shockPressure: shockPressure.total),
        primaryDriver: previewPrimaryDriver(context: PolicyPreviewDriverContext(
            rateChange: rateChange,
            policyGap: policyGap,
            laggedGap: laggedGap,
            shockPressure: shockPressure.total,
            inflationGap: inflationGap,
            unemploymentGap: unemploymentGap,
        )),
    )
}

public func buildPolicyPreview(session: GameSession, action: PolicyAction) -> PolicyPreview? {
    buildPolicyPreview(session: session, input: .action(action))
}

public func buildPolicyPreview(session: GameSession, customBasisPoints: Int) -> PolicyPreview? {
    buildPolicyPreview(session: session, input: .customBasisPoints(customBasisPoints))
}

public func buildPolicyPreview(session: GameSession, customBps: Int) -> PolicyPreview? {
    buildPolicyPreview(session: session, customBasisPoints: customBps)
}

private func previewPressure(_ value: Double) -> PolicyPreviewPressure {
    if value < -0.04 {
        return .lower
    }
    if value > 0.04 {
        return .higher
    }
    return .steady
}

private func previewMandateGapDirection(
    inflationGap: Double,
    unemploymentGap: Double,
    inflationImpulse: Double,
    unemploymentImpulse: Double,
) -> PolicyPreviewMandateGapDirection {
    let inflationImproves = abs(inflationGap) > 0.25 && inflationGap.sign != inflationImpulse.sign && abs(inflationImpulse) > 0.04
    let laborImproves = abs(unemploymentGap) > 0.25 && unemploymentGap.sign != unemploymentImpulse.sign && abs(unemploymentImpulse) > 0.04
    let inflationWorsens = abs(inflationGap) > 0.25 && inflationGap.sign == inflationImpulse.sign && abs(inflationImpulse) > 0.04
    let laborWorsens = abs(unemploymentGap) > 0.25 && unemploymentGap.sign == unemploymentImpulse.sign && abs(unemploymentImpulse) > 0.04

    if inflationImproves || laborImproves, !(inflationWorsens || laborWorsens) {
        return .narrowing
    }
    if inflationWorsens || laborWorsens, !(inflationImproves || laborImproves) {
        return .widening
    }
    if inflationImproves || laborImproves, inflationWorsens || laborWorsens {
        return .mixed
    }
    return .littleChanged
}

private func previewConfidence(laggedGap: Double, shockPressure: Double) -> PolicyPreviewConfidence {
    let uncertainty = abs(laggedGap) + abs(shockPressure)
    if uncertainty > 1.25 {
        return .low
    }
    if uncertainty > 0.55 {
        return .medium
    }
    return .high
}

private struct PolicyPreviewDriverContext {
    var rateChange: Double
    var policyGap: Double
    var laggedGap: Double
    var shockPressure: Double
    var inflationGap: Double
    var unemploymentGap: Double
}

private func previewPrimaryDriver(context: PolicyPreviewDriverContext) -> String {
    if abs(context.shockPressure) > max(abs(context.rateChange), abs(context.laggedGap), 0.45) {
        return "Active shocks"
    }
    if abs(context.laggedGap) > max(abs(context.rateChange), 0.45) {
        return context.laggedGap > 0 ? "Restrictive policy lag" : "Easy policy lag"
    }
    if abs(context.inflationGap) > abs(context.unemploymentGap), abs(context.inflationGap) > 0.5 {
        return context.inflationGap > 0 ? "Inflation gap" : "Soft inflation gap"
    }
    if abs(context.unemploymentGap) > 0.5 {
        return context.unemploymentGap > 0 ? "Labor-market slack" : "Tight labor market"
    }
    if abs(context.policyGap) > 0.35 {
        return context.policyGap > 0 ? "Restrictive stance" : "Easy stance"
    }
    return "Near-neutral stance"
}

private func previewLaggedPolicyGap(history: [MacroState], scenario: ScenarioConfig) -> Double {
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

private func previewShockPressure(
    activeShocks: [ActiveShock],
    scenario: ScenarioConfig,
) -> (demand: Double, supply: Double, labor: Double, total: Double) {
    var demand = 0.0
    var supply = 0.0
    var labor = 0.0
    for shock in activeShocks {
        let age = shock.persistence - shock.remaining
        let decayed = shock.magnitude * pow(scenario.coefficients.shockDecay, Double(max(0, age)))
        switch shock.type {
        case .demand:
            demand += decayed
        case .confidence:
            demand += 0.45 * decayed
        case .supply:
            supply += decayed
        case .energy:
            supply += 0.55 * decayed
        case .labor:
            labor += 0.35 * max(0, decayed)
        case .financial:
            demand -= abs(min(0, decayed)) * 0.8
            labor += abs(min(0, decayed)) * 0.2
        }
    }
    return (demand, supply, labor, abs(demand) + abs(supply) + abs(labor))
}
