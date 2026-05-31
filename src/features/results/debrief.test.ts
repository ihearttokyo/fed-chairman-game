import { describe, expect, it } from 'vitest'
import type { GameSession } from '../../types'
import { buildDebrief } from './debrief'

const session: GameSession = {
  sessionId: 'test-session',
  mode: 'classic_chair_the_fed',
  scenarioId: 'classic_normal_cycle',
  status: 'term_debrief',
  seed: 'test-seed',
  termNumber: 1,
  currentTermQuarter: 4,
  totalCareerQuarters: 4,
  completedTerms: [],
  current: {
    quarterIndex: 4,
    quartersRemaining: 0,
    inflation: 2.45,
    unemployment: 5.35,
    fedFundsRate: 4.25,
    outputGap: -0.3,
    gdpGrowth: 1.8,
    expectedInflation: 2.4,
    credibility: 78,
  },
  history: [
    {
      quarterIndex: 0,
      quartersRemaining: 4,
      inflation: 2.1,
      unemployment: 4.8,
      fedFundsRate: 4,
      outputGap: 0.2,
      gdpGrowth: 2.1,
      expectedInflation: 2.1,
      credibility: 82,
    },
    {
      quarterIndex: 1,
      quartersRemaining: 3,
      inflation: 2.2,
      unemployment: 4.9,
      fedFundsRate: 4.25,
      outputGap: 0.1,
      gdpGrowth: 2,
      expectedInflation: 2.2,
      credibility: 81,
    },
    {
      quarterIndex: 2,
      quartersRemaining: 2,
      inflation: 2.35,
      unemployment: 5.1,
      fedFundsRate: 4.25,
      outputGap: -0.1,
      gdpGrowth: 1.9,
      expectedInflation: 2.3,
      credibility: 80,
    },
    {
      quarterIndex: 3,
      quartersRemaining: 1,
      inflation: 2.9,
      unemployment: 5.2,
      fedFundsRate: 4.75,
      outputGap: -0.2,
      gdpGrowth: 1.7,
      expectedInflation: 2.8,
      credibility: 76,
    },
    {
      quarterIndex: 4,
      quartersRemaining: 0,
      inflation: 2.45,
      unemployment: 5.35,
      fedFundsRate: 4.25,
      outputGap: -0.3,
      gdpGrowth: 1.8,
      expectedInflation: 2.4,
      credibility: 78,
    },
  ],
  decisions: [
    {
      id: 'q1-hike',
      quarterIndex: 1,
      action: 'raise_25',
      rateChange: 0.25,
      resultingFedFundsRate: 4.25,
      timestamp: '2026-01-01T00:00:00.000Z',
    },
    {
      id: 'q2-hold',
      quarterIndex: 2,
      action: 'hold',
      rateChange: 0,
      resultingFedFundsRate: 4.25,
      timestamp: '2026-01-02T00:00:00.000Z',
    },
    {
      id: 'q3-hike',
      quarterIndex: 3,
      action: 'raise_50',
      rateChange: 0.5,
      resultingFedFundsRate: 4.75,
      timestamp: '2026-01-03T00:00:00.000Z',
    },
    {
      id: 'q4-cut',
      quarterIndex: 4,
      action: 'cut_50',
      rateChange: -0.5,
      resultingFedFundsRate: 4.25,
      timestamp: '2026-01-04T00:00:00.000Z',
    },
  ],
  traces: [
    {
      neutralRate: 3.5,
      policyGap: 0.75,
      laggedPolicyGap: 0.1,
      shockContrib: { demand: 0, supply: 0, financial: 0, labor: 0, energy: 0.1, confidence: 0 },
      inflationDelta: 0.1,
      unemploymentDelta: 0.1,
      gdpDelta: -0.1,
      explanation: 'Q1 trace.',
    },
    {
      neutralRate: 3.5,
      policyGap: 0.75,
      laggedPolicyGap: 0.2,
      shockContrib: { demand: 0, supply: 0, financial: 0, labor: 0, energy: 0.2, confidence: 0 },
      inflationDelta: 0.15,
      unemploymentDelta: 0.2,
      gdpDelta: -0.1,
      explanation: 'Q2 trace.',
    },
    {
      neutralRate: 3.6,
      policyGap: 1.15,
      laggedPolicyGap: 0.3,
      shockContrib: { demand: 0, supply: 0, financial: 0, labor: 0, energy: 0.3, confidence: 0 },
      inflationDelta: 0.55,
      unemploymentDelta: 0.1,
      gdpDelta: -0.2,
      explanation: 'Q3 trace.',
    },
    {
      neutralRate: 3.6,
      policyGap: 0.65,
      laggedPolicyGap: 0.55,
      shockContrib: { demand: -0.1, supply: 0, financial: -0.2, labor: 0, energy: 0.05, confidence: 0 },
      inflationDelta: -0.45,
      unemploymentDelta: 0.15,
      gdpDelta: 0.1,
      explanation: 'Q4 trace.',
    },
  ],
  activeShocks: [],
  latestTriggeredShocks: [],
  careerHistory: [
    {
      quarterIndex: 0,
      quartersRemaining: 4,
      inflation: 2.1,
      unemployment: 4.8,
      fedFundsRate: 4,
      outputGap: 0.2,
      gdpGrowth: 2.1,
      expectedInflation: 2.1,
      credibility: 82,
    },
    {
      quarterIndex: 1,
      quartersRemaining: 3,
      inflation: 2.2,
      unemployment: 4.9,
      fedFundsRate: 4.25,
      outputGap: 0.1,
      gdpGrowth: 2,
      expectedInflation: 2.2,
      credibility: 81,
    },
    {
      quarterIndex: 2,
      quartersRemaining: 2,
      inflation: 2.35,
      unemployment: 5.1,
      fedFundsRate: 4.25,
      outputGap: -0.1,
      gdpGrowth: 1.9,
      expectedInflation: 2.3,
      credibility: 80,
    },
    {
      quarterIndex: 3,
      quartersRemaining: 1,
      inflation: 2.9,
      unemployment: 5.2,
      fedFundsRate: 4.75,
      outputGap: -0.2,
      gdpGrowth: 1.7,
      expectedInflation: 2.8,
      credibility: 76,
    },
    {
      quarterIndex: 4,
      quartersRemaining: 0,
      inflation: 2.45,
      unemployment: 5.35,
      fedFundsRate: 4.25,
      outputGap: -0.3,
      gdpGrowth: 1.8,
      expectedInflation: 2.4,
      credibility: 78,
    },
  ],
  score: {
    score: 78.5,
    grade: 'C',
    reappointed: true,
    meanAbsInflationGap: 0.48,
    meanAbsUnemploymentGap: 0.19,
    volatilityIndex: 0.35,
    recessionQuarterShare: 0,
    credibilityBonus: 1.3,
    biggestMiss: 'inflation drift',
    takeaway: 'Inflation responds with a lag.',
  },
  careerScore: {
    score: 78.5,
    grade: 'C',
    reappointed: true,
    meanAbsInflationGap: 0.48,
    meanAbsUnemploymentGap: 0.19,
    volatilityIndex: 0.35,
    recessionQuarterShare: 0,
    credibilityBonus: 1.3,
    biggestMiss: 'inflation drift',
    takeaway: 'Inflation responds with a lag.',
  },
  ui: {
    selectedDecision: null,
    chartView: 'chart',
    reducedMotion: false,
    soundEnabled: false,
    reducedNoise: false,
    soundVolume: 0.25,
  },
}

describe('buildDebrief', () => {
  it('builds a session-derived term report without changing engine data', () => {
    const debrief = buildDebrief(session)

    expect(debrief.bestStretch).toBe('3 of 4 quarters were close to target; longest run was Q1-Q2.')
    expect(debrief.turningPoint).toBe('Q3 moved most: +0.65 total points across inflation and unemployment.')
    expect(debrief.mandateTrend).toBe('Final quarter inflation cooled to 2.45%; unemployment weakened to 5.35%.')
    expect(debrief.decisionMix).toBe('2 hikes, 1 cut, 1 hold across 4 meetings.')
    expect(debrief.finalImpulse).toBe('Final quarter: restrictive lag was cooling demand; net shocks leaned disinflationary (-0.25 pp).')
    expect(debrief.coachingFocus).toBe('Watch expected inflation and policy lag before inflation breaks far from target.')
    expect(debrief.largestPolicyMove).toBe('Largest move: Q3 raise 50 (+0.50 pp).')
    expect(debrief.termStanding).toBe('Term 1 scored 78.5 (C) across 4 policy meetings; reappointment earned.')
    expect(debrief.nextTermBrief).toBe('Term 2 opens with inflation near target and labor near balance; inherited rate 4.25%.')
    expect(debrief.streakQuarters).toBe(2)
    expect(debrief.boardVerdict).toBe('The board reappointed you for Term 2; your next four years inherit this economy.')
    expect(debrief.gateStatus).toBe('Retirement unlocks after completing one reappointment term; continue into Term 2 to build a career score.')
    expect(debrief.gateChoice).toBe('Your next click starts Term 2 immediately; retirement remains locked until that term is complete.')
    expect(debrief.retirementStatus).toBe('Retirement locked: complete 1 more reappointed term first.')
    expect(debrief.careerProgressLabel).toBe('1 term until retirement unlock')
    expect(debrief.careerProgressValue).toBe(1)
    expect(debrief.careerProgressMax).toBe(2)
    expect(debrief.termHandoff).toBe(
      'You inherited 2.10% inflation, 4.80% unemployment, and a 4.00% policy rate; the handoff is more strained on both sides of the mandate.',
    )
    expect(debrief.termHandoffMetrics).toEqual([
      {
        label: 'Inflation gap',
        start: '0.10 pp',
        end: '0.45 pp',
        delta: '+0.35 pp',
        tone: 'worse',
      },
      {
        label: 'Labor gap',
        start: '0.20 pp',
        end: '0.35 pp',
        delta: '+0.15 pp',
        tone: 'worse',
      },
      {
        label: 'Policy rate',
        start: '4.00%',
        end: '4.25%',
        delta: '+0.25 pp',
        tone: 'steady',
      },
      {
        label: 'Credibility',
        start: '82',
        end: '78',
        delta: '-4',
        tone: 'worse',
      },
    ])
    expect(debrief.careerStanding).toBe('No completed four-year terms yet.')
    expect(debrief.carryoverBrief).toBe('Carryover economy for Term 2: 2.45% inflation, 5.35% unemployment, 4.25% policy rate.')
    expect(debrief.carryoverMetrics).toEqual([
      '2.45% inflation',
      '5.35% unemployment',
      '4.25% policy rate',
      '1.80% GDP growth',
    ])
    expect(debrief.careerLedger).toEqual([])
  })

  it('summarizes completed terms for the reappointment gate', () => {
    const debrief = buildDebrief({
      ...session,
      completedTerms: [
        {
          termNumber: 1,
          startingState: session.history[0]!,
          endingState: session.current,
          history: session.history,
          decisions: session.decisions,
          traces: session.traces,
          score: session.score,
          reappointed: true,
        },
      ],
    })

    expect(debrief.careerStanding).toBe('1 completed four-year term; 1 reappointment earned. Career score 78.5 (C).')
    expect(debrief.careerLedger).toEqual([
      {
        termNumber: 1,
        label: 'Term 1',
        score: '78.5 (C)',
        outcome: 'Reappointed',
        finalInflation: '2.45%',
        finalUnemployment: '5.35%',
        finalRate: '4.25%',
        decisionMix: '2H / 1C / 1 hold',
      },
    ])
  })

  it('keeps term report calculations scoped to the latest completed term', () => {
    const weakCurrentHistory = [
      session.current,
      {
        ...session.current,
        quarterIndex: 1,
        quartersRemaining: 15,
        inflation: 5.8,
        unemployment: 8.4,
        fedFundsRate: 5.0,
      },
    ]
    const debrief = buildDebrief({
      ...session,
      termNumber: 2,
      history: weakCurrentHistory,
      decisions: [
        {
          id: 'current-term-cut',
          quarterIndex: 1,
          action: 'cut_75',
          rateChange: -0.75,
          resultingFedFundsRate: 3.5,
          timestamp: '2026-01-05T00:00:00.000Z',
        },
      ],
      completedTerms: [
        {
          termNumber: 1,
          startingState: session.history[0]!,
          endingState: session.current,
          history: session.history,
          decisions: session.decisions,
          traces: session.traces,
          score: session.score,
          reappointed: true,
        },
      ],
    })

    expect(debrief.termStanding).toBe('Term 1 scored 78.5 (C) across 4 policy meetings; reappointment earned.')
    expect(debrief.decisionMix).toBe('2 hikes, 1 cut, 1 hold across 4 meetings.')
    expect(debrief.largestPolicyMove).toBe('Largest move: Q3 raise 50 (+0.50 pp).')
    expect(debrief.mandateTrend).toBe('Final quarter inflation cooled to 2.45%; unemployment weakened to 5.35%.')
  })

  it('unlocks retirement copy after a reappointment term is completed', () => {
    const completedTerm = {
      termNumber: 1,
      startingState: session.history[0]!,
      endingState: session.current,
      history: session.history,
      decisions: session.decisions,
      traces: session.traces,
      score: session.score,
      reappointed: true,
    }
    const debrief = buildDebrief({
      ...session,
      termNumber: 2,
      completedTerms: [
        completedTerm,
        {
          ...completedTerm,
          termNumber: 2,
        },
      ],
    })

    expect(debrief.gateStatus).toBe('Choose another four-year term or retire with a final career score.')
    expect(debrief.gateChoice).toBe('Your next click either starts another inherited four-year term or locks the career score.')
    expect(debrief.retirementStatus).toBe('Retirement is available now because you completed at least one reappointment term.')
    expect(debrief.careerProgressLabel).toBe('Retirement eligible at this gate')
    expect(debrief.careerProgressValue).toBe(2)
    expect(debrief.careerProgressMax).toBe(2)
  })
})
