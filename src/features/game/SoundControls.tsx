import { Volume1, Volume2, VolumeX } from 'lucide-react'
import { audioEngine } from '../../audio/audioEngine'
import { useGameStore } from '../../state/gameStore'

export function SoundControls() {
  const session = useGameStore((state) => state.session)
  const setSoundEnabled = useGameStore((state) => state.setSoundEnabled)
  const setReducedNoise = useGameStore((state) => state.setReducedNoise)
  const setSoundVolume = useGameStore((state) => state.setSoundVolume)
  const Icon = session.ui.soundEnabled ? Volume2 : VolumeX

  async function toggleSound(): Promise<void> {
    const next = !session.ui.soundEnabled
    if (!next) {
      setSoundEnabled(false)
      return
    }
    const unlocked = await audioEngine.unlock()
    setSoundEnabled(unlocked)
    if (unlocked) {
      audioEngine.play('game:start', {
        soundEnabled: true,
        reducedNoise: session.ui.reducedNoise,
        soundVolume: session.ui.soundVolume,
      })
    }
  }

  return (
    <div className="sound-controls" aria-label="Sound controls">
      <button type="button" className="ghost-button icon-only" onClick={toggleSound} aria-pressed={session.ui.soundEnabled}>
        <Icon size={16} aria-hidden="true" />
        <span>{session.ui.soundEnabled ? 'Mute' : 'Sound'}</span>
      </button>
      <label>
        <Volume1 size={14} aria-hidden="true" />
        <input
          type="range"
          min="0"
          max="1"
          step="0.05"
          value={session.ui.soundVolume}
          onChange={(event) => setSoundVolume(Number(event.target.value))}
          disabled={!session.ui.soundEnabled}
          aria-label="Sound volume"
        />
      </label>
      <label className="toggle-label">
        <input
          type="checkbox"
          checked={session.ui.reducedNoise}
          onChange={(event) => setReducedNoise(event.target.checked)}
        />
        Reduced noise
      </label>
    </div>
  )
}
