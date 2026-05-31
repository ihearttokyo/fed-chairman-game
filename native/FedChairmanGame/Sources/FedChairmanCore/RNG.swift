import Foundation

private func hashString(_ input: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for scalar in input.unicodeScalars {
        hash ^= UInt32(scalar.value)
        hash = hash &* 16_777_619
    }
    return hash
}

public struct SeededRng: Sendable {
    private var state: UInt32

    public init(seed: String, cursor: UInt32 = 0) {
        state = hashString(seed) &+ cursor
    }

    public mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var value = state
        value = (value ^ (value >> 15)) &* (value | 1)
        value ^= value &+ ((value ^ (value >> 7)) &* (value | 61))
        return Double(value ^ (value >> 14)) / 4_294_967_296.0
    }

    public mutating func between(_ minValue: Double, _ maxValue: Double) -> Double {
        minValue + (maxValue - minValue) * next()
    }
}

public func deterministicNoise(seed: String, quarterIndex: Int, salt: String, scale: Double) -> Double {
    var rng = SeededRng(seed: "\(seed):\(quarterIndex):\(salt)")
    return rng.between(-scale, scale)
}
