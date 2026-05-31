import { formatRateChangeBps } from '../../engine/policy'
import type { EngineTrace, GameSession, MacroState, PolicyDecision } from '../../types'

export type CareerLedgerEntry = {
  termNumber: number
  label: string
  score: string
  outcome: string
  finalInflation: string
  finalUnemployment: string
  finalRate: string
  decisionMix: string
}

export type TermHandoffMetric = {
  label: string
  start: string
  end: string
  delta: string
  tone: 'better' | 'worse' | 'steady'
}

export type Debrief = {
  boardVerdict: string
  gateStatus: string
  gateChoice: string
  termStanding: string
  policyStyle: string
  bestStretch: string
  turningPoint: string
  mandateTrend: string
  decisionMix: string
  finalImpulse: string
  coachingFocus: string
  recommendation: string
  streakQuarters: number
  largestPolicyMove: string
  careerLedger: CareerLedgerEntry[]
  careerStanding: string
  carryoverBrief: string
  carryoverMetrics: string[]
  nextTermBrief: string
  retirementStatus: string
  careerProgressLabel: string
  careerProgressValue: number
  careerProgressMax: number
  termHandoff: string
  termHandoffMetrics: TermHandoffMetric[]
}

type DebriefScope = {
  termNumber: number
  history: MacroState[]
  decisions: PolicyDecision[]
  traces: EngineTrace[]
  score: GameSession['score']
}

function nearTarget(state: MacroState): boolean {
  return Math.abs(state.inflation - 2) <= 0.6 && Math.abs(state.unemployment - 5) <= 0.8
}

function formatSigned(value: number): string {
  const sign = value > 0 ? '+' : ''
  return `${sign}${value.toFixed(2)}`
}

function formatSignedPercent(value: number): string {
  const sign = value > 0 ? '+' : ''
  return `${sign}${value.toFixed(2)} pp`
}

function formatAction(action: PolicyDecision['action']): string {
  if (action === 'hold') {
    return 'hold'
  }
  return action.replace('_', ' ')
}

function formatDecision(decision: PolicyDecision): string {
  return decision.action === 'custom' ? `custom ${formatRateChangeBps(decision.rateChange)}` : formatAction(decision.action)
}

function longestNearTargetStreak(states: MacroState[]): { length: number; start: number; end: number } {
  let currentLength = 0
  let currentStart = 0
  let best = { length: 0, start: 0, end: 0 }

  states.forEach((state, index) => {
    if (nearTarget(state)) {
      if (currentLength === 0) {
        currentStart = index
      }
      currentLength += 1
      if (currentLength > best.length) {
        best = {
          length: currentLength,
          start: states[currentStart]?.quarterIndex ?? state.quarterIndex,
          end: state.quarterIndex,
        }
      }
      return
    }
    currentLength = 0
  })

  return best
}

function buildDecisionMix(decisions: PolicyDecision[]): string {
  const raises = decisions.filter((decision) => decision.rateChange > 0).length
  const cuts = decisions.filter((decision) => decision.rateChange < 0).length
  const holds = decisions.filter((decision) => decision.rateChange === 0).length
  const plural = (count: number, label: string) => `${count} ${label}${count === 1 ? '' : 's'}`
  return `${plural(raises, 'hike')}, ${plural(cuts, 'cut')}, ${plural(holds, 'hold')} across ${decisions.length} meetings.`
}

function compactDecisionMix(decisions: PolicyDecision[]): string {
  const raises = decisions.filter((decision) => decision.rateChange > 0).length
  const cuts = decisions.filter((decision) => decision.rateChange < 0).length
  const holds = decisions.filter((decision) => decision.rateChange === 0).length
  return `${raises}H / ${cuts}C / ${holds} hold`
}

function finalImpulse(trace: EngineTrace | undefined): string {
  if (!trace) {
    return 'No final model trace was recorded.'
  }
  const shockPressure = Object.values(trace.shockContrib).reduce((total, value) => total + value, 0)
  const policy =
    trace.laggedPolicyGap > 0.35 ? 'restrictive lag was cooling demand' : trace.laggedPolicyGap < -0.35 ? 'easy lag was supporting demand' : 'policy lag was near neutral'
  const shocks =
    Math.abs(shockPressure) < 0.08
      ? 'net shocks were muted'
      : shockPressure > 0
        ? 'net shocks leaned inflationary'
        : 'net shocks leaned disinflationary'
  return `Final quarter: ${policy}; ${shocks} (${formatSigned(shockPressure)} pp).`
}

function buildCareerLedger(session: GameSession): CareerLedgerEntry[] {
  return session.completedTerms.map((term) => ({
    termNumber: term.termNumber,
    label: `Term ${term.termNumber}`,
    score: `${term.score.score.toFixed(1)} (${term.score.grade})`,
    outcome: term.reappointed ? 'Reappointed' : 'Not reappointed',
    finalInflation: `${term.endingState.inflation.toFixed(2)}%`,
    finalUnemployment: `${term.endingState.unemployment.toFixed(2)}%`,
    finalRate: `${term.endingState.fedFundsRate.toFixed(2)}%`,
    decisionMix: compactDecisionMix(term.decisions),
  }))
}

function buildCareerStanding(session: GameSession): string {
  const completed = session.completedTerms.length
  if (completed === 0) {
    return 'No completed four-year terms yet.'
  }
  const reappointments = session.completedTerms.filter((term) => term.reappointed).length
  return `${completed} completed four-year term${completed === 1 ? '' : 's'}; ${reappointments} reappointment${reappointments === 1 ? '' : 's'} earned. Career score ${session.careerScore.score.toFixed(1)} (${session.careerScore.grade}).`
}

function buildCarryoverBrief(session: GameSession): string {
  const final = session.history.at(-1) ?? session.current
  if (session.status === 'term_debrief') {
    return `Carryover economy for Term ${session.termNumber + 1}: ${final.inflation.toFixed(2)}% inflation, ${final.unemployment.toFixed(2)}% unemployment, ${final.fedFundsRate.toFixed(2)}% policy rate.`
  }
  if (session.status === 'retired') {
    return `Retired after ${session.totalCareerQuarters} quarters with final inflation ${final.inflation.toFixed(2)}% and unemployment ${final.unemployment.toFixed(2)}%.`
  }
  if (session.status === 'not_reappointed') {
    return `The final economy ended at ${final.inflation.toFixed(2)}% inflation and ${final.unemployment.toFixed(2)}% unemployment, short of the reappointment bar.`
  }
  return `Current economy: ${final.inflation.toFixed(2)}% inflation, ${final.unemployment.toFixed(2)}% unemployment, ${final.fedFundsRate.toFixed(2)}% policy rate.`
}

function buildCarryoverMetrics(session: GameSession): string[] {
  const final = session.history.at(-1) ?? session.current
  return [
    `${final.inflation.toFixed(2)}% inflation`,
    `${final.unemployment.toFixed(2)}% unemployment`,
    `${final.fedFundsRate.toFixed(2)}% policy rate`,
    `${final.gdpGrowth.toFixed(2)}% GDP growth`,
  ]
}

function buildBoardVerdict(session: GameSession): string {
  if (session.status === 'retired') {
    return `You retired after ${session.completedTerms.length} completed four-year terms with a ${session.careerScore.grade} career grade.`
  }
  if (session.status === 'not_reappointed') {
    return `The board ended the appointment after Term ${session.termNumber}; the mandate score missed the reappointment threshold.`
  }
  if (session.status === 'term_debrief') {
    return `The board reappointed you for Term ${session.termNumber + 1}; your next four years inherit this economy.`
  }
  return 'The board will evaluate reappointment after the 16th quarter of the term.'
}

function buildGateStatus(session: GameSession): string {
  if (session.status === 'retired') {
    return 'Career score is final.'
  }
  if (session.status === 'not_reappointed') {
    return 'Career ended by board decision.'
  }
  if (session.status === 'term_debrief') {
    return session.completedTerms.length >= 2
      ? 'Choose another four-year term or retire with a final career score.'
      : 'Retirement unlocks after completing one reappointment term; continue into Term 2 to build a career score.'
  }
  return 'Finish the current four-year term to reach the reappointment gate.'
}

function buildGateChoice(session: GameSession): string {
  if (session.status === 'retired') {
    return 'Career ledger finalized.'
  }
  if (session.status === 'not_reappointed') {
    return 'Replay the same seed or start fresh from the opening economy.'
  }
  if (session.status === 'term_debrief') {
    return session.completedTerms.length >= 2
      ? 'Your next click either starts another inherited four-year term or locks the career score.'
      : 'Your next click starts Term 2 immediately; retirement remains locked until that term is complete.'
  }
  return 'The next gate appears only after Q16.'
}

function buildRetirementStatus(session: GameSession): string {
  if (session.status === 'retired') {
    return `Finalized after ${session.totalCareerQuarters} quarters.`
  }
  if (session.status !== 'term_debrief' || !session.score.reappointed) {
    return 'Retirement is available only at a successful term-boundary debrief.'
  }
  const completedTerms = Math.max(session.completedTerms.length, session.status === 'term_debrief' ? session.termNumber : 0)
  const remainingTerms = Math.max(0, 2 - completedTerms)
  if (remainingTerms === 0) {
    return 'Retirement is available now because you completed at least one reappointment term.'
  }
  return `Retirement locked: complete ${remainingTerms} more reappointed term${remainingTerms === 1 ? '' : 's'} first.`
}

function buildCareerProgress(session: GameSession): Pick<Debrief, 'careerProgressLabel' | 'careerProgressValue' | 'careerProgressMax'> {
  const completed = Math.max(session.completedTerms.length, session.status === 'term_debrief' ? session.termNumber : 0)
  if (session.status === 'retired' || session.status === 'not_reappointed') {
    return {
      careerProgressLabel: `${completed} completed term${completed === 1 ? '' : 's'}`,
      careerProgressValue: completed,
      careerProgressMax: Math.max(1, completed),
    }
  }
  const required = 2
  return {
    careerProgressLabel:
      completed >= required
        ? 'Retirement eligible at this gate'
        : `${Math.max(0, required - completed)} term${required - completed === 1 ? '' : 's'} until retirement unlock`,
    careerProgressValue: Math.min(required, completed),
    careerProgressMax: required,
  }
}

function getDebriefScope(session: GameSession): DebriefScope {
  const completedTerm = session.status === 'in_progress' ? undefined : session.completedTerms.at(-1)
  if (completedTerm) {
    return {
      termNumber: completedTerm.termNumber,
      history: completedTerm.history,
      decisions: completedTerm.decisions,
      traces: completedTerm.traces,
      score: completedTerm.score,
    }
  }
  return {
    termNumber: session.termNumber,
    history: session.history,
    decisions: session.decisions,
    traces: session.traces,
    score: session.score,
  }
}

function buildTermStanding(scope: DebriefScope): string {
  return `Term ${scope.termNumber} scored ${scope.score.score.toFixed(1)} (${scope.score.grade}) across ${scope.decisions.length} policy meetings; reappointment ${scope.score.reappointed ? 'earned' : 'missed'}.`
}

function toneForGap(startGap: number, endGap: number, tolerance = 0.05): TermHandoffMetric['tone'] {
  if (endGap < startGap - tolerance) {
    return 'better'
  }
  if (endGap > startGap + tolerance) {
    return 'worse'
  }
  return 'steady'
}

function buildTermHandoff(scope: DebriefScope): Pick<Debrief, 'termHandoff' | 'termHandoffMetrics'> {
  const start = scope.history[0]
  const end = scope.history.at(-1)
  if (!start || !end) {
    return {
      termHandoff: 'No completed term handoff is available yet.',
      termHandoffMetrics: [],
    }
  }
  const inflationGapStart = Math.abs(start.inflation - 2)
  const inflationGapEnd = Math.abs(end.inflation - 2)
  const laborGapStart = Math.abs(start.unemployment - 5)
  const laborGapEnd = Math.abs(end.unemployment - 5)
  const credibilityDelta = end.credibility - start.credibility
  const rateDelta = end.fedFundsRate - start.fedFundsRate
  const handoffBias =
    inflationGapEnd < inflationGapStart - 0.1 && laborGapEnd < laborGapStart - 0.1
      ? 'stronger on both sides of the mandate'
      : inflationGapEnd > inflationGapStart + 0.1 && laborGapEnd > laborGapStart + 0.1
        ? 'more strained on both sides of the mandate'
        : inflationGapEnd < inflationGapStart - 0.1
          ? 'cleaner on inflation but still mixed for labor'
          : laborGapEnd < laborGapStart - 0.1
            ? 'cleaner on labor but still mixed for inflation'
            : 'broadly similar to the economy you inherited'
  return {
    termHandoff: `You inherited ${start.inflation.toFixed(2)}% inflation, ${start.unemployment.toFixed(2)}% unemployment, and a ${start.fedFundsRate.toFixed(2)}% policy rate; the handoff is ${handoffBias}.`,
    termHandoffMetrics: [
      {
        label: 'Inflation gap',
        start: `${inflationGapStart.toFixed(2)} pp`,
        end: `${inflationGapEnd.toFixed(2)} pp`,
        delta: formatSignedPercent(inflationGapEnd - inflationGapStart),
        tone: toneForGap(inflationGapStart, inflationGapEnd),
      },
      {
        label: 'Labor gap',
        start: `${laborGapStart.toFixed(2)} pp`,
        end: `${laborGapEnd.toFixed(2)} pp`,
        delta: formatSignedPercent(laborGapEnd - laborGapStart),
        tone: toneForGap(laborGapStart, laborGapEnd),
      },
      {
        label: 'Policy rate',
        start: `${start.fedFundsRate.toFixed(2)}%`,
        end: `${end.fedFundsRate.toFixed(2)}%`,
        delta: formatSignedPercent(rateDelta),
        tone: Math.abs(rateDelta) < 0.05 ? 'steady' : 'steady',
      },
      {
        label: 'Credibility',
        start: `${start.credibility.toFixed(0)}`,
        end: `${end.credibility.toFixed(0)}`,
        delta: `${credibilityDelta > 0 ? '+' : ''}${credibilityDelta.toFixed(0)}`,
        tone: credibilityDelta > 1 ? 'better' : credibilityDelta < -1 ? 'worse' : 'steady',
      },
    ],
  }
}

function buildNextTermBrief(session: GameSession): string {
  const final = session.history.at(-1) ?? session.current
  if (session.status !== 'term_debrief' || !session.score.reappointed) {
    return 'No next term is scheduled from this debrief.'
  }
  const inflationRisk = final.inflation > 2.6 ? 'inflation still above target' : final.inflation < 1.4 ? 'inflation running soft' : 'inflation near target'
  const laborRisk = final.unemployment > 5.8 ? 'labor slack elevated' : final.unemployment < 4.2 ? 'labor market tight' : 'labor near balance'
  return `Term ${session.termNumber + 1} opens with ${inflationRisk} and ${laborRisk}; inherited rate ${final.fedFundsRate.toFixed(2)}%.`
}

export function buildDebrief(session: GameSession): Debrief {
  const scope = getDebriefScope(session)
  const played = scope.history.slice(1)
  const final = scope.history.at(-1) ?? session.current
  const previous = scope.history.at(-2) ?? final
  const bestCount = played.filter(nearTarget).length
  const bestStreak = longestNearTargetStreak(played)
  const biggestMove = played
    .map((state, index) => {
      const previous = scope.history[index] ?? state
      return {
        quarter: state.quarterIndex,
        move: Math.abs(state.inflation - previous.inflation) + Math.abs(state.unemployment - previous.unemployment),
      }
    })
    .sort((a, b) => b.move - a.move)[0]
  const averageChange =
    scope.decisions.reduce((total, decision) => total + Math.abs(decision.rateChange), 0) / Math.max(1, scope.decisions.length)
  const largestDecision = scope.decisions
    .slice()
    .sort((a, b) => Math.abs(b.rateChange) - Math.abs(a.rateChange))[0]
  const policyStyle =
    averageChange < 0.15
      ? 'Patient operator'
      : averageChange > 0.42
        ? 'Forceful rate mover'
        : scope.score.biggestMiss === 'inflation drift'
          ? 'Inflation responder'
          : scope.score.biggestMiss === 'unemployment gap'
          ? 'Labor-market defender'
          : 'Balanced stabilizer'
  const inflationDirection = final.inflation < previous.inflation - 0.05 ? 'cooled' : final.inflation > previous.inflation + 0.05 ? 'heated' : 'held steady'
  const unemploymentDirection =
    final.unemployment < previous.unemployment - 0.05 ? 'improved' : final.unemployment > previous.unemployment + 0.05 ? 'weakened' : 'held steady'
  const coachingFocus =
    scope.score.biggestMiss === 'inflation drift'
      ? 'Watch expected inflation and policy lag before inflation breaks far from target.'
      : scope.score.biggestMiss === 'unemployment gap'
        ? 'Ease earlier when labor slack opens and inflation is already moving toward target.'
        : scope.score.biggestMiss === 'recession risk'
          ? 'Use smaller steps when financial stress and unemployment are both rising.'
          : 'Keep rate moves measured when both mandate gaps are closing.'
  const careerProgress = buildCareerProgress(session)
  const termHandoff = buildTermHandoff(scope)
  return {
    boardVerdict: buildBoardVerdict(session),
    gateStatus: buildGateStatus(session),
    gateChoice: buildGateChoice(session),
    termStanding: buildTermStanding(scope),
    policyStyle,
    bestStretch:
      bestStreak.length > 0
        ? `${bestCount} of ${played.length} quarters were close to target; longest run was Q${bestStreak.start}-Q${bestStreak.end}.`
        : `0 of ${played.length} played quarters stayed close to both mandate targets.`,
    turningPoint: biggestMove
      ? `Q${biggestMove.quarter} moved most: ${formatSigned(biggestMove.move)} total points across inflation and unemployment.`
      : 'No major turning point yet.',
    mandateTrend: `Final quarter inflation ${inflationDirection} to ${final.inflation.toFixed(2)}%; unemployment ${unemploymentDirection} to ${final.unemployment.toFixed(2)}%.`,
    decisionMix: buildDecisionMix(scope.decisions),
    finalImpulse: finalImpulse(scope.traces.at(-1)),
    coachingFocus,
    recommendation:
      scope.score.reappointed
        ? 'Replay the same seed and try to win with fewer rate moves.'
        : 'Replay the same seed and respond earlier to the biggest miss identified in the scorecard.',
    streakQuarters: bestStreak.length,
    largestPolicyMove: largestDecision
      ? `Largest move: Q${largestDecision.quarterIndex} ${formatDecision(largestDecision)} (${formatSigned(largestDecision.rateChange)} pp).`
      : 'No policy moves recorded.',
    careerLedger: buildCareerLedger(session),
    careerStanding: buildCareerStanding(session),
    carryoverBrief: buildCarryoverBrief(session),
    carryoverMetrics: buildCarryoverMetrics(session),
    nextTermBrief: buildNextTermBrief(session),
    retirementStatus: buildRetirementStatus(session),
    ...termHandoff,
    ...careerProgress,
  }
}
