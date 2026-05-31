import { buildDebrief } from './debrief'
import type { GameSession } from '../../types'

export function EndScreen({
  session,
  onReplay,
  onContinueNextTerm,
  onRetire,
}: {
  session: GameSession
  onReplay: (seed: string) => void
  onContinueNextTerm: () => void
  onRetire: () => void
}) {
  const debrief = buildDebrief(session)
  const isFinal = session.status === 'retired' || session.status === 'not_reappointed'
  const displayScore = isFinal ? session.careerScore : session.score
  const canContinue = session.status === 'term_debrief' && session.score.reappointed
  const canRetire = canContinue && session.completedTerms.length >= 2
  const title =
    session.status === 'retired'
      ? 'Career complete'
      : session.status === 'not_reappointed'
        ? 'Not reappointed'
        : 'Reappointed'
  return (
    <section className="end-banner command-card" aria-labelledby="result-title">
      <div className="result-main">
        <p className="eyebrow">
          {isFinal ? `Career: ${session.totalCareerQuarters} quarters` : `Term ${session.termNumber} complete`}
        </p>
        <h2 id="result-title">{title}</h2>
        <p>
          {isFinal ? 'Career score' : 'Term score'} {displayScore.score.toFixed(1)} ({displayScore.grade}). Policy
          style: {debrief.policyStyle}.
        </p>
        <p className="board-verdict">{debrief.boardVerdict}</p>
      </div>
      <div className="score-pill" aria-label={`${isFinal ? 'Career' : 'Term'} grade ${displayScore.grade}`}>
        {displayScore.grade}
      </div>
      <div className="debrief-grid" aria-label="Final debrief">
        <article className="debrief-card debrief-score">
          <h3>Score breakdown</h3>
          <p>{debrief.termStanding}</p>
          <p>
            Inflation miss: {displayScore.meanAbsInflationGap.toFixed(2)} | Unemployment miss:{' '}
            {displayScore.meanAbsUnemploymentGap.toFixed(2)}
          </p>
          <p>
            Volatility: {displayScore.volatilityIndex.toFixed(2)} | Recession share:{' '}
            {(displayScore.recessionQuarterShare * 100).toFixed(0)}%
          </p>
        </article>
        <article className="debrief-card">
          <h3>Mandate trend</h3>
          <p>{debrief.mandateTrend}</p>
          <p>{debrief.decisionMix}</p>
        </article>
        <article className="debrief-card">
          <h3>Best stretch</h3>
          <p>{debrief.bestStretch}</p>
          <div
            className="streak-meter"
            role="progressbar"
            aria-label="Longest mandate streak"
            aria-valuenow={debrief.streakQuarters}
            aria-valuemin={0}
            aria-valuemax={Math.max(1, session.decisions.length)}
          >
            <span style={{ width: `${Math.min(100, (debrief.streakQuarters / Math.max(1, session.decisions.length)) * 100)}%` }} />
          </div>
        </article>
        <article className="debrief-card">
          <h3>Turning point</h3>
          <p>{debrief.turningPoint}</p>
          <p>{debrief.largestPolicyMove}</p>
        </article>
        <article className="debrief-card debrief-wide">
          <h3>Final impulse</h3>
          <p>{debrief.finalImpulse}</p>
          <p>{debrief.coachingFocus}</p>
        </article>
        <article className="debrief-card debrief-wide">
          <h3>Term handoff</h3>
          <p>{debrief.termHandoff}</p>
          <dl className="handoff-metrics" aria-label="Start and end of term mandate handoff">
            {debrief.termHandoffMetrics.map((metric) => (
              <div key={metric.label} data-tone={metric.tone}>
                <dt>{metric.label}</dt>
                <dd>
                  <span>{metric.start}</span>
                  <strong>{metric.end}</strong>
                  <em>{metric.delta}</em>
                </dd>
              </div>
            ))}
          </dl>
        </article>
        <article className="debrief-card debrief-career" aria-labelledby="career-ledger-title">
          <h3 id="career-ledger-title">Career ledger</h3>
          <p>{debrief.careerStanding}</p>
          <ol className="career-ledger" aria-label="Completed chair terms">
            {debrief.careerLedger.map((term) => (
              <li key={term.termNumber}>
                <div>
                  <strong>{term.label}</strong>
                  <span>{term.outcome}</span>
                </div>
                <dl>
                  <div>
                    <dt>Score</dt>
                    <dd>{term.score}</dd>
                  </div>
                  <div>
                    <dt>Inflation</dt>
                    <dd>{term.finalInflation}</dd>
                  </div>
                  <div>
                    <dt>Labor</dt>
                    <dd>{term.finalUnemployment}</dd>
                  </div>
                  <div>
                    <dt>Rate</dt>
                    <dd>{term.finalRate}</dd>
                  </div>
                  <div>
                    <dt>Moves</dt>
                    <dd>{term.decisionMix}</dd>
                  </div>
                </dl>
              </li>
            ))}
          </ol>
        </article>
        <article className="debrief-card debrief-gate">
          <h3>{canContinue ? 'Reappointment gate' : 'Next run'}</h3>
          <p>
            {canContinue
              ? 'A new four-year chair term begins from the economy you leave behind.'
              : debrief.recommendation}
          </p>
          {canContinue ? <p>{debrief.nextTermBrief}</p> : null}
          <p>{debrief.gateChoice}</p>
          <div className="career-progress" aria-label={debrief.careerProgressLabel}>
            <div>
              <span>{debrief.careerProgressLabel}</span>
              <strong>
                {debrief.careerProgressValue}/{debrief.careerProgressMax}
              </strong>
            </div>
            <div
              className="career-progress-meter"
              role="progressbar"
              aria-label="Retirement eligibility progress"
              aria-valuenow={debrief.careerProgressValue}
              aria-valuemin={0}
              aria-valuemax={debrief.careerProgressMax}
            >
              <span
                style={{
                  width: `${Math.min(100, (debrief.careerProgressValue / Math.max(1, debrief.careerProgressMax)) * 100)}%`,
                }}
              />
            </div>
          </div>
          <div className="carryover-snapshot" aria-label="Inherited economy snapshot">
            {debrief.carryoverMetrics.map((metric) => (
              <span key={metric}>{metric}</span>
            ))}
          </div>
          <p>{debrief.carryoverBrief}</p>
          <div className="gate-brief" aria-label="Term boundary choice">
            <strong>{debrief.gateStatus}</strong>
            <span>{debrief.retirementStatus}</span>
          </div>
          {canContinue ? (
            <div className="button-row term-actions">
              <button type="button" className="primary-button" onClick={onContinueNextTerm}>
                Continue next term
              </button>
              {canRetire ? (
                <button type="button" className="secondary-button" onClick={onRetire}>
                  Retire with final score
                </button>
              ) : (
                <span className="retirement-lock" aria-live="polite">
                  Retirement unlocks after Term 2
                </span>
              )}
            </div>
          ) : (
            <button
              type="button"
              className="secondary-button"
              onClick={() => onReplay(session.seed)}
              title={`Replay seed ${session.seed}`}
            >
              Replay same seed
            </button>
          )}
          <p className="seed-caption">Seed: {session.seed}</p>
        </article>
      </div>
    </section>
  )
}
