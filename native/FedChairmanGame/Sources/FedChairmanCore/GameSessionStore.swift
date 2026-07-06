import Combine
import Foundation

public final class GameSessionStore: ObservableObject {
    @Published public private(set) var session: GameSession

    public init(session: GameSession = makeInitialSession()) {
        self.session = session
    }

    public func start(seed: String = "classic-2026") {
        var next = Self.makeInitialSession(seed: seed)
        next.status = .inProgress
        session = next
    }

    public func commit(action: PolicyAction) throws {
        guard let next = try advancedSession(session: session, action: action) else {
            return
        }
        session = next
    }

    public func commitCustom(rateChange: Double) throws {
        let bps = (rateChange * 100).rounded()
        guard abs(bps) <= 300, abs(rateChange * 100 - bps) <= 0.000_000_001 else {
            return
        }
        guard let next = try advancedSession(session: session, action: .custom, customRateChange: bps / 100) else {
            return
        }
        session = next
    }

    public func continueNextTerm() throws {
        guard session.status == .termDebrief, session.score.reappointed else {
            return
        }
        let scenario = try getScenario(id: session.scenarioId)
        let startingState = resetForNextTerm(state: session.current, termQuarters: scenario.termQuarters)
        let termHistory = [startingState]
        let termScore = evaluateScore(
            history: termHistory,
            scenario: scenario,
            inflationUpperBound: reappointmentInflationUpperBound,
        )
        session.status = .inProgress
        session.termNumber += 1
        session.currentTermQuarter = 0
        session.current = startingState
        session.history = termHistory
        session.decisions = []
        session.traces = []
        session.activeShocks = []
        session.latestTriggeredShocks = []
        session.score = termScore
        session.ui.selectedDecision = nil
        session.ui.chartView = "chart"
    }

    public func retireCareer() {
        guard session.status == .termDebrief, session.score.reappointed, session.completedTerms.count >= 2 else {
            return
        }
        session.status = .retired
        session.score = session.careerScore
        session.ui.selectedDecision = nil
    }

    public func reset() {
        session = Self.makeInitialSession()
    }

    public func load(session loadedSession: GameSession) throws {
        session = try recomputeSessionScores(loadedSession)
    }

    public func setReducedMotion(_ enabled: Bool) {
        session.ui.reducedMotion = enabled
    }

    public func setSoundEnabled(_ enabled: Bool) {
        session.ui.soundEnabled = enabled
    }

    public func setReducedNoise(_ enabled: Bool) {
        session.ui.reducedNoise = enabled
    }

    public func setSoundVolume(_ value: Double) {
        session.ui.soundVolume = min(1, max(0, value))
    }

    public static func makeInitialSession(seed: String = "classic-2026") -> GameSession {
        let scenario = classicScenario
        let history = [scenario.startingState]
        let score = evaluateScore(history: history, scenario: scenario)
        return GameSession(
            sessionId: "session-\(seed)",
            mode: .classicChairTheFed,
            scenarioId: scenario.id,
            status: .notStarted,
            seed: seed,
            termNumber: 1,
            currentTermQuarter: 0,
            totalCareerQuarters: 0,
            completedTerms: [],
            careerHistory: history,
            careerScore: score,
            current: scenario.startingState,
            history: history,
            decisions: [],
            traces: [],
            activeShocks: [],
            latestTriggeredShocks: [],
            score: score,
            ui: .default,
        )
    }

    private static func resetForNextTerm(state: MacroState, termQuarters: Int) -> MacroState {
        var next = state
        next.quarterIndex = 0
        next.quartersRemaining = termQuarters
        return next
    }

    private func resetForNextTerm(state: MacroState, termQuarters: Int) -> MacroState {
        Self.resetForNextTerm(state: state, termQuarters: termQuarters)
    }

    private func advancedSession(session: GameSession, action: PolicyAction, customRateChange: Double? = nil) throws -> GameSession? {
        guard session.status == .inProgress else {
            return nil
        }
        let scenario = try getTermScenario(id: session.scenarioId, seed: session.seed, termNumber: session.termNumber)
        let decision = createDecision(action: action, current: session.current, customRateChange: customRateChange)
        guard decision.resultingFedFundsRate >= 0, decision.resultingFedFundsRate <= 20 else {
            return nil
        }
        let advanced = try advanceQuarter(
            history: session.history,
            decision: decision,
            scenario: scenario,
            activeShocks: session.activeShocks,
            seed: "\(session.seed):term-\(session.termNumber)",
            termNumber: session.termNumber,
            ui: session.ui,
            careerQuarterIndex: session.totalCareerQuarters + 1,
        )
        let decisionWithCareerIndex = PolicyDecision(
            id: decision.id,
            quarterIndex: decision.quarterIndex,
            careerQuarterIndex: session.totalCareerQuarters + 1,
            action: decision.action,
            rateChange: decision.rateChange,
            resultingFedFundsRate: decision.resultingFedFundsRate,
            timestamp: decision.timestamp,
        )
        let history = session.history + [advanced.nextState]
        let decisions = session.decisions + [decisionWithCareerIndex]
        let traces = session.traces + [advanced.trace]
        let careerHistory = session.careerHistory + [advanced.nextState]
        let completedTerm = advanced.nextState.quartersRemaining == 0
        let score = evaluateScore(
            history: history,
            scenario: scenario,
            inflationUpperBound: reappointmentInflationUpperBound,
        )
        let careerScore = try evaluateScore(history: careerHistory, scenario: getScenario(id: session.scenarioId))
        let termSummary = completedTerm
            ? CompletedTermSummary(
                termNumber: session.termNumber,
                startingState: history[0],
                endingState: advanced.nextState,
                history: history,
                decisions: decisions,
                traces: traces,
                score: score,
                reappointed: score.reappointed,
            )
            : nil
        var next = session
        next.status = completedTerm ? (score.reappointed ? .termDebrief : .notReappointed) : .inProgress
        next.currentTermQuarter = advanced.nextState.quarterIndex
        next.totalCareerQuarters += 1
        if let termSummary {
            next.completedTerms.append(termSummary)
        }
        next.careerHistory = careerHistory
        next.careerScore = careerScore
        next.current = advanced.nextState
        next.history = history
        next.decisions = decisions
        next.traces = traces
        next.activeShocks = advanced.activeShocks
        next.latestTriggeredShocks = advanced.triggeredShocks
        next.score = score
        next.ui.selectedDecision = nil
        return next
    }
}

public func makeInitialSession(seed: String = "classic-2026") -> GameSession {
    GameSessionStore.makeInitialSession(seed: seed)
}
