import { ArrowDownRight, ArrowUpRight, Activity, ShieldAlert } from 'lucide-react'
import type { TransmissionBriefing, TransmissionTrend } from './transmissionViewModel'

function TrendIcon({ trend }: { trend: TransmissionTrend }) {
  if (trend === 'cooling') {
    return <ArrowDownRight size={16} aria-hidden="true" />
  }
  if (trend === 'heating') {
    return <ArrowUpRight size={16} aria-hidden="true" />
  }
  if (trend === 'stress') {
    return <ShieldAlert size={16} aria-hidden="true" />
  }
  return <Activity size={16} aria-hidden="true" />
}

export function QuarterTransmission({ briefing }: { briefing: TransmissionBriefing | null }) {
  if (!briefing) {
    return null
  }
  return (
    <div className="quarter-transmission" aria-label="Three month transmission sequence">
      <h3>Three-month transmission</h3>
      <section className={`transmission-receipt trend-${briefing.receipt.tone}`} aria-label="Latest decision receipt">
        <div>
          <span>Decision receipt</span>
          <strong>{briefing.receipt.headline}</strong>
        </div>
        <p>{briefing.receipt.verdict}</p>
        <p>{briefing.receipt.policyEcho}</p>
        <p>{briefing.receipt.nextWatch}</p>
      </section>
      <section className={`decision-memo trend-${briefing.decisionMemo.tone}`} aria-label="Policy decision quality memo">
        <div>
          <span>Policy memo</span>
          <strong>{briefing.decisionMemo.headline}</strong>
        </div>
        <p>{briefing.decisionMemo.assessment}</p>
        <p>{briefing.decisionMemo.tradeoff}</p>
        <p>{briefing.decisionMemo.risk}</p>
        <p>{briefing.decisionMemo.nextBias}</p>
      </section>
      <p className="transmission-summary">{briefing.summary}</p>
      <ol className="transmission-path" aria-label="Policy transmission path">
        {briefing.path.map((leg, index) => (
          <li key={leg}>
            <span>Step {index + 1}</span>
            <strong>{leg}</strong>
          </li>
        ))}
      </ol>
      <ol className="transmission-causal-chain" aria-label="Causal explanation from decision to mandate">
        {briefing.causalChain.map((link) => (
          <li key={link.label} className={`trend-${link.tone}`}>
            <span>{link.label}</span>
            <p>{link.text}</p>
          </li>
        ))}
      </ol>
      <dl className="transmission-changes" aria-label="Quarter over quarter changes">
        {briefing.changes.map((change) => (
          <div key={change.label} className={`trend-${change.tone}`}>
            <dt>{change.label}</dt>
            <dd>
              <span>{change.previous}</span>
              <span aria-hidden="true">{'->'}</span>
              <strong>{change.current}</strong>
              <em>{change.delta}</em>
              <small>{change.reason}</small>
            </dd>
          </div>
        ))}
      </dl>
      <ol className="transmission-months">
        {briefing.steps.map((step) => (
          <li key={step.month} className={`trend-${step.trend}`}>
            <div className="month-chip">
              <TrendIcon trend={step.trend} />
              <span>{step.month}</span>
            </div>
            <div
              className="transmission-tape"
              aria-label={`${step.month} ${step.intensityLabel.toLowerCase()} ${step.intensity} percent`}
            >
              <span>{step.intensityLabel}</span>
              <strong>{step.intensity}%</strong>
              <div aria-hidden="true">
                <span style={{ width: `${step.intensity}%` }} />
              </div>
            </div>
            <span className="transmission-channel">{step.channel}</span>
            <span className="transmission-stance">{step.stance}</span>
            <strong>{step.title}</strong>
            <span className="transmission-driver">{step.driver}</span>
            <span className="transmission-value">{step.value}</span>
            <span className="transmission-comparison">{step.comparison}</span>
            <div className="transmission-evidence" aria-label={`${step.month} evidence`}>
              {step.evidence.map((item) => (
                <span key={item}>{item}</span>
              ))}
            </div>
            <span className="transmission-basis">{step.basis}</span>
            <div className="transmission-signals" aria-label={`${step.month} signals`}>
              {step.signals.map((signal) => (
                <span key={signal}>{signal}</span>
              ))}
            </div>
            <div className="transmission-trace-inputs" aria-label={`${step.month} trace inputs`}>
              <span>Trace inputs</span>
              <ul>
                {step.traceInputs.map((input) => (
                  <li key={input}>{input}</li>
                ))}
              </ul>
            </div>
            <p>{step.detail}</p>
          </li>
        ))}
      </ol>
    </div>
  )
}
