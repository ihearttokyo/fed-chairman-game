import Foundation

public enum GameMode: String, Codable, Sendable {
    case classicChairTheFed = "classic_chair_the_fed"
}

public enum PolicyAction: String, Codable, CaseIterable, Sendable {
    case cut150 = "cut_150"
    case cut100 = "cut_100"
    case cut75 = "cut_75"
    case cut50 = "cut_50"
    case cut25 = "cut_25"
    case hold
    case raise25 = "raise_25"
    case raise50 = "raise_50"
    case raise75 = "raise_75"
    case raise100 = "raise_100"
    case raise150 = "raise_150"
    case custom
}

public enum ShockType: String, Codable, CaseIterable, Sendable {
    case demand
    case supply
    case financial
    case labor
    case energy
    case confidence
}

public enum CareerStatus: String, Codable, Sendable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case termDebrief = "term_debrief"
    case retired
    case notReappointed = "not_reappointed"
}

public enum Grade: String, Codable, Sendable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case f = "F"
}

public struct PolicyDecision: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var quarterIndex: Int
    public var careerQuarterIndex: Int?
    public var action: PolicyAction
    public var rateChange: Double
    public var resultingFedFundsRate: Double
    public var timestamp: String

    public init(
        id: String,
        quarterIndex: Int,
        careerQuarterIndex: Int? = nil,
        action: PolicyAction,
        rateChange: Double,
        resultingFedFundsRate: Double,
        timestamp: String,
    ) {
        self.id = id
        self.quarterIndex = quarterIndex
        self.careerQuarterIndex = careerQuarterIndex
        self.action = action
        self.rateChange = rateChange
        self.resultingFedFundsRate = resultingFedFundsRate
        self.timestamp = timestamp
    }
}

public struct MacroState: Codable, Equatable, Sendable {
    public var quarterIndex: Int
    public var quartersRemaining: Int
    public var inflation: Double
    public var unemployment: Double
    public var fedFundsRate: Double
    public var outputGap: Double
    public var gdpGrowth: Double
    public var expectedInflation: Double
    public var credibility: Double
    public var longRate: Double?
    public var marketIndex: Double?
    public var confidence: Double?

    public init(
        quarterIndex: Int,
        quartersRemaining: Int,
        inflation: Double,
        unemployment: Double,
        fedFundsRate: Double,
        outputGap: Double,
        gdpGrowth: Double,
        expectedInflation: Double,
        credibility: Double,
        longRate: Double? = nil,
        marketIndex: Double? = nil,
        confidence: Double? = nil,
    ) {
        self.quarterIndex = quarterIndex
        self.quartersRemaining = quartersRemaining
        self.inflation = inflation
        self.unemployment = unemployment
        self.fedFundsRate = fedFundsRate
        self.outputGap = outputGap
        self.gdpGrowth = gdpGrowth
        self.expectedInflation = expectedInflation
        self.credibility = credibility
        self.longRate = longRate
        self.marketIndex = marketIndex
        self.confidence = confidence
    }
}

public struct Shock: Codable, Equatable, Sendable, Identifiable {
    public enum Quarter: Codable, Equatable, Sendable {
        case fixed(Int)
        case random

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Int.self) {
                self = .fixed(value)
                return
            }
            if (try? container.decode(String.self)) == "random" {
                self = .random
                return
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid shock quarter.")
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .fixed(value):
                try container.encode(value)
            case .random:
                try container.encode("random")
            }
        }
    }

    public var id: String
    public var quarter: Quarter
    public var type: ShockType
    public var magnitude: Double
    public var persistence: Int
    public var headlineKey: String

    public init(id: String, quarter: Quarter, type: ShockType, magnitude: Double, persistence: Int, headlineKey: String) {
        self.id = id
        self.quarter = quarter
        self.type = type
        self.magnitude = magnitude
        self.persistence = persistence
        self.headlineKey = headlineKey
    }
}

public struct ActiveShock: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var quarter: Shock.Quarter
    public var type: ShockType
    public var magnitude: Double
    public var persistence: Int
    public var headlineKey: String
    public var startedQuarter: Int
    public var remaining: Int

    public init(shock: Shock, startedQuarter: Int, remaining: Int) {
        id = shock.id
        quarter = shock.quarter
        type = shock.type
        magnitude = shock.magnitude
        persistence = shock.persistence
        headlineKey = shock.headlineKey
        self.startedQuarter = startedQuarter
        self.remaining = remaining
    }
}

public struct ModelCoefficients: Codable, Equatable, Sendable {
    public var realNeutralRate: Double
    public var trendGrowth: Double
    public var rateSensitivity: Double
    public var inflationRateSensitivity: Double
    public var phillipsSlope: Double
    public var okunCoefficient: Double
    public var shockDecay: Double
    public var noiseScale: Double
}

public struct ScenarioConfig: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var mode: GameMode
    public var termQuarters: Int
    public var startingState: MacroState
    public var targets: MandateTargets
    public var coefficients: ModelCoefficients
    public var shockDeck: [Shock]
    public var allowedTools: [String]
    public var difficulty: String
    public var summary: String
}

public struct MandateTargets: Codable, Equatable, Sendable {
    public var inflation: Double
    public var unemployment: Double
}

public struct EngineTrace: Codable, Equatable, Sendable {
    public var neutralRate: Double
    public var policyGap: Double
    public var laggedPolicyGap: Double
    public var shockContrib: [String: Double]
    public var credibilityBaseDrift: Double?
    public var credibilityRateMoveCost: Double?
    public var credibilityReappointmentGrace: Double?
    public var credibilityDelta: Double?
    public var inflationDelta: Double
    public var unemploymentDelta: Double
    public var gdpDelta: Double
    public var explanation: String
}

public struct AdvanceResult: Equatable, Sendable {
    public var nextState: MacroState
    public var trace: EngineTrace
    public var activeShocks: [ActiveShock]
    public var triggeredShocks: [Shock]
}

public struct ScoreState: Codable, Equatable, Sendable {
    public var score: Double
    public var grade: Grade
    public var reappointed: Bool
    public var meanAbsInflationGap: Double
    public var meanAbsUnemploymentGap: Double
    public var volatilityIndex: Double
    public var recessionQuarterShare: Double
    public var credibilityBonus: Double
    public var biggestMiss: String
    public var takeaway: String
}

public struct CompletedTermSummary: Codable, Equatable, Sendable {
    public var termNumber: Int
    public var startingState: MacroState
    public var endingState: MacroState
    public var history: [MacroState]
    public var decisions: [PolicyDecision]
    public var traces: [EngineTrace]
    public var score: ScoreState
    public var reappointed: Bool
}

public struct UiState: Codable, Equatable, Sendable {
    public var selectedDecision: PolicyAction?
    public var chartView: String
    public var reducedMotion: Bool
    public var soundEnabled: Bool
    public var reducedNoise: Bool
    public var soundVolume: Double

    public static let `default` = UiState(
        selectedDecision: nil,
        chartView: "chart",
        reducedMotion: false,
        soundEnabled: false,
        reducedNoise: false,
        soundVolume: 0.25,
    )
}

public struct GameSession: Codable, Equatable, Sendable {
    public static let currentEngineModelVersion = "classic-macro-v1"

    public var sessionId: String
    public var mode: GameMode
    public var scenarioId: String
    public var status: CareerStatus
    public var seed: String
    public var termNumber: Int
    public var currentTermQuarter: Int
    public var totalCareerQuarters: Int
    public var completedTerms: [CompletedTermSummary]
    public var careerHistory: [MacroState]
    public var careerScore: ScoreState
    public var current: MacroState
    public var history: [MacroState]
    public var decisions: [PolicyDecision]
    public var traces: [EngineTrace]
    public var activeShocks: [ActiveShock]
    public var latestTriggeredShocks: [Shock]
    public var score: ScoreState
    public var ui: UiState
    /// Optional so legacy envelopes decode cleanly and can be rejected after digest verification.
    public var engineModelVersion: String?
}
