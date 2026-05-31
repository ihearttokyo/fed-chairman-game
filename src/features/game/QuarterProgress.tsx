export function QuarterProgress({ currentQuarter, totalQuarters }: { currentQuarter: number; totalQuarters: number }) {
  return (
    <div
      className="quarter-progress"
      role="progressbar"
      aria-label="Quarter progress"
      aria-valuemin={0}
      aria-valuemax={totalQuarters}
      aria-valuenow={currentQuarter}
      aria-valuetext={`Quarter ${currentQuarter} of ${totalQuarters}`}
    >
      {Array.from({ length: totalQuarters }, (_, index) => {
        const quarter = index + 1
        return (
          <span
            key={quarter}
            className={quarter <= currentQuarter ? 'complete' : quarter === currentQuarter + 1 ? 'next' : ''}
            aria-hidden="true"
          />
        )
      })}
    </div>
  )
}
