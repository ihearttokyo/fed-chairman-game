import Foundation

func clamp(_ value: Double, _ minValue: Double, _ maxValue: Double) -> Double {
    guard value.isFinite else {
        return minValue
    }
    return min(maxValue, max(minValue, value))
}

func roundTo(_ value: Double, digits: Int = 2) -> Double {
    let factor = pow(10.0, Double(digits))
    return floor(value * factor + 0.5) / factor
}

func mean(_ values: [Double]) -> Double {
    guard !values.isEmpty else {
        return 0
    }
    return values.reduce(0, +) / Double(values.count)
}

func meanAbs(_ values: [Double]) -> Double {
    mean(values.map { abs($0) })
}
