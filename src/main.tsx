import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { applyTheme, readStoredTheme } from './ui/theme'
import './index.css'
import App from './App.tsx'

applyTheme(readStoredTheme())

const rootElement = document.getElementById('root')

if (!rootElement) {
  throw new Error('Fed Chairman Game could not find the root mount node.')
}

createRoot(rootElement).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
