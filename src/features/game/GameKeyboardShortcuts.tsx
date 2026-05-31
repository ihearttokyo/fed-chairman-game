import { useEffect } from 'react'
import type { PolicyAction } from '../../types'

function isInteractiveTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) {
    return false
  }
  return Boolean(target.closest('input, textarea, select, button, a, summary, [role="button"], [contenteditable="true"]'))
}

export function GameKeyboardShortcuts({
  onSelectDecision,
}: {
  onSelectDecision: (action: PolicyAction) => void
}) {
  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent): void {
      if (isInteractiveTarget(event.target)) {
        return
      }
      if (event.key.toLowerCase() === 'r') {
        event.preventDefault()
        onSelectDecision('raise_25')
      }
      if (event.key.toLowerCase() === 'h') {
        event.preventDefault()
        onSelectDecision('hold')
      }
      if (event.key.toLowerCase() === 'c') {
        event.preventDefault()
        onSelectDecision('cut_25')
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [onSelectDecision])

  return null
}
