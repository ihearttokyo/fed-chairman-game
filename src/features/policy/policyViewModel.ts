import { policyActions } from '../../engine/policy'
import { formatPct, formatSigned } from '../../lib/format'
import type { GameSession, PolicyAction, ScenarioConfig, ShockType } from '../../types'

export type PolicyActionView = {
  action: PolicyAction
  label: string
  delta: number
  hint: string
  resultingRate: number
  macroSignal: string
  disabled: boolean
  direction: 'raise' | 'cut' | 'hold'
}

export type PolicyReadinessBrief = {
  headline: string
  summary: string
  tiles: PolicyReadinessTile[]
  recommendedBias: 'tighten' | 'ease' | 'hold'
}

export type PolicyReadinessTile = {
  label: string
  value: string
  detail: string
  tone: 'inflation' | 'labor' | 'neutral' | 'risk'
}

export const policyOrder: PolicyAction[] = [
  'cut_150',
  'cut_100',
  'cut_75',
  'cut_50',
  'cut_25',
  'hold',
  'raise_25',
  'raise_50',
  'raise_75',
  'raise_100',
  'raise_150',
]

const shockLabels: Record<ShockType, string> = {
  demand: 'Demand shock',
  supply: 'Supply shock',
  financial: 'Financial stress',
  labor: 'Labor shock',
  energy: 'Energy shock',
  confidence: 'Confidence shock',
}

export function policyStance(session: GameSession, scenario: ScenarioConfig): string {
  const neutralRate = scenario.coefficients.realNeutralRate + session.current.expectedInflation
  if (session.current.fedFundsRate > neutralRate + 0.5) {
    return 'Restrictive'
  }
  if (session.current.fedFundsRate < neutralRate - 0.5) {
    return 'Expansionary'
  }
  return 'Near neutral'
}

export function policyActionViews(session: GameSession, scenario: ScenarioConfig, controlsDisabled: boolean): PolicyActionView[] {
  const neutralRate = scenario.coefficients.realNeutralRate + session.current.expectedInflation
  return policyOrder.map((action) => {
    const option = policyActions[action]
    const wouldBeRate = session.current.fedFundsRate + option.delta
    const resultingGap = wouldBeRate - neutralRate
    return {
      action,
      label: option.label,
      delta: option.delta,
      hint: option.hint,
      resultingRate: wouldBeRate,
      macroSignal: macroSignalForGap(resultingGap),
      disabled: controlsDisabled || wouldBeRate < 0 || wouldBeRate > 20,
      direction: option.delta > 0 ? 'raise' : option.delta < 0 ? 'cut' : 'hold',
    }
  })
}

export function buildPolicyReadinessBrief(session: GameSession, scenario: ScenarioConfig): PolicyReadinessBrief {
  const previous = session.history.at(-2) ?? null
  const trace = session.traces.at(-1) ?? null
  const inflationGap = session.current.inflation - scenario.targets.inflation
  const laborGap = session.current.unemployment - scenario.targets.unemployment
  const neutralRate = trace?.neutralRate ?? scenario.coefficients.realNeutralRate + session.current.expectedInflation
  const neutralGap = session.current.fedFundsRate - neutralRate
  const inflationMomentum = previous ? session.current.inflation - previous.inflation : 0
  const laborMomentum = previous ? session.current.unemployment - previous.unemployment : 0
  const dominantShock = trace
    ? (Object.entries(trace.shockContrib).sort(([, a], [, b]) => Math.abs(b) - Math.abs(a))[0] as [ShockType, number] | undefined)
    : undefined
  const shockDetail =
    dominantShock && Math.abs(dominantShock[1]) >= 0.05
      ? `${shockLabels[dominantShock[0]]} ${formatSigned(dominantShock[1])} pp in trace`
      : session.latestTriggeredShocks[0]
        ? `${shockLabels[session.latestTriggeredShocks[0].type]} active for ${session.latestTriggeredShocks[0].persistence} quarters`
        : 'No material shock pressure in the latest trace'
  const inflationPressure = inflationGap > 0.35 || inflationMomentum > 0.15
  const laborPressure = laborGap > 0.5 || laborMomentum > 0.2
  const tooRestrictive = neutralGap > 0.75 && laborGap > 0.2
  const tooEasy = neutralGap < -0.75 && inflationGap > 0.2
  const recommendedBias: PolicyReadinessBrief['recommendedBias'] =
    inflationPressure || tooEasy ? 'tighten' : laborPressure || tooRestrictive ? 'ease' : 'hold'
  const headline =
    recommendedBias === 'tighten'
      ? 'Inflation risk argues for restraint'
      : recommendedBias === 'ease'
        ? 'Labor slack argues for support'
        : 'Mandate balance supports patience'
  const summary =
    recommendedBias === 'tighten'
      ? 'The next click should weigh inflation credibility against the lag already in the pipeline.'
      : recommendedBias === 'ease'
        ? 'The next click should weigh labor weakness against inflation still above target.'
        : 'The next click can stay measured because the mandate gaps are not sending a single dominant signal.'

  return {
    headline,
    summary,
    recommendedBias,
    tiles: [
      {
        label: 'Inflation gap',
        value: `${formatSigned(inflationGap)} pp`,
        detail: `${formatPct(session.current.inflation)} now; momentum ${formatSigned(inflationMomentum)} pp`,
        tone: 'inflation',
      },
      {
        label: 'Labor gap',
        value: `${formatSigned(laborGap)} pp`,
        detail: `${formatPct(session.current.unemployment)} now; momentum ${formatSigned(laborMomentum)} pp`,
        tone: 'labor',
      },
      {
        label: 'Neutral gap',
        value: `${formatSigned(neutralGap)} pp`,
        detail: `${formatPct(session.current.fedFundsRate)} target vs ${formatPct(neutralRate)} neutral`,
        tone: 'neutral',
      },
      {
        label: 'Trace risk',
        value: trace ? formatSigned(Object.values(trace.shockContrib).reduce((total, value) => total + value, 0)) : '0.00',
        detail: shockDetail,
        tone: 'risk',
      },
    ],
  }
}

function macroSignalForGap(resultingGap: number): string {
  if (resultingGap > 0.5) {
    return 'Tighter stance should cool demand after a lag.'
  }
  if (resultingGap < -0.5) {
    return 'Easier stance should support hiring after a lag.'
  }
  return 'Near-neutral stance lets existing momentum and shocks dominate.'
}
