import Foundation

public struct PolicyActionInfo: Equatable, Sendable {
    public var label: String
    public var delta: Double
    public var hint: String
}

public let policyActions: [PolicyAction: PolicyActionInfo] = [
    .cut150: PolicyActionInfo(label: "-150 bps", delta: -1.5, hint: "An emergency cut supports demand after a lag; it needs a clear target-restoring case to preserve trust."),
    .cut100: PolicyActionInfo(label: "-100 bps", delta: -1.0, hint: "A very large cut supports demand after a lag while increasing future inflation risk."),
    .cut75: PolicyActionInfo(label: "-75 bps", delta: -0.75, hint: "A forceful cut eases conditions after a lag when labor slack or low inflation calls for support."),
    .cut50: PolicyActionInfo(label: "-50 bps", delta: -0.5, hint: "A larger cut eases conditions after a lag, trading labor support against future inflation risk."),
    .cut25: PolicyActionInfo(label: "-25 bps", delta: -0.25, hint: "A small cut gradually supports demand and employment after policy lags."),
    .hold: PolicyActionInfo(label: "Hold", delta: 0, hint: "Holding lets previous decisions keep working through policy lags."),
    .raise25: PolicyActionInfo(label: "+25 bps", delta: 0.25, hint: "A small hike gradually cools demand after policy lags."),
    .raise50: PolicyActionInfo(label: "+50 bps", delta: 0.5, hint: "A larger hike cools demand after a lag, trading inflation control against labor risk."),
    .raise75: PolicyActionInfo(label: "+75 bps", delta: 0.75, hint: "A forceful hike tightens conditions after a lag and raises overshoot risk."),
    .raise100: PolicyActionInfo(label: "+100 bps", delta: 1.0, hint: "A very large hike strongly tightens the maintained policy path and can raise recession risk."),
    .raise150: PolicyActionInfo(label: "+150 bps", delta: 1.5, hint: "An emergency hike can defend the inflation target when justified, but may overtighten or strain trust."),
    .custom: PolicyActionInfo(label: "Custom", delta: 0, hint: "Stage a custom basis-point move, review its directional path, then commit."),
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
