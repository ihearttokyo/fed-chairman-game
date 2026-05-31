export type GameMode = 'classic_chair_the_fed'

export type PolicyAction =
  | 'cut_150'
  | 'cut_100'
  | 'cut_75'
  | 'cut_50'
  | 'cut_25'
  | 'hold'
  | 'raise_25'
  | 'raise_50'
  | 'raise_75'
  | 'raise_100'
  | 'raise_150'
  | 'custom'

export type PolicyDecision = {
  id: string
  quarterIndex: number
  careerQuarterIndex?: number
  action: PolicyAction
  rateChange: number
  resultingFedFundsRate: number
  timestamp: string
}

export type MacroState = {
  quarterIndex: number
  quartersRemaining: number
  inflation: number
  unemployment: number
  fedFundsRate: number
  outputGap: number
  gdpGrowth: number
  expectedInflation: number
  credibility: number
  longRate?: number
  marketIndex?: number
  confidence?: number
}

export type ShockType = 'demand' | 'supply' | 'financial' | 'labor' | 'energy' | 'confidence'

export type Shock = {
  id: string
  quarter: number | 'random'
  type: ShockType
  magnitude: number
  persistence: number
  headlineKey: string
}

export type ActiveShock = Shock & {
  startedQuarter: number
  remaining: number
}

export type ModelCoefficients = {
  realNeutralRate: number
  trendGrowth: number
  rateSensitivity: number
  inflationRateSensitivity: number
  phillipsSlope: number
  okunCoefficient: number
  shockDecay: number
  noiseScale: number
}

export type PolicyToolId = 'fed_funds_rate'

export type ScenarioConfig = {
  id: string
  label: string
  mode: GameMode
  termQuarters: number
  startingState: MacroState
  targets: { inflation: number; unemployment: number }
  coefficients: ModelCoefficients
  shockDeck: Shock[]
  allowedTools: PolicyToolId[]
  difficulty: 'intro' | 'standard' | 'hard' | 'legendary'
  summary: string
}

export type EngineTrace = {
  neutralRate: number
  policyGap: number
  laggedPolicyGap: number
  shockContrib: Record<ShockType, number>
  credibilityBaseDrift?: number
  credibilityRateMoveCost?: number
  credibilityReappointmentGrace?: number
  credibilityDelta?: number
  inflationDelta: number
  unemploymentDelta: number
  gdpDelta: number
  explanation: string
}

export type AdvanceResult = {
  nextState: MacroState
  trace: EngineTrace
  activeShocks: ActiveShock[]
  triggeredShocks: Shock[]
}

export type ScoreState = {
  score: number
  grade: 'A' | 'B' | 'C' | 'D' | 'F'
  reappointed: boolean
  meanAbsInflationGap: number
  meanAbsUnemploymentGap: number
  volatilityIndex: number
  recessionQuarterShare: number
  credibilityBonus: number
  biggestMiss: string
  takeaway: string
}

export type UiState = {
  selectedDecision: PolicyAction | null
  chartView: 'chart' | 'table'
  reducedMotion: boolean
  soundEnabled: boolean
  reducedNoise: boolean
  soundVolume: number
}

export type CareerStatus = 'not_started' | 'in_progress' | 'term_debrief' | 'retired' | 'not_reappointed'

export type CompletedTermSummary = {
  termNumber: number
  startingState: MacroState
  endingState: MacroState
  history: MacroState[]
  decisions: PolicyDecision[]
  traces: EngineTrace[]
  score: ScoreState
  reappointed: boolean
}

export type GameSession = {
  sessionId: string
  mode: GameMode
  scenarioId: string
  status: CareerStatus
  seed: string
  termNumber: number
  currentTermQuarter: number
  totalCareerQuarters: number
  completedTerms: CompletedTermSummary[]
  careerHistory: MacroState[]
  careerScore: ScoreState
  current: MacroState
  history: MacroState[]
  decisions: PolicyDecision[]
  traces: EngineTrace[]
  activeShocks: ActiveShock[]
  latestTriggeredShocks: Shock[]
  score: ScoreState
  ui: UiState
}
