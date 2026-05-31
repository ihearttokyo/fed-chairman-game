import { describe, expect, it } from 'vitest'
import type { GameSession, ScenarioConfig } from '../../types'
import { buildShockTimeline } from './shockTimelineViewModel'

const scenario: ScenarioConfig = {
  id: 'classic_normal_cycle',
  label: 'Classic Normal Cycle',
  mode: 'classic_chair_the_fed',
  termQuarters: 16,
  startingState: {
    quarterIndex: 0,
    quartersRemaining: 16,
    inflation: 2.1,
    unemployment: 4.8,
    fedFundsRate: 4,
    outputGap: 0.2,
    gdpGrowth: 2.1,
    expectedInflation: 2.1,
    credibility: 82,
  },
  targets: { inflation: 2, unemployment: 5 },
  coefficients: {
    realNeutralRate: 1.5,
    trendGrowth: 2,
    rateSensitivity: 0.28,
    inflationRateSensitivity: 0.18,
    phillipsSlope: 0.13,
    okunCoefficient: 0.36,
    shockDecay: 0.58,
    noiseScale: 0.06,
  },
  shockDeck: [
    {
      id: 'early-energy',
      quarter: 3,
      type: 'energy',
      magnitude: 1.1,
      persistence: 2,
      headlineKey: 'energy',
    },
    {
      id: 'middle-financial',
      quarter: 7,
      type: 'financial',
      magnitude: -0.9,
      persistence: 3,
      headlineKey: 'financial',
    },
    {
      id: 'late-labor',
      quarter: 12,
      type: 'labor',
      magnitude: 0.7,
      persistence: 2,
      headlineKey: 'labor',
    },
  ],
  allowedTools: ['fed_funds_rate'],
  difficulty: 'standard',
  summary: 'Test scenario.',
}

const session: GameSession = {
  sessionId: 'test-session',
  mode: 'classic_chair_the_fed',
  scenarioId: 'classic_normal_cycle',
  status: 'in_progress',
  seed: 'test-seed',
  termNumber: 1,
  currentTermQuarter: 7,
  totalCareerQuarters: 7,
  completedTerms: [],
  careerHistory: [],
  careerScore: {
    score: 82,
    grade: 'B',
    reappointed: true,
    meanAbsInflationGap: 0.2,
    meanAbsUnemploymentGap: 0.2,
    volatilityIndex: 0.2,
    recessionQuarterShare: 0,
    credibilityBonus: 1,
    biggestMiss: 'balanced',
    takeaway: 'Stable.',
  },
  current: {
    quarterIndex: 7,
    quartersRemaining: 9,
    inflation: 2.4,
    unemployment: 5.1,
    fedFundsRate: 4.5,
    outputGap: -0.1,
    gdpGrowth: 1.9,
    expectedInflation: 2.3,
    credibility: 78,
  },
  history: [],
  decisions: [],
  traces: [],
  activeShocks: [],
  latestTriggeredShocks: [],
  score: {
    score: 82,
    grade: 'B',
    reappointed: true,
    meanAbsInflationGap: 0.2,
    meanAbsUnemploymentGap: 0.2,
    volatilityIndex: 0.2,
    recessionQuarterShare: 0,
    credibilityBonus: 1,
    biggestMiss: 'balanced',
    takeaway: 'Stable.',
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

describe('buildShockTimeline', () => {
  it('classifies deterministic shock windows by current quarter', () => {
    const timeline = buildShockTimeline(session, scenario)

    expect(timeline.summary).toBe('1 active shock still transmitting; 1 later risk remains.')
    expect(timeline.items).toEqual([
      expect.objectContaining({
        id: 'early-energy',
        status: 'passed',
        distanceLabel: 'Hit Q3',
        magnitudeLabel: '1.10 inflation pressure',
      }),
      expect.objectContaining({
        id: 'middle-financial',
        status: 'active',
        distanceLabel: '3 quarters left',
        magnitudeLabel: '0.90 growth drag',
      }),
      expect.objectContaining({
        id: 'late-labor',
        status: 'upcoming',
        distanceLabel: 'In 5 quarters',
        magnitudeLabel: '0.70 inflation pressure',
      }),
    ])
  })

  it('summarizes the next risk window when no shock is active', () => {
    const timeline = buildShockTimeline({ ...session, current: { ...session.current, quarterIndex: 5 } }, scenario)

    expect(timeline.summary).toBe('Next disclosed risk window: Q7 credit stress.')
    expect(timeline.items.map((item) => item.status)).toEqual(['passed', 'upcoming', 'upcoming'])
  })

  it('falls back after the term shock deck has fully played out', () => {
    const timeline = buildShockTimeline({ ...session, current: { ...session.current, quarterIndex: 16 } }, scenario)

    expect(timeline.summary).toBe('All scheduled term shocks have passed; policy lags remain the main known risk.')
    expect(timeline.items.every((item) => item.status === 'passed')).toBe(true)
  })
})
