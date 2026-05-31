import { describe, expect, it } from 'vitest'
import { classicScenario } from '../../scenarios/classic'
import { evaluateScore } from '../../engine/scoreEngine'
import { buildPolicyReadinessBrief, policyActionViews, policyStance } from './policyViewModel'
import type { GameSession } from '../../types'

function makeSession(): GameSession {
  const history = [classicScenario.startingState]
  return {
    sessionId: 'policy-test',
    mode: 'classic_chair_the_fed',
    scenarioId: classicScenario.id,
    status: 'in_progress',
    seed: 'policy-test',
    termNumber: 1,
    currentTermQuarter: 0,
    totalCareerQuarters: 0,
    completedTerms: [],
    careerHistory: history,
    careerScore: evaluateScore(history, classicScenario),
    current: classicScenario.startingState,
    history,
    decisions: [],
    traces: [],
    activeShocks: [],
    latestTriggeredShocks: [],
    score: evaluateScore(history, classicScenario),
    ui: {
      selectedDecision: 'raise_25',
      chartView: 'chart',
      reducedMotion: false,
      soundEnabled: false,
      reducedNoise: false,
      soundVolume: 0.25,
    },
  }
}

describe('policyActionViews', () => {
  it('describes each one-click decision without relying on selected preview state', () => {
    const views = policyActionViews(makeSession(), classicScenario, false)

    expect(views.map((view) => view.action)).toEqual([
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
    ])
    expect(views.map((view) => view.label)).toEqual([
      '-150 bps',
      '-100 bps',
      '-75 bps',
      '-50 bps',
      '-25 bps',
      'Hold',
      '+25 bps',
      '+50 bps',
      '+75 bps',
      '+100 bps',
      '+150 bps',
    ])
    expect(views.map((view) => view.resultingRate)).toEqual([2.5, 3, 3.25, 3.5, 3.75, 4, 4.25, 4.5, 4.75, 5, 5.5])
    expect(views.map((view) => view.disabled)).toEqual([false, false, false, false, false, false, false, false, false, false, false])
    expect(views[0]).not.toHaveProperty('selected')
    expect(views[4]?.macroSignal).toBe('Near-neutral stance lets existing momentum and shocks dominate.')
    expect(views.at(-1)?.macroSignal).toBe('Tighter stance should cool demand after a lag.')
  })

  it('disables all actions while quarter advancement is already in progress', () => {
    const views = policyActionViews(makeSession(), classicScenario, true)

    expect(views.every((view) => view.disabled)).toBe(true)
  })

  it('disables actions that would push fed funds outside the valid range', () => {
    const lowRateSession = {
      ...makeSession(),
      current: { ...classicScenario.startingState, fedFundsRate: 0.5 },
    }
    const highRateSession = {
      ...makeSession(),
      current: { ...classicScenario.startingState, fedFundsRate: 19.5 },
    }

    expect(policyActionViews(lowRateSession, classicScenario, false).map((view) => [view.action, view.disabled])).toEqual([
      ['cut_150', true],
      ['cut_100', true],
      ['cut_75', true],
      ['cut_50', false],
      ['cut_25', false],
      ['hold', false],
      ['raise_25', false],
      ['raise_50', false],
      ['raise_75', false],
      ['raise_100', false],
      ['raise_150', false],
    ])
    expect(policyActionViews(highRateSession, classicScenario, false).map((view) => [view.action, view.disabled])).toEqual([
      ['cut_150', false],
      ['cut_100', false],
      ['cut_75', false],
      ['cut_50', false],
      ['cut_25', false],
      ['hold', false],
      ['raise_25', false],
      ['raise_50', false],
      ['raise_75', true],
      ['raise_100', true],
      ['raise_150', true],
    ])
  })
})

describe('policyStance', () => {
  it('labels the opening stance against the neutral rate', () => {
    expect(policyStance(makeSession(), classicScenario)).toBe('Near neutral')
  })
})

describe('buildPolicyReadinessBrief', () => {
  it('summarizes the opening mandate balance without requiring a trace', () => {
    const brief = buildPolicyReadinessBrief(makeSession(), classicScenario)

    expect(brief.recommendedBias).toBe('hold')
    expect(brief.headline).toBe('Mandate balance supports patience')
    expect(brief.tiles.map((tile) => tile.label)).toEqual(['Inflation gap', 'Labor gap', 'Neutral gap', 'Trace risk'])
    expect(brief.tiles[2]?.detail).toContain('neutral')
    expect(brief.tiles[3]?.detail).toBe('No material shock pressure in the latest trace')
  })

  it('leans restrictive when inflation is above target and shock pressure is visible', () => {
    const session = {
      ...makeSession(),
      current: {
        ...classicScenario.startingState,
        quarterIndex: 2,
        inflation: 3.4,
        unemployment: 4.1,
        fedFundsRate: 4.5,
      },
      history: [
        classicScenario.startingState,
        { ...classicScenario.startingState, quarterIndex: 1, inflation: 3.1, unemployment: 4.0, fedFundsRate: 4.25 },
        { ...classicScenario.startingState, quarterIndex: 2, inflation: 3.4, unemployment: 4.1, fedFundsRate: 4.5 },
      ],
      traces: [
        {
          neutralRate: 4.1,
          policyGap: 0.4,
          laggedPolicyGap: 0.15,
          shockContrib: {
            demand: 0.42,
            supply: 0.05,
            financial: 0,
            labor: 0,
            energy: 0.12,
            confidence: 0,
          },
          inflationDelta: 0.3,
          unemploymentDelta: 0.1,
          gdpDelta: 0.2,
          explanation: 'Demand pressure lifted prices.',
        },
      ],
    } satisfies GameSession

    const brief = buildPolicyReadinessBrief(session, classicScenario)

    expect(brief.recommendedBias).toBe('tighten')
    expect(brief.headline).toBe('Inflation risk argues for restraint')
    expect(brief.tiles[0]?.value).toBe('+1.40 pp')
    expect(brief.tiles[3]?.detail).toBe('Demand shock +0.42 pp in trace')
  })

  it('leans easier when labor slack worsens under restrictive policy', () => {
    const session = {
      ...makeSession(),
      current: {
        ...classicScenario.startingState,
        quarterIndex: 2,
        inflation: 2.1,
        unemployment: 5.3,
        fedFundsRate: 5.6,
      },
      history: [
        classicScenario.startingState,
        { ...classicScenario.startingState, quarterIndex: 1, inflation: 2.2, unemployment: 4.9, fedFundsRate: 5.4 },
        { ...classicScenario.startingState, quarterIndex: 2, inflation: 2.1, unemployment: 5.3, fedFundsRate: 5.6 },
      ],
      traces: [
        {
          neutralRate: 4.4,
          policyGap: 1.2,
          laggedPolicyGap: 0.9,
          shockContrib: {
            demand: 0,
            supply: 0,
            financial: -0.1,
            labor: 0,
            energy: 0,
            confidence: 0,
          },
          inflationDelta: -0.1,
          unemploymentDelta: 0.4,
          gdpDelta: -0.2,
          explanation: 'Restrictive policy cooled activity.',
        },
      ],
    } satisfies GameSession

    const brief = buildPolicyReadinessBrief(session, classicScenario)

    expect(brief.recommendedBias).toBe('ease')
    expect(brief.headline).toBe('Labor slack argues for support')
    expect(brief.tiles[1]?.value).toBe('+0.30 pp')
    expect(brief.tiles[2]?.value).toBe('+1.20 pp')
  })
})
