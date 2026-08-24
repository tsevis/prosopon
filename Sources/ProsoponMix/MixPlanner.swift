import Foundation

/// Decides which four photographs make each composite, and which quadrant each one takes.
///
/// Not a shuffle. The joins are what the piece is made of, so the assignment is driven by
/// a measurement of the pixels either side of every seam:
///
/// 1. **The most frontal half of the corpus is reserved for the top quadrants.** That is
///    where the eyes are, and where a viewer looks first. Splitting the pool by frontality
///    before matching satisfies it exactly, rather than expressing it as a preference in a
///    cost function that a strong tone match could then outvote.
/// 2. **The mouth seam is matched first**, with the mouth band weighted several times the
///    rest of the strip. It is the hardest join in the picture — two halves of two
///    different mouths, meeting only because both are on the same pixels by construction —
///    so it gets the first and widest choice.
/// 3. **Then the cheeks**, each top quadrant chosen to meet the bottom one below it. The
///    second top pick also has to meet the first across the nose bridge, so it is scored
///    on both.
///
/// Greedy, and deliberately so: this is an assignment problem over hundreds of tiles where
/// an optimal solution is not worth its cost, and a good first choice on the hardest seam
/// is worth more than a balanced compromise across all four.
public enum MixPlanner {

    /// How much the mouth band counts against the rest of the vertical bottom strip.
    ///
    /// The strip runs the full 1024 px of the bottom half — chin, neck, shoulder, backdrop
    /// — and the mouth is a few hundred of them. Left unweighted, a matching backdrop
    /// would outvote a matching mouth, which is exactly backwards.
    static let mouthBandWeight = 4.0

    public static func plan(
        _ measurements: [TileMeasurement],
        seed: UInt64,
        frontalityBasis: FrontalityBasis
    ) -> MixPlan {
        guard measurements.count >= 4 else {
            return MixPlan(
                composites: [], unusedTileIndices: Array(measurements.indices),
                seed: seed, frontalityBasis: frontalityBasis
            )
        }

        var generator = SeededGenerator(seed: seed)
        let compositeCount = measurements.count / 4
        let (topPool, bottomPool) = pools(
            measurements, compositeCount: compositeCount,
            basis: frontalityBasis, using: &generator
        )

        var top = topPool
        var bottom = bottomPool
        var composites: [CompositePlan] = []

        for index in 0..<compositeCount {
            guard let plan = compose(
                index: index, measurements: measurements, top: &top, bottom: &bottom
            ) else { break }
            composites.append(plan)
        }

        let placed = Set(composites.flatMap { $0.quadrants.map(\.tileIndex) })
        let unused = measurements.indices.filter { !placed.contains($0) }

        return MixPlan(
            composites: composites, unusedTileIndices: unused,
            seed: seed, frontalityBasis: frontalityBasis
        )
    }

    // MARK: Pools

    /// Splits the corpus into the half that goes on top and the half that goes below.
    ///
    /// Exactly `2 x compositeCount` tiles are reserved for the top, which is the number of
    /// top slots there will be. Anything beyond `4 x compositeCount` is the remainder and
    /// falls out of the bottom pool's tail, where it is left unused rather than displacing
    /// a more frontal face from a top quadrant.
    private static func pools(
        _ measurements: [TileMeasurement],
        compositeCount: Int,
        basis: FrontalityBasis,
        using generator: inout SeededGenerator
    ) -> ([Int], [Int]) {
        let ranked = measurements.indices.sorted { left, right in
            let a = frontality(measurements[left], basis: basis)
            let b = frontality(measurements[right], basis: basis)
            if a != b { return a < b }
            // Ties break on name so a run is reproducible whatever order the filesystem
            // handed the tiles over in.
            return measurements[left].name < measurements[right].name
        }

        let topCount = compositeCount * 2
        var top = Array(ranked.prefix(topCount))
        var bottom = Array(ranked.dropFirst(topCount))
        top.shuffle(using: &generator)
        bottom.shuffle(using: &generator)
        return (top, bottom)
    }

    /// Lower is more frontal. Absent measurements sort last rather than pretending to be
    /// zero, since a detector's silence is not evidence of a frontal face.
    private static func frontality(_ tile: TileMeasurement, basis: FrontalityBasis) -> Double {
        switch basis {
        case .yaw: abs(tile.yawDegrees ?? .infinity)
        case .score: -(tile.score ?? -.infinity)
        case .none: 0
        }
    }

    // MARK: One composite

    private static func compose(
        index: Int,
        measurements: [TileMeasurement],
        top: inout [Int],
        bottom: inout [Int]
    ) -> CompositePlan? {
        // The bottom pool can run dry before the top one when the remainder falls that
        // way, so both are drawn through one helper that borrows from the other pool
        // rather than abandoning a composite half-built.
        guard let bottomLeft = take(first: &bottom, other: &top) else { return nil }

        // Two faces found in one photograph are two tiles with the same source. Putting
        // them in one composite would be quartering a portrait with itself, so a
        // candidate already represented is refused outright rather than merely
        // discouraged — and if refusing leaves nothing, `pick` falls back to the seeded
        // order and says so, because every tile is still used exactly once.
        var claimed: Set<String> = [measurements[bottomLeft].sourcePath]

        let bottomRight = pick(
            from: &bottom, fallback: &top,
            cost: { candidate in
                guard !claimed.contains(measurements[candidate].sourcePath) else { return .infinity }
                return verticalCost(
                    left: measurements[bottomLeft], right: measurements[candidate],
                    leftSide: .bottomLeftRight, rightSide: .bottomRightLeft
                )
            }
        )
        guard let bottomRight else { return nil }
        claimed.insert(measurements[bottomRight.index].sourcePath)

        let topLeft = pick(
            from: &top, fallback: &bottom,
            cost: { candidate in
                guard !claimed.contains(measurements[candidate].sourcePath) else { return .infinity }
                return horizontalCost(
                    above: measurements[candidate], below: measurements[bottomLeft],
                    aboveSide: .topLeftBottom, belowSide: .bottomLeftTop
                )
            }
        )
        guard let topLeft else { return nil }
        claimed.insert(measurements[topLeft.index].sourcePath)

        let topRight = pick(
            from: &top, fallback: &bottom,
            cost: { candidate in
                guard !claimed.contains(measurements[candidate].sourcePath) else { return .infinity }
                return horizontalCost(
                    above: measurements[candidate], below: measurements[bottomRight.index],
                    aboveSide: .topRightBottom, belowSide: .bottomRightTop
                )
                    + verticalCost(
                        left: measurements[topLeft.index], right: measurements[candidate],
                        leftSide: .topLeftRight, rightSide: .topRightLeft
                    )
            }
        )
        guard let topRight else { return nil }

        let assignments = [
            QuadrantAssignment(quadrant: .topLeft, tileIndex: topLeft.index,
                               reason: topLeft.matched ? .cheekSeam : .randomFallback,
                               cost: topLeft.cost),
            QuadrantAssignment(quadrant: .topRight, tileIndex: topRight.index,
                               reason: topRight.matched ? .cheekAndBridge : .randomFallback,
                               cost: topRight.cost),
            QuadrantAssignment(quadrant: .bottomLeft, tileIndex: bottomLeft,
                               reason: .seed, cost: nil),
            QuadrantAssignment(quadrant: .bottomRight, tileIndex: bottomRight.index,
                               reason: bottomRight.matched ? .mouthSeam : .randomFallback,
                               cost: bottomRight.cost),
        ]

        let tiles = [
            Quadrant.topLeft: measurements[topLeft.index],
            .topRight: measurements[topRight.index],
            .bottomLeft: measurements[bottomLeft],
            .bottomRight: measurements[bottomRight.index],
        ]

        return CompositePlan(
            index: index,
            quadrants: assignments,
            seamCosts: seamCosts(tiles),
            mouthBandCost: mouthBandCost(tiles)
        )
    }

    // MARK: Drawing from the pools

    private struct Pick {
        let index: Int
        let cost: Double?
        /// False when the tile was taken from the seeded order because there was nothing
        /// to choose between, or nothing left in its own pool.
        let matched: Bool
    }

    /// The next tile from `pool`, borrowing from `other` when it is empty.
    private static func take(first pool: inout [Int], other: inout [Int]) -> Int? {
        if !pool.isEmpty { return pool.removeFirst() }
        if !other.isEmpty { return other.removeFirst() }
        return nil
    }

    /// The candidate in `pool` with the lowest cost.
    ///
    /// When the pool is empty the pick is borrowed from `fallback` and marked as such:
    /// every tile is used exactly once, so running out of the right pool has to produce a
    /// worse composite rather than a missing one.
    private static func pick(
        from pool: inout [Int],
        fallback: inout [Int],
        cost: (Int) -> Double
    ) -> Pick? {
        if pool.isEmpty {
            guard !fallback.isEmpty else { return nil }
            return Pick(index: fallback.removeFirst(), cost: nil, matched: false)
        }

        var bestPosition = 0
        var bestCost = Double.infinity
        for (position, candidate) in pool.enumerated() {
            let value = cost(candidate)
            if value < bestCost {
                bestCost = value
                bestPosition = position
            }
        }
        // An unmeasurable candidate scores infinity; if every one of them did, there is
        // nothing to have chosen between and the pick is the seeded order's, not a match.
        guard bestCost.isFinite else {
            return Pick(index: pool.removeFirst(), cost: nil, matched: false)
        }
        return Pick(index: pool.remove(at: bestPosition), cost: bestCost, matched: true)
    }

    // MARK: Costs

    /// Across a vertical seam. The bottom one runs through the mouth, so its band is
    /// weighted; the top one has no band and this reduces to the strip alone.
    static func verticalCost(
        left: TileMeasurement, right: TileMeasurement,
        leftSide: SeamSide, rightSide: SeamSide
    ) -> Double {
        guard let a = left.edges[leftSide], let b = right.edges[rightSide] else { return .infinity }
        var total = a.distance(to: b)
        if let mouthA = left.mouthEdges[leftSide], let mouthB = right.mouthEdges[rightSide] {
            total += mouthBandWeight * mouthA.distance(to: mouthB)
        }
        return total
    }

    static func horizontalCost(
        above: TileMeasurement, below: TileMeasurement,
        aboveSide: SeamSide, belowSide: SeamSide
    ) -> Double {
        guard let a = above.edges[aboveSide], let b = below.edges[belowSide] else { return .infinity }
        return a.distance(to: b)
    }

    /// What every join in a finished composite came out at, for the manifest.
    static func seamCosts(_ tiles: [Quadrant: TileMeasurement]) -> [Seam: Double] {
        var costs: [Seam: Double] = [:]
        for seam in Seam.allCases {
            let (first, second) = seam.sides
            guard let a = tiles[first.quadrant]?.edges[first],
                  let b = tiles[second.quadrant]?.edges[second]
            else { continue }
            costs[seam] = a.distance(to: b)
        }
        return costs
    }

    /// The mouth band alone, unweighted, which is the figure to read when a mouth looks
    /// wrong.
    static func mouthBandCost(_ tiles: [Quadrant: TileMeasurement]) -> Double {
        guard let a = tiles[.bottomLeft]?.mouthEdges[.bottomLeftRight],
              let b = tiles[.bottomRight]?.mouthEdges[.bottomRightLeft]
        else { return .infinity }
        return a.distance(to: b)
    }
}
