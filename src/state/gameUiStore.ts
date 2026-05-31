import { create } from 'zustand'

export type CinematicPhase = 'idle' | 'advancing' | 'quarter_reveal' | 'shock_reveal' | 'score_reveal'

type GameUiStore = {
  cinematicPhase: CinematicPhase
  lastAdvancedQuarter: number | null
  setCinematicPhase: (phase: CinematicPhase, quarter?: number | null) => void
  completeReveal: () => void
}

export const useGameUiStore = create<GameUiStore>((set) => ({
  cinematicPhase: 'idle',
  lastAdvancedQuarter: null,
  setCinematicPhase: (phase, quarter = null) => set({ cinematicPhase: phase, lastAdvancedQuarter: quarter }),
  completeReveal: () => set({ cinematicPhase: 'idle' }),
}))
