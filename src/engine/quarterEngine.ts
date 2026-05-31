import type {
  ActiveShock,
  AdvanceResult,
  EngineTrace,
  MacroState,
  PolicyDecision,
  ScenarioConfig,
  Shock,
  ShockType,
} from '../types'
import { clamp, roundTo } from './math'
import { deterministicNoise, SeededRng } from './rng'

const shockTypes: ShockType[] = ['demand', 'supply', 'financial', 'labor', 'energy', 'confidence']
const INFLATION_CREDIBILITY_BAND = 0.5
const REAPPOINTMENT_GRACE_QUARTERS = 4
const NORMAL_CREDIBILITY_RECOVERY = 0.6
const OUT_OF_BAND_CREDIBILITY_DRIFT = -1.8
const RATE_MOVE_CREDIBILITY_COST = 0.75
const REAPPOINTMENT_GRACE_LIMIT = 2.4
const LAGGED_POLICY_ACTIVE_THRESHOLD = 0.35

function emptyShockContrib(): Record<ShockType, number> {
  return {
    demand: 0,
    supply: 0,
    financial: 0,
    labor: 0,
    energy: 0,
    confidence: 0,
  }
}

function shouldTrigger(shock: Shock, quarterIndex: number, seed: string): boolean {
  if (shock.quarter !== 'random') {
    return shock.quarter === quarterIndex
  }
  const rng = new SeededRng(`${seed}:${shock.id}:${quarterIndex}`)
  return rng.next() > 0.78
}

function nextActiveShocks(
  scenario: ScenarioConfig,
  activeShocks: ActiveShock[],
  quarterIndex: number,
  seed: string,
): { active: ActiveShock[]; triggered: Shock[] } {
  const carried = activeShocks
    .map((shock) => ({ ...shock, remaining: shock.remaining - 1 }))
    .filter((shock) => shock.remaining > 0)
  const triggered = scenario.shockDeck.filter((shock) => shouldTrigger(shock, quarterIndex, seed))
  const newActive = triggered.map((shock) => ({
    ...shock,
    startedQuarter: quarterIndex,
    remaining: shock.persistence,
  }))
  return { active: [...carried, ...newActive], triggered }
}

function shockContributions(activeShocks: ActiveShock[], scenario: ScenarioConfig): Record<ShockType, number> {
  const contrib = emptyShockContrib()
  for (const shock of activeShocks) {
    const age = shock.persistence - shock.remaining
    const decayed = shock.magnitude * scenario.coefficients.shockDecay ** Math.max(0, age)
    contrib[shock.type] += decayed
  }
  return contrib
}

function laggedPolicyGap(history: MacroState[], scenario: ScenarioConfig): number {
  const weights = [0.1, 0.25, 0.4, 0.25]
  const recent = history.slice(-4).reverse()
  if (recent.length === 0) {
    return 0
  }
  const weighted = recent.reduce((total, state, index) => {
    const neutralRate = scenario.coefficients.realNeutralRate + state.expectedInflation
    return total + (state.fedFundsRate - neutralRate) * (weights[index] ?? 0)
  }, 0)
  return weighted / weights.slice(0, recent.length).reduce((total, value) => total + value, 0)
}

export function advanceQuarter(input: {
  history: MacroState[]
  decision: PolicyDecision
  scenario: ScenarioConfig
  activeShocks: ActiveShock[]
  seed: string
  termNumber?: number
}): AdvanceResult {
  const previous = input.history.at(-1)
  if (!previous) {
    throw new Error('Cannot advance without history')
  }
  const quarterIndex = previous.quarterIndex + 1
  const { active, triggered } = nextActiveShocks(input.scenario, input.activeShocks, quarterIndex, input.seed)
  const shocks = shockContributions(active, input.scenario)
  const coefficients = input.scenario.coefficients
  const neutralRate = coefficients.realNeutralRate + previous.expectedInflation
  const currentPolicyGap = input.decision.resultingFedFundsRate - neutralRate
  const laggedGap = laggedPolicyGap(input.history, input.scenario)
  const demandShock = shocks.demand + 0.45 * shocks.confidence
  const financialStress = Math.abs(Math.min(0, shocks.financial)) * 0.8
  const supplyShock = shocks.supply + shocks.energy * 0.55
  const laborShock = Math.max(0, shocks.labor) * 0.35 + Math.abs(Math.min(0, shocks.financial)) * 0.2
  const noise = deterministicNoise(input.seed, quarterIndex, 'macro', coefficients.noiseScale)

  const outputGap = clamp(
    0.58 * previous.outputGap -
      coefficients.rateSensitivity * laggedGap +
      demandShock -
      financialStress +
      noise,
    -8,
    8,
  )
  const gdpGrowth = clamp(
    coefficients.trendGrowth + 0.65 * outputGap + demandShock * 0.35 - financialStress * 0.45,
    -9,
    9,
  )
  const unemployment = clamp(
    previous.unemployment - coefficients.okunCoefficient * (gdpGrowth - coefficients.trendGrowth) + laborShock,
    2,
    15,
  )
  const inflationGap = previous.inflation - input.scenario.targets.inflation
  const inflationInBand = Math.abs(inflationGap) <= INFLATION_CREDIBILITY_BAND
  const credibilityBaseDrift = inflationInBand ? NORMAL_CREDIBILITY_RECOVERY : OUT_OF_BAND_CREDIBILITY_DRIFT
  const credibilityRateMoveCost = Math.abs(input.decision.rateChange) * RATE_MOVE_CREDIBILITY_COST
  const rightDirectionForHighInflation =
    inflationGap > INFLATION_CREDIBILITY_BAND &&
    (input.decision.rateChange > 0 ||
      (input.decision.rateChange === 0 && laggedGap > LAGGED_POLICY_ACTIVE_THRESHOLD))
  const rightDirectionForLowInflation =
    inflationGap < -INFLATION_CREDIBILITY_BAND &&
    (input.decision.rateChange < 0 ||
      (input.decision.rateChange === 0 && laggedGap < -LAGGED_POLICY_ACTIVE_THRESHOLD))
  const eligibleForReappointmentGrace =
    (input.termNumber ?? 1) > 1 &&
    quarterIndex <= REAPPOINTMENT_GRACE_QUARTERS &&
    !inflationInBand &&
    (rightDirectionForHighInflation || rightDirectionForLowInflation)
  const rawCredibilityDelta = credibilityBaseDrift - credibilityRateMoveCost
  const credibilityReappointmentGrace = eligibleForReappointmentGrace
    ? Math.min(REAPPOINTMENT_GRACE_LIMIT, NORMAL_CREDIBILITY_RECOVERY - rawCredibilityDelta)
    : 0
  const credibilityDelta = Math.min(
    NORMAL_CREDIBILITY_RECOVERY,
    rawCredibilityDelta + credibilityReappointmentGrace,
  )
  const credibility = clamp(
    previous.credibility + credibilityDelta,
    0,
    100,
  )
  const expectationsAnchor = input.scenario.targets.inflation + (100 - credibility) / 100
  const expectedInflation = clamp(
    0.72 * previous.expectedInflation + 0.18 * previous.inflation + 0.1 * expectationsAnchor,
    0,
    10,
  )
  const inflation = clamp(
    0.55 * previous.inflation +
      0.3 * expectedInflation +
      0.15 * input.scenario.targets.inflation +
      coefficients.phillipsSlope * previous.outputGap +
      supplyShock -
      coefficients.inflationRateSensitivity * laggedGap +
      noise,
    -2,
    20,
  )
  const nextState: MacroState = {
    quarterIndex,
    quartersRemaining: Math.max(0, input.scenario.termQuarters - quarterIndex),
    inflation: roundTo(inflation),
    unemployment: roundTo(unemployment),
    fedFundsRate: roundTo(input.decision.resultingFedFundsRate),
    outputGap: roundTo(outputGap),
    gdpGrowth: roundTo(gdpGrowth),
    expectedInflation: roundTo(expectedInflation),
    credibility: roundTo(credibility),
  }
  const trace: EngineTrace = {
    neutralRate: roundTo(neutralRate),
    policyGap: roundTo(currentPolicyGap),
    laggedPolicyGap: roundTo(laggedGap),
    shockContrib: Object.fromEntries(shockTypes.map((type) => [type, roundTo(shocks[type])])) as Record<
      ShockType,
      number
    >,
    credibilityBaseDrift: roundTo(credibilityBaseDrift),
    credibilityRateMoveCost: roundTo(credibilityRateMoveCost),
    credibilityReappointmentGrace: roundTo(credibilityReappointmentGrace),
    credibilityDelta: roundTo(nextState.credibility - previous.credibility),
    inflationDelta: roundTo(nextState.inflation - previous.inflation),
    unemploymentDelta: roundTo(nextState.unemployment - previous.unemployment),
    gdpDelta: roundTo(nextState.gdpGrowth - previous.gdpGrowth),
    explanation:
      laggedGap > 0.35
        ? 'Earlier restrictive policy is cooling demand, lowering inflation pressure while lifting unemployment risk.'
        : laggedGap < -0.35
          ? 'Earlier easier policy is supporting demand, improving labor conditions while adding inflation pressure.'
          : 'Policy is close to neutral, so shocks and momentum explain most of this quarter.',
  }

  return { nextState, trace, activeShocks: active, triggeredShocks: triggered }
}
