import ProsoponInsight
import ProsoponVision

/// Where the three landmarks come from.
///
/// Shared by the command line and the app so that a run made from either is made the same
/// way, and so the manifest's `detector` field means one thing. As with `FaceSelection`,
/// the `ExpressibleByArgument` conformance stays in the CLI.
public enum DetectorChoice: String, CaseIterable, Sendable, Identifiable {
    case vision
    case insightface

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .vision: "Vision"
        case .insightface: "InsightFace"
        }
    }

    /// The one sentence somebody needs to choose between them.
    public var detail: String {
        switch self {
        case .vision:
            "Built in. No model files, runs on the Neural Engine."
        case .insightface:
            "106 landmarks and head pose worth gating on. Needs buffalo_l installed."
        }
    }

    /// Vision reports yaw only in 45 degree steps — on a six-face photograph it gave 0
    /// for faces turned 13, 20 and 37 degrees — so a pose gate set against it does
    /// nothing. Worth knowing before choosing.
    public var reportsUsableYaw: Bool { self == .insightface }

    /// Built once per run: loading two ONNX models is a per-process cost, not a per-image
    /// one, and the same instance is then shared across the whole batch.
    public func make(
        modelPath: String? = nil,
        minimumConfidence: Double = 0.3,
        usesPupils: Bool = false
    ) throws -> any LandmarkDetector {
        switch self {
        case .vision:
            VisionLandmarkDetector(usesPupils: usesPupils, minimumConfidence: minimumConfidence)
        case .insightface:
            try InsightFaceLandmarkDetector(
                bundle: modelPath.map { try ModelBundle.locate(explicit: $0) },
                minimumConfidence: minimumConfidence
            )
        }
    }
}
