import { soundDesign, type SoundEvent } from './soundDesign'

type AudioContextConstructor = typeof AudioContext
type WebAudioWindow = Window & {
  AudioContext?: AudioContextConstructor
  webkitAudioContext?: AudioContextConstructor
}

export type AudioPreferences = {
  soundEnabled: boolean
  reducedNoise: boolean
  soundVolume: number
}

export class AudioEngine {
  private context: AudioContext | null = null
  private unlocked = false
  private activeNodes = 0
  private maxNodes = 24
  private unlockTimeoutMs = 750

  isUnlocked(): boolean {
    return this.unlocked
  }

  async unlock(): Promise<boolean> {
    const ContextClass = this.contextConstructor()
    if (!ContextClass) {
      return false
    }
    if (!this.context) {
      this.context = new ContextClass()
    }
    try {
      if (this.context.state === 'suspended') {
        await this.withTimeout(this.context.resume(), this.unlockTimeoutMs)
      }
      this.unlocked = this.context.state === 'running'
      return this.unlocked
    } catch {
      this.unlocked = false
      return false
    }
  }

  play(event: SoundEvent, preferences: AudioPreferences): void {
    if (!preferences.soundEnabled || this.activeNodes >= this.maxNodes) {
      return
    }
    const definition = soundDesign[event]
    if (!definition || (definition.noisy && preferences.reducedNoise)) {
      return
    }
    const context = this.context
    if (!context || !this.unlocked || context.state !== 'running') {
      return
    }

    let startTime = context.currentTime
    for (const tone of definition.tones) {
      const oscillator = context.createOscillator()
      const gain = context.createGain()
      const safeGain = Math.min(0.2, Math.max(0, (tone.gain ?? 0.08) * preferences.soundVolume))
      oscillator.type = tone.type ?? 'sine'
      oscillator.frequency.setValueAtTime(tone.frequency, startTime)
      gain.gain.setValueAtTime(0.0001, startTime)
      gain.gain.exponentialRampToValueAtTime(Math.max(0.0001, safeGain), startTime + 0.012)
      gain.gain.exponentialRampToValueAtTime(0.0001, startTime + tone.duration)
      oscillator.connect(gain)
      gain.connect(context.destination)
      oscillator.start(startTime)
      oscillator.stop(startTime + tone.duration + 0.02)
      this.activeNodes += 1
      oscillator.onended = () => {
        oscillator.disconnect()
        gain.disconnect()
        this.activeNodes = Math.max(0, this.activeNodes - 1)
      }
      startTime += tone.duration
    }
  }

  async resetForTests(): Promise<void> {
    const context = this.context
    this.context = null
    this.unlocked = false
    this.activeNodes = 0
    if (context && typeof context.close === 'function') {
      await context.close().catch(() => undefined)
    }
  }

  private contextConstructor(): AudioContextConstructor | null {
    if (typeof window === 'undefined') {
      return null
    }
    const audioWindow = window as WebAudioWindow
    return audioWindow.AudioContext ?? audioWindow.webkitAudioContext ?? null
  }

  private async withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
    let timeoutId: ReturnType<typeof window.setTimeout> | undefined
    try {
      return await Promise.race([
        promise,
        new Promise<never>((_, reject) => {
          timeoutId = window.setTimeout(() => reject(new Error('Audio unlock timed out')), timeoutMs)
        }),
      ])
    } finally {
      if (timeoutId !== undefined) {
        window.clearTimeout(timeoutId)
      }
    }
  }
}

export const audioEngine = new AudioEngine()
