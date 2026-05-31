import { beforeEach, describe, expect, it } from 'vitest'
import { buildCareerPolicySummary, buildCareerTimeline } from '../features/history/careerTimeline'
import type { GameSession } from '../types'
import { sessionToCsv, sessionToMarkdown } from './exporters'
import { useGameStore } from './gameStore'
import { createSaveFile, parseSaveFile } from './saveFile'

describe('gameStore', () => {
  beforeEach(() => {
    localStorage.clear()
    useGameStore.getState().resetGame()
  })

  it('starts, advances, saves, loads, and exports a session', () => {
    useGameStore.getState().startGame('store-test')
    useGameStore.getState().selectDecision('hold')
    useGameStore.getState().advance()

    let session = useGameStore.getState().session
    expect(session.current.quarterIndex).toBe(1)
    expect(session.history).toHaveLength(2)
    expect(localStorage.getItem('fed-chairman-classic-v1')).toContain('store-test')

    useGameStore.getState().resetGame()
    expect(useGameStore.getState().loadSavedGame()).toBe(false)

    useGameStore.getState().startGame('store-test')
    useGameStore.getState().selectDecision('hold')
    useGameStore.getState().advance()
    expect(useGameStore.getState().loadSavedGame()).toBe(true)
    session = useGameStore.getState().session

    expect(sessionToCsv(session).split('\n')).toHaveLength(session.history.length + 1)
    expect(sessionToMarkdown(session)).toContain('Classic Monetary Policy Debrief')
  })

  it('keeps career timeline labels unique after reappointment rollover', () => {
    useGameStore.getState().startGame('raiseEarly')
    const firstTermPath = [
      'raise_25',
      'raise_25',
      'hold',
      'hold',
      'hold',
      'cut_25',
      'cut_25',
      'hold',
      'hold',
      'hold',
      'hold',
      'hold',
      'cut_25',
      'hold',
      'raise_25',
      'hold',
    ] as const
    firstTermPath.forEach((action) => useGameStore.getState().commitDecision(action))
    expect(useGameStore.getState().session.status).toBe('term_debrief')

    useGameStore.getState().continueNextTerm()
    useGameStore.getState().commitDecision('hold')
    const session = useGameStore.getState().session
    const timeline = buildCareerTimeline(session)
    const keys = timeline.map((point) => point.key)

    expect(timeline.map((point) => point.label)).toEqual(
      expect.arrayContaining(['T1 Q16', 'T2 start', 'T2 Q1']),
    )
    expect(timeline.find((point) => point.label === 'T1 Q1')).toMatchObject({
      decisionLabel: '+25 bps',
      decisionTone: 'raise',
      decisionResultingRate: 4.25,
    })
    expect(timeline.find((point) => point.label === 'T1 Q6')).toMatchObject({
      decisionLabel: '-25 bps',
      decisionTone: 'cut',
    })
    expect(timeline.find((point) => point.label === 'T2 Q1')).toMatchObject({
      careerQuarter: 17,
      decisionLabel: 'Hold',
      decisionTone: 'hold',
    })
    expect(buildCareerPolicySummary(timeline)).toMatchObject({
      cuts: 3,
      holds: 11,
      raises: 3,
      latestLabel: 'T2 Q1: Hold',
      cadence: '35% active moves across 17 career meetings.',
    })
    expect(new Set(keys).size).toBe(keys.length)
    expect(sessionToCsv(session)).toContain('2,1,17,')
    expect(sessionToCsv(session).split('\n')[0]).toContain('label,boundary')
    expect(sessionToCsv(session)).toContain('T2 start,term start')
    expect(sessionToMarkdown(session)).toContain('## Term Boundaries')
    expect(sessionToMarkdown(session)).toContain('- T2 start: career Q16')
    expect(sessionToMarkdown(session)).toContain('| T2 Q1 | Q17 | Hold |')
  })

  it('creates and validates tamper-evident portable save files', async () => {
    useGameStore.getState().startGame('save-file')
    useGameStore.getState().commitDecision('hold')
    const session = useGameStore.getState().session
    const saveA = JSON.parse(await createSaveFile(session)) as { digest: string; payload: typeof session }
    const saveB = JSON.parse(await createSaveFile(JSON.parse(JSON.stringify(session)) as typeof session)) as {
      digest: string
      payload: typeof session
    }

    expect(saveA.digest).toBe(saveB.digest)
    await expect(parseSaveFile(JSON.stringify(saveA))).resolves.toMatchObject({
      sessionId: session.sessionId,
      currentTermQuarter: 1,
    })

    saveA.payload.current.inflation += 1
    await expect(parseSaveFile(JSON.stringify(saveA))).rejects.toThrow('integrity')
  })

  it('loads a portable save into the store and recomputes stale scores', async () => {
    useGameStore.getState().startGame('save-load')
    useGameStore.getState().commitDecision('hold')
    const staleSession = JSON.parse(JSON.stringify(useGameStore.getState().session)) as GameSession
    staleSession.score = { ...staleSession.score, score: 1, grade: 'F' }
    staleSession.careerScore = { ...staleSession.careerScore, score: 1, grade: 'F' }
    const saveText = await createSaveFile(staleSession)

    useGameStore.getState().resetGame()
    const result = await useGameStore.getState().importSaveFile(saveText)
    const loaded = useGameStore.getState().session

    expect(result).toMatchObject({
      ok: true,
      summary: {
        label: 'term 1 quarter 1; 1 career quarters; career 99 (A)',
        totalCareerQuarters: 1,
      },
    })
    expect(loaded.currentTermQuarter).toBe(1)
    expect(loaded.score.score).not.toBe(1)
    expect(loaded.careerScore.score).not.toBe(1)
  })

  it('rejects malformed saved sessions instead of hydrating invalid state', () => {
    localStorage.setItem(
      'fed-chairman-classic-v1',
      JSON.stringify({
        version: 1,
        session: {
          scenarioId: 'unknown',
          history: [],
          ui: { chartView: 'broken' },
        },
      }),
    )
    expect(useGameStore.getState().loadSavedGame()).toBe(false)
    expect(localStorage.getItem('fed-chairman-classic-v1')).toBeNull()
  })

  it('does not advance after completion', () => {
    useGameStore.getState().startGame('complete-test')
    for (let index = 0; index < 16; index += 1) {
      useGameStore.getState().selectDecision('hold')
      useGameStore.getState().advance()
    }
    const completed = useGameStore.getState().session
    expect(['term_debrief', 'not_reappointed']).toContain(completed.status)
    useGameStore.getState().selectDecision('hold')
    useGameStore.getState().advance()
    expect(useGameStore.getState().session.history).toHaveLength(completed.history.length)
  })

  it('commits a one-click decision atomically without persisting selected state', () => {
    useGameStore.getState().startGame('commit-test')
    useGameStore.getState().commitDecision('raise_25')
    const session = useGameStore.getState().session

    expect(session.current.quarterIndex).toBe(1)
    expect(session.decisions).toHaveLength(1)
    expect(session.decisions[0]?.action).toBe('raise_25')
    expect(session.ui.selectedDecision).toBeNull()
    expect(localStorage.getItem('fed-chairman-classic-v1')).toContain('"selectedDecision":null')
  })

  it('commits a custom bps decision with rateChange as the canonical value', () => {
    useGameStore.getState().startGame('custom-bps')
    useGameStore.getState().commitCustomDecision(0.37)
    const session = useGameStore.getState().session

    expect(session.current.quarterIndex).toBe(1)
    expect(session.decisions[0]).toMatchObject({
      action: 'custom',
      rateChange: 0.37,
      resultingFedFundsRate: 4.37,
    })
    expect(sessionToMarkdown(session)).toContain('| T1 Q1 | Q1 | Custom +37 bps | 4.37% |')

    useGameStore.getState().commitCustomDecision(3.01)
    expect(useGameStore.getState().session.current.quarterIndex).toBe(1)
  })

  it('keeps retirement locked until a reappointed second term debrief', () => {
    useGameStore.getState().startGame('retire-lock')
    for (let index = 0; index < 16; index += 1) {
      useGameStore.getState().commitDecision('hold')
    }
    const debrief = useGameStore.getState().session
    if (debrief.status !== 'term_debrief') {
      return
    }

    useGameStore.getState().retireCareer()
    expect(useGameStore.getState().session.status).toBe('term_debrief')
  })
})
