import { useEffect, useMemo, useRef } from 'react'
import { audioEngine } from './audioEngine'
import type { SoundEvent } from './soundDesign'
import type { GameSession, PolicyAction } from '../types'

function decisionSound(action: PolicyAction): SoundEvent {
  if (action.startsWith('raise')) {
    return 'decision:select_raise'
  }
  if (action.startsWith('cut')) {
    return 'decision:select_cut'
  }
  return 'decision:select_hold'
}

export function useSoundFeedback(session: GameSession): void {
  const previousDecision = useRef<PolicyAction | null>(session.ui.selectedDecision)
  const previousQuarter = useRef(session.current.quarterIndex)
  const termCompletePlayed = useRef(false)
  const selectedDecision = session.ui.selectedDecision
  const quarterIndex = session.current.quarterIndex
  const triggeredShockCount = session.latestTriggeredShocks.length
  const status = session.status
  const reappointed = session.score.reappointed
  const prefs = useMemo(
    () => ({
      soundEnabled: session.ui.soundEnabled,
      reducedNoise: session.ui.reducedNoise,
      soundVolume: session.ui.soundVolume,
    }),
    [session.ui.reducedNoise, session.ui.soundEnabled, session.ui.soundVolume],
  )

  useEffect(() => {
    if (selectedDecision && selectedDecision !== previousDecision.current) {
      audioEngine.play(decisionSound(selectedDecision), prefs)
    }
    previousDecision.current = selectedDecision
  }, [selectedDecision, prefs])

  useEffect(() => {
    if (quarterIndex > previousQuarter.current) {
      audioEngine.play('quarter:advance', prefs)
      if (triggeredShockCount > 0) {
        audioEngine.play('shock:triggered', prefs)
      }
    }
    previousQuarter.current = quarterIndex
  }, [quarterIndex, triggeredShockCount, prefs])

  useEffect(() => {
    const termComplete = status === 'term_debrief' || status === 'not_reappointed'
    if (termComplete && !termCompletePlayed.current) {
      audioEngine.play(reappointed ? 'term:completed_reappointed' : 'term:completed_not_reappointed', prefs)
      termCompletePlayed.current = true
    }
    if (!termComplete) {
      termCompletePlayed.current = false
    }
  }, [status, reappointed, prefs])
}
