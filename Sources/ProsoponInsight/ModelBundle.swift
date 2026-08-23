import Foundation

/// Locates the InsightFace `buffalo_l` models.
public struct ModelBundle: Sendable {
    public let detector: String
    public let landmarks: String

    static let detectorFile = "det_10g.onnx"
    static let landmarkFile = "2d106det.onnx"

    /// Places the models are commonly unpacked to, tried in order.
    public static var searchPaths: [String] {
        [
            "~/.insightface/models/buffalo_l",
            "~/.insightface/models/models/buffalo_l",
            "~/AI/ClaudeCode/mozaix/models/models/buffalo_l",
        ].map { ($0 as NSString).expandingTildeInPath }
    }

    public static func locate(explicit: String? = nil) throws -> ModelBundle {
        let candidates = explicit.map { [($0 as NSString).expandingTildeInPath] } ?? searchPaths
        for directory in candidates {
            let detector = (directory as NSString).appendingPathComponent(detectorFile)
            let landmarks = (directory as NSString).appendingPathComponent(landmarkFile)
            if FileManager.default.fileExists(atPath: detector),
               FileManager.default.fileExists(atPath: landmarks) {
                return ModelBundle(detector: detector, landmarks: landmarks)
            }
        }
        throw InsightError.modelsNotFound(candidates)
    }
}
