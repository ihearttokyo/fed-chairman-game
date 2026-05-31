import type { MacroState, ScenarioConfig } from '../../types'

export type MetricView = {
  id: 'inflation' | 'unemployment' | 'fedFundsRate' | 'expectedInflation' | 'credibility'
  label: string
  value: number
  suffix: '%' | ''
  targetLabel: string
  deviation: number
  quarterDelta: number | null
  status: 'good' | 'watch' | 'danger'
}

function statusFor(absDeviation: number, watch: number, danger: number): MetricView['status'] {
  if (absDeviation >= danger) {
    return 'danger'
  }
  if (absDeviation >= watch) {
    return 'watch'
  }
  return 'good'
}

function delta(current: number, previous: number | undefined): number | null {
  return previous === undefined ? null : current - previous
}

export function buildMetricViews(current: MacroState, scenario: ScenarioConfig, previous?: MacroState): MetricView[] {
  const inflationDeviation = current.inflation - scenario.targets.inflation
  const unemploymentDeviation = current.unemployment - scenario.targets.unemployment
  return [
    {
      id: 'inflation',
      label: 'Inflation',
      value: current.inflation,
      suffix: '%',
      targetLabel: `Target ${scenario.targets.inflation.toFixed(1)}%`,
      deviation: inflationDeviation,
      quarterDelta: delta(current.inflation, previous?.inflation),
      status: statusFor(Math.abs(inflationDeviation), 0.6, 1.5),
    },
    {
      id: 'unemployment',
      label: 'Unemployment',
      value: current.unemployment,
      suffix: '%',
      targetLabel: `Target ${scenario.targets.unemployment.toFixed(1)}%`,
      deviation: unemploymentDeviation,
      quarterDelta: delta(current.unemployment, previous?.unemployment),
      status: statusFor(Math.abs(unemploymentDeviation), 0.8, 2),
    },
    {
      id: 'fedFundsRate',
      label: 'Fed Funds',
      value: current.fedFundsRate,
      suffix: '%',
      targetLabel: `Remaining ${current.quartersRemaining}`,
      deviation: current.fedFundsRate - (scenario.coefficients.realNeutralRate + current.expectedInflation),
      quarterDelta: delta(current.fedFundsRate, previous?.fedFundsRate),
      status: 'good',
    },
    {
      id: 'expectedInflation',
      label: 'Expectations',
      value: current.expectedInflation,
      suffix: '%',
      targetLabel: 'Credibility-sensitive',
      deviation: current.expectedInflation - scenario.targets.inflation,
      quarterDelta: delta(current.expectedInflation, previous?.expectedInflation),
      status: statusFor(Math.abs(current.expectedInflation - scenario.targets.inflation), 0.5, 1.3),
    },
    {
      id: 'credibility',
      label: 'Credibility',
      value: current.credibility,
      suffix: '',
      targetLabel: 'Higher is better',
      deviation: current.credibility - 80,
      quarterDelta: delta(current.credibility, previous?.credibility),
      status: current.credibility >= 75 ? 'good' : current.credibility >= 60 ? 'watch' : 'danger',
    },
  ]
}
