import Foundation
import ProsoponCore

/// One candidate tile as the reviewer sees it: what the detector found, what the
/// reviewer has since changed, and what the solve makes of it.
///
/// The landmarks are kept in **source** pixel space, because that is the only place a
/// correction means anything. In canvas space the eyes sit on their targets by
/// construction whatever the detector did, so there would be nothing to drag.
public struct ReviewEntry: Identifiable, Sendable {
    public let id: String
    public let sourceURL: URL
    public let outputURL: URL?
    public let faceIndex: Int
    public let sourceWidth: Int
    public let sourceHeight: Int

    /// What the detector originally produced, kept so a correction can be undone.
    public let detected: FaceLandmarks
    public private(set) var landmarks: FaceLandmarks

    public private(set) var alignment: Alignment?
    public private(set) var fit: SourceFit?
    public private(set) var quality: QualityReport?
    public private(set) var failure: String?

    /// How far this tile sat from the stack consensus, when a QA run has been read in.
    public var consensusDisplacement: Double?
    public var consensusMatched: Bool?

    public var isEdited: Bool { landmarks != detected }
    public var name: String { sourceURL.deletingPathExtension().lastPathComponent }

    public init(
        id: String, sourceURL: URL, outputURL: URL?, faceIndex: Int,
        sourceWidth: Int, sourceHeight: Int, detected: FaceLandmarks,
        spec: CanvasSpec = .standard, options: SolveOptions = .default
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.faceIndex = faceIndex
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.detected = detected
        self.landmarks = detected
        resolve(spec: spec, options: options)
    }

    /// Re-runs the solve. Cheap enough to call on every frame of a drag.
    public mutating func resolve(spec: CanvasSpec = .standard, options: SolveOptions = .default) {
        do {
            let solved = try AlignmentSolver.solve(landmarks: landmarks, spec: spec, options: options)
            let measured = SourceFit.evaluate(
                alignment: solved,
                sourceWidth: Double(sourceWidth), sourceHeight: Double(sourceHeight),
                spec: spec
            )
            alignment = solved
            fit = measured
            quality = QualityReport.evaluate(alignment: solved, fit: measured)
            failure = nil
        } catch {
            alignment = nil
            fit = nil
            quality = nil
            failure = "\(error)"
        }
    }

    public mutating func setLandmark(
        _ which: Landmark, toSourcePoint point: Point2D,
        spec: CanvasSpec = .standard, options: SolveOptions = .default
    ) {
        landmarks = landmarks.replacing(which, with: point)
        resolve(spec: spec, options: options)
    }

    /// Moves a landmark by naming where its feature actually sits in the **canvas**.
    ///
    /// This is what a drag in the preview means: the reviewer puts the marker on the
    /// pupil as currently rendered, and the point is carried back through the transform
    /// to become the corrected source landmark. Re-solving then brings that pupil onto
    /// the target, so the image moves under a marker that stays put — which is the
    /// behaviour that makes the correction visible.
    public mutating func setLandmark(
        _ which: Landmark, toCanvasPoint point: Point2D,
        spec: CanvasSpec = .standard, options: SolveOptions = .default
    ) {
        guard let inverse = alignment?.transform.inverted else { return }
        setLandmark(which, toSourcePoint: inverse.apply(to: point), spec: spec, options: options)
    }

    public mutating func revert(spec: CanvasSpec = .standard, options: SolveOptions = .default) {
        landmarks = detected
        resolve(spec: spec, options: options)
    }

    /// Worst-first ordering key: unsolvable tiles, then rejected, then by score.
    public var triageRank: Double {
        if failure != nil { return -2 }
        guard let quality else { return -1 }
        return quality.isAccepted ? quality.score : quality.score - 1
    }
}
