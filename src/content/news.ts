import type { EngineTrace, MacroState, Shock } from '../types'

export type NewsItem = {
  severity: 'info' | 'warning' | 'critical'
  kicker: string
  headline: string
  explanation: string
  policyQuestion: string
  watchItem: string
}

const shockCopy: Record<string, { headline: string; explanation: string; severity: NewsItem['severity'] }> = {
  energy: {
    headline: 'Energy costs put pressure on household budgets',
    explanation: 'A temporary energy shock lifts inflation and can squeeze real spending until it fades.',
    severity: 'warning',
  },
  demandSoft: {
    headline: 'Household demand cools after a cautious spending quarter',
    explanation: 'Softer demand lowers output pressure, which can ease inflation but raise labor-market risk.',
    severity: 'warning',
  },
  financial: {
    headline: 'Credit conditions tighten across lending markets',
    explanation: 'Financial stress slows activity and can push unemployment higher even when inflation is easing.',
    severity: 'critical',
  },
  supply: {
    headline: 'Supply bottlenecks lift business costs',
    explanation: 'A supply disruption raises prices while making real activity harder to read.',
    severity: 'warning',
  },
  labor: {
    headline: 'Wage pressure builds in a tight labor market',
    explanation: 'A hot labor shock can support incomes while keeping inflation pressure alive.',
    severity: 'warning',
  },
  confidence: {
    headline: 'Confidence slips as households turn cautious',
    explanation: 'A confidence shock can weaken spending before it fully appears in labor data.',
    severity: 'warning',
  },
}

export function openingNews(): NewsItem {
  return {
    severity: 'info',
    kicker: 'Opening briefing',
    headline: 'Your term begins with inflation and unemployment close to target',
    explanation: 'The economy is near balance, but policy choices and shocks will shape the next four years.',
    policyQuestion: 'Will you hold steady, or move early to build credibility before shocks arrive?',
    watchItem: 'Neutral rate, expectations, and the first policy lag',
  }
}

export function createNews(current: MacroState, trace: EngineTrace | undefined, triggered: Shock[] = []): NewsItem {
  const shock = triggered[0]
  if (shock) {
    const copy = shockCopy[shock.headlineKey] ?? {
      severity: 'warning' as const,
      headline: 'A new economic shock changes the outlook',
      explanation: 'Unexpected conditions are feeding through the economy and may require a policy response.',
    }
    return {
      ...copy,
      kicker: 'Economic Gazette | Shock desk',
      policyQuestion:
        shock.type === 'energy' || shock.type === 'supply'
          ? 'Do you look through the temporary price shock, or tighten to protect credibility?'
          : 'Do you cushion the slowdown, or hold policy steady until the signal is clearer?',
      watchItem: shock.type === 'financial' ? 'Credit stress and unemployment' : 'Expected inflation and output gap',
    }
  }

  if (current.inflation >= 4) {
    return {
      severity: 'critical',
      kicker: 'Inflation alert',
      headline: 'Inflation is moving well above the price-stability goal',
      explanation: trace?.explanation ?? 'Demand and expectations are putting upward pressure on prices.',
      policyQuestion: 'How much labor-market risk are you willing to accept to regain price stability?',
      watchItem: 'Inflation expectations and credibility',
    }
  }
  if (current.unemployment >= 7) {
    return {
      severity: 'critical',
      kicker: 'Labor-market alert',
      headline: 'Labor-market weakness is becoming a reappointment risk',
      explanation: trace?.explanation ?? 'Output has softened enough to push unemployment away from target.',
      policyQuestion: 'Can you ease conditions without reigniting inflation later?',
      watchItem: 'Unemployment, output gap, and lagged policy',
    }
  }
  if (Math.abs(current.inflation - 2) <= 0.6 && Math.abs(current.unemployment - 5) <= 0.8) {
    return {
      severity: 'info',
      kicker: 'Balanced mandate',
      headline: 'The economy remains close to the dual-mandate targets',
      explanation: trace?.explanation ?? 'Conditions are stable, though policy still works with a lag.',
      policyQuestion: 'Do you preserve the current stance or prepare for the next shock?',
      watchItem: 'Volatility and expectations',
    }
  }
  if (current.inflation > 2.8) {
    return {
      severity: 'warning',
      kicker: 'Price watch',
      headline: 'Price growth is running hot enough to watch closely',
      explanation: trace?.explanation ?? 'Inflation is above target and could become harder to contain.',
      policyQuestion: 'Is a small hike enough, or is patience more valuable while lags unfold?',
      watchItem: 'Inflation gap and credibility',
    }
  }
  if (current.outputGap < -1.5) {
    return {
      severity: 'warning',
      kicker: 'Growth watch',
      headline: 'Growth is cooling and recession risk is rising',
      explanation: trace?.explanation ?? 'Weak demand is pulling output below potential.',
      policyQuestion: 'Do you support demand now, or wait for inflation to settle further?',
      watchItem: 'Output gap and unemployment',
    }
  }
  return {
    severity: 'info',
    kicker: 'Mixed signal',
    headline: 'Mixed signals leave the policy path open',
    explanation: trace?.explanation ?? 'Inflation, unemployment, and growth are not sending a single clear signal.',
    policyQuestion: 'Which mandate risk deserves more attention this quarter?',
    watchItem: 'Policy gap and latest deltas',
  }
}
