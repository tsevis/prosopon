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

    /// What the detector reported for head pose, carried through from the manifest.
    ///
    /// The reviewer re-solves the geometry from the landmarks, but yaw is not recoverable
    /// that way -- it comes from a 3D landmark model, not from three points. Dropping it
    /// here made the metrics panel read "not measured" over a manifest that held a value,
    /// and made saving a correction write that value out of the tile's quality report.
    public let detectedYawDegrees: Double?

    /// The gates this run was aligned with, carried from its manifest.
    ///
    /// Re-solving against the built-in defaults instead is how a run made with a raised
    /// magnification limit reopens showing most of its tiles as rejected, with their
    /// files sitting untouched beside the manifest and no correction able to fix it.
    public let thresholds: QualityThresholds

    /// What the detector originally produced, kept so a correction can be undone.
    public let detected: FaceLandmarks
    public private(set) var landmarks: FaceLandmarks
    /// What was last written to disk. Equal to `detected` on load, because that is what
    /// the manifest holds.
    public private(set) var savedLandmarks: FaceLandmarks

    public private(set) var alignment: Alignment?
    public private(set) var fit: SourceFit?
    public private(set) var quality: QualityReport?
    public private(set) var failure: String?

    /// How far this tile sat from the stack consensus, when a QA run has been read in.
    public var consensusDisplacement: Double?
    public var consensusMatched: Bool?

    /// Changed since the last save — the thing "N corrections not yet saved" is counting,
    /// and the set a save has to re-render.
    ///
    /// **Not** "differs from the detector". Measured against `detected`, this could never
    /// become false: a correction stays a correction after it is written, so the banner
    /// went on claiming unsaved work for ever, Save stayed lit, and pressing it again
    /// re-rendered the same twenty tiles. The save was working; only the accounting was
    /// wrong, which is indistinguishable from the outside.
    public var isEdited: Bool { landmarks != savedLandmarks }

    /// Differs from what the detector found, saved or not. What Revert undoes.
    public var isCorrected: Bool { landmarks != detected }

    public var name: String { sourceURL.deletingPathExtension().lastPathComponent }

    public init(
        id: String, sourceURL: URL, outputURL: URL?, faceIndex: Int,
        sourceWidth: Int, sourceHeight: Int, detected: FaceLandmarks,
        detectedYawDegrees: Double? = nil,
        spec: CanvasSpec = .standard, options: SolveOptions = .default,
        thresholds: QualityThresholds = .default
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.faceIndex = faceIndex
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.detectedYawDegrees = detectedYawDegrees
        self.thresholds = thresholds
        self.detected = detected
        self.landmarks = detected
        self.savedLandmarks = detected
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
            quality = QualityReport.evaluate(
                alignment: solved, fit: measured, yawDegrees: detectedYawDegrees,
                thresholds: thresholds
            )
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

    /// Records that `landmarks` are now what is on disk.
    ///
    /// Takes the landmarks that were actually written rather than trusting the current
    /// ones: a save runs off the main actor over a snapshot, and a tile edited again while
    /// it was in flight has not been saved in its present state.
    public mutating func markSaved(_ written: FaceLandmarks) {
        guard landmarks == written else { return }
        savedLandmarks = written
    }

    /// Worst-first ordering key: unsolvable tiles, then rejected, then by score.
    public var triageRank: Double {
        if failure != nil { return -2 }
        guard let quality else { return -1 }
        return quality.isAccepted ? quality.score : quality.score - 1
    }
}
