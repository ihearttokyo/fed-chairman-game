import type { EngineTrace, Shock, ShockType } from '../../types'

export type TraceDriverTone = 'cooling' | 'heating' | 'stabilizing' | 'stress'

export type TraceDriver = {
  label: string
  value: number
  display: string
  detail: string
  tone: TraceDriverTone
  width: number
}

export type TraceReadout = {
  policyLag: string
  largestShock: string
  inflationDelta: number
  unemploymentDelta: number
  gdpDelta: number
  credibilityDelta: number
  credibilityDetail: string
  explanation: string
  drivers: TraceDriver[]
}

const shockLabels: Record<ShockType, string> = {
  demand: 'demand',
  supply: 'supply',
  financial: 'financial stress',
  labor: 'labor conditions',
  energy: 'energy prices',
  confidence: 'confidence',
}

function formatSigned(value: number): string {
  const sign = value > 0 ? '+' : ''
  return `${sign}${value.toFixed(2)}`
}

function toneForDriver(label: string, value: number): TraceDriverTone {
  if (Math.abs(value) < 0.05) {
    return 'stabilizing'
  }
  if (label === 'Policy lag') {
    return value > 0 ? 'cooling' : 'heating'
  }
  if (label === 'Unemployment') {
    return value > 0 ? 'stress' : 'stabilizing'
  }
  return value > 0 ? 'heating' : 'cooling'
}

function roundDriver(value: number): number {
  return Math.round(value * 100) / 100
}

function buildDrivers(trace: EngineTrace): TraceDriver[] {
  const shockPressure = Object.values(trace.shockContrib).reduce((total, value) => total + value, 0)
  const rawDrivers = [
    {
      label: 'Policy lag',
      value: roundDriver(trace.laggedPolicyGap),
      detail: 'Prior rates versus neutral',
    },
    {
      label: 'Net shocks',
      value: roundDriver(shockPressure),
      detail: 'Demand, supply, financial, labor, energy, confidence',
    },
    {
      label: 'Inflation',
      value: roundDriver(trace.inflationDelta),
      detail: 'Completed quarter price move',
    },
    {
      label: 'Unemployment',
      value: roundDriver(trace.unemploymentDelta),
      detail: 'Completed quarter labor move',
    },
    {
      label: 'GDP growth',
      value: roundDriver(trace.gdpDelta),
      detail: 'Completed quarter growth move',
    },
  ]
  const maxAbs = Math.max(0.1, ...rawDrivers.map((driver) => Math.abs(driver.value)))

  return rawDrivers.map((driver) => ({
    ...driver,
    display: `${formatSigned(driver.value)} pp`,
    tone: toneForDriver(driver.label, driver.value),
    width: Math.max(8, Math.round((Math.abs(driver.value) / maxAbs) * 100)),
  }))
}

export function buildTraceReadout(trace: EngineTrace | undefined, triggered: Shock[]): TraceReadout | null {
  if (!trace) {
    return null
  }
  const policyLag =
    trace.laggedPolicyGap > 0.35 ? 'Restrictive policy lag' : trace.laggedPolicyGap < -0.35 ? 'Expansionary policy lag' : 'Near-neutral policy lag'
  const largestShockEntry = Object.entries(trace.shockContrib).sort(([, a], [, b]) => Math.abs(b) - Math.abs(a))[0]
  const largestShock =
    triggered[0]?.headlineKey ??
    (largestShockEntry && Math.abs(largestShockEntry[1]) > 0.05 ? shockLabels[largestShockEntry[0] as ShockType] : 'none')
  return {
    policyLag,
    largestShock,
    inflationDelta: trace.inflationDelta,
    unemploymentDelta: trace.unemploymentDelta,
    gdpDelta: trace.gdpDelta,
    credibilityDelta: trace.credibilityDelta ?? 0,
    credibilityDetail: `base ${formatSigned(trace.credibilityBaseDrift ?? 0)}, rate cost ${formatSigned(-(trace.credibilityRateMoveCost ?? 0))}, reappointment grace ${formatSigned(trace.credibilityReappointmentGrace ?? 0)}`,
    explanation: trace.explanation,
    drivers: buildDrivers(trace),
  }
}
