import { describe, expect, it } from 'vitest'
import { evaluateScore } from './scoreEngine'
import { classicScenario } from '../scenarios/classic'
import type { MacroState } from '../types'

function state(overrides: Partial<MacroState>): MacroState {
  return {
    ...classicScenario.startingState,
    quarterIndex: 1,
    quartersRemaining: 15,
    ...overrides,
  }
}

describe('evaluateScore', () => {
  it('reappoints a stable target path', () => {
    const history = [classicScenario.startingState, state({ inflation: 2.1, unemployment: 5.1, credibility: 86 })]
    const score = evaluateScore(history, classicScenario)
    expect(score.score).toBeGreaterThanOrEqual(70)
    expect(score.reappointed).toBe(true)
  })

  it('rejects a path with final misses beyond classic thresholds', () => {
    const history = [classicScenario.startingState, state({ inflation: 5.2, unemployment: 8.1, credibility: 44 })]
    const score = evaluateScore(history, classicScenario)
    expect(score.reappointed).toBe(false)
    expect(score.biggestMiss.length).toBeGreaterThan(0)
    expect(score.takeaway.length).toBeGreaterThan(0)
  })
})
