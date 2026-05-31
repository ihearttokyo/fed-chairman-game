import type { ScenarioConfig } from '../types'
import { SeededRng } from '../engine/rng'
import { scenarioSchema } from './schema'

export const classicScenario = scenarioSchema.parse({
  id: 'classic_normal_cycle',
  label: 'Classic Normal Cycle',
  mode: 'classic_chair_the_fed',
  termQuarters: 16,
  startingState: {
    quarterIndex: 0,
    quartersRemaining: 16,
    inflation: 2.11,
    unemployment: 4.68,
    fedFundsRate: 4,
    outputGap: 0.2,
    gdpGrowth: 2.1,
    expectedInflation: 2.15,
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
  shockDeck: [],
  allowedTools: ['fed_funds_rate'],
  difficulty: 'standard',
  summary: 'A 16-quarter clean-room classic mode focused on the inflation and unemployment tradeoff.',
}) as ScenarioConfig

export const scenarios = [classicScenario]

export function getScenario(id = 'classic_normal_cycle'): ScenarioConfig {
  const scenario = scenarios.find((item) => item.id === id)
  if (!scenario) {
    throw new Error(`Unknown scenario: ${id}`)
  }
  return scenario
}

const shockTemplates = [
  {
    id: 'energy-price-squeeze',
    type: 'energy' as const,
    headlineKey: 'energy',
    magnitude: [0.85, 1.35],
    persistence: [2, 3],
  },
  {
    id: 'household-demand-softens',
    type: 'demand' as const,
    headlineKey: 'demandSoft',
    magnitude: [-1.2, -0.65],
    persistence: [2, 3],
  },
  {
    id: 'credit-markets-tighten',
    type: 'financial' as const,
    headlineKey: 'financial',
    magnitude: [-1.25, -0.75],
    persistence: [2, 4],
  },
  {
    id: 'supply-chain-snarls',
    type: 'supply' as const,
    headlineKey: 'supply',
    magnitude: [0.55, 1.05],
    persistence: [2, 3],
  },
  {
    id: 'labor-market-heats-up',
    type: 'labor' as const,
    headlineKey: 'labor',
    magnitude: [0.5, 0.95],
    persistence: [2, 3],
  },
  {
    id: 'confidence-slide',
    type: 'confidence' as const,
    headlineKey: 'confidence',
    magnitude: [-1.0, -0.45],
    persistence: [2, 3],
  },
]

function pickQuarter(rng: SeededRng, min: number, max: number): number {
  return Math.floor(rng.between(min, max + 1))
}

export function buildTermShockDeck(seed: string, termNumber: number): ScenarioConfig['shockDeck'] {
  const rng = new SeededRng(`${seed}:term-${termNumber}:shock-deck`)
  const windows = [
    [3, 5],
    [7, 9],
    [11, 13],
    [14, 16],
  ] as const
  const offset = Math.floor(rng.between(0, shockTemplates.length))
  return windows.map(([minQuarter, maxQuarter], index) => {
    const template = shockTemplates[(offset + index) % shockTemplates.length]!
    const [magnitudeMin, magnitudeMax] = template.magnitude
    const [persistenceMin, persistenceMax] = template.persistence
    const magnitude = rng.between(magnitudeMin!, magnitudeMax!)
    const persistence = pickQuarter(rng, persistenceMin!, persistenceMax!)
    return {
      id: `${template.id}-t${termNumber}-${index + 1}`,
      quarter: pickQuarter(rng, minQuarter, maxQuarter),
      type: template.type,
      magnitude: Number(magnitude.toFixed(2)),
      persistence,
      headlineKey: template.headlineKey,
    }
  })
}

export function getTermScenario(id = 'classic_normal_cycle', seed = 'classic-2026', termNumber = 1): ScenarioConfig {
  const scenario = getScenario(id)
  return {
    ...scenario,
    shockDeck: buildTermShockDeck(seed, termNumber),
  }
}
