import { formatPct } from '../../lib/format'
import type { MacroState } from '../../types'
import type { CareerTimelinePoint } from './careerTimeline'

type HistoryRow = MacroState | CareerTimelinePoint

function rowLabel(state: HistoryRow): string {
  return 'label' in state ? state.label : `Q${state.quarterIndex}`
}

function careerQuarter(state: HistoryRow): string {
  return 'careerQuarter' in state && state.termQuarter > 0 ? String(state.careerQuarter) : ''
}

function policyAction(state: HistoryRow): string {
  return 'decisionLabel' in state && state.decisionLabel ? state.decisionLabel : 'Start'
}

export function HistoryTable({ history, className }: { history: HistoryRow[]; className?: string }) {
  const isScreenReaderOnly = className?.split(' ').includes('sr-table') === true
  return (
    <div className={className ? `table-wrap ${className}` : 'table-wrap'} tabIndex={isScreenReaderOnly ? undefined : 0}>
      <table>
        <caption>Quarterly macroeconomic history</caption>
        <thead>
          <tr>
            <th>Quarter</th>
            <th>Career Q</th>
            <th>Policy</th>
            <th>Inflation</th>
            <th>Unemployment</th>
            <th>Fed funds</th>
            <th>Output gap</th>
            <th>Expectations</th>
            <th>Credibility</th>
          </tr>
        </thead>
        <tbody>
          {history.map((state) => (
            <tr key={'key' in state ? state.key : state.quarterIndex} className={'isTermStart' in state && state.isTermStart ? 'term-boundary-row' : undefined}>
              <td>{rowLabel(state)}</td>
              <td>{careerQuarter(state)}</td>
              <td>
                <span className={'decisionTone' in state ? `policy-table-chip policy-${state.decisionTone}` : 'policy-table-chip policy-none'}>
                  {policyAction(state)}
                </span>
              </td>
              <td>{formatPct(state.inflation)}</td>
              <td>{formatPct(state.unemployment)}</td>
              <td>{formatPct(state.fedFundsRate)}</td>
              <td>{formatPct(state.outputGap)}</td>
              <td>{formatPct(state.expectedInflation)}</td>
              <td>{state.credibility.toFixed(0)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
