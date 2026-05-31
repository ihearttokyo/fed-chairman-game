import type { MacroState, ScenarioConfig } from '../../types'
import type { CareerTimelinePoint } from './careerTimeline'

export type ChartPoint = {
  key: string
  quarter: string
  termBoundary: boolean
  inflation: number
  unemployment: number
  fedFundsRate: number
  expectedInflation: number
  credibility: number
  outputGap: number
  decisionLabel: string
  decisionTone: 'cut' | 'hold' | 'raise' | 'none'
}

export type MandateCorridorSummary = {
  inflation: CorridorMetric
  unemployment: CorridorMetric
}

export type CorridorMetric = {
  label: string
  latest: number
  target: number
  gap: number
  inCorridor: boolean
  timeInCorridorPct: number
  direction: 'improving' | 'worsening' | 'steady'
  summary: string
}

type HistoryPoint = MacroState | CareerTimelinePoint

function isCareerPoint(state: HistoryPoint): state is CareerTimelinePoint {
  return 'label' in state && 'key' in state
}

export function buildChartData(history: HistoryPoint[]): ChartPoint[] {
  return history.map((state) => ({
    key: isCareerPoint(state) ? state.key : `q${state.quarterIndex}`,
    quarter: isCareerPoint(state) ? state.label : `Q${state.quarterIndex}`,
    termBoundary: isCareerPoint(state) ? state.isTermStart : false,
    inflation: state.inflation,
    unemployment: state.unemployment,
    fedFundsRate: state.fedFundsRate,
    expectedInflation: state.expectedInflation,
    credibility: state.credibility / 10,
    outputGap: state.outputGap,
    decisionLabel: isCareerPoint(state) ? state.decisionLabel : '',
    decisionTone: isCareerPoint(state) ? state.decisionTone : 'none',
  }))
}

function directionFromGap(currentGap: number, previousGap: number | null): CorridorMetric['direction'] {
  if (previousGap === null || Math.abs(Math.abs(currentGap) - Math.abs(previousGap)) < 0.05) {
    return 'steady'
  }
  return Math.abs(currentGap) < Math.abs(previousGap) ? 'improving' : 'worsening'
}

function buildCorridorMetric({
  label,
  values,
  target,
  corridorRadius,
}: {
  label: string
  values: number[]
  target: number
  corridorRadius: number
}): CorridorMetric {
  const latest = values.at(-1) ?? target
  const previous = values.length > 1 ? values.at(-2) ?? null : null
  const rawGap = latest - target
  const gap = Number(rawGap.toFixed(2))
  const inCorridor = Math.abs(rawGap) <= corridorRadius
  const quartersInCorridor = values.filter((value) => Math.abs(value - target) <= corridorRadius).length
  const timeInCorridorPct = values.length === 0 ? 0 : Math.round((quartersInCorridor / values.length) * 100)
  const direction = directionFromGap(rawGap, previous === null ? null : previous - target)
  const gapLabel = Math.abs(rawGap) < 0.05 ? 'at target' : `${Math.abs(rawGap).toFixed(1)} pp ${rawGap > 0 ? 'above' : 'below'} target`
  const directionLabel = direction === 'improving' ? 'closing' : direction === 'worsening' ? 'widening' : 'stable'

  return {
    label,
    latest,
    target,
    gap,
    inCorridor,
    timeInCorridorPct,
    direction,
    summary: `${gapLabel}; gap ${directionLabel}`,
  }
}

export function buildMandateCorridorSummary(
  history: HistoryPoint[],
  scenario: ScenarioConfig,
): MandateCorridorSummary {
  return {
    inflation: buildCorridorMetric({
      label: 'Inflation corridor',
      values: history.map((state) => state.inflation),
      target: scenario.targets.inflation,
      corridorRadius: 0.5,
    }),
    unemployment: buildCorridorMetric({
      label: 'Labor corridor',
      values: history.map((state) => state.unemployment),
      target: scenario.targets.unemployment,
      corridorRadius: 0.8,
    }),
  }
}
