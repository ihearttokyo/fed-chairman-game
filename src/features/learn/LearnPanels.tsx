import { Info } from 'lucide-react'
import { getLearnPanels } from '../../content/learn'
import type { GameSession, ScenarioConfig } from '../../types'

export function LearnPanels({ session, scenario }: { session: GameSession; scenario: ScenarioConfig }) {
  const panels = getLearnPanels(session.current, scenario, session.traces.at(-1), session.activeShocks)
  return (
    <section className="panel learn-panel command-card" aria-labelledby="learn-title">
      <div className="panel-heading">
        <h2 id="learn-title">Policy Notebook</h2>
        <Info size={18} aria-hidden="true" />
      </div>
      <div className="learn-list">
        {panels.map((panel) => (
          <details key={panel.title} open={panel.title === 'Your Job' || panel.title === 'Federal Funds Rate'}>
            <summary>{panel.title}</summary>
            <p>{panel.body}</p>
          </details>
        ))}
      </div>
    </section>
  )
}
