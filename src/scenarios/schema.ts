import { z } from 'zod'

export const macroStateSchema = z.object({
  quarterIndex: z.number().int().min(0),
  quartersRemaining: z.number().int().min(0),
  inflation: z.number().finite(),
  unemployment: z.number().finite(),
  fedFundsRate: z.number().finite().min(0),
  outputGap: z.number().finite(),
  gdpGrowth: z.number().finite(),
  expectedInflation: z.number().finite(),
  credibility: z.number().finite().min(0).max(100),
  longRate: z.number().finite().optional(),
  marketIndex: z.number().finite().optional(),
  confidence: z.number().finite().optional(),
})

export const scenarioSchema = z.object({
  id: z.string().min(1),
  label: z.string().min(1),
  mode: z.literal('classic_chair_the_fed'),
  termQuarters: z.literal(16),
  startingState: macroStateSchema,
  targets: z.object({
    inflation: z.literal(2),
    unemployment: z.literal(5),
  }),
  coefficients: z.object({
    realNeutralRate: z.number().finite(),
    trendGrowth: z.number().finite(),
    rateSensitivity: z.number().finite(),
    inflationRateSensitivity: z.number().finite(),
    phillipsSlope: z.number().finite(),
    okunCoefficient: z.number().finite(),
    shockDecay: z.number().finite(),
    noiseScale: z.number().finite().min(0),
  }),
  shockDeck: z.array(
    z.object({
      id: z.string().min(1),
      quarter: z.union([z.number().int().min(1).max(16), z.literal('random')]),
      type: z.enum(['demand', 'supply', 'financial', 'labor', 'energy', 'confidence']),
      magnitude: z.number().finite(),
      persistence: z.number().int().min(1),
      headlineKey: z.string().min(1),
    }),
  ),
  allowedTools: z.array(z.literal('fed_funds_rate')).min(1),
  difficulty: z.enum(['intro', 'standard', 'hard', 'legendary']),
  summary: z.string().min(1),
})
