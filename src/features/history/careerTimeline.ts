import { policyDecisionLabel } from '../../engine/policy'
import type { GameSession, MacroState, PolicyDecision } from '../../types'

export type CareerTimelinePoint = MacroState & {
  key: string
  label: string
  termNumber: number
  termQuarter: number
  careerQuarter: number
  isTermStart: boolean
  decisionLabel: string
  decisionTone: 'cut' | 'hold' | 'raise' | 'none'
  decisionRateChange: number
  decisionResultingRate: number
}

export type CareerPolicySummary = {
  cuts: number
  holds: number
  raises: number
  latestLabel: string
  latestDetail: string
  cadence: string
}

function decisionTone(decision: PolicyDecision | undefined): CareerTimelinePoint['decisionTone'] {
  if (!decision) {
    return 'none'
  }
  if (decision.rateChange < 0) {
    return 'cut'
  }
  if (decision.rateChange > 0) {
    return 'raise'
  }
  return 'hold'
}

function decisionLabel(decision: PolicyDecision | undefined): string {
  return decision ? policyDecisionLabel(decision) : ''
}

function pointFromState(
  state: MacroState,
  termNumber: number,
  decision: PolicyDecision | undefined,
): CareerTimelinePoint {
  const careerQuarter = (termNumber - 1) * 16 + state.quarterIndex
  return {
    ...state,
    key: `t${termNumber}-q${state.quarterIndex}`,
    label: state.quarterIndex === 0 ? `T${termNumber} start` : `T${termNumber} Q${state.quarterIndex}`,
    termNumber,
    termQuarter: state.quarterIndex,
    careerQuarter,
    isTermStart: state.quarterIndex === 0,
    decisionLabel: decisionLabel(decision),
    decisionTone: decisionTone(decision),
    decisionRateChange: decision?.rateChange ?? 0,
    decisionResultingRate: decision?.resultingFedFundsRate ?? state.fedFundsRate,
  }
}

export function buildCareerTimeline(session: GameSession): CareerTimelinePoint[] {
  const completed = session.completedTerms.flatMap((term) =>
    term.history.map((state) => pointFromState(
      state,
      term.termNumber,
      term.decisions.find((decision) => decision.quarterIndex === state.quarterIndex),
    )),
  )
  if (session.status === 'in_progress' || session.status === 'not_started') {
    return [
      ...completed,
      ...session.history.map((state) => pointFromState(
        state,
        session.termNumber,
        session.decisions.find((decision) => decision.quarterIndex === state.quarterIndex),
      )),
    ]
  }
  return completed.length > 0
    ? completed
    : session.history.map((state) => pointFromState(
      state,
      session.termNumber,
      session.decisions.find((decision) => decision.quarterIndex === state.quarterIndex),
    ))
}

export function buildCareerPolicySummary(timeline: CareerTimelinePoint[]): CareerPolicySummary {
  const played = timeline.filter((point) => point.decisionTone !== 'none')
  const cuts = played.filter((point) => point.decisionTone === 'cut').length
  const holds = played.filter((point) => point.decisionTone === 'hold').length
  const raises = played.filter((point) => point.decisionTone === 'raise').length
  const latest = played.at(-1)
  const total = played.length
  const activeShare = total === 0 ? 0 : Math.round(((cuts + raises) / total) * 100)
  const cadence = total === 0
    ? 'No policy meetings logged yet.'
    : `${activeShare}% active moves across ${total} career meetings.`

  return {
    cuts,
    holds,
    raises,
    latestLabel: latest ? `${latest.label}: ${latest.decisionLabel}` : 'Awaiting first decision',
    latestDetail: latest
      ? `Rate landed at ${latest.decisionResultingRate.toFixed(2)}%; ${latest.decisionTone} at the latest logged meeting.`
      : 'The first one-click move will appear on the live career timeline.',
    cadence,
  }
}
