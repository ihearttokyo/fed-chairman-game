import { describe, expect, it } from 'vitest'
import { createDecision } from './policy'
import { advanceQuarter } from './quarterEngine'
import { classicScenario } from '../scenarios/classic'
import type { MacroState, PolicyAction, ScenarioConfig } from '../types'

function noShockScenario(): ScenarioConfig {
  return { ...classicScenario, shockDeck: [] }
}

function runActions(actions: PolicyAction[], scenario = noShockScenario(), termNumber = 1): MacroState[] {
  let history = [scenario.startingState]
  let activeShocks: never[] = []
  for (const action of actions) {
    const decision = createDecision(action, history.at(-1)!, 'test')
    const result = advanceQuarter({
      history,
      decision,
      scenario,
      activeShocks,
      seed: 'unit-seed',
      termNumber,
    })
    history = [...history, result.nextState]
    activeShocks = result.activeShocks as never[]
  }
  return history
}

describe('advanceQuarter', () => {
  it('is deterministic with a fixed seed and decision script', () => {
    const actions: PolicyAction[] = ['hold', 'raise_25', 'raise_25', 'hold', 'cut_25', 'hold']
    expect(runActions(actions)).toEqual(runActions(actions))
  })

  it('makes sustained hikes lower inflation pressure and raise unemployment with lags', () => {
    const hold = runActions(Array<PolicyAction>(8).fill('hold'))
    const hikes = runActions(Array<PolicyAction>(8).fill('raise_50'))
    expect(hikes.at(-1)!.inflation).toBeLessThan(hold.at(-1)!.inflation)
    expect(hikes.at(-1)!.unemployment).toBeGreaterThan(hold.at(-1)!.unemployment)
  })

  it('makes sustained cuts raise inflation pressure and support employment with lags', () => {
    const hold = runActions(Array<PolicyAction>(8).fill('hold'))
    const cuts = runActions(Array<PolicyAction>(8).fill('cut_25'))
    expect(cuts.at(-1)!.inflation).toBeGreaterThan(hold.at(-1)!.inflation)
    expect(cuts.at(-1)!.unemployment).toBeLessThan(hold.at(-1)!.unemployment)
  })

  it('keeps extreme paths finite and clamped', () => {
    const history = runActions(Array<PolicyAction>(16).fill('raise_50'))
    for (const state of history) {
      expect(Number.isFinite(state.inflation)).toBe(true)
      expect(Number.isFinite(state.unemployment)).toBe(true)
      expect(state.fedFundsRate).toBeGreaterThanOrEqual(0)
      expect(state.fedFundsRate).toBeLessThanOrEqual(20)
      expect(state.unemployment).toBeGreaterThanOrEqual(2)
      expect(state.unemployment).toBeLessThanOrEqual(15)
    }
  })

  it('applies first-year reappointment credibility grace for right-direction inflation policy only', () => {
    const scenario = noShockScenario()
    const overheated = {
      ...scenario.startingState,
      inflation: 4.2,
      unemployment: 5,
      expectedInflation: 3.1,
      credibility: 55,
    }
    const hike = createDecision('raise_50', overheated, 'test')
    const cut = createDecision('cut_50', overheated, 'test')
    const termTwoHike = advanceQuarter({
      history: [overheated],
      decision: hike,
      scenario,
      activeShocks: [],
      seed: 'unit-seed',
      termNumber: 2,
    })
    const termOneHike = advanceQuarter({
      history: [overheated],
      decision: hike,
      scenario,
      activeShocks: [],
      seed: 'unit-seed',
      termNumber: 1,
    })
    const wrongWayCut = advanceQuarter({
      history: [overheated],
      decision: cut,
      scenario,
      activeShocks: [],
      seed: 'unit-seed',
      termNumber: 2,
    })

    expect(termTwoHike.trace.credibilityReappointmentGrace).toBeGreaterThan(0)
    expect(termTwoHike.trace.credibilityDelta).toBeGreaterThan(0)
    expect(termTwoHike.trace.credibilityDelta).toBeLessThanOrEqual(0.6)
    expect(termOneHike.trace.credibilityReappointmentGrace).toBe(0)
    expect(wrongWayCut.trace.credibilityReappointmentGrace).toBe(0)
    expect(termTwoHike.nextState.credibility).toBeGreaterThan(termOneHike.nextState.credibility)
  })

  it('does not grant reappointment grace merely because unemployment is in band', () => {
    const scenario = noShockScenario()
    const lowInflation = {
      ...scenario.startingState,
      inflation: 1.1,
      unemployment: 5,
      expectedInflation: 1.6,
      credibility: 58,
    }
    const decision = createDecision('raise_25', lowInflation, 'test')
    const result = advanceQuarter({
      history: [lowInflation],
      decision,
      scenario,
      activeShocks: [],
      seed: 'unit-seed',
      termNumber: 2,
    })

    expect(result.trace.credibilityReappointmentGrace).toBe(0)
    expect(result.trace.credibilityDelta).toBeLessThan(0)
  })
})
