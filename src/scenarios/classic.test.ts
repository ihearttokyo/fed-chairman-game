import { describe, expect, it } from 'vitest'
import { classicScenario } from './classic'
import { scenarioSchema } from './schema'

describe('classicScenario', () => {
  it('matches the clean-room classic starting values and validates', () => {
    expect(() => scenarioSchema.parse(classicScenario)).not.toThrow()
    expect(classicScenario.termQuarters).toBe(16)
    expect(classicScenario.startingState.inflation).toBe(2.11)
    expect(classicScenario.startingState.unemployment).toBe(4.68)
    expect(classicScenario.startingState.fedFundsRate).toBe(4)
    expect(classicScenario.targets).toEqual({ inflation: 2, unemployment: 5 })
    expect(classicScenario.allowedTools).toEqual(['fed_funds_rate'])
  })
})
