import { describe, expect, it } from 'vitest'
import { classicScenario } from '../../scenarios/classic'
import type { MacroState } from '../../types'
import { buildMandateCorridorSummary } from './chartViewModel'

function state(overrides: Partial<MacroState>): MacroState {
  return {
    ...classicScenario.startingState,
    ...overrides,
  }
}

describe('buildMandateCorridorSummary', () => {
  it('summarizes target corridor performance from played history', () => {
    const history = [
      state({ quarterIndex: 0, inflation: 3.2, unemployment: 4.8 }),
      state({ quarterIndex: 1, inflation: 2.4, unemployment: 5.4 }),
      state({ quarterIndex: 2, inflation: 2.1, unemployment: 6.1 }),
    ]

    const summary = buildMandateCorridorSummary(history, classicScenario)

    expect(summary.inflation).toMatchObject({
      label: 'Inflation corridor',
      latest: 2.1,
      target: 2,
      gap: 0.1,
      inCorridor: true,
      timeInCorridorPct: 67,
      direction: 'improving',
      summary: '0.1 pp above target; gap closing',
    })
    expect(summary.unemployment).toMatchObject({
      label: 'Labor corridor',
      latest: 6.1,
      target: 5,
      gap: 1.1,
      inCorridor: false,
      timeInCorridorPct: 67,
      direction: 'worsening',
      summary: '1.1 pp above target; gap widening',
    })
  })

  it('treats a tiny latest miss as at target and stable', () => {
    const summary = buildMandateCorridorSummary(
      [state({ quarterIndex: 0, inflation: 2.03, unemployment: 4.98 })],
      classicScenario,
    )

    expect(summary.inflation.summary).toBe('at target; gap stable')
    expect(summary.inflation.direction).toBe('steady')
    expect(summary.inflation.inCorridor).toBe(true)
    expect(summary.unemployment.summary).toBe('at target; gap stable')
  })
})
