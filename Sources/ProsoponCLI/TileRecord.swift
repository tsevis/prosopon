import Foundation
import ProsoponCore

/// One row of the run manifest: everything known about one candidate tile.
///
/// The transform is stored so a stack can be re-rendered at 4096, or with a different
/// resampler, without re-running detection.
struct TileRecord: Codable, Sendable {
    var sourcePath: String
    var sourceWidth: Int
    var sourceHeight: Int
    var faceIndex: Int
    var outputPath: String?
    var accepted: Bool
    var rejections: [RejectionReason]
    var failure: String?

    var landmarks: FaceLandmarks?
    var transform: Affine2D?
    var nativeMouthDropRatio: Double?
    var quality: QualityReport?
    var detectorConfidence: Double?
    var yawDegrees: Double?
    var pitchDegrees: Double?

    static func failed(source: URL, width: Int, height: Int, faceIndex: Int, message: String) -> TileRecord {
        TileRecord(
            sourcePath: source.path, sourceWidth: width, sourceHeight: height,
            faceIndex: faceIndex, outputPath: nil, accepted: false,
            rejections: [], failure: message
        )
    }
}

struct RunManifest: Codable, Sendable {
    var canvasSize: Double
    var gridStep: Double
    var targets: [String: Point2D]
    var maxStretch: Double
    var maxShear: Double
    var detector: String
    var tiles: [TileRecord]
}
