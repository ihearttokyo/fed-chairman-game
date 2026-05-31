import { create } from 'zustand'
import { createDecision } from '../engine/policy'
import { advanceQuarter } from '../engine/quarterEngine'
import { evaluateScore } from '../engine/scoreEngine'
import { getScenario, getTermScenario } from '../scenarios/classic'
import { gameSessionSchema } from './sessionSchema'
import { createSaveFile, parseSaveFile, summarizeSaveSession, type SaveFileSummary } from './saveFile'
import type { CompletedTermSummary, GameSession, MacroState, PolicyAction, UiState } from '../types'

const SAVE_KEY = 'fed-chairman-classic-v1'
const SAVE_VERSION = 3

type SerializedSave = {
  version: number
  session: unknown
}

type GameStore = {
  session: GameSession
  hasSavedGame: boolean
  startGame: (seed?: string) => void
  selectDecision: (action: PolicyAction) => void
  advance: () => void
  commitDecision: (action: PolicyAction) => void
  commitCustomDecision: (rateChange: number) => void
  continueNextTerm: () => void
  retireCareer: () => void
  resetGame: () => void
  loadSavedGame: () => boolean
  exportSaveFile: () => Promise<string>
  importSaveFile: (text: string) => Promise<{ ok: true; summary: SaveFileSummary } | { ok: false; error: string }>
  setChartView: (view: GameSession['ui']['chartView']) => void
  setReducedMotion: (value: boolean) => void
  setSoundEnabled: (value: boolean) => void
  setReducedNoise: (value: boolean) => void
  setSoundVolume: (value: number) => void
}

function prefersReducedMotion(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true
  )
}

function defaultUiState(): UiState {
  const reducedMotion = prefersReducedMotion()
  return {
    selectedDecision: null,
    chartView: 'chart',
    reducedMotion,
    soundEnabled: false,
    reducedNoise: reducedMotion,
    soundVolume: 0.25,
  }
}

function makeInitialSession(seed = 'classic-2026'): GameSession {
  const scenario = getScenario()
  const history = [scenario.startingState]
  const score = evaluateScore(history, scenario)
  return {
    sessionId: `session-${seed}`,
    mode: 'classic_chair_the_fed',
    scenarioId: scenario.id,
    status: 'not_started',
    seed,
    termNumber: 1,
    currentTermQuarter: 0,
    totalCareerQuarters: 0,
    completedTerms: [],
    careerHistory: history,
    careerScore: score,
    current: scenario.startingState,
    history,
    decisions: [],
    traces: [],
    activeShocks: [],
    latestTriggeredShocks: [],
    score,
    ui: defaultUiState(),
  }
}

function saveSession(session: GameSession): void {
  try {
    if (typeof localStorage === 'undefined') {
      return
    }
    localStorage.setItem(SAVE_KEY, JSON.stringify({ version: SAVE_VERSION, session }))
  } catch {
    // Storage can be blocked or full; gameplay should continue in memory.
  }
}

function readSession(): GameSession | null {
  let raw: string | null
  try {
    if (typeof localStorage === 'undefined') {
      return null
    }
    raw = localStorage.getItem(SAVE_KEY)
  } catch {
    return null
  }
  if (!raw) {
    return null
  }
  try {
    const parsed = JSON.parse(raw) as SerializedSave
    if (!parsed.session) {
      clearSession()
      return null
    }
    const migrated = migrateSession(parsed.version, parsed.session)
    const result = gameSessionSchema.safeParse(migrated)
    if (!result.success) {
      clearSession()
      return null
    }
    return result.data as GameSession
  } catch {
    clearSession()
    return null
  }
}

function clearSession(): void {
  try {
    if (typeof localStorage !== 'undefined') {
      localStorage.removeItem(SAVE_KEY)
    }
  } catch {
    // Ignore blocked storage.
  }
}

function migrateSession(version: number, session: unknown): unknown {
  if (version === SAVE_VERSION) {
    return session
  }
  if ((version === 1 || version === 2) && typeof session === 'object' && session !== null) {
    const oldSession = session as Omit<Partial<GameSession>, 'status'> & { status?: GameSession['status'] | 'completed' }
    const scenario = getScenario(oldSession.scenarioId)
    const history = oldSession.history ?? [scenario.startingState]
    const score = oldSession.score ?? evaluateScore(history, scenario)
    const status = oldSession.status === 'completed'
      ? score.reappointed
        ? 'term_debrief'
        : 'not_reappointed'
      : (oldSession.status ?? 'not_started')
    const completedTerms: CompletedTermSummary[] =
      oldSession.status === 'completed'
        ? [
            {
              termNumber: 1,
              startingState: history[0] ?? scenario.startingState,
              endingState: history.at(-1) ?? oldSession.current ?? scenario.startingState,
              history,
              decisions: oldSession.decisions ?? [],
              traces: oldSession.traces ?? [],
              score,
              reappointed: score.reappointed,
            },
          ]
        : []
    return {
      ...oldSession,
      status,
      termNumber: oldSession.termNumber ?? 1,
      currentTermQuarter: oldSession.currentTermQuarter ?? oldSession.current?.quarterIndex ?? 0,
      totalCareerQuarters: oldSession.totalCareerQuarters ?? Math.max(0, history.length - 1),
      completedTerms: oldSession.completedTerms ?? completedTerms,
      careerHistory: oldSession.careerHistory ?? history,
      careerScore: oldSession.careerScore ?? score,
      ui: {
        ...defaultUiState(),
        ...(oldSession.ui ?? {}),
      },
    }
  }
  return null
}

function resetForNextTerm(state: MacroState, termQuarters: number): MacroState {
  return {
    ...state,
    quarterIndex: 0,
    quartersRemaining: termQuarters,
  }
}

function updateSessionUi(session: GameSession, ui: Partial<UiState>): GameSession {
  return {
    ...session,
    ui: {
      ...session.ui,
      ...ui,
    },
  }
}

function advancedSession(session: GameSession, action: PolicyAction, customRateChange?: number): GameSession | null {
  if (session.status !== 'in_progress') {
    return null
  }
  const scenario = getTermScenario(session.scenarioId, session.seed, session.termNumber)
  const decision = createDecision(action, session.current, undefined, customRateChange)
  if (decision.resultingFedFundsRate < 0 || decision.resultingFedFundsRate > 20) {
    return null
  }
  const advanced = advanceQuarter({
    history: session.history,
    decision,
    scenario,
    activeShocks: session.activeShocks,
    seed: `${session.seed}:term-${session.termNumber}`,
    termNumber: session.termNumber,
  })
  const history = [...session.history, advanced.nextState]
  const decisions = [...session.decisions, { ...decision, careerQuarterIndex: session.totalCareerQuarters + 1 }]
  const traces = [...session.traces, advanced.trace]
  const careerHistory = [...session.careerHistory, advanced.nextState]
  const completedTerm = advanced.nextState.quartersRemaining === 0
  const score = evaluateScore(history, scenario)
  const careerScore = evaluateScore(careerHistory, getScenario(session.scenarioId))
  const termSummary: CompletedTermSummary | null = completedTerm
    ? {
        termNumber: session.termNumber,
        startingState: history[0]!,
        endingState: advanced.nextState,
        history,
        decisions,
        traces,
        score,
        reappointed: score.reappointed,
      }
    : null
  return {
    ...session,
    status: completedTerm ? (score.reappointed ? 'term_debrief' : 'not_reappointed') : 'in_progress',
    currentTermQuarter: advanced.nextState.quarterIndex,
    totalCareerQuarters: session.totalCareerQuarters + 1,
    completedTerms: termSummary ? [...session.completedTerms, termSummary] : session.completedTerms,
    careerHistory,
    careerScore,
    current: advanced.nextState,
    history,
    decisions,
    traces,
    activeShocks: advanced.activeShocks,
    latestTriggeredShocks: advanced.triggeredShocks,
    score,
    ui: { ...session.ui, selectedDecision: null },
  }
}

export const useGameStore = create<GameStore>((set, get) => ({
  session: makeInitialSession(),
  hasSavedGame: readSession() !== null,
  startGame: (seed = 'classic-2026') => {
    const session = { ...makeInitialSession(seed), status: 'in_progress' as const }
    saveSession(session)
    set({ session, hasSavedGame: true })
  },
  selectDecision: (action) => {
    const { session } = get()
    if (session.status !== 'in_progress') {
      return
    }
    const decision = createDecision(action, session.current)
    if (decision.resultingFedFundsRate < 0 || decision.resultingFedFundsRate > 20) {
      return
    }
    const nextSession = updateSessionUi(session, { selectedDecision: action })
    set({ session: nextSession })
  },
  advance: () => {
    const { session } = get()
    if (!session.ui.selectedDecision) {
      return
    }
    const nextSession = advancedSession(session, session.ui.selectedDecision)
    if (!nextSession) {
      return
    }
    saveSession(nextSession)
    set({ session: nextSession, hasSavedGame: true })
  },
  commitDecision: (action) => {
    const nextSession = advancedSession(get().session, action)
    if (!nextSession) {
      return
    }
    saveSession(nextSession)
    set({ session: nextSession, hasSavedGame: true })
  },
  commitCustomDecision: (rateChange) => {
    const bps = Math.round(rateChange * 100)
    if (Math.abs(bps) > 300 || Math.abs(rateChange * 100 - bps) > 1e-9) {
      return
    }
    const nextSession = advancedSession(get().session, 'custom', bps / 100)
    if (!nextSession) {
      return
    }
    saveSession(nextSession)
    set({ session: nextSession, hasSavedGame: true })
  },
  continueNextTerm: () => {
    const session = get().session
    if (session.status !== 'term_debrief' || !session.score.reappointed) {
      return
    }
    const scenario = getScenario(session.scenarioId)
    const startingState = resetForNextTerm(session.current, scenario.termQuarters)
    const termHistory = [startingState]
    const termScore = evaluateScore(termHistory, scenario)
    const nextSession: GameSession = {
      ...session,
      status: 'in_progress',
      termNumber: session.termNumber + 1,
      currentTermQuarter: 0,
      current: startingState,
      history: termHistory,
      decisions: [],
      traces: [],
      activeShocks: [],
      latestTriggeredShocks: [],
      score: termScore,
      ui: { ...session.ui, selectedDecision: null, chartView: 'chart' },
    }
    saveSession(nextSession)
    set({ session: nextSession, hasSavedGame: true })
  },
  retireCareer: () => {
    const session = get().session
    if (session.status !== 'term_debrief' || !session.score.reappointed || session.completedTerms.length < 2) {
      return
    }
    const nextSession: GameSession = {
      ...session,
      status: 'retired',
      score: session.careerScore,
      ui: { ...session.ui, selectedDecision: null },
    }
    saveSession(nextSession)
    set({ session: nextSession, hasSavedGame: true })
  },
  resetGame: () => {
    clearSession()
    set({ session: makeInitialSession(), hasSavedGame: false })
  },
  loadSavedGame: () => {
    const saved = readSession()
    if (!saved) {
      return false
    }
    set({ session: saved, hasSavedGame: true })
    return true
  },
  exportSaveFile: async () => createSaveFile(get().session),
  importSaveFile: async (text) => {
    try {
      const session = await parseSaveFile(text)
      saveSession(session)
      set({ session, hasSavedGame: true })
      return { ok: true, summary: summarizeSaveSession(session) }
    } catch (error) {
      return { ok: false, error: error instanceof Error ? error.message : 'Save file could not be loaded.' }
    }
  },
  setChartView: (view) => {
    const { session } = get()
    const nextSession = updateSessionUi(session, { chartView: view })
    saveSession(nextSession)
    set({ session: nextSession })
  },
  setReducedMotion: (value) => {
    const nextSession = updateSessionUi(get().session, { reducedMotion: value })
    saveSession(nextSession)
    set({ session: nextSession })
  },
  setSoundEnabled: (value) => {
    const nextSession = updateSessionUi(get().session, { soundEnabled: value })
    saveSession(nextSession)
    set({ session: nextSession })
  },
  setReducedNoise: (value) => {
    const nextSession = updateSessionUi(get().session, { reducedNoise: value })
    saveSession(nextSession)
    set({ session: nextSession })
  },
  setSoundVolume: (value) => {
    const nextSession = updateSessionUi(get().session, { soundVolume: Math.min(1, Math.max(0, value)) })
    saveSession(nextSession)
    set({ session: nextSession })
  },
}))
