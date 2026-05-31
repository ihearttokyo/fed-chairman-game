import { createNews, openingNews } from '../../content/news'
import type { GameSession } from '../../types'
import { buildTraceReadout } from './briefingViewModel'
import { QuarterTransmission } from './QuarterTransmission'
import { TraceReadout } from './TraceReadout'
import { buildShockTimeline } from './shockTimelineViewModel'
import { buildTransmissionBriefing } from './transmissionViewModel'
import type { ScenarioConfig } from '../../types'

export function NewsPanel({ session, scenario }: { session: GameSession; scenario: ScenarioConfig }) {
  const trace = session.traces.at(-1)
  const news = session.current.quarterIndex === 0 ? openingNews() : createNews(session.current, trace, session.latestTriggeredShocks)
  const shock = session.latestTriggeredShocks[0]
  const shockTimeline = buildShockTimeline(session, scenario)
  return (
    <section
      className={`panel news-panel ${news.severity} ${shock ? 'newspaper-entry' : ''} command-card`}
      aria-labelledby="news-title"
    >
      <div className="panel-heading news-heading">
        <div>
          <p className="kicker">{news.kicker}</p>
          <h2 id="news-title">Quarterly Briefing</h2>
        </div>
        <span>Term {session.termNumber} | Q{session.current.quarterIndex}</span>
      </div>
      {shock ? (
        <div className="news-dateline" aria-label="Shock report metadata">
          <span>Macro desk dispatch</span>
          <span>{shock.type} shock</span>
          <span>Persistence {shock.persistence} quarters</span>
        </div>
      ) : null}
      <h3>{news.headline}</h3>
      <p>{news.explanation}</p>
      {shock ? (
        <p className="shock-policy-note">
          Policy implication: magnitude {shock.magnitude > 0 ? '+' : ''}
          {shock.magnitude.toFixed(2)} feeds into this term's model trace until it decays.
        </p>
      ) : null}
      <div className="briefing-question">
        <strong>Policy question</strong>
        <span>{news.policyQuestion}</span>
      </div>
      <div className="watch-item">
        <strong>Watch</strong>
        <span>{news.watchItem}</span>
      </div>
      {shockTimeline.items.length > 0 ? (
        <div className="risk-calendar-strip" aria-label="Deterministic term shock calendar">
          <strong>Risk calendar</strong>
          <span>{shockTimeline.summary}</span>
        </div>
      ) : null}
    </section>
  )
}

export function QuarterReviewPanel({ session, scenario }: { session: GameSession; scenario: ScenarioConfig }) {
  const trace = session.traces.at(-1)
  const readout = buildTraceReadout(trace, session.latestTriggeredShocks)
  const transmissionBriefing = buildTransmissionBriefing(session, scenario)
  return (
    <section className="panel quarter-review-panel command-card" aria-labelledby="quarter-review-title">
      <div className="panel-heading">
        <div>
          <p className="kicker">Model trace</p>
          <h2 id="quarter-review-title">Quarter Review</h2>
        </div>
        <span>Derived from the latest decision</span>
      </div>
      <TraceReadout readout={readout} />
      <QuarterTransmission briefing={transmissionBriefing} />
    </section>
  )
}
