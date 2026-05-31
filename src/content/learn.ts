import type { EngineTrace, MacroState, ScenarioConfig, Shock } from '../types'

export type LearnPanel = {
  title: string
  body: string
}

export function getLearnPanels(
  current: MacroState,
  scenario: ScenarioConfig,
  trace?: EngineTrace,
  activeShocks: Shock[] = [],
): LearnPanel[] {
  const neutralRate = scenario.coefficients.realNeutralRate + current.expectedInflation
  const stance =
    current.fedFundsRate > neutralRate + 0.5
      ? 'restrictive'
      : current.fedFundsRate < neutralRate - 0.5
        ? 'expansionary'
        : 'near neutral'

  const panels: LearnPanel[] = [
    {
      title: 'Your Job',
      body: `Guide inflation toward ${scenario.targets.inflation.toFixed(1)}% while keeping unemployment near ${scenario.targets.unemployment.toFixed(1)}% over a 16-quarter term.`,
    },
    {
      title: 'Federal Funds Rate',
      body: `The current rate is ${current.fedFundsRate.toFixed(2)}%. The model estimates neutral near ${neutralRate.toFixed(2)}%, so policy is ${stance}.`,
    },
    {
      title: 'Dual Mandate',
      body: 'A good term balances price stability and maximum employment. Pushing one goal too hard can damage the other.',
    },
    {
      title: 'Expansionary Policy',
      body: 'Rate cuts tend to support spending, output, and hiring. If demand runs too hot, inflation can rise later.',
    },
    {
      title: 'Contractionary Policy',
      body: 'Rate hikes tend to cool spending and inflation. The tradeoff is a higher chance of weaker growth and unemployment.',
    },
    {
      title: 'Policy Lags',
      body: 'Your decisions work gradually. The strongest effect usually appears several quarters after the rate change.',
    },
  ]
  if (current.inflation > scenario.targets.inflation + 1) {
    panels.push({
      title: 'Why Credibility Matters',
      body: 'When inflation stays high, expectations can drift up. Strong credibility makes it easier to return inflation to target without a deeper slowdown.',
    })
  }
  if (current.unemployment > scenario.targets.unemployment + 1.4) {
    panels.push({
      title: 'Easing With Care',
      body: 'Cuts can support hiring, but their full effect arrives later. If inflation is still elevated, easing too quickly can create a stop-go cycle.',
    })
  }
  if (trace && Math.abs(trace.laggedPolicyGap) > 0.75) {
    panels.push({
      title: 'Reading Old Decisions',
      body: 'A large lagged policy gap means today’s data is still being shaped by earlier rate choices. Reacting only to the latest quarter can cause overcorrection.',
    })
  }
  if (activeShocks.length > 0) {
    panels.push({
      title: 'Temporary Shock Or Trend?',
      body: 'A shock can move inflation and unemployment at the same time. The policy challenge is judging whether it will fade or change expectations.',
    })
  }
  return panels
}
