import type { MacroState, ScoreState, ScenarioConfig } from '../types'
import { clamp, mean, meanAbs, roundTo } from './math'

function gradeFor(score: number): ScoreState['grade'] {
  if (score >= 90) {
    return 'A'
  }
  if (score >= 80) {
    return 'B'
  }
  if (score >= 70) {
    return 'C'
  }
  if (score >= 60) {
    return 'D'
  }
  return 'F'
}

export function evaluateScore(history: MacroState[], scenario: ScenarioConfig): ScoreState {
  const played = history.slice(1)
  const scored = played.length > 0 ? played : history
  const inflationGaps = scored.map((state) => state.inflation - scenario.targets.inflation)
  const unemploymentGaps = scored.map((state) => state.unemployment - scenario.targets.unemployment)
  const volatilityIndex =
    mean(
      scored.slice(1).map((state, index) => {
        const previous = scored[index] ?? state
        return Math.abs(state.inflation - previous.inflation) + Math.abs(state.unemployment - previous.unemployment)
      }),
    ) || 0
  const recessionQuarterShare =
    scored.filter((state) => state.outputGap < -2 || state.unemployment > 7).length / Math.max(1, scored.length)
  const averageCredibility = mean(scored.map((state) => state.credibility))
  const credibilityBonus = clamp((averageCredibility - 70) / 6, 0, 5)
  const meanAbsInflationGap = meanAbs(inflationGaps)
  const meanAbsUnemploymentGap = meanAbs(unemploymentGaps)
  const rawScore =
    100 -
    10 * meanAbsInflationGap -
    8 * meanAbsUnemploymentGap -
    5 * volatilityIndex -
    12 * recessionQuarterShare +
    credibilityBonus
  const score = roundTo(clamp(rawScore, 0, 100), 1)
  const final = history.at(-1) ?? scenario.startingState
  const reappointed = score >= 70 && final.inflation <= 4 && final.unemployment <= 7
  const misses = [
    { label: 'inflation drift', value: meanAbsInflationGap },
    { label: 'unemployment gap', value: meanAbsUnemploymentGap },
    { label: 'quarter-to-quarter volatility', value: volatilityIndex },
    { label: 'recession risk', value: recessionQuarterShare * 2 },
  ].sort((a, b) => b.value - a.value)
  const biggestMiss = misses[0]?.label ?? 'none'
  const takeaway =
    biggestMiss === 'inflation drift'
      ? 'Inflation responds with a lag, so waiting too long can require sharper later moves.'
      : biggestMiss === 'unemployment gap'
        ? 'Tight policy can stabilize prices but may overshoot into a weaker labor market.'
        : biggestMiss === 'recession risk'
          ? 'A successful term balances price stability against avoidable downturns.'
          : 'Moderate, steady decisions usually work better than chasing each quarter of data.'

  return {
    score,
    grade: gradeFor(score),
    reappointed,
    meanAbsInflationGap: roundTo(meanAbsInflationGap),
    meanAbsUnemploymentGap: roundTo(meanAbsUnemploymentGap),
    volatilityIndex: roundTo(volatilityIndex),
    recessionQuarterShare: roundTo(recessionQuarterShare),
    credibilityBonus: roundTo(credibilityBonus),
    biggestMiss,
    takeaway,
  }
}
