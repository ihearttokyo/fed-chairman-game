import Foundation

public let classicScenario = ScenarioConfig(
    id: "classic_normal_cycle",
    label: "Classic Normal Cycle",
    mode: .classicChairTheFed,
    termQuarters: 16,
    startingState: MacroState(
        quarterIndex: 0,
        quartersRemaining: 16,
        inflation: 2.11,
        unemployment: 4.68,
        fedFundsRate: 4,
        outputGap: 0.2,
        gdpGrowth: 2.1,
        expectedInflation: 2.15,
        credibility: 82,
    ),
    targets: MandateTargets(inflation: 2, unemployment: 5),
    coefficients: ModelCoefficients(
        realNeutralRate: 1.5,
        trendGrowth: 2,
        rateSensitivity: 0.28,
        inflationRateSensitivity: 0.18,
        phillipsSlope: 0.13,
        okunCoefficient: 0.36,
        shockDecay: 0.58,
        noiseScale: 0.06,
    ),
    shockDeck: [],
    allowedTools: ["fed_funds_rate"],
    difficulty: "standard",
    summary: "A 16-quarter clean-room classic mode focused on the inflation and unemployment tradeoff.",
)

private struct ShockTemplate {
    let id: String
    let type: ShockType
    let headlineKey: String
    let magnitude: ClosedRange<Double>
    let persistence: ClosedRange<Int>
}

private let shockTemplates: [ShockTemplate] = [
    ShockTemplate(id: "energy-price-squeeze", type: .energy, headlineKey: "energy", magnitude: 0.85 ... 1.35, persistence: 2 ... 3),
    ShockTemplate(id: "household-demand-softens", type: .demand, headlineKey: "demandSoft", magnitude: -1.2 ... -0.65, persistence: 2 ... 3),
    ShockTemplate(id: "credit-markets-tighten", type: .financial, headlineKey: "financial", magnitude: -1.25 ... -0.75, persistence: 2 ... 4),
    ShockTemplate(id: "supply-chain-snarls", type: .supply, headlineKey: "supply", magnitude: 0.55 ... 1.05, persistence: 2 ... 3),
    ShockTemplate(id: "labor-market-heats-up", type: .labor, headlineKey: "labor", magnitude: 0.5 ... 0.95, persistence: 2 ... 3),
    ShockTemplate(id: "confidence-slide", type: .confidence, headlineKey: "confidence", magnitude: -1.0 ... -0.45, persistence: 2 ... 3),
]

public func getScenario(id: String = "classic_normal_cycle") throws -> ScenarioConfig {
    guard id == classicScenario.id else {
        throw NativeEngineError.unknownScenario(id)
    }
    return classicScenario
}

private func pickQuarter(rng: inout SeededRng, min: Int, max: Int) -> Int {
    Int(floor(rng.between(Double(min), Double(max + 1))))
}

public func buildTermShockDeck(seed: String, termNumber: Int) -> [Shock] {
    var rng = SeededRng(seed: "\(seed):term-\(termNumber):shock-deck")
    let windows = [(3, 5), (7, 9), (11, 13), (14, 16)]
    let offset = Int(floor(rng.between(0, Double(shockTemplates.count))))
    let firstTermShockScale = termNumber == 1 ? 0.72 : 1.0
    return windows.enumerated().map { index, window in
        let template = shockTemplates[(offset + index) % shockTemplates.count]
        let magnitude = rng.between(template.magnitude.lowerBound, template.magnitude.upperBound) * firstTermShockScale
        let persistence = pickQuarter(rng: &rng, min: template.persistence.lowerBound, max: template.persistence.upperBound)
        return Shock(
            id: "\(template.id)-t\(termNumber)-\(index + 1)",
            quarter: .fixed(pickQuarter(rng: &rng, min: window.0, max: window.1)),
            type: template.type,
            magnitude: Double(String(format: "%.2f", magnitude)) ?? roundTo(magnitude),
            persistence: persistence,
            headlineKey: template.headlineKey,
        )
    }
}

public func getTermScenario(id: String = "classic_normal_cycle", seed: String = "classic-2026", termNumber: Int = 1) throws -> ScenarioConfig {
    var scenario = try getScenario(id: id)
    scenario.shockDeck = buildTermShockDeck(seed: seed, termNumber: termNumber)
    return scenario
}

public enum NativeEngineError: Error, Equatable {
    case unknownScenario(String)
    case missingHistory
    case invalidPolicyMove
    case unsupportedSaveFile
    case tamperedSaveFile
}
