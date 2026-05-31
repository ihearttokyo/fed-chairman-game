import { Activity, BarChart3, Gauge, ShieldCheck, TrendingUp } from 'lucide-react'
import { formatPct, formatSigned } from '../../lib/format'
import { MandateMeter } from './MandateMeter'
import type { MetricView } from './metricViewModel'

const iconMap = {
  inflation: Activity,
  unemployment: Gauge,
  fedFundsRate: BarChart3,
  expectedInflation: TrendingUp,
  credibility: ShieldCheck,
}

function statusLabel(metric: MetricView): string {
  if (metric.status === 'good') {
    return 'near target'
  }
  if (metric.status === 'watch') {
    return metric.deviation >= 0 ? 'above target' : 'below target'
  }
  return metric.deviation >= 0 ? 'high risk' : 'low risk'
}

export function MetricCard({ metric }: { metric: MetricView }) {
  const Icon = iconMap[metric.id]
  const value = metric.suffix === '%' ? formatPct(metric.value) : metric.value.toFixed(0)
  return (
    <article className={`metric-card ${metric.status}`}>
      <div className="metric-icon" aria-hidden="true">
        <Icon size={22} />
      </div>
      <div className="metric-body">
        <div className="metric-title-row">
          <h2>{metric.label}</h2>
          <span className={`status-badge ${metric.status}`}>{statusLabel(metric)}</span>
        </div>
        <p className="metric-value">{value}</p>
        <p className="metric-target">
          {metric.targetLabel}
          {metric.id !== 'fedFundsRate' ? ` | ${formatSigned(metric.deviation)} from reference` : ''}
        </p>
        {metric.quarterDelta !== null ? (
          <p className={`metric-delta ${metric.quarterDelta > 0 ? 'up' : metric.quarterDelta < 0 ? 'down' : 'flat'}`}>
            {formatSigned(metric.quarterDelta)} {metric.suffix === '%' ? 'pp' : 'pts'} since last quarter
          </p>
        ) : null}
        <MandateMeter metric={metric} />
      </div>
    </article>
  )
}
