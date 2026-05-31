import { evaluateScore } from '../engine/scoreEngine'
import { getScenario } from '../scenarios/classic'
import type { CompletedTermSummary, GameSession } from '../types'
import { gameSessionSchema } from './sessionSchema'

const SAVE_FILE_VERSION = 1
const SAVE_FILE_NAMESPACE = 'fed-chairman-game-save-v1'

export type SaveFileEnvelope = {
  version: typeof SAVE_FILE_VERSION
  payload: GameSession
  digest: string
}

export type SaveFileSummary = {
  sessionId: string
  seed: string
  status: GameSession['status']
  termNumber: number
  currentTermQuarter: number
  totalCareerQuarters: number
  completedTerms: number
  careerScore: number
  careerGrade: string
  label: string
}

function canonicalize(value: unknown): string {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value)
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalize(item)).join(',')}]`
  }
  const record = value as Record<string, unknown>
  return `{${Object.keys(record)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${canonicalize(record[key])}`)
    .join(',')}}`
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input)
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

async function digestPayload(payload: GameSession): Promise<string> {
  return sha256Hex(`${SAVE_FILE_NAMESPACE}:${canonicalize(payload)}`)
}

function recomputeTerm(term: CompletedTermSummary, fallbackScenarioId: string): CompletedTermSummary {
  const scenario = getScenario(fallbackScenarioId)
  const score = evaluateScore(term.history, scenario)
  return {
    ...term,
    score,
    reappointed: score.reappointed,
  }
}

export function recomputeSessionScores(session: GameSession): GameSession {
  const scenario = getScenario(session.scenarioId)
  const completedTerms = session.completedTerms.map((term) => recomputeTerm(term, session.scenarioId))
  const currentTermScore =
    session.status === 'in_progress' || session.status === 'not_started'
      ? evaluateScore(session.history, scenario)
      : completedTerms.at(-1)?.score ?? evaluateScore(session.history, scenario)
  const careerScore = evaluateScore(session.careerHistory, scenario)
  return {
    ...session,
    completedTerms,
    score: session.status === 'retired' ? careerScore : currentTermScore,
    careerScore,
  }
}

export async function createSaveFile(session: GameSession): Promise<string> {
  const payload = recomputeSessionScores(session)
  const envelope: SaveFileEnvelope = {
    version: SAVE_FILE_VERSION,
    payload,
    digest: await digestPayload(payload),
  }
  return JSON.stringify(envelope, null, 2)
}

export async function parseSaveFile(text: string): Promise<GameSession> {
  const parsed = JSON.parse(text) as Partial<SaveFileEnvelope>
  if (parsed.version !== SAVE_FILE_VERSION || !parsed.payload || typeof parsed.digest !== 'string') {
    throw new Error('Save file is not a supported Fed Chairman save.')
  }
  const expectedDigest = await digestPayload(parsed.payload)
  if (expectedDigest !== parsed.digest) {
    throw new Error('Save file failed integrity check.')
  }
  const result = gameSessionSchema.safeParse(parsed.payload)
  if (!result.success) {
    throw new Error('Save file does not match the current session schema.')
  }
  return recomputeSessionScores(result.data as GameSession)
}

function describeStatus(session: GameSession): string {
  if (session.status === 'retired') {
    return 'retired career'
  }
  if (session.status === 'term_debrief') {
    return `term ${session.termNumber} debrief`
  }
  if (session.status === 'not_reappointed') {
    return 'not reappointed'
  }
  if (session.status === 'not_started') {
    return 'not started'
  }
  return `term ${session.termNumber} quarter ${session.currentTermQuarter}`
}

export function summarizeSaveSession(session: GameSession): SaveFileSummary {
  const statusLabel = describeStatus(session)
  const label = `${statusLabel}; ${session.totalCareerQuarters} career quarters; career ${session.careerScore.score} (${session.careerScore.grade})`
  return {
    sessionId: session.sessionId,
    seed: session.seed,
    status: session.status,
    termNumber: session.termNumber,
    currentTermQuarter: session.currentTermQuarter,
    totalCareerQuarters: session.totalCareerQuarters,
    completedTerms: session.completedTerms.length,
    careerScore: session.careerScore.score,
    careerGrade: session.careerScore.grade,
    label,
  }
}

export async function inspectSaveFile(text: string): Promise<SaveFileSummary> {
  return summarizeSaveSession(await parseSaveFile(text))
}
