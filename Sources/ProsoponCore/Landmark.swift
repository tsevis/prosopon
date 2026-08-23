import Foundation

/// The three points every part of Prosopon is organised around.
///
/// The `CodingKeyRepresentable` conformance is load-bearing rather than decorative.
/// Swift encodes a `Dictionary` as a JSON object only when its key is a `String`, an
/// `Int`, or `CodingKeyRepresentable`; for anything else it silently falls back to a
/// flat array of alternating keys and values. Without this, `[Landmark: ConsensusOffset]`
/// serialises as `["viewerLeftEye", {...}, "mouth", {...}]`, which reads back as
/// nothing at all in any consumer expecting an object.
public enum Landmark: String, CaseIterable, Sendable, Hashable, Codable, CodingKeyRepresentable {
    case viewerLeftEye
    case viewerRightEye
    case mouth

    /// Compact, for labels that share a line with numbers.
    public var shortName: String {
        switch self {
        case .viewerLeftEye: "L eye"
        case .viewerRightEye: "R eye"
        case .mouth: "mouth"
        }
    }

    public var displayName: String {
        switch self {
        case .viewerLeftEye: "left eye"
        case .viewerRightEye: "right eye"
        case .mouth: "mouth"
        }
    }

    public func target(in spec: CanvasSpec) -> Point2D {
        switch self {
        case .viewerLeftEye: spec.viewerLeftEye
        case .viewerRightEye: spec.viewerRightEye
        case .mouth: spec.mouth
        }
    }

    public func point(in landmarks: FaceLandmarks) -> Point2D {
        switch self {
        case .viewerLeftEye: landmarks.viewerLeftEye
        case .viewerRightEye: landmarks.viewerRightEye
        case .mouth: landmarks.mouth
        }
    }
}

extension FaceLandmarks {
    public func replacing(_ which: Landmark, with point: Point2D) -> FaceLandmarks {
        switch which {
        case .viewerLeftEye:
            FaceLandmarks(viewerLeftEye: point, viewerRightEye: viewerRightEye, mouth: mouth)
        case .viewerRightEye:
            FaceLandmarks(viewerLeftEye: viewerLeftEye, viewerRightEye: point, mouth: mouth)
        case .mouth:
            FaceLandmarks(viewerLeftEye: viewerLeftEye, viewerRightEye: viewerRightEye, mouth: point)
        }
    }
}
