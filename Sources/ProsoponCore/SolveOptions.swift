import Foundation

/// Tunables for the alignment solve. Defaults encode the decisions in `docs/PLAN.md`.
public struct SolveOptions: Hashable, Sendable, Codable {
    /// Maximum allowed anisotropy, as a fraction. 0.05 means the vertical scale may
    /// range over [1/1.05, 1.05] relative to the horizontal — the "no more than 5 %
    /// stretch" rule, taken as a ratio so squash and stretch are capped symmetrically.
    public var maxStretch: Double

    /// Maximum shear, as horizontal displacement per unit of vertical distance below
    /// the eye line. 0.05 is about 2.9 degrees. Shear is the only linear operation
    /// that can slide the mouth horizontally onto x = 1024 while leaving both eyes
    /// pinned, so for mosaic work it earns a more generous budget than stretch.
    public var maxShear: Double

    /// When false, the mouth's horizontal offset is left uncorrected and the solve
    /// reduces to similarity + vertical stretch.
    public var correctsHorizontalMouthOffset: Bool

    public init(maxStretch: Double = 0.05, maxShear: Double = 0.05, correctsHorizontalMouthOffset: Bool = true) {
        self.maxStretch = maxStretch
        self.maxShear = maxShear
        self.correctsHorizontalMouthOffset = correctsHorizontalMouthOffset
    }

    public static let `default` = SolveOptions()

    /// Similarity only: both eyes exact, mouth wherever the face's own proportions put it.
    public static let rigid = SolveOptions(maxStretch: 0, maxShear: 0, correctsHorizontalMouthOffset: false)

    public var stretchRange: ClosedRange<Double> { (1 / (1 + maxStretch))...(1 + maxStretch) }
}
