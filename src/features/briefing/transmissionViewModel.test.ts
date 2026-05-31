import { describe, expect, it } from 'vitest'
import { advanceQuarter } from '../../engine/quarterEngine'
import { createDecision } from '../../engine/policy'
import { classicScenario } from '../../scenarios/classic'
import { evaluateScore } from '../../engine/scoreEngine'
import { buildTransmissionBriefing, buildTransmissionSteps } from './transmissionViewModel'
import type { GameSession } from '../../types'

function makeSessionAfterOneQuarter(action: Parameters<typeof createDecision>[0]): GameSession {
  const decision = createDecision(action, classicScenario.startingState, 'test-time')
  const advanced = advanceQuarter({
    history: [classicScenario.startingState],
    decision,
    scenario: classicScenario,
    activeShocks: [],
    seed: 'transmission-test',
  })
  const history = [classicScenario.startingState, advanced.nextState]
  const score = evaluateScore(history, classicScenario)
  return {
    sessionId: 'test',
    mode: 'classic_chair_the_fed',
    scenarioId: classicScenario.id,
    status: 'in_progress',
    seed: 'transmission-test',
    termNumber: 1,
    currentTermQuarter: 1,
    totalCareerQuarters: 1,
    completedTerms: [],
    careerHistory: history,
    careerScore: score,
    current: advanced.nextState,
    history,
    decisions: [decision],
    traces: [advanced.trace],
    activeShocks: advanced.activeShocks,
    latestTriggeredShocks: advanced.triggeredShocks,
    score,
    ui: {
      selectedDecision: null,
      chartView: 'chart',
      reducedMotion: false,
      soundEnabled: false,
      reducedNoise: false,
      soundVolume: 0.25,
    },
  }
}

describe('buildTransmissionSteps', () => {
  it('summarizes what changed since the previous quarter without extra simulation', () => {
    const session = makeSessionAfterOneQuarter('cut_25')
    const briefing = buildTransmissionBriefing(session, classicScenario)

    expect(briefing?.summary).toMatch(/^After cutting rates -0.25 pp, the quarter closed with inflation/)
    expect(briefing?.receipt).toEqual({
      headline: 'Mandate gap narrowed',
      verdict: 'The combined inflation and labor miss improved 0.09 pp this quarter.',
      policyEcho: 'The cut moved -0.25 pp to 3.75%; the current lag registered +0.35 pp.',
      nextWatch: 'Watch labor gap next: -0.31 pp from target.',
      tone: 'stabilizing',
    })
    expect(briefing?.decisionMemo).toEqual({
      headline: 'Contrarian easing against cooling pressure',
      assessment: 'Before the vote: inflation +0.11 pp from target, labor -0.32 pp from target.',
      tradeoff: 'The easing impulse met a +0.35 pp policy lag while output moved -0.22 pp.',
      risk: 'Main risk: labor remains -0.31 pp from target after the decision.',
      nextBias: 'Next bias: lean tighter unless the mandate gap cools.',
      tone: 'stress',
    })
    expect(briefing?.summary).toContain('unemployment')
    expect(briefing?.summary).toContain('output gap')
    expect(briefing?.summary).toContain('lag reached the economy')
    expect(briefing?.path).toEqual([
      'Lower target -0.25 pp',
      'Neutral lag +0.35 pp',
      'Inflation -0.08 pp, jobs +0.01 pp',
    ])
    expect(briefing?.causalChain).toEqual([
      {
        label: 'Decision impulse',
        text: 'The move leaves policy +0.10 pp from neutral, setting the signal that markets absorb first.',
        tone: 'heating',
      },
      {
        label: 'Lag plus shocks',
        text: 'That signal meets a +0.35 pp lag and 0.00 shock pressure, moving output -0.22 pp.',
        tone: 'cooling',
      },
      {
        label: 'Mandate read-through',
        text: 'The combined inflation and labor miss moved -0.09 pp, ending +0.03 pp on inflation and -0.31 pp on jobs.',
        tone: 'stabilizing',
      },
    ])
    expect(briefing?.changes).toEqual([
      {
        label: 'Inflation',
        previous: '2.11%',
        current: '2.03%',
        delta: '-0.08 pp',
        reason: 'Engine delta -0.08 pp; expectations 0.00 pp.',
        tone: 'cooling',
      },
      {
        label: 'Unemployment',
        previous: '4.68%',
        current: '4.69%',
        delta: '+0.01 pp',
        reason: 'Labor delta +0.01 pp; output -0.22 pp.',
        tone: 'stabilizing',
      },
      {
        label: 'Output gap',
        previous: '+0.20 pp',
        current: '-0.02 pp',
        delta: '-0.22 pp',
        reason: 'Lagged policy gap +0.35 pp; shocks 0.00.',
        tone: 'cooling',
      },
      {
        label: 'Credibility',
        previous: '82',
        current: '82',
        delta: '+0.41 pts',
        reason: 'Policy move -0.25 pp; expectations 0.00 pp.',
        tone: 'stabilizing',
      },
    ])
    expect(briefing?.steps).toHaveLength(3)
  })

  it('derives a deterministic three-month sequence from the latest quarter', () => {
    const session = makeSessionAfterOneQuarter('raise_25')
    const steps = buildTransmissionSteps(session, classicScenario)

    expect(steps.map((step) => step.month)).toEqual(['Month 1', 'Month 2', 'Month 3'])
    expect(steps.map((step) => step.channel)).toEqual(['Decision', 'Demand lag', 'Mandate close'])
    expect(steps[0]?.title).toBe('Rate hike committed')
    expect(steps[0]?.stance).toBe('Restrictive signal')
    expect(steps[0]?.intensity).toBe(48)
    expect(steps[0]?.intensityLabel).toBe('Policy signal strength')
    expect(steps[0]?.driver).toBe('Policy impulse: +0.25 pp move, +0.60 pp versus neutral')
    expect(steps[0]?.value).toBe('4.25% target')
    expect(steps[0]?.comparison).toBe('Fed funds: 4.00% -> 4.25%')
    expect(steps[0]?.basis).toContain('committed rate decision')
    expect(steps[0]?.evidence).toEqual(['Previous rate 4.00%', 'New rate 4.25%', 'Neutral 3.65%'])
    expect(steps[0]?.signals).toContain('Move: +0.25 pp')
    expect(steps[0]?.traceInputs).toEqual([
      'latest PolicyDecision',
      'EngineTrace.neutralRate',
      'scenario inflation target',
    ])
    expect(steps[1]?.value).toContain('pp lag')
    expect(steps[1]?.stance).toMatch(/Demand|Shock|Momentum/)
    expect(steps[1]?.intensity).toBeGreaterThanOrEqual(8)
    expect(steps[1]?.intensity).toBeLessThanOrEqual(100)
    expect(steps[1]?.intensityLabel).toMatch(/Lag pressure|Shock pressure/)
    expect(steps[1]?.driver).toMatch(/^Transmission driver: lag [+-]\d+\.\d{2} pp, shocks [+-]?\d+\.\d{2}$/)
    expect(steps[1]?.comparison).toMatch(/^Output gap: /)
    expect(steps[1]?.basis).toContain('lagged policy gap')
    expect(steps[1]?.evidence).toHaveLength(3)
    expect(steps[1]?.evidence[0]).toMatch(/^Output [+-]\d+\.\d{2} pp$/)
    expect(steps[1]?.evidence[1]).toMatch(/^GDP [+-]\d+\.\d{2} pp$/)
    expect(steps[1]?.evidence[2]).toMatch(/^Shocks [+-]?\d+\.\d{2}$/)
    expect(steps[1]?.signals[0]).toMatch(/^Lag:/)
    expect(steps[1]?.signals[1]).toMatch(/^Dominant:/)
    expect(steps[1]?.traceInputs).toEqual([
      'previous MacroState',
      'current MacroState',
      'EngineTrace.laggedPolicyGap',
      'EngineTrace.shockContrib',
    ])
    expect(steps[2]?.value).toContain('/')
    expect(steps[2]?.stance).toMatch(/^Mandate /)
    expect(steps[2]?.intensity).toBeGreaterThanOrEqual(8)
    expect(steps[2]?.intensity).toBeLessThanOrEqual(100)
    expect(steps[2]?.intensityLabel).toMatch(/Progress toward mandate|Mandate pressure/)
    expect(steps[2]?.driver).toMatch(/^Mandate driver: inflation gap [+-]\d+\.\d{2} pp, jobs gap [+-]\d+\.\d{2} pp$/)
    expect(steps[2]?.comparison).toMatch(/^Inflation /)
    expect(steps[2]?.basis).toContain('engine deltas')
    expect(steps[2]?.evidence).toHaveLength(3)
    expect(steps[2]?.evidence[0]).toMatch(/^Inflation [+-]\d+\.\d{2} pp$/)
    expect(steps[2]?.evidence[1]).toMatch(/^Unemployment [+-]\d+\.\d{2} pp$/)
    expect(steps[2]?.evidence[2]).toMatch(/^Credibility [+-]\d+\.\d{2} pts$/)
    expect(steps[2]?.signals[0]).toMatch(/^Distance: [+-]\d+\.\d{2} pp$/)
    expect(steps[2]?.signals).toHaveLength(3)
    expect(steps[2]?.traceInputs).toEqual([
      'previous MacroState',
      'current MacroState',
      'EngineTrace.inflationDelta',
      'EngineTrace.unemploymentDelta',
      'scenario mandate targets',
    ])
  })

  it('returns no sequence until a completed quarter exists', () => {
    const session = makeSessionAfterOneQuarter('hold')
    const openingSession = {
      ...session,
      current: classicScenario.startingState,
      history: [classicScenario.startingState],
      decisions: [],
      traces: [],
    }

    expect(buildTransmissionSteps(openingSession, classicScenario)).toEqual([])
    expect(buildTransmissionBriefing(openingSession, classicScenario)).toBeNull()
  })
})
