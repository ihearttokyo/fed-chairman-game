import type { MacroState, PolicyAction, PolicyDecision } from '../types'
import { roundTo } from './math'

export const policyActions: Record<PolicyAction, { label: string; delta: number; hint: string }> = {
  cut_150: {
    label: '-150 bps',
    delta: -1.5,
    hint: 'An emergency cut strongly supports demand, but can quickly damage inflation credibility.',
  },
  cut_100: {
    label: '-100 bps',
    delta: -1,
    hint: 'A very large cut supports demand quickly, but can add material inflation pressure.',
  },
  cut_75: {
    label: '-75 bps',
    delta: -0.75,
    hint: 'A forceful cut eases conditions quickly, but can weaken inflation credibility.',
  },
  cut_50: {
    label: '-50 bps',
    delta: -0.5,
    hint: 'A larger cut eases conditions quickly, but can weaken inflation credibility.',
  },
  cut_25: {
    label: '-25 bps',
    delta: -0.25,
    hint: 'A small cut supports demand and employment, but can add inflation pressure.',
  },
  hold: {
    label: 'Hold',
    delta: 0,
    hint: 'Holding lets previous decisions keep working through policy lags.',
  },
  raise_25: {
    label: '+25 bps',
    delta: 0.25,
    hint: 'A small hike tends to cool inflation pressure with some labor-market cost.',
  },
  raise_50: {
    label: '+50 bps',
    delta: 0.5,
    hint: 'A larger hike fights inflation faster, but raises recession risk.',
  },
  raise_75: {
    label: '+75 bps',
    delta: 0.75,
    hint: 'A forceful hike fights inflation faster, but raises recession risk.',
  },
  raise_100: {
    label: '+100 bps',
    delta: 1,
    hint: 'A very large hike fights inflation hard, but can sharply raise recession risk.',
  },
  raise_150: {
    label: '+150 bps',
    delta: 1.5,
    hint: 'An emergency hike can defend inflation credibility, but may overtighten into recession.',
  },
  custom: {
    label: 'Custom',
    delta: 0,
    hint: 'A custom basis-point move commits immediately and advances one quarter.',
  },
}

export function createDecision(
  action: PolicyAction,
  current: MacroState,
  timestamp = new Date().toISOString(),
  customRateChange?: number,
): PolicyDecision {
  const rateChange = action === 'custom' ? roundTo(customRateChange ?? 0, 2) : policyActions[action].delta
  const resultingFedFundsRate = roundTo(current.fedFundsRate + rateChange, 2)
  return {
    id: `${current.quarterIndex + 1}-${action}-${rateChange}-${timestamp}`,
    quarterIndex: current.quarterIndex + 1,
    action,
    rateChange,
    resultingFedFundsRate,
    timestamp,
  }
}

export function formatRateChangeBps(rateChange: number): string {
  const bps = Math.round(rateChange * 100)
  return bps === 0 ? 'Hold' : `${bps > 0 ? '+' : ''}${bps} bps`
}

export function policyDecisionLabel(decision: PolicyDecision): string {
  return decision.action === 'custom' ? `Custom ${formatRateChangeBps(decision.rateChange)}` : policyActions[decision.action].label
}
