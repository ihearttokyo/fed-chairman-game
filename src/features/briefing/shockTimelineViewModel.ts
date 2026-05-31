import type { GameSession, ScenarioConfig, Shock } from '../../types'

export type ShockTimelineItem = {
  id: string
  quarter: number
  label: string
  detail: string
  status: 'passed' | 'active' | 'upcoming'
  distanceLabel: string
  magnitudeLabel: string
}

export type ShockTimeline = {
  summary: string
  items: ShockTimelineItem[]
}

const shockLabels: Record<string, string> = {
  energy: 'Energy costs',
  demandSoft: 'Demand cooling',
  financial: 'Credit stress',
  supply: 'Supply bottlenecks',
  labor: 'Labor pressure',
  confidence: 'Confidence slide',
}

function quarterOf(shock: Shock): number | null {
  return typeof shock.quarter === 'number' ? shock.quarter : null
}

function statusFor(shock: Shock, currentQuarter: number): ShockTimelineItem['status'] {
  const quarter = quarterOf(shock)
  if (quarter === null) {
    return 'upcoming'
  }
  if (quarter > currentQuarter) {
    return 'upcoming'
  }
  if (quarter + shock.persistence - 1 >= currentQuarter) {
    return 'active'
  }
  return 'passed'
}

function distanceLabel(shock: Shock, currentQuarter: number): string {
  const quarter = quarterOf(shock)
  if (quarter === null) {
    return 'Timing hidden'
  }
  const status = statusFor(shock, currentQuarter)
  if (status === 'upcoming') {
    const distance = quarter - currentQuarter
    return distance === 1 ? 'Next quarter' : `In ${distance} quarters`
  }
  if (status === 'active') {
    const remaining = quarter + shock.persistence - currentQuarter
    return remaining <= 1 ? 'Final quarter' : `${remaining} quarters left`
  }
  return `Hit Q${quarter}`
}

function magnitudeLabel(shock: Shock): string {
  const direction = shock.magnitude > 0 ? 'inflation pressure' : 'growth drag'
  return `${Math.abs(shock.magnitude).toFixed(2)} ${direction}`
}

function makeItem(shock: Shock, currentQuarter: number): ShockTimelineItem | null {
  const quarter = quarterOf(shock)
  if (quarter === null) {
    return null
  }
  return {
    id: shock.id,
    quarter,
    label: shockLabels[shock.headlineKey] ?? 'Macro shock',
    detail: `${shock.type} shock, ${shock.persistence} quarter${shock.persistence === 1 ? '' : 's'}`,
    status: statusFor(shock, currentQuarter),
    distanceLabel: distanceLabel(shock, currentQuarter),
    magnitudeLabel: magnitudeLabel(shock),
  }
}

export function buildShockTimeline(session: GameSession, scenario: ScenarioConfig): ShockTimeline {
  const currentQuarter = session.current.quarterIndex
  const items = scenario.shockDeck
    .map((shock) => makeItem(shock, currentQuarter))
    .filter((item): item is ShockTimelineItem => item !== null)
    .sort((a, b) => a.quarter - b.quarter)

  const active = items.filter((item) => item.status === 'active').length
  const upcoming = items.filter((item) => item.status === 'upcoming').length
  const next = items.find((item) => item.status === 'upcoming')

  if (active > 0) {
    const laterRiskCopy = upcoming === 1 ? '1 later risk remains' : `${upcoming} later risks remain`
    return {
      summary: `${active} active shock${active === 1 ? '' : 's'} still transmitting; ${laterRiskCopy}.`,
      items,
    }
  }
  if (next) {
    return {
      summary: `Next disclosed risk window: Q${next.quarter} ${next.label.toLowerCase()}.`,
      items,
    }
  }
  return {
    summary: 'All scheduled term shocks have passed; policy lags remain the main known risk.',
    items,
  }
}
