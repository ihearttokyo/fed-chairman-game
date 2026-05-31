import { audioEngine } from '../../audio/audioEngine'
import { useSoundFeedback } from '../../audio/useSoundFeedback'
import { buildMetricViews } from '../metrics/metricViewModel'
import { MetricsStrip } from '../metrics/MetricsStrip'
import { NewsPanel, QuarterReviewPanel } from '../briefing/NewsPanel'
import { HistoryPanel } from '../history/HistoryPanel'
import { PolicyControls } from '../policy/PolicyControls'
import { buildPolicyReadinessBrief, policyActionViews, policyStance } from '../policy/policyViewModel'
import { LearnPanels } from '../learn/LearnPanels'
import { ExportControls } from '../export/ExportControls'
import { EndScreen } from '../results/EndScreen'
import { GameHeader } from './GameHeader'
import { GameKeyboardShortcuts } from './GameKeyboardShortcuts'
import { useGameStore } from '../../state/gameStore'
import { useGameUiStore } from '../../state/gameUiStore'
import { getScenario } from '../../scenarios/classic'
import type { PolicyAction } from '../../types'
import { buildCareerTimeline } from '../history/careerTimeline'

export function GameScreen() {
  const session = useGameStore((state) => state.session)
  const resetGame = useGameStore((state) => state.resetGame)
  const startGame = useGameStore((state) => state.startGame)
  const commitDecision = useGameStore((state) => state.commitDecision)
  const commitCustomDecision = useGameStore((state) => state.commitCustomDecision)
  const continueNextTerm = useGameStore((state) => state.continueNextTerm)
  const retireCareer = useGameStore((state) => state.retireCareer)
  const setChartView = useGameStore((state) => state.setChartView)
  const setCinematicPhase = useGameUiStore((state) => state.setCinematicPhase)
  const completeReveal = useGameUiStore((state) => state.completeReveal)
  const cinematicPhase = useGameUiStore((state) => state.cinematicPhase)
  const scenario = getScenario(session.scenarioId)
  const showResults = session.status === 'term_debrief' || session.status === 'not_reappointed' || session.status === 'retired'
  const controlsDisabled = session.status !== 'in_progress' || cinematicPhase === 'advancing'
  const previousQuarter = session.history.at(-2)
  const metrics = buildMetricViews(session.current, scenario, previousQuarter)
  const policyReadiness = buildPolicyReadinessBrief(session, scenario)
  const careerTimeline = buildCareerTimeline(session)

  useSoundFeedback(session)

  function onCommit(action: PolicyAction): void {
    if (session.status !== 'in_progress' || controlsDisabled) {
      return
    }
    setCinematicPhase(session.ui.reducedMotion ? 'idle' : 'advancing', session.current.quarterIndex + 1)
    commitDecision(action)
    if (!session.ui.reducedMotion) {
      window.setTimeout(() => completeReveal(), 620)
    }
  }

  function onCommitCustom(rateChange: number): void {
    if (session.status !== 'in_progress' || controlsDisabled) {
      return
    }
    setCinematicPhase(session.ui.reducedMotion ? 'idle' : 'advancing', session.current.quarterIndex + 1)
    commitCustomDecision(rateChange)
    if (!session.ui.reducedMotion) {
      window.setTimeout(() => completeReveal(), 620)
    }
  }

  function onReset(): void {
    audioEngine.play('reset', session.ui)
    resetGame()
  }

  return (
    <main className={`app-shell phase-${cinematicPhase}`}>
      <GameKeyboardShortcuts onSelectDecision={onCommit} />
      <GameHeader
        scenarioLabel={scenario.label}
        termNumber={session.termNumber}
        currentQuarter={session.current.quarterIndex}
        totalQuarters={scenario.termQuarters}
        totalCareerQuarters={session.totalCareerQuarters}
        onReset={onReset}
      />
      {showResults ? (
        <>
          <EndScreen
            session={session}
            onReplay={startGame}
            onContinueNextTerm={continueNextTerm}
            onRetire={retireCareer}
          />
          <div className="results-actions">
            <ExportControls session={session} />
          </div>
          <footer className="app-footer">
            Independent educational simulation. Original UI, copy, and assets only; no Federal Reserve endorsement is implied.
          </footer>
        </>
      ) : (
        <>
          <NewsPanel session={session} scenario={scenario} />
          <div className="cockpit-window">
            <HistoryPanel history={careerTimeline} session={session} scenario={scenario} onSetChartView={setChartView} />
          </div>
          <div className="control-deck">
            <PolicyControls
              fedFundsRate={session.current.fedFundsRate}
              stance={policyStance(session, scenario)}
              readiness={policyReadiness}
              actions={policyActionViews(session, scenario, controlsDisabled)}
              onCommitDecision={onCommit}
              onCommitCustomDecision={onCommitCustom}
            />
            <div className="instrument-column">
              <MetricsStrip metrics={metrics} />
            </div>
            <aside className="side-column">
              <LearnPanels session={session} scenario={scenario} />
              <ExportControls session={session} />
            </aside>
          </div>
          <QuarterReviewPanel session={session} scenario={scenario} />
          <footer className="app-footer">
            Independent educational simulation. Original UI, copy, and assets only; no Federal Reserve endorsement is
            implied.
          </footer>
        </>
      )}
    </main>
  )
}
