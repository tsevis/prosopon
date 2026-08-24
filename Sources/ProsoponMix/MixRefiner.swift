import Foundation

/// Improves a finished plan by swapping tiles between composites.
///
/// The planner is greedy, and greedy on a hard problem leaves a great deal behind: it
/// commits to the first composite's four tiles before it has seen what the fifty-first
/// needs, and a tile that would have joined beautifully somewhere else is long gone by
/// the time that place comes up. The joins are what the piece is made of, so it is worth
/// a second pass.
///
/// This is a 2-opt: try exchanging the tiles in two slots, keep the exchange if the two
/// composites together get better, repeat until a whole sweep finds nothing. It cannot
/// make the plan worse — every accepted swap strictly lowers the total — and it cannot
/// change what the plan *is*: every tile is still used exactly once, and no composite
/// ever holds two faces from one photograph.
///
/// Top slots are only ever swapped with top slots. The reservation of the most frontal
/// half for the quadrants with the eyes in them is a decision made before matching, and
/// this pass must not quietly undo it by finding a good tone match for a face in profile.
public enum MixRefiner {

    /// A slot in the plan: which composite, and which quadrant of it.
    struct Slot: Sendable {
        let composite: Int
        let quadrant: Quadrant
    }

    /// How many full sweeps to allow.
    ///
    /// A sweep that improves nothing stops the pass, so this only bounds the pathological
    /// case. On 51 composites it settles in single figures.
    static let maxSweeps = 12

    public static func refine(_ plan: MixPlan, measurements: [TileMeasurement]) -> MixPlan {
        guard plan.composites.count > 1 else { return plan }

        // Tiles by slot, which is the only thing that changes.
        var assignment: [[Quadrant: Int]] = plan.composites.map { composite in
            var byQuadrant: [Quadrant: Int] = [:]
            for quadrant in composite.quadrants { byQuadrant[quadrant.quadrant] = quadrant.tileIndex }
            return byQuadrant
        }

        let slots = assignment.indices.flatMap { composite in
            Quadrant.allCases.map { Slot(composite: composite, quadrant: $0) }
        }

        for _ in 0..<maxSweeps {
            var improved = false
            for (first, a) in slots.enumerated() {
                for b in slots[(first + 1)...] {
                    guard a.composite != b.composite else { continue }
                    // The frontality split is a hard decision, not a preference.
                    guard a.quadrant.isTop == b.quadrant.isTop else { continue }
                    guard let gain = gainFromSwapping(
                        a, b, in: &assignment, measurements: measurements
                    ), gain > 0 else { continue }
                    improved = true
                }
            }
            if !improved { break }
        }

        return rebuild(plan, assignment: assignment, measurements: measurements)
    }

    /// Performs the swap when it helps, and reports what it saved. Nil when the swap is
    /// not allowed at all.
    private static func gainFromSwapping(
        _ a: Slot,
        _ b: Slot,
        in assignment: inout [[Quadrant: Int]],
        measurements: [TileMeasurement]
    ) -> Double? {
        guard let tileA = assignment[a.composite][a.quadrant],
              let tileB = assignment[b.composite][b.quadrant]
        else { return nil }

        let before = cost(assignment[a.composite], measurements)
            + cost(assignment[b.composite], measurements)

        assignment[a.composite][a.quadrant] = tileB
        assignment[b.composite][b.quadrant] = tileA

        // A swap that puts two faces from one photograph in one composite is not a swap,
        // however well the tones join.
        guard isWellFormed(assignment[a.composite], measurements),
              isWellFormed(assignment[b.composite], measurements)
        else {
            assignment[a.composite][a.quadrant] = tileA
            assignment[b.composite][b.quadrant] = tileB
            return nil
        }

        let after = cost(assignment[a.composite], measurements)
            + cost(assignment[b.composite], measurements)

        guard after < before else {
            assignment[a.composite][a.quadrant] = tileA
            assignment[b.composite][b.quadrant] = tileB
            return 0
        }
        return before - after
    }

    /// No photograph twice in one composite.
    static func isWellFormed(
        _ composite: [Quadrant: Int], _ measurements: [TileMeasurement]
    ) -> Bool {
        let sources = composite.values.map { measurements[$0].sourcePath }
        return Set(sources).count == sources.count
    }

    /// What all four joins of one composite come to, with the mouth weighted as the
    /// planner weights it. The same currency the planner chooses in, so a swap that
    /// lowers this is a swap the planner would have preferred had it seen it.
    static func cost(_ composite: [Quadrant: Int], _ measurements: [TileMeasurement]) -> Double {
        guard let topLeft = composite[.topLeft], let topRight = composite[.topRight],
              let bottomLeft = composite[.bottomLeft], let bottomRight = composite[.bottomRight]
        else { return .infinity }

        let total = MixPlanner.verticalCost(
            left: measurements[bottomLeft], right: measurements[bottomRight],
            leftSide: .bottomLeftRight, rightSide: .bottomRightLeft
        )
            + MixPlanner.verticalCost(
                left: measurements[topLeft], right: measurements[topRight],
                leftSide: .topLeftRight, rightSide: .topRightLeft
            )
            + MixPlanner.horizontalCost(
                above: measurements[topLeft], below: measurements[bottomLeft],
                aboveSide: .topLeftBottom, belowSide: .bottomLeftTop
            )
            + MixPlanner.horizontalCost(
                above: measurements[topRight], below: measurements[bottomRight],
                aboveSide: .topRightBottom, belowSide: .bottomRightTop
            )
        return total
    }

    /// Puts the plan back together from the refined assignment.
    ///
    /// Every quadrant a swap touched is marked `refined`, so the manifest still says how
    /// each tile came to be where it is rather than crediting the greedy pass for a
    /// choice it did not make.
    private static func rebuild(
        _ plan: MixPlan, assignment: [[Quadrant: Int]], measurements: [TileMeasurement]
    ) -> MixPlan {
        let composites = plan.composites.enumerated().map { index, composite -> CompositePlan in
            let quadrants = composite.quadrants.map { original -> QuadrantAssignment in
                guard let tile = assignment[index][original.quadrant] else { return original }
                guard tile != original.tileIndex else { return original }
                return QuadrantAssignment(
                    quadrant: original.quadrant, tileIndex: tile, reason: .refined, cost: nil
                )
            }
            var tiles: [Quadrant: TileMeasurement] = [:]
            for quadrant in quadrants { tiles[quadrant.quadrant] = measurements[quadrant.tileIndex] }
            return CompositePlan(
                index: composite.index,
                quadrants: quadrants,
                seamCosts: MixPlanner.seamCosts(tiles),
                mouthBandCost: MixPlanner.mouthBandCost(tiles),
                worstSeamDisagreement: MixPlanner.worstSeamDisagreement(tiles)
            )
        }
        return MixPlan(
            composites: composites, unusedTileIndices: plan.unusedTileIndices,
            seed: plan.seed, frontalityBasis: plan.frontalityBasis
        )
    }
}
