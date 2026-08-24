import Foundation

/// SplitMix64, so a mix run reproduces.
///
/// Swift's own `SystemRandomNumberGenerator` cannot be seeded, and an unseeded shuffle
/// would mean a run could never be repeated — which matters here, because the interesting
/// question about a batch of composites is usually "what did the *other* seed do", and
/// that is only answerable if a seed is a thing you can go back to.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        // A seed of zero is a perfectly reasonable thing to type and a degenerate state
        // for several generators, so it is folded rather than used raw.
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
