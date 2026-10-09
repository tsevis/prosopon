import Foundation

/// Locates the InsightFace `buffalo_l` models.
public struct ModelBundle: Sendable {
    public let detector: String
    public let landmarks: String
    /// Optional: without it, pose is simply not reported.
    public let pose: String?

    static let detectorFile = "det_10g.onnx"
    static let landmarkFile = "2d106det.onnx"
    static let poseFile = "1k3d68.onnx"

    /// Environment variable naming extra model directories, separated like `PATH` (`:`).
    /// Each entry is a folder that directly holds `det_10g.onnx` and `2d106det.onnx`.
    static let extraDirectoriesVariable = "PROSOPON_EXTRA_MODEL_DIRS"

    /// Places the models are commonly unpacked to, tried in order, followed by any
    /// directories listed in `PROSOPON_EXTRA_MODEL_DIRS`.
    public static var searchPaths: [String] {
        let extra = (ProcessInfo.processInfo.environment[extraDirectoriesVariable] ?? "")
            .split(separator: ":")
            .map(String.init)
        return (
            [
                "~/.insightface/models/buffalo_l",
                "~/.insightface/models/models/buffalo_l",
            ] + extra
        ).map { ($0 as NSString).expandingTildeInPath }
    }

    public static func locate(explicit: String? = nil) throws -> ModelBundle {
        let candidates = explicit.map { [($0 as NSString).expandingTildeInPath] } ?? searchPaths
        for directory in candidates {
            let detector = (directory as NSString).appendingPathComponent(detectorFile)
            let landmarks = (directory as NSString).appendingPathComponent(landmarkFile)
            if FileManager.default.fileExists(atPath: detector),
               FileManager.default.fileExists(atPath: landmarks) {
                let pose = (directory as NSString).appendingPathComponent(poseFile)
                return ModelBundle(
                    detector: detector, landmarks: landmarks,
                    pose: FileManager.default.fileExists(atPath: pose) ? pose : nil
                )
            }
        }
        throw InsightError.modelsNotFound(candidates)
    }
}
