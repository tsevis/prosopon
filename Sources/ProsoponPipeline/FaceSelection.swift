import ProsoponCore

/// Which faces in a photograph become candidate tiles.
///
/// `all` is the default because the goal is corpus yield: a group shot is several
/// usable tiles, and every one of them still has to pass the same gates before it is
/// written. Restricting to the largest face throws away material for no benefit.
///
/// `ExpressibleByArgument` is deliberately *not* declared here. It belongs to
/// ArgumentParser, which is the command line's dependency and has no business being
/// linked into the app; the CLI adds the conformance in an extension of its own.
public enum FaceSelection: String, CaseIterable, Sendable {
    case all
    case largest
    case central

    public func choose(from faces: [DetectedFace], imageWidth: Double, imageHeight: Double) -> [DetectedFace] {
        switch self {
        case .all:
            return faces
        case .largest:
            return faces.max { $0.boundingBox.area < $1.boundingBox.area }.map { [$0] } ?? []
        case .central:
            let centre = Point2D(imageWidth / 2, imageHeight / 2)
            return faces.min {
                $0.boundingBox.center.distance(to: centre) < $1.boundingBox.center.distance(to: centre)
            }.map { [$0] } ?? []
        }
    }
}
