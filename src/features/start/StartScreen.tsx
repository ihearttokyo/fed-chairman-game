import { Upload } from 'lucide-react'
import { useRef, useState } from 'react'
import { audioEngine } from '../../audio/audioEngine'
import { useGameStore } from '../../state/gameStore'
import { BrandMark } from '../../ui/BrandMark'
import { ThemeSwitch } from '../../ui/ThemeSwitch'

export function StartScreen() {
  const fileInput = useRef<HTMLInputElement>(null)
  const startGame = useGameStore((state) => state.startGame)
  const loadSavedGame = useGameStore((state) => state.loadSavedGame)
  const importSaveFile = useGameStore((state) => state.importSaveFile)
  const hasSavedGame = useGameStore((state) => state.hasSavedGame)
  const [seed, setSeed] = useState('classic-2026')
  const [loadStatus, setLoadStatus] = useState<string | null>(null)

  async function start(): Promise<void> {
    startGame(seed || 'classic-2026')
  }

  async function resume(): Promise<void> {
    const loaded = loadSavedGame()
    const loadedSession = useGameStore.getState().session
    if (loaded && loadedSession.ui.soundEnabled) {
      await audioEngine.unlock()
      if (audioEngine.isUnlocked()) {
        audioEngine.play('game:start', loadedSession.ui)
      } else {
        useGameStore.getState().setSoundEnabled(false)
      }
    }
  }

  async function loadPortableFile(file: File | undefined): Promise<void> {
    if (!file) {
      return
    }
    const result = await importSaveFile(await file.text())
    setLoadStatus(result.ok ? `Save loaded: ${result.summary.label}.` : result.error)
  }

  return (
    <main className="start-shell" aria-labelledby="start-title">
      <section className="start-panel command-card">
        <div className="start-toolbar">
          <ThemeSwitch />
        </div>
        <div className="start-art" aria-hidden="true">
          <div className="radar-ring" />
          <BrandMark size={88} />
          <div className="lag-wave" />
        </div>
        <p className="eyebrow">Clean-room policy command simulation</p>
        <h1 id="start-title">Classic Monetary Policy Mode</h1>
        <p className="start-copy">
          A four-year Fed Chair term where every rate move, shock, and lag shows up in the mandate dashboard. Earn
          reappointment to keep the career going.
        </p>
        <div className="start-grid" aria-label="Classic starting conditions">
          <span>
            Inflation starts at <strong>2.11%</strong>
          </span>
          <span>
            Unemployment starts at <strong>4.68%</strong>
          </span>
          <span>
            Fed funds starts at <strong>4.00%</strong>
          </span>
        </div>
        <label className="seed-field">
          Shared seed
          <input value={seed} onChange={(event) => setSeed(event.target.value)} aria-label="Shared seed" />
        </label>
        <div className="button-row">
          <button className="primary-button" type="button" onClick={start}>
            Start term
          </button>
          <button className="secondary-button" type="button" disabled={!hasSavedGame} onClick={resume}>
            Resume saved term
          </button>
          <button className="secondary-button" type="button" onClick={() => fileInput.current?.click()} title="Load a portable .fedchair-save.json file.">
            <Upload size={16} aria-hidden="true" />
            Load save
          </button>
        </div>
        <input
          ref={fileInput}
          className="sr-only"
          type="file"
          accept=".json,.fedchair-save.json,application/json"
          aria-label="Load Fed Chairman save file"
          onChange={(event) => {
            void loadPortableFile(event.currentTarget.files?.[0])
            event.currentTarget.value = ''
          }}
        />
        {loadStatus ? <p className="file-status" aria-live="polite">{loadStatus}</p> : null}
        <p className="disclaimer">
          Independent educational simulation. Not affiliated with, sponsored by, endorsed by, or approved by the Board of
          Governors of the Federal Reserve System, any Federal Reserve Bank, or the original Chair the Fed game.
        </p>
      </section>
    </main>
  )
}
