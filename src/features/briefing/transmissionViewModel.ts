import { formatPct, formatSigned } from '../../lib/format'
import type { EngineTrace, GameSession, MacroState, PolicyDecision, ScenarioConfig, ShockType } from '../../types'

export type TransmissionTrend = 'cooling' | 'heating' | 'stabilizing' | 'stress'

export type TransmissionStep = {
  month: 'Month 1' | 'Month 2' | 'Month 3'
  channel: string
  title: string
  stance: string
  intensity: number
  intensityLabel: string
  driver: string
  value: string
  comparison: string
  basis: string
  detail: string
  trend: TransmissionTrend
  evidence: string[]
  signals: string[]
  traceInputs: string[]
}

export type TransmissionBriefing = {
  receipt: TransmissionReceipt
  decisionMemo: TransmissionDecisionMemo
  summary: string
  path: string[]
  causalChain: TransmissionCausalLink[]
  changes: TransmissionChange[]
  steps: TransmissionStep[]
}

export type TransmissionReceipt = {
  headline: string
  verdict: string
  policyEcho: string
  nextWatch: string
  tone: TransmissionTrend
}

export type TransmissionDecisionMemo = {
  headline: string
  assessment: string
  tradeoff: string
  risk: string
  nextBias: string
  tone: TransmissionTrend
}

export type TransmissionCausalLink = {
  label: string
  text: string
  tone: TransmissionTrend
}

export type TransmissionChange = {
  label: string
  previous: string
  current: string
  delta: string
  reason: string
  tone: TransmissionTrend
}

const shockLabels: Record<ShockType, string> = {
  demand: 'demand',
  supply: 'supply chain',
  financial: 'financial stress',
  labor: 'labor market',
  energy: 'energy prices',
  confidence: 'confidence',
}

function clampIntensity(value: number): number {
  return Math.min(100, Math.max(8, Math.round(value)))
}

function formatMagnitude(value: number): string {
  return Math.abs(value).toFixed(2)
}

function previousState(session: GameSession): MacroState | null {
  return session.history.at(-2) ?? null
}

function latestDecision(session: GameSession): PolicyDecision | null {
  return session.decisions.at(-1) ?? null
}

function rateTransmission(decision: PolicyDecision, trace: EngineTrace, scenario: ScenarioConfig): TransmissionStep {
  const neutralGap = decision.resultingFedFundsRate - trace.neutralRate
  const absChange = Math.abs(decision.rateChange)
  const previousRate = decision.resultingFedFundsRate - decision.rateChange
  const trend: TransmissionTrend =
    decision.rateChange > 0 ? 'cooling' : decision.rateChange < 0 ? 'heating' : Math.abs(neutralGap) < 0.35 ? 'stabilizing' : neutralGap > 0 ? 'cooling' : 'heating'
  const action =
    decision.rateChange > 0
      ? 'Rate hike committed'
      : decision.rateChange < 0
        ? 'Rate cut committed'
        : 'Target rate held'
  const force =
    absChange >= 0.5
      ? 'a strong signal'
      : absChange > 0
        ? 'a measured signal'
        : 'a wait-and-watch signal'
  return {
    month: 'Month 1',
    channel: 'Decision',
    title: action,
    stance:
      decision.rateChange > 0
        ? 'Restrictive signal'
        : decision.rateChange < 0
          ? 'Easier signal'
          : Math.abs(neutralGap) < 0.35
            ? 'Neutral hold'
            : neutralGap > 0
            ? 'Restrictive hold'
            : 'Easy hold',
    intensity: clampIntensity(Math.max(absChange / 0.75, Math.abs(neutralGap) / 1.25) * 100),
    intensityLabel: absChange > 0 ? 'Policy signal strength' : 'Neutral-gap pressure',
    driver: `Policy impulse: ${formatSigned(decision.rateChange)} pp move, ${formatSigned(neutralGap)} pp versus neutral`,
    value: `${formatPct(decision.resultingFedFundsRate)} target`,
    comparison: `Fed funds: ${formatPct(previousRate)} -> ${formatPct(decision.resultingFedFundsRate)}`,
    basis: 'Uses the committed rate decision and this quarter’s neutral-rate trace.',
    detail: `The desk sends ${force}; neutral is near ${formatPct(trace.neutralRate)} against the ${formatPct(scenario.targets.inflation, 1)} inflation mandate.`,
    trend,
    evidence: [
      `Previous rate ${formatPct(previousRate)}`,
      `New rate ${formatPct(decision.resultingFedFundsRate)}`,
      `Neutral ${formatPct(trace.neutralRate)}`,
    ],
    signals: [
      `Move: ${formatSigned(decision.rateChange)} pp`,
      `Gap: ${formatSigned(neutralGap)} pp`,
    ],
    traceInputs: [
      'latest PolicyDecision',
      'EngineTrace.neutralRate',
      'scenario inflation target',
    ],
  }
}

function demandTransmission(previous: MacroState, current: MacroState, trace: EngineTrace): TransmissionStep {
  const shockPressure = Object.values(trace.shockContrib).reduce((total, value) => total + value, 0)
  const dominantShock = Object.entries(trace.shockContrib).sort(([, a], [, b]) => Math.abs(b) - Math.abs(a))[0] as
    | [ShockType, number]
    | undefined
  const dominantShockLabel =
    dominantShock && Math.abs(dominantShock[1]) > 0.05
      ? `${shockLabels[dominantShock[0]]} ${formatSigned(dominantShock[1])}`
      : 'none'
  const trend: TransmissionTrend =
    trace.laggedPolicyGap > 0.35
      ? 'cooling'
      : trace.laggedPolicyGap < -0.35
        ? 'heating'
        : Math.abs(shockPressure) > 0.35
          ? 'stress'
          : 'stabilizing'
  const channel =
    trace.laggedPolicyGap > 0.35
      ? 'Credit conditions lean tighter'
      : trace.laggedPolicyGap < -0.35
        ? 'Credit conditions lean easier'
        : 'Momentum leads the quarter'
  const shockLine =
    Math.abs(shockPressure) > 0.05
      ? `net shock pressure ${formatSigned(shockPressure)}`
      : 'limited shock pressure'
  const demandIntensity = clampIntensity(Math.max(Math.abs(trace.laggedPolicyGap) / 1.1, Math.abs(shockPressure) / 1.2) * 100)
  return {
    month: 'Month 2',
    channel: 'Demand lag',
    title: channel,
    stance:
      trace.laggedPolicyGap > 0.35
        ? 'Demand cooling'
        : trace.laggedPolicyGap < -0.35
          ? 'Demand heating'
          : Math.abs(shockPressure) > 0.35
          ? 'Shock led'
          : 'Momentum steady',
    intensity: demandIntensity,
    intensityLabel: Math.abs(shockPressure) > Math.abs(trace.laggedPolicyGap) ? 'Shock pressure' : 'Lag pressure',
    driver: `Transmission driver: lag ${formatSigned(trace.laggedPolicyGap)} pp, shocks ${formatSigned(shockPressure)}`,
    value: `${formatSigned(trace.laggedPolicyGap)} pp lag`,
    comparison: `Output gap: ${formatSigned(previous.outputGap)} -> ${formatSigned(current.outputGap)} pp`,
    basis: 'Uses the prior quarter, current quarter, lagged policy gap, and shock contribution trace.',
    detail: `Policy works through the lagged gap while ${shockLine} shifts output and hiring.`,
    trend,
    evidence: [
      `Output ${formatSigned(current.outputGap - previous.outputGap)} pp`,
      `GDP ${formatSigned(trace.gdpDelta)} pp`,
      `Shocks ${formatSigned(shockPressure)}`,
    ],
    signals: [
      trace.laggedPolicyGap > 0.35 ? 'Lag: restrictive' : trace.laggedPolicyGap < -0.35 ? 'Lag: easy' : 'Lag: near neutral',
      `Dominant: ${dominantShockLabel}`,
    ],
    traceInputs: [
      'previous MacroState',
      'current MacroState',
      'EngineTrace.laggedPolicyGap',
      'EngineTrace.shockContrib',
    ],
  }
}

function mandateTransmission(previous: MacroState, current: MacroState, trace: EngineTrace, scenario: ScenarioConfig): TransmissionStep {
  const inflationGap = current.inflation - scenario.targets.inflation
  const unemploymentGap = current.unemployment - scenario.targets.unemployment
  const combinedMiss = Math.abs(inflationGap) + Math.abs(unemploymentGap)
  const previousMiss =
    Math.abs(previous.inflation - scenario.targets.inflation) +
    Math.abs(previous.unemployment - scenario.targets.unemployment)
  const mandateDistanceMove = combinedMiss - previousMiss
  const trend: TransmissionTrend =
    mandateDistanceMove < -0.05
      ? 'stabilizing'
      : trace.inflationDelta > 0.15 || trace.unemploymentDelta > 0.2
        ? 'stress'
        : trace.inflationDelta < -0.1
          ? 'cooling'
          : 'heating'
  return {
    month: 'Month 3',
    channel: 'Mandate close',
    title: combinedMiss < previousMiss ? 'Mandate distance narrowed' : 'Mandate distance widened',
    stance:
      mandateDistanceMove < -0.05
        ? 'Mandate improving'
        : mandateDistanceMove > 0.05
          ? 'Mandate slipping'
          : 'Mandate steady',
    intensity: clampIntensity(Math.max(Math.abs(mandateDistanceMove) / 0.8, combinedMiss / 3.2) * 100),
    intensityLabel: mandateDistanceMove < 0 ? 'Progress toward mandate' : 'Mandate pressure',
    driver: `Mandate driver: inflation gap ${formatSigned(inflationGap)} pp, jobs gap ${formatSigned(unemploymentGap)} pp`,
    value: `${formatSigned(current.inflation - previous.inflation)} / ${formatSigned(current.unemployment - previous.unemployment)} pp`,
    comparison: `Inflation ${formatPct(previous.inflation)} -> ${formatPct(current.inflation)}; unemployment ${formatPct(previous.unemployment)} -> ${formatPct(current.unemployment)}`,
    basis: 'Uses the closing mandate metrics and engine deltas from the completed quarter.',
    detail: `Inflation is ${formatSigned(inflationGap)} pp from target; unemployment is ${formatSigned(unemploymentGap)} pp from target.`,
    trend,
    evidence: [
      `Inflation ${formatSigned(current.inflation - previous.inflation)} pp`,
      `Unemployment ${formatSigned(current.unemployment - previous.unemployment)} pp`,
      `Credibility ${formatSigned(current.credibility - previous.credibility)} pts`,
    ],
    signals: [
      `Distance: ${formatSigned(mandateDistanceMove)} pp`,
      `Inflation: ${formatSigned(trace.inflationDelta)} pp`,
      `Jobs: ${formatSigned(trace.unemploymentDelta)} pp`,
    ],
    traceInputs: [
      'previous MacroState',
      'current MacroState',
      'EngineTrace.inflationDelta',
      'EngineTrace.unemploymentDelta',
      'scenario mandate targets',
    ],
  }
}

function transmissionSummary(decision: PolicyDecision, previous: MacroState, current: MacroState, trace: EngineTrace): string {
  const action =
    decision.rateChange > 0
      ? `raising rates ${formatSigned(decision.rateChange)} pp`
      : decision.rateChange < 0
        ? `cutting rates ${formatSigned(decision.rateChange)} pp`
        : 'holding rates steady'
  const inflationMove = current.inflation - previous.inflation
  const unemploymentMove = current.unemployment - previous.unemployment
  const outputMove = current.outputGap - previous.outputGap
  const lagStance =
    trace.laggedPolicyGap > 0.35
      ? 'restrictive lag'
      : trace.laggedPolicyGap < -0.35
        ? 'easy lag'
        : 'near-neutral lag'

  return `After ${action}, the quarter closed with inflation ${formatSigned(inflationMove)} pp, unemployment ${formatSigned(unemploymentMove)} pp, and output gap ${formatSigned(outputMove)} pp as the ${lagStance} reached the economy.`
}

function transmissionPath(decision: PolicyDecision, previous: MacroState, current: MacroState, trace: EngineTrace): string[] {
  const policyLeg =
    decision.rateChange > 0
      ? `Higher target ${formatSigned(decision.rateChange)} pp`
      : decision.rateChange < 0
        ? `Lower target ${formatSigned(decision.rateChange)} pp`
        : `Hold at ${formatPct(decision.resultingFedFundsRate)}`
  const demandLeg =
    trace.laggedPolicyGap > 0.35
      ? `Tighter lag ${formatSigned(trace.laggedPolicyGap)} pp`
      : trace.laggedPolicyGap < -0.35
        ? `Easier lag ${formatSigned(trace.laggedPolicyGap)} pp`
        : `Neutral lag ${formatSigned(trace.laggedPolicyGap)} pp`
  const mandateLeg = `Inflation ${formatSigned(current.inflation - previous.inflation)} pp, jobs ${formatSigned(current.unemployment - previous.unemployment)} pp`

  return [policyLeg, demandLeg, mandateLeg]
}

function causalChain(
  decision: PolicyDecision,
  previous: MacroState,
  current: MacroState,
  trace: EngineTrace,
  scenario: ScenarioConfig,
): TransmissionCausalLink[] {
  const neutralGap = decision.resultingFedFundsRate - trace.neutralRate
  const shockPressure = Object.values(trace.shockContrib).reduce((total, value) => total + value, 0)
  const outputDelta = current.outputGap - previous.outputGap
  const inflationGap = current.inflation - scenario.targets.inflation
  const unemploymentGap = current.unemployment - scenario.targets.unemployment
  const previousMandateMiss =
    Math.abs(previous.inflation - scenario.targets.inflation) +
    Math.abs(previous.unemployment - scenario.targets.unemployment)
  const currentMandateMiss = Math.abs(inflationGap) + Math.abs(unemploymentGap)
  const mandateDelta = currentMandateMiss - previousMandateMiss
  const policyTone: TransmissionTrend =
    decision.rateChange > 0 || neutralGap > 0.35
      ? 'cooling'
      : decision.rateChange < 0 || neutralGap < -0.35
        ? 'heating'
        : 'stabilizing'
  const demandTone: TransmissionTrend =
    Math.abs(shockPressure) > Math.abs(trace.laggedPolicyGap) && Math.abs(shockPressure) > 0.25
      ? 'stress'
      : outputDelta > 0.05
        ? 'heating'
        : outputDelta < -0.05
          ? 'cooling'
          : 'stabilizing'
  const mandateTone: TransmissionTrend =
    mandateDelta < -0.05 ? 'stabilizing' : mandateDelta > 0.05 ? 'stress' : 'stabilizing'

  return [
    {
      label: 'Decision impulse',
      text: `The move leaves policy ${formatSigned(neutralGap)} pp from neutral, setting the signal that markets absorb first.`,
      tone: policyTone,
    },
    {
      label: 'Lag plus shocks',
      text: `That signal meets a ${formatSigned(trace.laggedPolicyGap)} pp lag and ${formatSigned(shockPressure)} shock pressure, moving output ${formatSigned(outputDelta)} pp.`,
      tone: demandTone,
    },
    {
      label: 'Mandate read-through',
      text: `The combined inflation and labor miss moved ${formatSigned(mandateDelta)} pp, ending ${formatSigned(inflationGap)} pp on inflation and ${formatSigned(unemploymentGap)} pp on jobs.`,
      tone: mandateTone,
    },
  ]
}

function transmissionChanges(previous: MacroState, current: MacroState, decision: PolicyDecision, trace: EngineTrace): TransmissionChange[] {
  const inflationDelta = current.inflation - previous.inflation
  const unemploymentDelta = current.unemployment - previous.unemployment
  const outputDelta = current.outputGap - previous.outputGap
  const credibilityDelta = current.credibility - previous.credibility
  const expectationsDelta = current.expectedInflation - previous.expectedInflation
  const shockPressure = Object.values(trace.shockContrib).reduce((total, value) => total + value, 0)

  return [
    {
      label: 'Inflation',
      previous: formatPct(previous.inflation),
      current: formatPct(current.inflation),
      delta: `${formatSigned(inflationDelta)} pp`,
      reason: `Engine delta ${formatSigned(trace.inflationDelta)} pp; expectations ${formatSigned(expectationsDelta)} pp.`,
      tone: inflationDelta > 0.05 ? 'heating' : inflationDelta < -0.05 ? 'cooling' : 'stabilizing',
    },
    {
      label: 'Unemployment',
      previous: formatPct(previous.unemployment),
      current: formatPct(current.unemployment),
      delta: `${formatSigned(unemploymentDelta)} pp`,
      reason: `Labor delta ${formatSigned(trace.unemploymentDelta)} pp; output ${formatSigned(outputDelta)} pp.`,
      tone: unemploymentDelta > 0.05 ? 'stress' : unemploymentDelta < -0.05 ? 'stabilizing' : 'stabilizing',
    },
    {
      label: 'Output gap',
      previous: `${formatSigned(previous.outputGap)} pp`,
      current: `${formatSigned(current.outputGap)} pp`,
      delta: `${formatSigned(outputDelta)} pp`,
      reason: `Lagged policy gap ${formatSigned(trace.laggedPolicyGap)} pp; shocks ${formatSigned(shockPressure)}.`,
      tone: outputDelta > 0.05 ? 'heating' : outputDelta < -0.05 ? 'cooling' : 'stabilizing',
    },
    {
      label: 'Credibility',
      previous: previous.credibility.toFixed(0),
      current: current.credibility.toFixed(0),
      delta: `${formatSigned(credibilityDelta)} pts`,
      reason: `Policy move ${formatSigned(decision.rateChange)} pp; expectations ${formatSigned(expectationsDelta)} pp.`,
      tone: credibilityDelta < -0.05 ? 'stress' : credibilityDelta > 0.05 ? 'stabilizing' : 'stabilizing',
    },
  ]
}

function transmissionReceipt(
  previous: MacroState,
  current: MacroState,
  decision: PolicyDecision,
  trace: EngineTrace,
  scenario: ScenarioConfig,
): TransmissionReceipt {
  const inflationGap = current.inflation - scenario.targets.inflation
  const laborGap = current.unemployment - scenario.targets.unemployment
  const previousMiss =
    Math.abs(previous.inflation - scenario.targets.inflation) +
    Math.abs(previous.unemployment - scenario.targets.unemployment)
  const currentMiss = Math.abs(inflationGap) + Math.abs(laborGap)
  const mandateMove = currentMiss - previousMiss
  const shockPressure = Object.values(trace.shockContrib).reduce((total, value) => total + value, 0)
  const rateMove = Math.abs(decision.rateChange)
  const policyDirection =
    decision.rateChange > 0
      ? 'hike'
      : decision.rateChange < 0
        ? 'cut'
        : 'hold'
  const tone: TransmissionTrend =
    mandateMove < -0.08
      ? 'stabilizing'
      : mandateMove > 0.08 || Math.abs(shockPressure) > 0.65
        ? 'stress'
        : trace.laggedPolicyGap > 0.35
          ? 'cooling'
          : trace.laggedPolicyGap < -0.35
            ? 'heating'
            : 'stabilizing'
  const headline =
    mandateMove < -0.08
      ? 'Mandate gap narrowed'
      : mandateMove > 0.08
        ? 'Mandate gap widened'
        : 'Mandate gap held steady'
  const verdict =
    mandateMove < -0.08
      ? `The combined inflation and labor miss improved ${formatMagnitude(mandateMove)} pp this quarter.`
      : mandateMove > 0.08
        ? `The combined inflation and labor miss deteriorated ${formatSigned(mandateMove)} pp this quarter.`
        : `The combined inflation and labor miss moved only ${formatSigned(mandateMove)} pp this quarter.`
  const policyEcho =
    policyDirection === 'hold'
      ? `The hold kept the target at ${formatPct(decision.resultingFedFundsRate)} while the lag registered ${formatSigned(trace.laggedPolicyGap)} pp.`
      : `The ${policyDirection} moved ${formatSigned(decision.rateChange)} pp to ${formatPct(decision.resultingFedFundsRate)}; the current lag registered ${formatSigned(trace.laggedPolicyGap)} pp.`
  const nextWatch =
    Math.abs(shockPressure) > Math.abs(trace.laggedPolicyGap) && Math.abs(shockPressure) > 0.25
      ? `Watch shock pressure next: net shocks were ${formatSigned(shockPressure)} this quarter.`
      : rateMove >= 0.75
        ? 'Watch for overshoot risk: a large move can keep transmitting into the next quarter.'
        : Math.abs(inflationGap) > Math.abs(laborGap)
          ? `Watch inflation gap next: ${formatSigned(inflationGap)} pp from target.`
          : `Watch labor gap next: ${formatSigned(laborGap)} pp from target.`

  return {
    headline,
    verdict,
    policyEcho,
    nextWatch,
    tone,
  }
}

function decisionMemo(
  previous: MacroState,
  current: MacroState,
  decision: PolicyDecision,
  trace: EngineTrace,
  scenario: ScenarioConfig,
): TransmissionDecisionMemo {
  const previousInflationGap = previous.inflation - scenario.targets.inflation
  const previousLaborGap = previous.unemployment - scenario.targets.unemployment
  const currentInflationGap = current.inflation - scenario.targets.inflation
  const currentLaborGap = current.unemployment - scenario.targets.unemployment
  const outputDelta = current.outputGap - previous.outputGap
  const shockPressure = Object.values(trace.shockContrib).reduce((total, value) => total + value, 0)
  const needsCooling = previousInflationGap > 0.15 || previousLaborGap < -0.25
  const needsHeating = previousInflationGap < -0.15 || previousLaborGap > 0.25
  const actionTone: TransmissionTrend =
    decision.rateChange > 0 ? 'cooling' : decision.rateChange < 0 ? 'heating' : 'stabilizing'
  const pressureTone: TransmissionTrend = needsCooling ? 'cooling' : needsHeating ? 'heating' : 'stabilizing'
  const aligned =
    (pressureTone === 'cooling' && decision.rateChange > 0) ||
    (pressureTone === 'heating' && decision.rateChange < 0) ||
    (pressureTone === 'stabilizing' && decision.rateChange === 0)
  const contrarian =
    (pressureTone === 'cooling' && decision.rateChange < 0) ||
    (pressureTone === 'heating' && decision.rateChange > 0)
  const actionLabel =
    decision.rateChange > 0 ? 'tightening' : decision.rateChange < 0 ? 'easing' : 'holding'
  const pressureLabel =
    pressureTone === 'cooling' ? 'cooling pressure' : pressureTone === 'heating' ? 'support pressure' : 'balanced pressure'
  const headlinePrefix = aligned ? 'Aligned' : contrarian ? 'Contrarian' : 'Cautious'
  const headline = `${headlinePrefix} ${actionLabel} against ${pressureLabel}`
  const assessment = `Before the vote: inflation ${formatSigned(previousInflationGap)} pp from target, labor ${formatSigned(previousLaborGap)} pp from target.`
  const tradeoff =
    decision.rateChange === 0
      ? `The hold let the ${formatSigned(trace.laggedPolicyGap)} pp lag carry the quarter while output moved ${formatSigned(outputDelta)} pp.`
      : `The ${actionLabel} impulse met a ${formatSigned(trace.laggedPolicyGap)} pp policy lag while output moved ${formatSigned(outputDelta)} pp.`
  const risk =
    Math.abs(shockPressure) > Math.abs(trace.laggedPolicyGap) && Math.abs(shockPressure) > 0.25
      ? `Main risk: net shocks at ${formatSigned(shockPressure)} can swamp the latest rate signal.`
      : Math.abs(currentInflationGap) >= Math.abs(currentLaborGap)
        ? `Main risk: inflation remains ${formatSigned(currentInflationGap)} pp from target after the decision.`
        : `Main risk: labor remains ${formatSigned(currentLaborGap)} pp from target after the decision.`
  const nextBias =
    currentInflationGap > 0.25 || currentLaborGap < -0.3
      ? 'Next bias: lean tighter unless the mandate gap cools.'
      : currentInflationGap < -0.25 || currentLaborGap > 0.3
        ? 'Next bias: lean easier unless activity firms.'
        : 'Next bias: stay data-dependent near the mandate corridor.'

  return {
    headline,
    assessment,
    tradeoff,
    risk,
    nextBias,
    tone: contrarian ? 'stress' : actionTone,
  }
}

export function buildTransmissionBriefing(session: GameSession, scenario: ScenarioConfig): TransmissionBriefing | null {
  const trace = session.traces.at(-1)
  const decision = latestDecision(session)
  const previous = previousState(session)
  if (!trace || !decision || !previous) {
    return null
  }
  return {
    receipt: transmissionReceipt(previous, session.current, decision, trace, scenario),
    decisionMemo: decisionMemo(previous, session.current, decision, trace, scenario),
    summary: transmissionSummary(decision, previous, session.current, trace),
    path: transmissionPath(decision, previous, session.current, trace),
    causalChain: causalChain(decision, previous, session.current, trace, scenario),
    changes: transmissionChanges(previous, session.current, decision, trace),
    steps: [
      rateTransmission(decision, trace, scenario),
      demandTransmission(previous, session.current, trace),
      mandateTransmission(previous, session.current, trace, scenario),
    ],
  }
}

export function buildTransmissionSteps(session: GameSession, scenario: ScenarioConfig): TransmissionStep[] {
  return buildTransmissionBriefing(session, scenario)?.steps ?? []
}
