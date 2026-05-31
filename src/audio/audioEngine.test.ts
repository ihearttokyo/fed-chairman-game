import { afterEach, describe, expect, it, vi } from 'vitest'
import { AudioEngine } from './audioEngine'

const originalAudioContext = window.AudioContext
const originalWebkitAudioContext = (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext

class FakeAudioParam {
  setValueAtTime = vi.fn()
  exponentialRampToValueAtTime = vi.fn()
}

class FakeOscillator {
  type: OscillatorType = 'sine'
  frequency = new FakeAudioParam()
  connect = vi.fn()
  disconnect = vi.fn()
  start = vi.fn()
  stop = vi.fn()
}

class FakeGain {
  gain = new FakeAudioParam()
  connect = vi.fn()
  disconnect = vi.fn()
}

class FakeAudioContext {
  state: AudioContextState = 'running'
  currentTime = 1
  destination = {}
  createdOscillators = 0
  close = vi.fn(async () => undefined)
  resume = vi.fn(async () => {
    this.state = 'running'
  })
  createOscillator(): FakeOscillator {
    this.createdOscillators += 1
    return new FakeOscillator()
  }
  createGain(): FakeGain {
    return new FakeGain()
  }
}

class HangingAudioContext extends FakeAudioContext {
  state: AudioContextState = 'suspended'
  resume = vi.fn(() => new Promise<void>(() => undefined))
}

function installAudioContext(instance: FakeAudioContext): void {
  const Constructor = vi.fn(function FakeAudioContextConstructor() {
    return instance
  })
  Object.defineProperty(window, 'AudioContext', {
    configurable: true,
    value: Constructor as unknown as typeof AudioContext,
  })
  Object.defineProperty(window, 'webkitAudioContext', {
    configurable: true,
    value: undefined,
  })
}

describe('AudioEngine', () => {
  afterEach(() => {
    Object.defineProperty(window, 'AudioContext', {
      configurable: true,
      value: originalAudioContext,
    })
    Object.defineProperty(window, 'webkitAudioContext', {
      configurable: true,
      value: originalWebkitAudioContext,
    })
    vi.restoreAllMocks()
  })

  it('fails closed when no Web Audio constructor is available', async () => {
    Object.defineProperty(window, 'AudioContext', { configurable: true, value: undefined })
    Object.defineProperty(window, 'webkitAudioContext', { configurable: true, value: undefined })

    const engine = new AudioEngine()

    await expect(engine.unlock()).resolves.toBe(false)
    expect(engine.isUnlocked()).toBe(false)
  })

  it('fails closed when Web Audio unlock never resolves', async () => {
    vi.useFakeTimers()
    const context = new HangingAudioContext()
    installAudioContext(context)
    const engine = new AudioEngine()

    const unlock = engine.unlock()
    await vi.advanceTimersByTimeAsync(800)

    await expect(unlock).resolves.toBe(false)
    expect(engine.isUnlocked()).toBe(false)
    vi.useRealTimers()
  })

  it('plays enabled quiet events and suppresses reduced-noise events', async () => {
    const context = new FakeAudioContext()
    installAudioContext(context)
    const engine = new AudioEngine()

    await expect(engine.unlock()).resolves.toBe(true)
    engine.play('export:success', { soundEnabled: true, reducedNoise: true, soundVolume: 0.5 })
    engine.play('shock:triggered', { soundEnabled: true, reducedNoise: true, soundVolume: 0.5 })

    expect(context.createdOscillators).toBe(1)
  })

  it('closes an existing context when reset for tests', async () => {
    const context = new FakeAudioContext()
    installAudioContext(context)
    const engine = new AudioEngine()

    await engine.unlock()
    await engine.resetForTests()

    expect(context.close).toHaveBeenCalledTimes(1)
    expect(engine.isUnlocked()).toBe(false)
  })
})
