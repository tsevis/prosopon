import Foundation

/// How far one tile's landmark sits from where the rest of the stack agrees it should be.
public struct ConsensusOffset: Hashable, Sendable, Codable {
    /// Displacement in canvas pixels. Positive `dx` means this tile's feature sits to
    /// the right of the consensus.
    public let dx: Double
    public let dy: Double
    /// Peak normalised cross-correlation, 0...1. A low value means the comparison found
    /// nothing to lock onto, so the offset should not be trusted.
    public let correlation: Double
    /// True when the best match sat on the edge of the search window, meaning the real
    /// displacement is at least this large and possibly larger.
    public let clipped: Bool

    public init(dx: Double, dy: Double, correlation: Double, clipped: Bool) {
        self.dx = dx
        self.dy = dy
        self.correlation = correlation
        self.clipped = clipped
    }

    public var magnitude: Double { (dx * dx + dy * dy).squareRoot() }

    public static let none = ConsensusOffset(dx: 0, dy: 0, correlation: 0, clipped: false)
}

public enum Registration {
    /// Side of the window actually compared, in canvas pixels. A 96 px square centred on
    /// an eye covers the iris and the inner lid margins, which is plenty of structure to
    /// lock onto without dragging in the eyebrow.
    public static let windowSide = 96
    /// How far the search looks, in pixels, in each direction.
    public static let searchRadius = 10
    /// The patch that must be cached per tile to allow that search.
    public static var patchSide: Int { windowSide + 2 * searchRadius }

    /// Finds the displacement that best aligns `tile` to `reference`.
    ///
    /// Both patches must be `patchSide` square; only the central `windowSide` square is
    /// compared, which is what leaves room for the search to shift without running off
    /// the edge. Correlation rather than plain difference, so that a tile which is
    /// merely darker than the average is not mistaken for a misaligned one.
    public static func consensusOffset(
        of tile: LuminancePatch,
        against reference: LuminancePatch,
        searchRadius: Int = searchRadius
    ) -> ConsensusOffset {
        let side = reference.side
        let window = side - 2 * searchRadius
        guard tile.side == side, window > 2 else { return .none }

        let referenceWindow = centredWindow(reference, window: window, offsetX: 0, offsetY: 0)
        let referenceMean = referenceWindow.reduce(0.0) { $0 + Double($1) } / Double(referenceWindow.count)
        let referenceCentred = referenceWindow.map { Double($0) - referenceMean }
        let referenceEnergy = referenceCentred.reduce(0.0) { $0 + $1 * $1 }
        guard referenceEnergy > 1e-9 else { return .none }

        var scores = [Double](repeating: -1, count: (2 * searchRadius + 1) * (2 * searchRadius + 1))
        var best = (score: -Double.infinity, dx: 0, dy: 0)

        for dy in -searchRadius...searchRadius {
            for dx in -searchRadius...searchRadius {
                let candidate = centredWindow(tile, window: window, offsetX: dx, offsetY: dy)
                let score = correlation(referenceCentred, referenceEnergy, candidate)
                scores[(dy + searchRadius) * (2 * searchRadius + 1) + (dx + searchRadius)] = score
                if score > best.score { best = (score, dx, dy) }
            }
        }

        guard best.score > -.infinity else { return .none }
        let clipped = abs(best.dx) == searchRadius || abs(best.dy) == searchRadius

        // Fit a parabola through the peak and its neighbours on each axis. The true
        // displacement is rarely a whole number of pixels, and rounding it to one would
        // put a floor on every measurement this tool reports.
        func refine(_ axis: (Int) -> Double) -> Double {
            let low = axis(-1), centre = axis(0), high = axis(1)
            let denominator = low - 2 * centre + high
            guard abs(denominator) > 1e-12 else { return 0 }
            return max(-0.5, min(0.5, 0.5 * (low - high) / denominator))
        }
        func score(_ dx: Int, _ dy: Int) -> Double {
            guard abs(dx) <= searchRadius, abs(dy) <= searchRadius else { return -1 }
            return scores[(dy + searchRadius) * (2 * searchRadius + 1) + (dx + searchRadius)]
        }

        let subX = clipped ? 0 : refine { score(best.dx + $0, best.dy) }
        let subY = clipped ? 0 : refine { score(best.dx, best.dy + $0) }

        return ConsensusOffset(
            dx: Double(best.dx) + subX,
            dy: Double(best.dy) + subY,
            correlation: best.score,
            clipped: clipped
        )
    }

    private static func centredWindow(
        _ patch: LuminancePatch, window: Int, offsetX: Int, offsetY: Int
    ) -> [UInt8] {
        let origin = (patch.side - window) / 2
        var output = [UInt8](repeating: 0, count: window * window)
        patch.values.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                for row in 0..<window {
                    let y = min(max(origin + row + offsetY, 0), patch.side - 1)
                    let sourceRow = y * patch.side
                    for column in 0..<window {
                        let x = min(max(origin + column + offsetX, 0), patch.side - 1)
                        destination[row * window + column] = source[sourceRow + x]
                    }
                }
            }
        }
        return output
    }

    private static func correlation(
        _ referenceCentred: [Double], _ referenceEnergy: Double, _ candidate: [UInt8]
    ) -> Double {
        let count = Double(candidate.count)
        var sum = 0.0
        for value in candidate { sum += Double(value) }
        let mean = sum / count

        var cross = 0.0
        var energy = 0.0
        candidate.withUnsafeBufferPointer { values in
            referenceCentred.withUnsafeBufferPointer { reference in
                for index in 0..<values.count {
                    let centred = Double(values[index]) - mean
                    cross += reference[index] * centred
                    energy += centred * centred
                }
            }
        }
        guard energy > 1e-9 else { return -1 }
        return cross / (referenceEnergy * energy).squareRoot()
    }
}
