import { formatPct, formatSigned } from '../../lib/format'
import type { TraceReadout as TraceReadoutModel } from './briefingViewModel'

export function TraceReadout({ readout }: { readout: TraceReadoutModel | null }) {
  if (!readout) {
    return null
  }
  return (
    <div className="trace-readout" aria-label="What moved this quarter">
      <h3>What moved this quarter</h3>
      <dl>
        <div>
          <dt>Policy lag</dt>
          <dd>{readout.policyLag}</dd>
        </div>
        <div>
          <dt>Largest shock</dt>
          <dd>{readout.largestShock}</dd>
        </div>
        <div>
          <dt>Inflation change</dt>
          <dd>{formatSigned(readout.inflationDelta)} pp</dd>
        </div>
        <div>
          <dt>Unemployment change</dt>
          <dd>{formatSigned(readout.unemploymentDelta)} pp</dd>
        </div>
        <div>
          <dt>GDP growth change</dt>
          <dd>{formatPct(readout.gdpDelta)}</dd>
        </div>
        <div>
          <dt>Credibility change</dt>
          <dd title={readout.credibilityDetail}>{formatSigned(readout.credibilityDelta)} pts</dd>
        </div>
      </dl>
      <div className="trace-drivers" aria-label="Quarter driver contribution bars">
        {readout.drivers.map((driver) => (
          <div key={driver.label} className={`trace-driver trace-driver-${driver.tone}`}>
            <span className="trace-driver-label">{driver.label}</span>
            <span className="trace-driver-bar" aria-hidden="true">
              <span style={{ width: `${driver.width}%` }} />
            </span>
            <strong>{driver.display}</strong>
            <small>{driver.detail}</small>
          </div>
        ))}
      </div>
      <p>{readout.explanation}</p>
    </div>
  )
}
