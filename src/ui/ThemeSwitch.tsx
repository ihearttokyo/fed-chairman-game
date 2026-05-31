import { Moon, Sun } from 'lucide-react'
import { useEffect, useState } from 'react'
import { applyTheme, persistTheme, readStoredTheme, type ThemeMode } from './theme'

export function ThemeSwitch() {
  const [theme, setTheme] = useState<ThemeMode>(readStoredTheme)
  const isDark = theme === 'dark'

  useEffect(() => {
    applyTheme(theme)
    persistTheme(theme)
  }, [theme])

  return (
    <label className="theme-switch">
      <input
        type="checkbox"
        role="switch"
        checked={isDark}
        onChange={(event) => setTheme(event.target.checked ? 'dark' : 'light')}
        aria-label="Use dark cockpit theme"
      />
      <span aria-hidden="true" className="theme-switch-track">
        <span className="theme-switch-thumb">{isDark ? <Moon size={13} /> : <Sun size={13} />}</span>
      </span>
      <span className="theme-switch-label">{isDark ? 'Dark' : 'Light'}</span>
    </label>
  )
}
