import Foundation

/// One row of the run manifest: everything known about one candidate tile.
///
/// The landmarks and the transform are both stored, which is what lets the review app
/// reopen a run, move a landmark the detector got wrong, and re-solve from scratch --
/// and what lets a stack be re-rendered at 4096, or with a different resampler, without
/// re-running detection at all.
public struct TileRecord: Codable, Sendable {
    public var sourcePath: String
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var faceIndex: Int
    public var outputPath: String?
    public var accepted: Bool
    public var rejections: [RejectionReason]
    public var failure: String?

    public var landmarks: FaceLandmarks?
    public var transform: Affine2D?
    public var nativeMouthDropRatio: Double?
    public var quality: QualityReport?
    public var detectorConfidence: Double?
    public var yawDegrees: Double?
    public var pitchDegrees: Double?

    public init(
        sourcePath: String, sourceWidth: Int, sourceHeight: Int, faceIndex: Int,
        outputPath: String? = nil, accepted: Bool = false,
        rejections: [RejectionReason] = [], failure: String? = nil,
        landmarks: FaceLandmarks? = nil, transform: Affine2D? = nil,
        nativeMouthDropRatio: Double? = nil, quality: QualityReport? = nil,
        detectorConfidence: Double? = nil, yawDegrees: Double? = nil, pitchDegrees: Double? = nil
    ) {
        self.sourcePath = sourcePath
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.faceIndex = faceIndex
        self.outputPath = outputPath
        self.accepted = accepted
        self.rejections = rejections
        self.failure = failure
        self.landmarks = landmarks
        self.transform = transform
        self.nativeMouthDropRatio = nativeMouthDropRatio
        self.quality = quality
        self.detectorConfidence = detectorConfidence
        self.yawDegrees = yawDegrees
        self.pitchDegrees = pitchDegrees
    }

    public static func failed(source: URL, width: Int, height: Int, faceIndex: Int, message: String) -> TileRecord {
        TileRecord(
            sourcePath: source.path, sourceWidth: width, sourceHeight: height,
            faceIndex: faceIndex, outputPath: nil, accepted: false,
            rejections: [], failure: message
        )
    }
}

public struct RunManifest: Codable, Sendable {
    public var canvasSize: Double
    public var gridStep: Double
    public var targets: [String: Point2D]
    public var maxStretch: Double
    public var maxShear: Double
    public var detector: String
    public var resampler: String
    public var tiles: [TileRecord]

    public init(
        canvasSize: Double, gridStep: Double, targets: [String: Point2D],
        maxStretch: Double, maxShear: Double, detector: String, resampler: String,
        tiles: [TileRecord]
    ) {
        self.canvasSize = canvasSize
        self.gridStep = gridStep
        self.targets = targets
        self.maxStretch = maxStretch
        self.maxShear = maxShear
        self.detector = detector
        self.resampler = resampler
        self.tiles = tiles
    }

    /// Tolerates manifests written before a field existed.
    ///
    /// Refusing to open a whole run because one string is missing would be a poor way to
    /// treat someone's earlier work, and these files are meant to be re-read months later.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canvasSize = try container.decode(Double.self, forKey: .canvasSize)
        gridStep = try container.decode(Double.self, forKey: .gridStep)
        targets = try container.decodeIfPresent([String: Point2D].self, forKey: .targets) ?? [:]
        maxStretch = try container.decodeIfPresent(Double.self, forKey: .maxStretch) ?? 0.05
        maxShear = try container.decodeIfPresent(Double.self, forKey: .maxShear) ?? 0.05
        detector = try container.decodeIfPresent(String.self, forKey: .detector) ?? "vision"
        resampler = try container.decodeIfPresent(String.self, forKey: .resampler) ?? "lanczos"
        tiles = try container.decode([TileRecord].self, forKey: .tiles)
    }
}
