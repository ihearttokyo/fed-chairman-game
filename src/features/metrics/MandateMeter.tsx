import { classNames } from '../../lib/format'
import type { MetricView } from './metricViewModel'

export function MandateMeter({ metric }: { metric: MetricView }) {
  const normalized = Math.max(0, Math.min(100, 50 + metric.deviation * 18))
  return (
    <div className={classNames('mandate-meter', metric.status)} aria-hidden="true">
      <span className="meter-target" />
      <span className="meter-needle" style={{ left: `${normalized}%` }} />
    </div>
  )
}
