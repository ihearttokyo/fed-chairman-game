import './index.css'
import { GameScreen } from './features/game/GameScreen'
import { StartScreen } from './features/start/StartScreen'
import { useGameStore } from './state/gameStore'

function App() {
  const session = useGameStore((state) => state.session)
  return session.status === 'not_started' ? <StartScreen /> : <GameScreen />
}

export default App
