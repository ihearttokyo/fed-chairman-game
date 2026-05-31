import { Download, FileJson, FileText, Save, Upload } from 'lucide-react'
import { useRef, useState } from 'react'
import { audioEngine } from '../../audio/audioEngine'
import { downloadText, sessionToCsv, sessionToJson, sessionToMarkdown } from '../../state/exporters'
import { useGameStore } from '../../state/gameStore'
import type { GameSession } from '../../types'

export function ExportControls({ session }: { session: GameSession }) {
  const fileInput = useRef<HTMLInputElement>(null)
  const exportSaveFile = useGameStore((state) => state.exportSaveFile)
  const importSaveFile = useGameStore((state) => state.importSaveFile)
  const [loadStatus, setLoadStatus] = useState<string | null>(null)

  function playSuccess(): void {
    audioEngine.play('export:success', session.ui)
  }

  async function savePortableFile(): Promise<void> {
    downloadText('fed-chairman-career.fedchair-save.json', await exportSaveFile(), 'application/json')
    playSuccess()
  }

  async function loadPortableFile(file: File | undefined): Promise<void> {
    if (!file) {
      return
    }
    const result = await importSaveFile(await file.text())
    if (result.ok) {
      setLoadStatus(`Save loaded: ${result.summary.label}.`)
      playSuccess()
      return
    }
    setLoadStatus(result.error)
  }

  return (
    <section className="panel export-panel command-card" aria-labelledby="export-title">
      <h2 id="export-title">Files</h2>
      <div className="export-buttons">
        <button type="button" onClick={() => void savePortableFile()}>
          <Save size={16} aria-hidden="true" />
          Save
        </button>
        <button type="button" onClick={() => fileInput.current?.click()}>
          <Upload size={16} aria-hidden="true" />
          Load save
        </button>
        <button
          type="button"
          onClick={() => {
            downloadText('fed-chairman-history.csv', sessionToCsv(session), 'text/csv')
            playSuccess()
          }}
        >
          <Download size={16} aria-hidden="true" />
          CSV
        </button>
        <button
          type="button"
          onClick={() => {
            downloadText('fed-chairman-session.json', sessionToJson(session), 'application/json')
            playSuccess()
          }}
        >
          <FileJson size={16} aria-hidden="true" />
          JSON
        </button>
        <button
          type="button"
          onClick={() => {
            downloadText('fed-chairman-debrief.md', sessionToMarkdown(session), 'text/markdown')
            playSuccess()
          }}
        >
          <FileText size={16} aria-hidden="true" />
          Markdown
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
    </section>
  )
}
