import Foundation

public struct PolicyActionInfo: Equatable, Sendable {
    public var label: String
    public var delta: Double
    public var hint: String
}

public let policyActions: [PolicyAction: PolicyActionInfo] = [
    .cut150: PolicyActionInfo(label: "-150 bps", delta: -1.5, hint: "An emergency cut strongly supports demand, but can quickly damage inflation credibility."),
    .cut100: PolicyActionInfo(label: "-100 bps", delta: -1.0, hint: "A very large cut supports demand quickly, but can add material inflation pressure."),
    .cut75: PolicyActionInfo(label: "-75 bps", delta: -0.75, hint: "A forceful cut eases conditions quickly, but can weaken inflation credibility."),
    .cut50: PolicyActionInfo(label: "-50 bps", delta: -0.5, hint: "A larger cut eases conditions quickly, but can weaken inflation credibility."),
    .cut25: PolicyActionInfo(label: "-25 bps", delta: -0.25, hint: "A small cut supports demand and employment, but can add inflation pressure."),
    .hold: PolicyActionInfo(label: "Hold", delta: 0, hint: "Holding lets previous decisions keep working through policy lags."),
    .raise25: PolicyActionInfo(label: "+25 bps", delta: 0.25, hint: "A small hike tends to cool inflation pressure with some labor-market cost."),
    .raise50: PolicyActionInfo(label: "+50 bps", delta: 0.5, hint: "A larger hike fights inflation faster, but raises recession risk."),
    .raise75: PolicyActionInfo(label: "+75 bps", delta: 0.75, hint: "A forceful hike fights inflation faster, but raises recession risk."),
    .raise100: PolicyActionInfo(label: "+100 bps", delta: 1.0, hint: "A very large hike fights inflation hard, but can sharply raise recession risk."),
    .raise150: PolicyActionInfo(label: "+150 bps", delta: 1.5, hint: "An emergency hike can defend inflation credibility, but may overtighten into recession."),
    .custom: PolicyActionInfo(label: "Custom", delta: 0, hint: "A custom basis-point move commits immediately and advances one quarter."),
]

public func createDecision(
    action: PolicyAction,
    current: MacroState,
    timestamp: String = ISO8601DateFormatter().string(from: Date()),
    customRateChange: Double? = nil,
) -> PolicyDecision {
    let rateChange = action == .custom ? roundTo(customRateChange ?? 0) : policyActions[action]?.delta ?? 0
    let resultingRate = roundTo(current.fedFundsRate + rateChange)
    return PolicyDecision(
        id: "\(current.quarterIndex + 1)-\(action.rawValue)-\(rateChange)-\(timestamp)",
        quarterIndex: current.quarterIndex + 1,
        action: action,
        rateChange: rateChange,
        resultingFedFundsRate: resultingRate,
        timestamp: timestamp,
    )
}

public func formatRateChangeBps(_ rateChange: Double) -> String {
    let bps = Int((rateChange * 100).rounded())
    if bps == 0 {
        return "Hold"
    }
    return "\(bps > 0 ? "+" : "")\(bps) bps"
}

public func policyDecisionLabel(_ decision: PolicyDecision) -> String {
    if decision.action == .custom {
        return "Custom \(formatRateChangeBps(decision.rateChange))"
    }
    return policyActions[decision.action]?.label ?? decision.action.rawValue
}
