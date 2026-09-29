import Foundation

/// Compile with the unchanged production Core sources, not a rewritten simulator.
@main
enum LegacyModelAudit {
    static func main() throws {
        let policies = ["hold", "cut50_then_hold", "raise50_then_hold", "balanced_feedback", "inflation_feedback"]
        let seedCount = 500
        var summaries: [[String: Any]] = []
        for policy in policies {
            var passed = [0, 0, 0, 0]
            var failedInflation = 0, failedJobs = 0, failedScore = 0
            var inflation: [Double] = [], unemployment: [Double] = [], scores: [Double] = []
            for seed in 0 ..< seedCount {
                let store = GameSessionStore()
                store.start(seed: "review-seed-\(seed)")
                for term in 0 ..< 4 {
                    for quarter in 0 ..< 16 {
                        let s = store.session.current
                        var change = 0.0
                        switch policy {
                        case "cut50_then_hold": change = term == 0 && quarter == 0 ? -0.5 : 0
                        case "raise50_then_hold": change = term == 0 && quarter == 0 ? 0.5 : 0
                        case "balanced_feedback":
                            let target = 1.5 + s.expectedInflation + 1.25 * (s.inflation - 2) - 0.75 * (s.unemployment - 5)
                            change = min(0.5, max(-0.5, target - s.fedFundsRate))
                        case "inflation_feedback":
                            let target = 1.5 + s.expectedInflation + 1.25 * (s.inflation - 2)
                            change = min(0.5, max(-0.5, target - s.fedFundsRate))
                        default: break
                        }
                        change = max(-s.fedFundsRate, min(20 - s.fedFundsRate, change))
                        try store.commitCustom(rateChange: (change * 100).rounded() / 100)
                        precondition(store.session.currentTermQuarter == quarter + 1, "A valid policy did not advance")
                    }
                    if term == 0 {
                        inflation.append(store.session.current.inflation)
                        unemployment.append(store.session.current.unemployment)
                        scores.append(store.session.score.score)
                        failedInflation += store.session.current.inflation > 4 ? 1 : 0
                        failedJobs += store.session.current.unemployment > 7 ? 1 : 0
                        failedScore += store.session.score.score < 70 ? 1 : 0
                    }
                    if !store.session.score.reappointed { break }
                    passed[term] += 1
                    try store.continueNextTerm()
                }
            }
            summaries.append([
                "policy": policy, "seeds": seedCount, "survivedThroughTerm": passed,
                "firstTermMeanInflation": mean(inflation), "firstTermMeanUnemployment": mean(unemployment),
                "firstTermMeanScore": mean(scores), "firstTermFailureReasonsNonExclusive": ["inflation": failedInflation, "unemployment": failedJobs, "score": failedScore],
            ])
        }

        func controlled(_ initial: MacroState, quarters: Int, desiredRate: (MacroState) -> Double) throws -> [MacroState] {
            var scenario = classicScenario
            scenario.coefficients.noiseScale = 0
            scenario.termQuarters = quarters
            var history = [initial]
            for _ in 0 ..< quarters {
                let previous = history.last!
                let decision = createDecision(action: .custom, current: previous, timestamp: "audit", customRateChange: desiredRate(previous) - previous.fedFundsRate)
                let next = try advanceQuarter(history: history, decision: decision, scenario: scenario, activeShocks: [], seed: "controlled")
                history.append(next.nextState)
            }
            return history
        }
        var equilibrium = classicScenario.startingState
        equilibrium.inflation = 2; equilibrium.expectedInflation = 2; equilibrium.outputGap = 0
        equilibrium.unemployment = 5; equilibrium.gdpGrowth = 2; equilibrium.fedFundsRate = 3.5; equilibrium.credibility = 100
        let neutral = try controlled(equilibrium, quarters: 96) { _ in 3.5 }
        precondition(neutral.allSatisfy { $0.inflation == 2 && $0.unemployment == 5 && $0.outputGap == 0 })
        var detachedLabor = equilibrium
        detachedLabor.unemployment = 8
        let stranded = try controlled(detachedLabor, quarters: 96) { _ in 3.5 }
        let tight = try controlled(equilibrium, quarters: 96) { $0.expectedInflation + 3 }
        let encoded = try JSONEncoder().encode([neutral.last!, stranded.last!, tight.last!])
        let controls = try JSONSerialization.jsonObject(with: encoded)
        let result: [String: Any] = [
            "sourceCommit": CommandLine.arguments.dropFirst().first ?? "unknown", "method": "Unmodified production Swift Core, same 500 seeds for each policy, no future shock access, four terms or rejection; deterministic exploratory benchmark, not optimal play or human difficulty measurement.",
            "policies": summaries, "controlled96QuarterEndpoints": controls,
            "controlsOrder": ["neutral equilibrium", "neutral but unemployment starts at 8", "permanent 1.5 pp real-rate gap"],
            "tightLastEightOutputGaps": tight.suffix(8).map(\.outputGap),
            "tightLastEightGrowthRates": tight.suffix(8).map(\.gdpGrowth),
            "tightLastEightUnemployment": tight.suffix(8).map(\.unemployment),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
