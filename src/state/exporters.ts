import type { GameSession } from '../types'
import { buildDebrief } from '../features/results/debrief'
import { buildCareerTimeline } from '../features/history/careerTimeline'
import { policyDecisionLabel } from '../engine/policy'

function escapeCsv(value: string | number): string {
  const raw = String(value)
  return raw.includes(',') || raw.includes('\n') || raw.includes('"') ? `"${raw.replaceAll('"', '""')}"` : raw
}

type ExportDecisionRow = {
  termNumber: number
  termQuarter: number
  careerQuarter: number
  action: string
  resultingFedFundsRate: number
  inflation: number | undefined
  unemployment: number | undefined
}

function buildDecisionRows(session: GameSession): ExportDecisionRow[] {
  const activeTermRows =
    session.status === 'in_progress' || session.status === 'not_started'
      ? [{ termNumber: session.termNumber, decisions: session.decisions, history: session.history }]
      : []
  return [
    ...session.completedTerms.map((term) => ({
      termNumber: term.termNumber,
      decisions: term.decisions,
      history: term.history,
    })),
    ...activeTermRows,
  ].flatMap((term) =>
    term.decisions.map((decision, index) => {
      const state = term.history[index + 1]
      return {
        termNumber: term.termNumber,
        termQuarter: decision.quarterIndex,
        careerQuarter: decision.careerQuarterIndex ?? (term.termNumber - 1) * 16 + decision.quarterIndex,
        action: policyDecisionLabel(decision),
        resultingFedFundsRate: decision.resultingFedFundsRate,
        inflation: state?.inflation,
        unemployment: state?.unemployment,
      }
    }),
  )
}

export function sessionToCsv(session: GameSession): string {
  const timeline = buildCareerTimeline(session)
  const rows = [
    [
      'term',
      'quarter',
      'careerQuarter',
      'label',
      'boundary',
      'policyAction',
      'policyRateChange',
      'inflation',
      'unemployment',
      'fedFundsRate',
      'outputGap',
      'gdpGrowth',
      'expectedInflation',
      'credibility',
    ],
    ...timeline.map((state) => [
      state.termNumber,
      state.termQuarter,
      state.termQuarter === 0 ? '' : state.careerQuarter,
      state.label,
      state.isTermStart ? 'term start' : '',
      state.decisionLabel,
      state.isTermStart ? '' : state.decisionRateChange,
      state.inflation,
      state.unemployment,
      state.fedFundsRate,
      state.outputGap,
      state.gdpGrowth,
      state.expectedInflation,
      state.credibility,
    ]),
  ]
  return rows.map((row) => row.map(escapeCsv).join(',')).join('\n')
}

export function sessionToJson(session: GameSession): string {
  return JSON.stringify(session, null, 2)
}

export function sessionToMarkdown(session: GameSession): string {
  const final = session.history.at(-1)
  const debrief = buildDebrief(session)
  const timeline = buildCareerTimeline(session)
  const termBoundaries = timeline
    .filter((point) => point.isTermStart)
    .map((point) => `- ${point.label}: career Q${point.careerQuarter}, ${point.inflation.toFixed(2)}% inflation, ${point.unemployment.toFixed(2)}% unemployment, ${point.fedFundsRate.toFixed(2)}% policy rate.`)
  const decisions = buildDecisionRows(session).map((decision) => {
    return `| T${decision.termNumber} Q${decision.termQuarter} | Q${decision.careerQuarter} | ${decision.action} | ${decision.resultingFedFundsRate.toFixed(2)}% | ${decision.inflation?.toFixed(2) ?? '-'}% | ${decision.unemployment?.toFixed(2) ?? '-'}% |`
  })
  const finalTrace = session.traces.at(-1)
  return [
    '# Classic Monetary Policy Debrief',
    '',
    `- Scenario: ${session.scenarioId}`,
    `- Seed: ${session.seed}`,
    `- Terms completed: ${session.completedTerms.length}`,
    `- Quarters played: ${session.totalCareerQuarters}`,
    `- Career score: ${session.careerScore.score} (${session.careerScore.grade})`,
    `- Current term score: ${session.score.score} (${session.score.grade})`,
    `- Result: ${session.status === 'retired' ? 'Retired' : session.score.reappointed ? 'Reappointed' : 'Not reappointed'}`,
    final ? `- Final inflation: ${final.inflation.toFixed(2)}%` : '',
    final ? `- Final unemployment: ${final.unemployment.toFixed(2)}%` : '',
    final ? `- Final fed funds rate: ${final.fedFundsRate.toFixed(2)}%` : '',
    `- Biggest miss: ${session.score.biggestMiss}`,
    `- Takeaway: ${session.score.takeaway}`,
    `- Policy style: ${debrief.policyStyle}`,
    `- Best stretch: ${debrief.bestStretch}`,
    `- Turning point: ${debrief.turningPoint}`,
    `- Next run: ${debrief.recommendation}`,
    finalTrace ? `- Final model readout: ${finalTrace.explanation}` : '',
    '',
    '## Term Boundaries',
    '',
    ...termBoundaries,
    '',
    '## Score Components',
    '',
    `- Mean inflation miss: ${session.score.meanAbsInflationGap.toFixed(2)}`,
    `- Mean unemployment miss: ${session.score.meanAbsUnemploymentGap.toFixed(2)}`,
    `- Volatility index: ${session.score.volatilityIndex.toFixed(2)}`,
    `- Recession quarter share: ${(session.score.recessionQuarterShare * 100).toFixed(0)}%`,
    `- Credibility bonus: ${session.score.credibilityBonus.toFixed(2)}`,
    '',
    '## Decision Log',
    '',
    '| Term quarter | Career quarter | Decision | Resulting rate | Inflation | Unemployment |',
    '| --- | ---: | --- | ---: | ---: | ---: |',
    ...decisions,
  ]
    .filter(Boolean)
    .join('\n')
}

export function downloadText(filename: string, text: string, mimeType: string): void {
  const blob = new Blob([text], { type: mimeType })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.append(link)
  link.click()
  link.remove()
  window.setTimeout(() => URL.revokeObjectURL(url), 0)
}
