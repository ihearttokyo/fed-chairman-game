import { RotateCcw } from 'lucide-react'
import { BrandMark } from '../../ui/BrandMark'
import { ThemeSwitch } from '../../ui/ThemeSwitch'
import { QuarterProgress } from './QuarterProgress'
import { SoundControls } from './SoundControls'

export function GameHeader({
  scenarioLabel,
  termNumber,
  currentQuarter,
  totalQuarters,
  totalCareerQuarters,
  onReset,
}: {
  scenarioLabel: string
  termNumber: number
  currentQuarter: number
  totalQuarters: number
  totalCareerQuarters: number
  onReset: () => void
}) {
  return (
    <header className="app-header">
      <div className="title-lockup">
        <BrandMark size={52} />
        <div>
          <p className="eyebrow">Classic Monetary Policy Mode</p>
          <h1>Classic Monetary Policy Mode</h1>
        </div>
      </div>
      <div className="header-meta" aria-label="Game status">
        <span>{scenarioLabel}</span>
        <span>Term {termNumber}</span>
        <span>
          Quarter {currentQuarter} of {totalQuarters}
        </span>
        <span>{totalCareerQuarters} career quarters</span>
        <QuarterProgress currentQuarter={currentQuarter} totalQuarters={totalQuarters} />
        <ThemeSwitch />
        <SoundControls />
        <button type="button" className="ghost-button" onClick={onReset}>
          <RotateCcw size={16} aria-hidden="true" />
          Reset
        </button>
      </div>
    </header>
  )
}
