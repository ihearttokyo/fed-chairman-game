import { describe, expect, it } from 'vitest'
import type { EngineTrace } from '../../types'
import { buildTraceReadout } from './briefingViewModel'

const trace: EngineTrace = {
  neutralRate: 3.65,
  policyGap: 0.6,
  laggedPolicyGap: 0.35,
  shockContrib: {
    demand: 0.2,
    supply: -0.1,
    financial: -0.4,
    labor: 0,
    energy: 0.3,
    confidence: 0.1,
  },
  inflationDelta: -0.08,
  unemploymentDelta: 0.21,
  gdpDelta: -0.42,
  explanation: 'Trace explanation.',
}

describe('buildTraceReadout', () => {
  it('builds a deterministic driver breakdown from engine trace values', () => {
    const readout = buildTraceReadout(trace, [])

    expect(readout?.drivers).toEqual([
      {
        label: 'Policy lag',
        value: 0.35,
        display: '+0.35 pp',
        detail: 'Prior rates versus neutral',
        tone: 'cooling',
        width: 83,
      },
      {
        label: 'Net shocks',
        value: 0.1,
        display: '+0.10 pp',
        detail: 'Demand, supply, financial, labor, energy, confidence',
        tone: 'heating',
        width: 24,
      },
      {
        label: 'Inflation',
        value: -0.08,
        display: '-0.08 pp',
        detail: 'Completed quarter price move',
        tone: 'cooling',
        width: 19,
      },
      {
        label: 'Unemployment',
        value: 0.21,
        display: '+0.21 pp',
        detail: 'Completed quarter labor move',
        tone: 'stress',
        width: 50,
      },
      {
        label: 'GDP growth',
        value: -0.42,
        display: '-0.42 pp',
        detail: 'Completed quarter growth move',
        tone: 'cooling',
        width: 100,
      },
    ])
  })

  it('falls back to the largest trace shock when no headline triggered', () => {
    const readout = buildTraceReadout(trace, [])

    expect(readout?.largestShock).toBe('financial stress')
  })
})
