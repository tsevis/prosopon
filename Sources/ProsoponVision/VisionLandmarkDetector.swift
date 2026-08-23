import CoreGraphics
import Foundation
import ProsoponCore
import Vision

/// Landmarks from Apple's Vision framework.
///
/// Two definitions matter more here than the choice of detector (see `docs/PLAN.md`
/// section 5):
///
/// - **Eye centre is the canthus midpoint**, not the pupil. Vision reports pupils, but
///   the pupil moves with gaze, and a sideways glance would leak into the solved scale
///   and rotation for the whole face. The canthi are anatomically fixed.
/// - **Mouth centre is the commissure midpoint**, which survives the mouth opening.
///
/// Both are recovered as the farthest-apart pair of points in their contour, which
/// avoids depending on Vision's landmark ordering.
public struct VisionLandmarkDetector: LandmarkDetector {
    public let name = "vision"

    /// When true, the eye centre is taken from Vision's pupil point instead of the
    /// canthi. Less stable across gaze, but matches how the reference overlays were drawn.
    public let usesPupils: Bool

    /// Discards faces Vision is not reasonably sure about.
    public let minimumConfidence: Double

    public init(usesPupils: Bool = false, minimumConfidence: Double = 0.3) {
        self.usesPupils = usesPupils
        self.minimumConfidence = minimumConfidence
    }

    public func detect(in image: CGImage) throws -> [DetectedFace] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])

        let size = CGSize(width: image.width, height: image.height)
        return (request.results ?? []).compactMap { face($0, imageSize: size) }
    }

    private func face(_ observation: VNFaceObservation, imageSize: CGSize) -> DetectedFace? {
        guard Double(observation.confidence) >= minimumConfidence,
              let landmarks = observation.landmarks,
              let eyeA = eyeCentre(landmarks.leftEye, pupil: landmarks.leftPupil, imageSize: imageSize),
              let eyeB = eyeCentre(landmarks.rightEye, pupil: landmarks.rightPupil, imageSize: imageSize),
              let lips = landmarks.outerLips,
              let mouth = commissureMidpoint(of: lips, imageSize: imageSize)
        else { return nil }

        let ordered = DetectedFace.orderEyesForViewer(eyeA, eyeB, mouth: mouth)

        return DetectedFace(
            landmarks: FaceLandmarks(
                viewerLeftEye: ordered.viewerLeft,
                viewerRightEye: ordered.viewerRight,
                mouth: mouth
            ),
            boundingBox: boundingBox(observation.boundingBox, imageSize: imageSize),
            confidence: Double(observation.confidence),
            rollDegrees: observation.roll.map { degrees($0.doubleValue) },
            yawDegrees: observation.yaw.map { degrees($0.doubleValue) },
            pitchDegrees: observation.pitch.map { degrees($0.doubleValue) }
        )
    }

    private func eyeCentre(
        _ contour: VNFaceLandmarkRegion2D?,
        pupil: VNFaceLandmarkRegion2D?,
        imageSize: CGSize
    ) -> Point2D? {
        if usesPupils, let pupil, let point = points(of: pupil, imageSize: imageSize).first {
            return point
        }
        guard let contour else { return nil }
        let contourPoints = points(of: contour, imageSize: imageSize)
        guard let (inner, outer) = Point2D.extremePair(of: contourPoints) else { return nil }
        return .midpoint(inner, outer)
    }

    private func commissureMidpoint(of lips: VNFaceLandmarkRegion2D, imageSize: CGSize) -> Point2D? {
        guard let (left, right) = Point2D.extremePair(of: points(of: lips, imageSize: imageSize)) else { return nil }
        return .midpoint(left, right)
    }

    /// Vision reports image-space points with a bottom-left origin; Prosopon is y-down.
    private func points(of region: VNFaceLandmarkRegion2D, imageSize: CGSize) -> [Point2D] {
        region.pointsInImage(imageSize: imageSize).map {
            Point2D(Double($0.x), Double(imageSize.height) - Double($0.y))
        }
    }

    private func boundingBox(_ normalised: CGRect, imageSize: CGSize) -> BoundingBox {
        let width = normalised.width * imageSize.width
        let height = normalised.height * imageSize.height
        let x = normalised.minX * imageSize.width
        // Flip the origin corner along with the axis.
        let y = imageSize.height - normalised.maxY * imageSize.height
        return BoundingBox(x: Double(x), y: Double(y), width: Double(width), height: Double(height))
    }

    private func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
