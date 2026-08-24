import Foundation

/// One aligned tile, and everything the matcher knows about it.
///
/// Deliberately not the image: measuring is a separate pass from composing, and this is
/// all that survives it. Hundreds of these fit in memory where hundreds of 2048 x 2048
/// tiles do not.
public struct TileMeasurement: Sendable {
    /// The written tile on disk. Only tiles that exist are measured — a candidate the
    /// gates declined has no file, and a corrected tile that later failed one has had its
    /// file removed.
    public let tileURL: URL
    /// The photograph the tile was rendered from, carried through so the mix manifest can
    /// name the original rather than only the derivative.
    public let sourcePath: String
    public let name: String
    /// As the detector reported it. Vision does not report a usable one; see
    /// `FrontalityBasis`.
    public let yawDegrees: Double?
    /// The tile's quality score, when the run manifest carried one.
    public let score: Double?
    /// The eight interior strips, keyed by which quadrant placement shows them.
    public let edges: [SeamSide: EdgeSignature]
    /// The two vertical bottom strips again, over the mouth band alone.
    public let mouthEdges: [SeamSide: EdgeSignature]

    public init(
        tileURL: URL,
        sourcePath: String,
        name: String,
        yawDegrees: Double?,
        score: Double?,
        edges: [SeamSide: EdgeSignature],
        mouthEdges: [SeamSide: EdgeSignature]
    ) {
        self.tileURL = tileURL
        self.sourcePath = sourcePath
        self.name = name
        self.yawDegrees = yawDegrees
        self.score = score
        self.edges = edges
        self.mouthEdges = mouthEdges
    }
}

/// Which measurement decided who goes on top.
///
/// The distinction is worth recording. A Vision run reports yaw in 45-degree steps — it
/// gave 0 for faces turned 13, 20 and 37 — so a mix made from one is not pose-sorted, and
/// a manifest that did not say so would look exactly like one that was.
public enum FrontalityBasis: String, Sendable, Codable {
    /// Head yaw from the detector. What the top quadrants should be chosen on.
    case yaw
    /// The tile's quality score, which carries a pose term only when the detector
    /// reported one.
    case score
    /// Nothing to sort on: a folder of tiles with no manifest beside it.
    case none

    public var explanation: String {
        switch self {
        case .yaw: "most frontal faces on top, by detected head yaw"
        case .score:
            "most frontal faces on top, by quality score — this run's detector reported no "
                + "usable yaw, so the ordering is a proxy rather than a pose measurement"
        case .none:
            "no frontality measurement was available, so the top quadrants were filled in "
                + "the seeded order like the bottom ones"
        }
    }
}
