import Foundation

/// Why a tile ended up in the quadrant it did.
///
/// Recorded per quadrant so a join that looks wrong can be traced rather than guessed at:
/// a bad mouth reads differently depending on whether the matcher chose that pairing on
/// purpose and got it wrong, or never had a choice left to make.
public enum MatchReason: String, Sendable, Codable {
    /// The first pick of a composite. Nothing to match against yet.
    case seed
    /// Chosen to meet the other half of a mouth.
    case mouthSeam
    /// Chosen to meet a cheek across the horizontal seam.
    case cheekSeam
    /// Chosen to meet a cheek *and* the other eye's quadrant across the nose bridge.
    case cheekAndBridge
    /// The matcher had nothing left to choose between; taken from the seeded order.
    case randomFallback
    /// Moved here by the refinement pass, which swapped it with a tile in another
    /// composite because both composites came out better for it.
    case refined

    public var label: String {
        switch self {
        case .seed: "first pick"
        case .mouthSeam: "matched on the mouth seam"
        case .cheekSeam: "matched on the cheek seam"
        case .cheekAndBridge: "matched on the cheek seam and the nose bridge"
        case .randomFallback: "no match available — taken from the seeded order"
        case .refined: "swapped in by the refinement pass"
        }
    }
}

public struct QuadrantAssignment: Sendable {
    public let quadrant: Quadrant
    /// Index into the measurements the plan was built from.
    public let tileIndex: Int
    public let reason: MatchReason
    /// What the winning candidate scored. Nil for a seed pick and a random fallback,
    /// which were not chosen by cost.
    public let cost: Double?

    public init(quadrant: Quadrant, tileIndex: Int, reason: MatchReason, cost: Double?) {
        self.quadrant = quadrant
        self.tileIndex = tileIndex
        self.reason = reason
        self.cost = cost
    }
}

public struct CompositePlan: Sendable {
    public let index: Int
    /// Always four, in `Quadrant.allCases` order.
    public let quadrants: [QuadrantAssignment]
    /// What each of the four joins came out at, in Lab distance. Lower is a better join.
    public let seamCosts: [Seam: Double]
    /// The mouth band alone, which is the number worth reading first.
    public let mouthBandCost: Double
    /// The largest colour difference at any single point along any of the four joins,
    /// in ΔE.
    ///
    /// Reported because it is the figure that corresponds to what a viewer sees. A seam
    /// can average well and still break visibly at one end — a jaw meeting a neck — and
    /// an average is exactly the statistic that hides it. It is also neutral: it depends
    /// only on the tiles chosen, not on how they were chosen, so two matchers can be
    /// compared on it.
    public let worstSeamDisagreement: Double

    public init(
        index: Int,
        quadrants: [QuadrantAssignment],
        seamCosts: [Seam: Double],
        mouthBandCost: Double,
        worstSeamDisagreement: Double = .infinity
    ) {
        self.index = index
        self.quadrants = quadrants
        self.seamCosts = seamCosts
        self.mouthBandCost = mouthBandCost
        self.worstSeamDisagreement = worstSeamDisagreement
    }

    public func tileIndex(for quadrant: Quadrant) -> Int? {
        quadrants.first { $0.quadrant == quadrant }?.tileIndex
    }
}

/// Which tile goes where, for a whole batch. No pixels involved.
public struct MixPlan: Sendable {
    public let composites: [CompositePlan]
    /// Tiles left over because a composite needs exactly four. Named rather than dropped
    /// silently: losing four photographs without being told is not a good way to find out.
    public let unusedTileIndices: [Int]
    public let seed: UInt64
    public let frontalityBasis: FrontalityBasis

    public init(
        composites: [CompositePlan], unusedTileIndices: [Int],
        seed: UInt64, frontalityBasis: FrontalityBasis
    ) {
        self.composites = composites
        self.unusedTileIndices = unusedTileIndices
        self.seed = seed
        self.frontalityBasis = frontalityBasis
    }

    /// Every tile index the plan places, in order. The invariant worth testing is that
    /// this has no duplicates and, together with `unusedTileIndices`, covers every tile
    /// exactly once.
    public var placedTileIndices: [Int] {
        composites.flatMap { $0.quadrants.map(\.tileIndex) }
    }
}
