import Foundation

/// What a mix run leaves behind beside the documents.
///
/// Named `mix-manifest.json` rather than `manifest.json` on purpose: a folder holding a
/// `manifest.json` is an *align* run, and `review.sh` and `ReviewSession` both go looking
/// for one. A mix folder that answered to that name would be opened as a run with no
/// tiles in it.
public struct MixManifest: Codable, Sendable {
    public var canvasSize: Int
    public var quadrantSize: Int
    public var seed: UInt64
    public var seamWidth: Int
    public var mouthBandHeight: Int
    public var measureSize: Int
    public var frontalityBasis: FrontalityBasis
    /// The basis said in words, because "score" on its own does not tell somebody reading
    /// this in six months that the run's detector reported no usable yaw.
    public var frontalityNote: String
    /// The align run the tiles came from, when there was one.
    public var sourceRun: String?
    public var tileCount: Int
    public var composites: [CompositeRecord]
    /// Tiles that no composite could take, each with the reason.
    public var unused: [UnusedTile]

    public init(
        canvasSize: Int, quadrantSize: Int, seed: UInt64, seamWidth: Int,
        mouthBandHeight: Int, measureSize: Int, frontalityBasis: FrontalityBasis,
        frontalityNote: String, sourceRun: String?, tileCount: Int,
        composites: [CompositeRecord], unused: [UnusedTile]
    ) {
        self.canvasSize = canvasSize
        self.quadrantSize = quadrantSize
        self.seed = seed
        self.seamWidth = seamWidth
        self.mouthBandHeight = mouthBandHeight
        self.measureSize = measureSize
        self.frontalityBasis = frontalityBasis
        self.frontalityNote = frontalityNote
        self.sourceRun = sourceRun
        self.tileCount = tileCount
        self.composites = composites
        self.unused = unused
    }
}

public struct CompositeRecord: Codable, Sendable {
    public var index: Int
    /// Nil on a dry run, and for any composite beyond `--limit`. The plan is recorded
    /// either way, so a partial run still says what the rest would have been.
    public var documentPath: String?
    public var previewPath: String?
    public var flatPath: String?
    /// The mouth band alone, in Lab distance. The first number to read when a mouth looks
    /// wrong.
    public var mouthSeam: Double?
    /// Every join, keyed by `Seam`. Lower is a closer match.
    public var seams: [String: Double]
    /// The largest colour difference at any one point along any join, in ΔE.
    ///
    /// The figure that corresponds to what is actually visible: a seam can average well
    /// and still break at one end, and an average is the statistic that hides exactly
    /// that. Optional so a manifest written before it existed still decodes.
    public var worstSeam: Double?
    public var quadrants: [QuadrantRecord]

    public init(
        index: Int, documentPath: String?, previewPath: String?, flatPath: String?,
        mouthSeam: Double?, seams: [String: Double], worstSeam: Double? = nil,
        quadrants: [QuadrantRecord]
    ) {
        self.index = index
        self.documentPath = documentPath
        self.previewPath = previewPath
        self.flatPath = flatPath
        self.mouthSeam = mouthSeam
        self.seams = seams
        self.worstSeam = worstSeam
        self.quadrants = quadrants
    }
}

public struct QuadrantRecord: Codable, Sendable {
    public var quadrant: Quadrant
    public var name: String
    public var tilePath: String
    /// The photograph the tile was rendered from, so a bad quadrant leads back to the
    /// original rather than only to the derivative.
    public var sourcePath: String
    public var yawDegrees: Double?
    public var score: Double?
    public var chosenBy: MatchReason
    /// What the winning candidate scored. Nil where nothing was chosen between.
    public var cost: Double?

    public init(
        quadrant: Quadrant, name: String, tilePath: String, sourcePath: String,
        yawDegrees: Double?, score: Double?, chosenBy: MatchReason, cost: Double?
    ) {
        self.quadrant = quadrant
        self.name = name
        self.tilePath = tilePath
        self.sourcePath = sourcePath
        self.yawDegrees = yawDegrees
        self.score = score
        self.chosenBy = chosenBy
        self.cost = cost
    }
}

public struct UnusedTile: Codable, Sendable {
    public var tilePath: String
    public var name: String
    public var reason: String

    public init(tilePath: String, name: String, reason: String) {
        self.tilePath = tilePath
        self.name = name
        self.reason = reason
    }
}

/// A distance that JSON can hold.
///
/// A cost can be infinite — an unmeasurable strip scores that way — and `JSONEncoder`
/// refuses to write one, throwing part-way through a manifest that has already cost a
/// corpus-wide measurement pass. Non-finite values become nil, which reads correctly as
/// "there was no number here".
func encodable(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
}

/// The same data as a spreadsheet: one row per quadrant, so a batch can be sorted by the
/// seam that went worst.
public enum MixReport {
    public static func render(_ manifest: MixManifest) -> String {
        var lines = [
            "composite,quadrant,name,chosen_by,cost,mouth_seam,seam_vertical_top,"
                + "seam_vertical_bottom,seam_horizontal_left,seam_horizontal_right,"
                + "yaw_degrees,score,tile_path,source_path",
        ]

        for composite in manifest.composites {
            for quadrant in composite.quadrants {
                lines.append([
                    String(composite.index),
                    quadrant.quadrant.rawValue,
                    escaped(quadrant.name),
                    quadrant.chosenBy.rawValue,
                    number(quadrant.cost),
                    number(composite.mouthSeam),
                    number(composite.seams[Seam.verticalTop.rawValue]),
                    number(composite.seams[Seam.verticalBottom.rawValue]),
                    number(composite.seams[Seam.horizontalLeft.rawValue]),
                    number(composite.seams[Seam.horizontalRight.rawValue]),
                    number(quadrant.yawDegrees),
                    number(quadrant.score),
                    escaped(quadrant.tilePath),
                    escaped(quadrant.sourcePath),
                ].joined(separator: ","))
            }
        }

        for tile in manifest.unused {
            lines.append([
                "", "unused", escaped(tile.name), escaped(tile.reason),
                "", "", "", "", "", "", "", "", escaped(tile.tilePath), "",
            ].joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.3f", value)
    }

    private static func escaped(_ text: String) -> String {
        guard text.contains(",") || text.contains("\"") || text.contains("\n") else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

public extension MixManifest {
    static let fileName = "mix-manifest.json"

    /// Reads the manifest a mix run left in `directory`.
    ///
    /// Deliberately throwing rather than returning nil: a manifest that is present and
    /// will not decode is a bug worth seeing, and a `try?` here would show an empty Mix
    /// stage beside a folder full of composites with nothing to explain it.
    static func read(in directory: URL) throws -> MixManifest {
        let url = directory.appendingPathComponent(fileName)
        return try JSONDecoder().decode(MixManifest.self, from: Data(contentsOf: url))
    }

    static func exists(in directory: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(fileName).path
        )
    }

    /// Where the preview for a composite is, when one was written.
    func previewURL(for composite: CompositeRecord, in directory: URL) -> URL? {
        composite.previewPath.map { directory.appendingPathComponent($0) }
    }
}
