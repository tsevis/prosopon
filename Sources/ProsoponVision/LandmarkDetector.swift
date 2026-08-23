import CoreGraphics
import ProsoponCore

/// A source of the three landmarks Prosopon aligns on.
///
/// Vision is the default because it needs no model files and runs on the Neural
/// Engine. The InsightFace tier (`det_10g` + `2d106det`, already on this machine)
/// will conform to the same protocol through ONNX Runtime's CoreML provider.
public protocol LandmarkDetector: Sendable {
    var name: String { get }
    /// Faces found in `image`, which must already have its EXIF orientation baked in.
    func detect(in image: CGImage) throws -> [DetectedFace]
}
