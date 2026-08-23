import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponVision

/// Landmarks from InsightFace's `buffalo_l`, run through ONNX Runtime on the GPU and
/// Neural Engine via the CoreML execution provider.
///
/// The Vision backend needs no model files and is the sensible default. This one exists
/// because its 106-point contour puts the canthi and the mouth commissures directly,
/// rather than leaving them to be inferred from a coarser constellation.
public final class InsightFaceLandmarkDetector: LandmarkDetector, @unchecked Sendable {
    public let name = "insightface"

    private let detector: SCRFD
    private let landmarks: Landmark106
    public let minimumConfidence: Double

    public init(
        bundle: ModelBundle? = nil,
        minimumConfidence: Double = 0.5,
        useCoreML: Bool = true
    ) throws {
        let resolved = try bundle ?? ModelBundle.locate()
        self.detector = SCRFD(
            model: try ONNXModel(path: resolved.detector, useCoreML: useCoreML),
            scoreThreshold: minimumConfidence
        )
        self.landmarks = Landmark106(
            model: try ONNXModel(path: resolved.landmarks, useCoreML: useCoreML)
        )
        self.minimumConfidence = minimumConfidence
    }

    public func detect(in image: CGImage) throws -> [DetectedFace] {
        // Landmark failures propagate rather than being read as "no face here": a model
        // that cannot run is a systemic problem, and silently returning an empty list
        // would look exactly like a photograph with nobody in it.
        try detector.detect(in: image).compactMap { detection in
            let points = try landmarks.points(in: image, box: detection.box)
            guard let canonical = Landmark106.canonicalLandmarks(from: points) else { return nil }
            return DetectedFace(
                landmarks: canonical,
                boundingBox: detection.box,
                confidence: detection.score,
                rollDegrees: roll(of: canonical)
            )
        }
    }

    /// The 106-point model carries no pose head, so roll is read off the eye line.
    /// Yaw and pitch are left unreported rather than guessed at.
    private func roll(of landmarks: FaceLandmarks) -> Double {
        let axis = landmarks.viewerRightEye - landmarks.viewerLeftEye
        return atan2(axis.y, axis.x) * 180 / .pi
    }

    /// Every one of the 106 points, for diagnostics and for verifying the index mapping.
    public func allPoints(in image: CGImage) throws -> [(box: BoundingBox, points: [Point2D])] {
        try detector.detect(in: image).map { detection in
            (detection.box, try landmarks.points(in: image, box: detection.box))
        }
    }
}
