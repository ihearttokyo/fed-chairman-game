import { z } from 'zod'
import { macroStateSchema } from '../scenarios/schema'

const policyActionSchema = z.enum([
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
  'custom',
])

const shockSchema = z.object({
  id: z.string().min(1),
  quarter: z.union([z.number().int().min(1).max(16), z.literal('random')]),
  type: z.enum(['demand', 'supply', 'financial', 'labor', 'energy', 'confidence']),
  magnitude: z.number().finite(),
  persistence: z.number().int().min(1),
  headlineKey: z.string().min(1),
})

const activeShockSchema = shockSchema.extend({
  startedQuarter: z.number().int().min(1),
  remaining: z.number().int().min(1),
})

const policyDecisionSchema = z.object({
  id: z.string().min(1),
  quarterIndex: z.number().int().min(1).max(16),
  careerQuarterIndex: z.number().int().min(1).optional(),
  action: policyActionSchema,
  rateChange: z.number().finite(),
  resultingFedFundsRate: z.number().finite().min(0).max(20),
  timestamp: z.string().min(1),
})

const engineTraceSchema = z.object({
  neutralRate: z.number().finite(),
  policyGap: z.number().finite(),
  laggedPolicyGap: z.number().finite(),
  shockContrib: z.record(z.enum(['demand', 'supply', 'financial', 'labor', 'energy', 'confidence']), z.number().finite()),
  credibilityBaseDrift: z.number().finite().default(0),
  credibilityRateMoveCost: z.number().finite().default(0),
  credibilityReappointmentGrace: z.number().finite().default(0),
  credibilityDelta: z.number().finite().default(0),
  inflationDelta: z.number().finite(),
  unemploymentDelta: z.number().finite(),
  gdpDelta: z.number().finite(),
  explanation: z.string().min(1),
})

const scoreStateSchema = z.object({
  score: z.number().finite().min(0).max(100),
  grade: z.enum(['A', 'B', 'C', 'D', 'F']),
  reappointed: z.boolean(),
  meanAbsInflationGap: z.number().finite().min(0),
  meanAbsUnemploymentGap: z.number().finite().min(0),
  volatilityIndex: z.number().finite().min(0),
  recessionQuarterShare: z.number().finite().min(0).max(1),
  credibilityBonus: z.number().finite(),
  biggestMiss: z.string().min(1),
  takeaway: z.string().min(1),
})

const completedTermSchema = z.object({
  termNumber: z.number().int().min(1),
  startingState: macroStateSchema,
  endingState: macroStateSchema,
  history: z.array(macroStateSchema).min(17).max(17),
  decisions: z.array(policyDecisionSchema).min(16).max(16),
  traces: z.array(engineTraceSchema).min(16).max(16),
  score: scoreStateSchema,
  reappointed: z.boolean(),
})

export const gameSessionSchema = z
  .object({
    sessionId: z.string().min(1),
    mode: z.literal('classic_chair_the_fed'),
    scenarioId: z.literal('classic_normal_cycle'),
    status: z.enum(['not_started', 'in_progress', 'term_debrief', 'retired', 'not_reappointed']),
    seed: z.string().min(1),
    termNumber: z.number().int().min(1),
    currentTermQuarter: z.number().int().min(0).max(16),
    totalCareerQuarters: z.number().int().min(0),
    completedTerms: z.array(completedTermSchema),
    careerHistory: z.array(macroStateSchema).min(1),
    careerScore: scoreStateSchema,
    current: macroStateSchema,
    history: z.array(macroStateSchema).min(1).max(17),
    decisions: z.array(policyDecisionSchema).max(16),
    traces: z.array(engineTraceSchema).max(16),
    activeShocks: z.array(activeShockSchema),
    latestTriggeredShocks: z.array(shockSchema),
    score: scoreStateSchema,
    ui: z.object({
      selectedDecision: policyActionSchema.nullable(),
      chartView: z.enum(['chart', 'table']),
      reducedMotion: z.boolean(),
      soundEnabled: z.boolean(),
      reducedNoise: z.boolean(),
      soundVolume: z.number().finite().min(0).max(1),
    }),
  })
  .superRefine((session, context) => {
    const latest = session.history.at(-1)
    if (latest && latest.quarterIndex !== session.current.quarterIndex) {
      context.addIssue({
        code: 'custom',
        message: 'Current state must match the latest history state.',
        path: ['current'],
      })
    }
    if (session.currentTermQuarter !== session.current.quarterIndex) {
      context.addIssue({
        code: 'custom',
        message: 'Current term quarter must match current state quarter.',
        path: ['currentTermQuarter'],
      })
    }
    if (session.decisions.length > session.currentTermQuarter) {
      context.addIssue({
        code: 'custom',
        message: 'Decision count cannot exceed current quarter.',
        path: ['decisions'],
      })
    }
    if ((session.status === 'term_debrief' || session.status === 'retired' || session.status === 'not_reappointed') && session.current.quartersRemaining !== 0) {
      context.addIssue({
        code: 'custom',
        message: 'Completed terms must have no quarters remaining.',
        path: ['status'],
      })
    }
    if (latest && JSON.stringify(latest) !== JSON.stringify(session.current)) {
      context.addIssue({
        code: 'custom',
        message: 'Current state values must equal the latest history entry.',
        path: ['history'],
      })
    }
    if (session.status !== 'not_started' && session.decisions.length !== session.currentTermQuarter) {
      context.addIssue({
        code: 'custom',
        message: 'Decision count must match the current played quarter.',
        path: ['decisions'],
      })
    }
    if (session.traces.length > session.currentTermQuarter) {
      context.addIssue({
        code: 'custom',
        message: 'Trace count cannot exceed the current played quarter.',
        path: ['traces'],
      })
    }
    if (session.completedTerms.length > session.termNumber) {
      context.addIssue({
        code: 'custom',
        message: 'Completed terms cannot exceed current term number.',
        path: ['completedTerms'],
      })
    }
    if (session.totalCareerQuarters < session.completedTerms.length * 16) {
      context.addIssue({
        code: 'custom',
        message: 'Career quarters must cover completed terms.',
        path: ['totalCareerQuarters'],
      })
    }
  })
