export type ThemeMode = 'light' | 'dark'

export const THEME_KEY = 'fed-chairman-theme'

export function systemTheme(): ThemeMode {
  return typeof window !== 'undefined' && window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

export function readStoredTheme(): ThemeMode {
  try {
    const stored = typeof localStorage === 'undefined' ? null : localStorage.getItem(THEME_KEY)
    return stored === 'dark' || stored === 'light' ? stored : systemTheme()
  } catch {
    return systemTheme()
  }
}

export function applyTheme(theme: ThemeMode): void {
  if (typeof document === 'undefined') {
    return
  }
  document.documentElement.dataset.theme = theme
  document.documentElement.style.colorScheme = theme
}

export function persistTheme(theme: ThemeMode): void {
  try {
    localStorage.setItem(THEME_KEY, theme)
  } catch {
    // Theme preference is progressive enhancement; blocked storage should not affect play.
  }
}
