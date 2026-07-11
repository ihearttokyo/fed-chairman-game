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
        let scaledBasisPoints = rateChange * 100
        guard scaledBasisPoints.isFinite else {
            return nil
        }
        let roundedBasisPoints = scaledBasisPoints.rounded()
        guard
            abs(scaledBasisPoints - roundedBasisPoints) <= 0.000_000_001,
            roundedBasisPoints >= Double(customBasisPointRange.lowerBound),
            roundedBasisPoints <= Double(customBasisPointRange.upperBound)
        else {
            return nil
        }
        let basisPoints = Int(roundedBasisPoints)
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

    public var credibilityEffect: Double {
        estimatedCredibilityEffectValue
    }

    public var moveLabel: String
    public var resultingFedFundsRate: Double
    public var estimatedInflationPressure: PolicyPreviewPressure
    public var estimatedUnemploymentPressure: PolicyPreviewPressure
    public var estimatedInflationPressureValue: Double
    public var estimatedUnemploymentPressureValue: Double
    public var horizonQuarters: Int
    public var estimatedCredibilityEffect: PolicyPreviewPressure
    public var estimatedCredibilityEffectValue: Double
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
        horizonQuarters: Int = 0,
        estimatedCredibilityEffect: PolicyPreviewPressure = .steady,
        estimatedCredibilityEffectValue: Double = 0,
    ) {
        self.moveLabel = moveLabel
        self.resultingFedFundsRate = resultingFedFundsRate
        self.estimatedInflationPressure = estimatedInflationPressure
        self.estimatedUnemploymentPressure = estimatedUnemploymentPressure
        self.estimatedInflationPressureValue = estimatedInflationPressureValue
        self.estimatedUnemploymentPressureValue = estimatedUnemploymentPressureValue
        self.horizonQuarters = horizonQuarters
        self.estimatedCredibilityEffect = estimatedCredibilityEffect
        self.estimatedCredibilityEffectValue = estimatedCredibilityEffectValue
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
    guard let current = canonicalPreviewCurrent(session: session, termQuarters: scenario.termQuarters) else {
        return nil
    }
    let resultingRate = roundTo(current.fedFundsRate + rateChange)
    let horizonQuarters = min(4, scenario.termQuarters - current.quarterIndex)
    guard resultingRate >= 0, resultingRate <= 20, horizonQuarters > 0 else {
        return nil
    }

    guard
        let candidate = try? projectPolicyPath(
            session: session,
            input: input,
            scenario: scenario,
            horizonQuarters: horizonQuarters,
        ),
        let baseline = try? projectPolicyPath(
            session: session,
            input: .action(.hold),
            scenario: scenario,
            horizonQuarters: horizonQuarters,
        )
    else {
        return nil
    }

    let inflationGap = current.inflation - scenario.targets.inflation
    let unemploymentGap = current.unemployment - scenario.targets.unemployment
    let laggedGap = baseline.traces.first?.laggedPolicyGap ?? 0
    let neutralRate = scenario.coefficients.realNeutralRate + current.expectedInflation
    let policyGap = resultingRate - neutralRate
    let shockPressure = baseline.traces.reduce(0.0) { maximum, trace in
        max(maximum, trace.shockContrib.values.reduce(0.0) { $0 + abs($1) })
    }
    let inflationImpulse = roundTo(candidate.endState.inflation - baseline.endState.inflation)
    let unemploymentImpulse = roundTo(candidate.endState.unemployment - baseline.endState.unemployment)
    let credibilityEffect = roundTo(candidate.endState.credibility - baseline.endState.credibility)
    let credibilityCost = roundTo(max(0, -credibilityEffect))
    let moveLabel = input.action == .custom
        ? "Custom \(formatRateChangeBps(rateChange))"
        : policyActions[input.action]?.label ?? formatRateChangeBps(rateChange)

    return PolicyPreview(
        moveLabel: moveLabel,
        resultingFedFundsRate: resultingRate,
        estimatedInflationPressure: previewPressure(inflationImpulse),
        estimatedUnemploymentPressure: previewPressure(unemploymentImpulse),
        estimatedInflationPressureValue: inflationImpulse,
        estimatedUnemploymentPressureValue: unemploymentImpulse,
        credibilityCost: credibilityCost,
        mandateGapDirection: previewMandateGapDirection(
            candidate: candidate.endState,
            baseline: baseline.endState,
            targets: scenario.targets,
        ),
        confidence: previewConfidence(laggedGap: laggedGap, shockPressure: shockPressure),
        primaryDriver: previewPrimaryDriver(context: PolicyPreviewDriverContext(
            rateChange: rateChange,
            policyGap: policyGap,
            laggedGap: laggedGap,
            shockPressure: shockPressure,
            inflationGap: inflationGap,
            unemploymentGap: unemploymentGap,
        )),
        horizonQuarters: horizonQuarters,
        estimatedCredibilityEffect: previewPressure(credibilityEffect),
        estimatedCredibilityEffectValue: credibilityEffect,
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

func previewMandateGapDirection(
    candidate: MacroState,
    baseline: MacroState,
    targets: MandateTargets,
) -> PolicyPreviewMandateGapDirection {
    let materialDistanceChange = 0.04
    let inflationDistanceChange = abs(candidate.inflation - targets.inflation) -
        abs(baseline.inflation - targets.inflation)
    let unemploymentDistanceChange = abs(candidate.unemployment - targets.unemployment) -
        abs(baseline.unemployment - targets.unemployment)
    let inflationImproves = inflationDistanceChange < -materialDistanceChange
    let laborImproves = unemploymentDistanceChange < -materialDistanceChange
    let inflationWorsens = inflationDistanceChange > materialDistanceChange
    let laborWorsens = unemploymentDistanceChange > materialDistanceChange

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

private func canonicalPreviewCurrent(session: GameSession, termQuarters: Int) -> MacroState? {
    guard
        termQuarters > 0,
        let current = session.history.last,
        session.current == current,
        current.quarterIndex >= 0,
        current.quarterIndex < termQuarters,
        session.currentTermQuarter == current.quarterIndex,
        session.termNumber >= 1,
        session.completedTerms.count == session.termNumber - 1,
        session.history.count == current.quarterIndex + 1,
        session.history.enumerated().allSatisfy({ index, state in state.quarterIndex == index })
    else {
        return nil
    }
    return current
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

private struct PolicyProjection {
    var endState: MacroState
    var traces: [EngineTrace]
}

private func projectPolicyPath(
    session: GameSession,
    input: PolicyPreviewInput,
    scenario: ScenarioConfig,
    horizonQuarters: Int,
) throws -> PolicyProjection {
    var history = session.history
    var activeShocks = session.activeShocks
    var traces: [EngineTrace] = []
    let seed = "\(session.seed):term-\(session.termNumber)"

    for offset in 0 ..< horizonQuarters {
        guard let current = history.last else {
            throw NativeEngineError.missingHistory
        }
        let action = offset == 0 ? input.action : .hold
        let decision = createDecision(
            action: action,
            current: current,
            timestamp: "preview",
            customRateChange: action == .custom ? input.rateChange : nil,
        )
        let advanced = try advanceQuarter(
            history: history,
            decision: decision,
            scenario: scenario,
            activeShocks: activeShocks,
            seed: seed,
            termNumber: session.termNumber,
            ui: session.ui,
            careerQuarterIndex: session.totalCareerQuarters + offset + 1,
        )
        history.append(advanced.nextState)
        activeShocks = advanced.activeShocks
        traces.append(advanced.trace)
    }

    guard let endState = history.last else {
        throw NativeEngineError.missingHistory
    }
    return PolicyProjection(endState: endState, traces: traces)
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
