export type SoundEvent =
  | 'game:start'
  | 'decision:select_raise'
  | 'decision:select_cut'
  | 'decision:select_hold'
  | 'decision:invalid'
  | 'quarter:advance'
  | 'shock:triggered'
  | 'news:warning'
  | 'news:critical'
  | 'term:completed_reappointed'
  | 'term:completed_not_reappointed'
  | 'export:success'
  | 'reset'

export type ToneStep = {
  frequency: number
  duration: number
  type?: OscillatorType
  gain?: number
}

export type SoundDefinition = {
  noisy?: boolean
  tones: ToneStep[]
}

export const soundDesign: Record<SoundEvent, SoundDefinition> = {
  'game:start': {
    tones: [
      { frequency: 440, duration: 0.08, type: 'sine', gain: 0.12 },
      { frequency: 660, duration: 0.1, type: 'sine', gain: 0.1 },
    ],
  },
  'decision:select_raise': {
    tones: [
      { frequency: 520, duration: 0.05, type: 'triangle', gain: 0.08 },
      { frequency: 700, duration: 0.06, type: 'triangle', gain: 0.07 },
    ],
  },
  'decision:select_cut': {
    tones: [
      { frequency: 700, duration: 0.05, type: 'triangle', gain: 0.08 },
      { frequency: 480, duration: 0.06, type: 'triangle', gain: 0.07 },
    ],
  },
  'decision:select_hold': {
    tones: [{ frequency: 420, duration: 0.07, type: 'sine', gain: 0.07 }],
  },
  'decision:invalid': {
    noisy: true,
    tones: [{ frequency: 170, duration: 0.06, type: 'square', gain: 0.04 }],
  },
  'quarter:advance': {
    tones: [
      { frequency: 180, duration: 0.04, type: 'triangle', gain: 0.08 },
      { frequency: 360, duration: 0.08, type: 'sine', gain: 0.06 },
    ],
  },
  'shock:triggered': {
    noisy: true,
    tones: [
      { frequency: 130, duration: 0.08, type: 'sawtooth', gain: 0.05 },
      { frequency: 96, duration: 0.1, type: 'triangle', gain: 0.05 },
    ],
  },
  'news:warning': {
    noisy: true,
    tones: [{ frequency: 260, duration: 0.11, type: 'triangle', gain: 0.07 }],
  },
  'news:critical': {
    noisy: true,
    tones: [
      { frequency: 180, duration: 0.08, type: 'triangle', gain: 0.07 },
      { frequency: 150, duration: 0.1, type: 'triangle', gain: 0.06 },
    ],
  },
  'term:completed_reappointed': {
    tones: [
      { frequency: 392, duration: 0.09, type: 'sine', gain: 0.1 },
      { frequency: 523, duration: 0.12, type: 'sine', gain: 0.1 },
      { frequency: 659, duration: 0.16, type: 'sine', gain: 0.08 },
    ],
  },
  'term:completed_not_reappointed': {
    tones: [
      { frequency: 330, duration: 0.11, type: 'sine', gain: 0.08 },
      { frequency: 247, duration: 0.16, type: 'sine', gain: 0.06 },
    ],
  },
  'export:success': {
    tones: [{ frequency: 720, duration: 0.06, type: 'sine', gain: 0.06 }],
  },
  reset: {
    tones: [
      { frequency: 360, duration: 0.07, type: 'triangle', gain: 0.06 },
      { frequency: 220, duration: 0.08, type: 'triangle', gain: 0.05 },
    ],
  },
}
