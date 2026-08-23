import Foundation
import ProsoponCore

/// One tile measured against the stack's consensus.
public struct TileQA: Sendable, Codable {
    public var name: String
    public var path: String
    public var offsets: [Landmark: ConsensusOffset]

    /// The largest landmark displacement, which is what decides whether a tile is worth
    /// a second look.
    public var worstDisplacement: Double {
        offsets.values.map(\.magnitude).max() ?? 0
    }

    public var worstLandmark: Landmark? {
        offsets.max { $0.value.magnitude < $1.value.magnitude }?.key
    }

    public var lowestCorrelation: Double {
        offsets.values.map(\.correlation).min() ?? 0
    }

    public var anyClipped: Bool { offsets.values.contains(where: \.clipped) }
}

/// How sharp the stack's average is in a region, relative to how sharp the individual
/// tiles are there.
///
/// One means the average is as crisp as a single face, which no real stack reaches
/// because faces genuinely differ. What matters is the contrast between the landmarks
/// and everywhere else: high at the eyes and mouth and low elsewhere is precisely the
/// signature of a correctly registered stack.
public struct SharpnessRetention: Sendable, Codable {
    public var meanImageAcutance: Double
    public var averageTileAcutance: Double
    public var retention: Double
}

public struct StackQA: Sendable, Codable {
    public var tileCount: Int
    public var canvasSize: Double
    public var landmarkSharpness: [Landmark: SharpnessRetention]
    public var globalSharpness: SharpnessRetention
    public var tiles: [TileQA]

    /// Landmark retention divided by whole-canvas retention.
    ///
    /// Above one says the eyes and mouth survived averaging better than the rest of the
    /// face did, which is the thing being checked. Around one says the landmarks blurred
    /// just as much as the hair, and the stack is not registered.
    public var registrationContrast: Double {
        let landmarks = landmarkSharpness.values.map(\.retention)
        guard !landmarks.isEmpty, globalSharpness.retention > 1e-9 else { return .nan }
        let average = landmarks.reduce(0, +) / Double(landmarks.count)
        return average / globalSharpness.retention
    }

    public var displacements: [Double] {
        tiles.map(\.worstDisplacement).sorted()
    }

    public func percentile(_ fraction: Double) -> Double {
        let sorted = displacements
        guard !sorted.isEmpty else { return .nan }
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[index]
    }

    /// Below this correlation, the search did not find the feature at all, so whatever
    /// displacement it reports is meaningless.
    public static let matchFloor = 0.7

    /// Tiles that were matched confidently but sit further than `pixels` from consensus.
    ///
    /// These are the alignment failures: the landmark was found, and it is in the wrong
    /// place. Tiles that could not be matched are excluded and reported separately,
    /// because the two call for different responses.
    public func suspects(beyond pixels: Double, matchedAbove floor: Double = matchFloor) -> [TileQA] {
        tiles.filter { $0.lowestCorrelation >= floor && $0.worstDisplacement > pixels }
            .sorted { $0.worstDisplacement > $1.worstDisplacement }
    }

    /// Tiles the consensus could not be matched against at all.
    ///
    /// A mirrored face, a very different pose, or a detection landing on the wrong
    /// feature entirely. The reported displacement is not a measurement in these cases,
    /// so calling them misaligned by so many pixels would be inventing a number.
    public func unmatched(below floor: Double = matchFloor) -> [TileQA] {
        tiles.filter { $0.lowestCorrelation < floor }
            .sorted { $0.lowestCorrelation < $1.lowestCorrelation }
    }
}

extension ConsensusOffset {
    public var describedOffset: String {
        String(format: "%+.2f,%+.2f", dx, dy)
    }
}
