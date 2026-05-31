import { ArrowDown, ArrowUp, Gauge } from 'lucide-react'
import { useMemo, useState } from 'react'
import { formatPct } from '../../lib/format'
import type { PolicyAction } from '../../types'
import type { PolicyActionView, PolicyReadinessBrief } from './policyViewModel'

export function PolicyControls({
  fedFundsRate,
  stance,
  readiness,
  actions,
  onCommitDecision,
  onCommitCustomDecision,
}: {
  fedFundsRate: number
  stance: string
  readiness: PolicyReadinessBrief
  actions: PolicyActionView[]
  onCommitDecision: (action: PolicyAction) => void
  onCommitCustomDecision: (rateChange: number) => void
}) {
  const [customBps, setCustomBps] = useState('')
  const customMove = useMemo(() => {
    if (!/^[+-]?\d+$/.test(customBps.trim())) {
      return null
    }
    const bps = Number(customBps)
    const rateChange = bps / 100
    const resultingRate = fedFundsRate + rateChange
    return {
      bps,
      rateChange,
      resultingRate,
      valid: Math.abs(bps) <= 300 && resultingRate >= 0 && resultingRate <= 20,
    }
  }, [customBps, fedFundsRate])
  const customLabel = customMove
    ? `${customMove.bps > 0 ? '+' : ''}${customMove.bps} bps to ${formatPct(customMove.resultingRate)}`
    : 'Enter whole bps'

  function commitCustom(): void {
    if (!customMove?.valid) {
      return
    }
    onCommitCustomDecision(customMove.rateChange)
    setCustomBps('')
  }

  return (
    <section className="panel controls-panel command-card" aria-labelledby="policy-title">
      <div className="panel-heading">
        <h2 id="policy-title">Policy Lever</h2>
        <span>{stance}</span>
      </div>
      <div className="rate-dial" aria-label={`Fed funds rate ${formatPct(fedFundsRate)}`}>
        <span className="dial-label">Fed funds</span>
        <strong>{formatPct(fedFundsRate)}</strong>
        <div className="custom-bps-control">
          <label htmlFor="custom-bps">Custom bps</label>
          <div>
            <input
              id="custom-bps"
              inputMode="numeric"
              pattern="-?[0-9]*"
              placeholder="+37"
              value={customBps}
              onChange={(event) => setCustomBps(event.target.value)}
              aria-describedby="custom-bps-status"
            />
            <button
              type="button"
              onClick={commitCustom}
              disabled={!customMove?.valid}
              title={customMove?.valid ? `Custom move: ${customLabel}. Commits and advances one quarter.` : 'Enter a whole basis-point move from -300 to +300 that keeps the rate in range.'}
              aria-label={customMove?.valid ? `Custom ${customLabel}; commit and advance one quarter` : 'Custom move unavailable'}
            >
              Commit
            </button>
          </div>
          <small id="custom-bps-status">{customLabel}</small>
        </div>
      </div>
      <div className={`policy-readiness readiness-${readiness.recommendedBias}`} aria-label="Policy readiness brief">
        <div title={readiness.summary}>
          <span>Decision brief</span>
          <strong>{readiness.headline}</strong>
        </div>
        <dl>
          {readiness.tiles.map((tile) => (
            <div key={tile.label} className={`readiness-tile tile-${tile.tone}`} title={tile.detail}>
              <dt>{tile.label}</dt>
              <dd>
                <strong>{tile.value}</strong>
              </dd>
            </div>
          ))}
        </dl>
      </div>
      <div className="control-grid policy-bps-stack">
        {actions.map((view) => {
          const Icon = view.direction === 'raise' ? ArrowUp : view.direction === 'cut' ? ArrowDown : Gauge
          return (
            <button
              key={view.action}
              type="button"
              className={`policy-button ${view.direction}`}
              onClick={() => onCommitDecision(view.action)}
              disabled={view.disabled}
              title={
                view.disabled
                  ? 'This move is unavailable at the current rate.'
                  : `${view.hint} ${formatPct(fedFundsRate)} to ${formatPct(view.resultingRate)}. ${view.macroSignal} Commits and advances one quarter.`
              }
              aria-label={`${view.label}; ${formatPct(fedFundsRate)} to ${formatPct(view.resultingRate)}; commit and advance one quarter`}
            >
              <Icon size={18} aria-hidden="true" />
              <span className="policy-button-main">
                <strong>{view.label}</strong>
              </span>
            </button>
          )
        })}
      </div>
      <p className="shortcut-note">Shortcuts work when focus is outside controls: R raises 25 bps, H holds, C cuts 25 bps.</p>
    </section>
  )
}
