import Foundation

struct ShockChannels: Equatable {
    var demand: Double
    var financialActivityDrag: Double
    var priceSupply: Double
    var laborTightness: Double
    var financialLaborStress: Double

    var activityNet: Double {
        demand - financialActivityDrag
    }

    var laborNet: Double {
        laborTightness - financialLaborStress
    }

    var totalIntensity: Double {
        abs(demand) + financialActivityDrag + abs(priceSupply) + laborTightness + financialLaborStress
    }
}

func shockChannels(contributions: [ShockType: Double]) -> ShockChannels {
    let financialStress = abs(min(0, contributions[.financial] ?? 0))
    return ShockChannels(
        demand: (contributions[.demand] ?? 0) + 0.45 * (contributions[.confidence] ?? 0),
        financialActivityDrag: financialStress * 0.8,
        priceSupply: (contributions[.supply] ?? 0) + 0.55 * (contributions[.energy] ?? 0),
        laborTightness: max(0, contributions[.labor] ?? 0) * 0.35,
        financialLaborStress: financialStress * 0.2,
    )
}

func shockChannels(traceContributions: [String: Double]) -> ShockChannels {
    let typed = Dictionary(uniqueKeysWithValues: ShockType.allCases.map { type in
        (type, traceContributions[type.rawValue] ?? 0)
    })
    return shockChannels(contributions: typed)
}

func shockChannelSummary(_ channels: ShockChannels) -> String {
    var parts: [String] = []
    if channels.demand > 0.05 {
        parts.append("demand support \(formatShockMagnitude(channels.demand))")
    } else if channels.demand < -0.05 {
        parts.append("demand drag \(formatShockMagnitude(abs(channels.demand)))")
    }
    if channels.financialActivityDrag > 0.05 {
        parts.append("financial drag \(formatShockMagnitude(channels.financialActivityDrag))")
    }
    if channels.priceSupply > 0.05 {
        parts.append("price pressure \(formatShockMagnitude(channels.priceSupply))")
    } else if channels.priceSupply < -0.05 {
        parts.append("price relief \(formatShockMagnitude(abs(channels.priceSupply)))")
    }
    if channels.laborTightness > 0.05 {
        parts.append("labor tightness \(formatShockMagnitude(channels.laborTightness))")
    }
    if channels.financialLaborStress > 0.05 {
        parts.append("labor stress \(formatShockMagnitude(channels.financialLaborStress))")
    }
    return parts.isEmpty ? "no material shock channel" : parts.joined(separator: ", ")
}

private func formatShockMagnitude(_ value: Double) -> String {
    String(format: "%.2f", value)
}
