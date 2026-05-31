import { MetricCard } from './MetricCard'
import type { MetricView } from './metricViewModel'

export function MetricsStrip({ metrics }: { metrics: MetricView[] }) {
  return (
    <section className="metrics" aria-label="Current macro indicators">
      {metrics.map((metric) => (
        <MetricCard key={metric.id} metric={metric} />
      ))}
    </section>
  )
}
