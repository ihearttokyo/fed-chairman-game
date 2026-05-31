import {
  BarChart3,
  CheckCircle2,
  CircleAlert,
  Scissors,
  TrendingDown,
  TrendingUp,
  Table2,
  Target,
} from 'lucide-react'
import {
  Area,
  CartesianGrid,
  ComposedChart,
  Line,
  ReferenceArea,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { buildChartData, buildMandateCorridorSummary, type CorridorMetric } from './chartViewModel'
import { HistoryTable } from './HistoryTable'
import { formatPct } from '../../lib/format'
import type { GameSession, MacroState, ScenarioConfig } from '../../types'
import { buildCareerPolicySummary, type CareerTimelinePoint } from './careerTimeline'

function CorridorCard({ metric }: { metric: CorridorMetric }) {
  const DirectionIcon = metric.direction === 'worsening' ? TrendingUp : TrendingDown
  const StatusIcon = metric.inCorridor ? CheckCircle2 : CircleAlert
  const tone = metric.inCorridor ? 'inside' : 'outside'

  return (
    <article className={`corridor-card corridor-${tone}`}>
      <div className="corridor-card-top">
        <span className="corridor-label">
          <StatusIcon size={16} aria-hidden="true" />
          {metric.label}
        </span>
        <span className={`corridor-direction direction-${metric.direction}`}>
          <DirectionIcon size={15} aria-hidden="true" />
          {metric.direction}
        </span>
      </div>
      <strong>{metric.summary}</strong>
      <div
        className="corridor-meter"
        role="progressbar"
        aria-label={`${metric.label} time in corridor`}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={metric.timeInCorridorPct}
      >
        <span style={{ width: `${metric.timeInCorridorPct}%` }} />
      </div>
      <small>{metric.timeInCorridorPct}% of played quarters inside corridor</small>
    </article>
  )
}

function PolicyPathSummary({ history }: { history: Array<MacroState | CareerTimelinePoint> }) {
  const timeline = history.filter((point): point is CareerTimelinePoint => 'decisionTone' in point)
  const summary = buildCareerPolicySummary(timeline)

  return (
    <div className="policy-path-summary" aria-label="Full career policy path summary">
      <article>
        <span>
          <Target size={16} aria-hidden="true" />
          Latest meeting
        </span>
        <strong>{summary.latestLabel}</strong>
        <small>{summary.latestDetail}</small>
      </article>
      <article>
        <span>
          <Scissors size={16} aria-hidden="true" />
          Decision mix
        </span>
        <strong>{summary.cuts} cuts / {summary.holds} holds / {summary.raises} hikes</strong>
        <small>{summary.cadence}</small>
      </article>
    </div>
  )
}

export function HistoryPanel({
  history,
  session,
  scenario,
  onSetChartView,
}: {
  history: Array<MacroState | CareerTimelinePoint>
  session: GameSession
  scenario: ScenarioConfig
  onSetChartView: (view: GameSession['ui']['chartView']) => void
}) {
  const data = buildChartData(history)
  const corridorSummary = buildMandateCorridorSummary(history, scenario)
  const termBoundaries = data.filter((point) => point.termBoundary && point.quarter !== 'T1 start')
  return (
    <section className="panel chart-panel command-card" aria-labelledby="chart-title">
      <div className="panel-heading">
        <h2 id="chart-title">Mandate Dashboard</h2>
        <div className="segmented" role="group" aria-label="History view">
          <button type="button" className={session.ui.chartView === 'chart' ? 'active' : ''} onClick={() => onSetChartView('chart')} aria-pressed={session.ui.chartView === 'chart'}>
            <BarChart3 size={16} aria-hidden="true" />
            Chart
          </button>
          <button type="button" className={session.ui.chartView === 'table' ? 'active' : ''} onClick={() => onSetChartView('table')} aria-pressed={session.ui.chartView === 'table'}>
            <Table2 size={16} aria-hidden="true" />
            Table
          </button>
        </div>
      </div>
      <p className="sr-only" id="chart-summary" aria-live="polite">
        Latest values: inflation {formatPct(session.current.inflation)}, unemployment {formatPct(session.current.unemployment)}, fed funds {formatPct(session.current.fedFundsRate)}. Inflation corridor is {corridorSummary.inflation.summary}. Labor corridor is {corridorSummary.unemployment.summary}. Switch to table view for the full quarter history.
      </p>
      <div className="corridor-summary" aria-label="Mandate target corridor summary">
        <CorridorCard metric={corridorSummary.inflation} />
        <CorridorCard metric={corridorSummary.unemployment} />
      </div>
      <PolicyPathSummary history={history} />
      {session.ui.chartView === 'chart' ? (
        <>
          <div className="chart-frame" role="img" aria-label="Line chart of inflation, unemployment, and fed funds rate" aria-describedby="chart-summary">
            <ResponsiveContainer width="100%" height={420}>
              <ComposedChart data={data} margin={{ top: 12, right: 28, bottom: 4, left: 0 }}>
                <CartesianGrid strokeDasharray="4 4" stroke="rgba(18, 26, 24, 0.22)" />
                <XAxis dataKey="quarter" stroke="var(--ink)" tick={{ fill: 'var(--ink)', fontWeight: 800 }} />
                <YAxis domain={[0, 10]} tickFormatter={(value) => `${value}%`} stroke="var(--ink)" tick={{ fill: 'var(--ink)', fontWeight: 800 }} />
                <Tooltip formatter={(value) => `${Number(value).toFixed(2)}%`} />
                <ReferenceArea y1={1.5} y2={2.5} fill="var(--target-inflation)" fillOpacity={0.18} />
                <ReferenceArea y1={4.2} y2={5.8} fill="var(--target-unemployment)" fillOpacity={0.16} />
                <ReferenceLine y={scenario.targets.inflation} stroke="var(--data-inflation)" strokeWidth={2} strokeDasharray="6 4" />
                <ReferenceLine y={scenario.targets.unemployment} stroke="var(--data-unemployment)" strokeWidth={2} strokeDasharray="2 4" />
                {data.filter((point) => point.decisionTone !== 'none' && point.decisionTone !== 'hold').map((point) => (
                  <ReferenceLine
                    key={`policy-${point.key}`}
                    x={point.quarter}
                    stroke={point.decisionTone === 'raise' ? 'rgba(154, 52, 18, 0.5)' : 'rgba(7, 92, 55, 0.5)'}
                    strokeDasharray={point.decisionTone === 'raise' ? '2 5' : '8 5'}
                    label={{ value: point.decisionLabel, fill: 'var(--muted)', fontSize: 11, fontWeight: 800 }}
                  />
                ))}
                {termBoundaries.map((point) => (
                  <ReferenceLine
                    key={point.key}
                    x={point.quarter}
                    stroke="rgba(18, 26, 24, 0.36)"
                    strokeDasharray="4 5"
                    label={{ value: point.quarter, fill: 'var(--muted)', fontSize: 12, fontWeight: 800 }}
                  />
                ))}
                <Area type="monotone" dataKey="credibility" name="Credibility / 10" fill="var(--data-credibility)" stroke="transparent" fillOpacity={0.08} isAnimationActive={!session.ui.reducedMotion} />
                <Line type="monotone" dataKey="inflation" name="Inflation" stroke="var(--data-inflation)" strokeWidth={4} dot={{ r: 4, strokeWidth: 2 }} isAnimationActive={!session.ui.reducedMotion} />
                <Line type="monotone" dataKey="unemployment" name="Unemployment" stroke="var(--data-unemployment)" strokeWidth={4} strokeDasharray="8 4" dot={{ r: 4, strokeWidth: 2 }} isAnimationActive={!session.ui.reducedMotion} />
                <Line type="monotone" dataKey="fedFundsRate" name="Fed funds rate" stroke="var(--data-rate)" strokeWidth={4} strokeDasharray="2 6" dot={{ r: 4, strokeWidth: 2 }} isAnimationActive={!session.ui.reducedMotion} />
              </ComposedChart>
            </ResponsiveContainer>
          </div>
          <HistoryTable history={history} className="sr-table" />
        </>
      ) : (
        <HistoryTable history={history} />
      )}
      <div className="legend" aria-hidden="true">
        <span className="legend-inflation">Inflation</span>
        <span className="legend-unemployment">Unemployment</span>
        <span className="legend-rate">Fed funds</span>
        <span className="legend-policy">Policy move</span>
      </div>
    </section>
  )
}
