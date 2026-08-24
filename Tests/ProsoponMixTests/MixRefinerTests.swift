import Foundation
import Testing
@testable import ProsoponMix

/// What the refinement pass must never do, whatever it gains by it.
@Suite("Mix refinement")
struct MixRefinerTests {

    /// A tile whose every strip is one flat colour, so joins are predictable.
    private func tile(_ name: String, lightness: Double, source: String? = nil) -> TileMeasurement {
        let signature = EdgeSignature(
            lightness: lightness, greenRed: 0, blueYellow: 0, texture: 0,
            profile: Array(
                repeating: LabSample(lightness: lightness, greenRed: 0, blueYellow: 0),
                count: EdgeSignature.profileLength
            )
        )
        var edges: [SeamSide: EdgeSignature] = [:]
        var mouths: [SeamSide: EdgeSignature] = [:]
        for side in SeamSide.allCases {
            edges[side] = signature
            if side.crossesTheMouth { mouths[side] = signature }
        }
        return TileMeasurement(
            tileURL: URL(fileURLWithPath: "/tmp/\(name).png"),
            sourcePath: source ?? "/src/\(name).png",
            name: name, yawDegrees: 0, score: 1, edges: edges, mouthEdges: mouths
        )
    }

    /// Eight tiles in two tone groups that the greedy order deliberately interleaves, so
    /// there is something for the refiner to find.
    private var interleaved: [TileMeasurement] {
        [
            tile("a", lightness: 20), tile("b", lightness: 80),
            tile("c", lightness: 20), tile("d", lightness: 80),
            tile("e", lightness: 20), tile("f", lightness: 80),
            tile("g", lightness: 20), tile("h", lightness: 80),
        ]
    }

    @Test("every tile is still used exactly once")
    func usesEveryTileOnce() {
        let measurements = interleaved
        let plan = MixPlanner.plan(measurements, seed: 1, frontalityBasis: .score)
        let placed = plan.placedTileIndices

        #expect(Set(placed).count == placed.count, "no tile appears twice")
        #expect(
            Set(placed).union(plan.unusedTileIndices) == Set(measurements.indices),
            "and none has gone missing"
        )
    }

    @Test("no composite ends up with two faces from one photograph")
    func neverPutsAPhotographAgainstItself() {
        // The refiner swaps on tone alone, and two tiles cut from one photograph match
        // each other perfectly — so this is exactly the swap it would most like to make.
        let measurements = [
            tile("a1", lightness: 50, source: "/src/one.png"),
            tile("a2", lightness: 50, source: "/src/one.png"),
            tile("b1", lightness: 50, source: "/src/two.png"),
            tile("b2", lightness: 50, source: "/src/two.png"),
            tile("c1", lightness: 51, source: "/src/three.png"),
            tile("c2", lightness: 51, source: "/src/three.png"),
            tile("d1", lightness: 51, source: "/src/four.png"),
            tile("d2", lightness: 51, source: "/src/four.png"),
        ]
        let plan = MixPlanner.plan(measurements, seed: 3, frontalityBasis: .score)

        for composite in plan.composites {
            let sources = composite.quadrants.map { measurements[$0.tileIndex].sourcePath }
            #expect(Set(sources).count == sources.count, "composite \(composite.index) repeats a source")
        }
    }

    @Test("the frontality reservation survives refinement")
    func keepsTheMostFrontalFacesOnTop() {
        // Splitting the pool before matching is a decision made on purpose; a pass that
        // swaps on tone must not quietly undo it. Scores are distinct so the intended
        // top half is unambiguous.
        let measurements = (0..<8).map { index in
            var t = tile("t\(index)", lightness: index.isMultiple(of: 2) ? 20 : 80)
            t = TileMeasurement(
                tileURL: t.tileURL, sourcePath: t.sourcePath, name: t.name,
                yawDegrees: nil, score: Double(8 - index), edges: t.edges, mouthEdges: t.mouthEdges
            )
            return t
        }
        let plan = MixPlanner.plan(measurements, seed: 1, frontalityBasis: .score)

        let onTop = Set(
            plan.composites.flatMap { composite in
                composite.quadrants.filter { $0.quadrant.isTop }.map(\.tileIndex)
            }
        )
        // Four top slots over two composites, filled from the four highest scores.
        #expect(onTop == Set(0..<4), "the top quadrants hold the four most frontal tiles")
    }

    @Test("refining never makes a composite worse than the greedy pass left it")
    func neverRegresses() {
        let measurements = interleaved
        let greedyOnly = MixPlanner.plan(measurements, seed: 1, frontalityBasis: .score)

        let total = greedyOnly.composites.reduce(0.0) { sum, composite in
            var tiles: [Quadrant: Int] = [:]
            for quadrant in composite.quadrants { tiles[quadrant.quadrant] = quadrant.tileIndex }
            return sum + MixRefiner.cost(tiles, measurements)
        }
        #expect(total.isFinite)

        // Refining an already-refined plan must find nothing left to take.
        let again = MixRefiner.refine(greedyOnly, measurements: measurements)
        let againTotal = again.composites.reduce(0.0) { sum, composite in
            var tiles: [Quadrant: Int] = [:]
            for quadrant in composite.quadrants { tiles[quadrant.quadrant] = quadrant.tileIndex }
            return sum + MixRefiner.cost(tiles, measurements)
        }
        #expect(againTotal <= total + 1e-9, "a settled plan does not drift")
    }

    @Test("a plan with one composite is left alone")
    func nothingToSwapWithOneComposite() {
        let measurements = Array(interleaved.prefix(4))
        let plan = MixPlanner.plan(measurements, seed: 1, frontalityBasis: .score)
        #expect(plan.composites.count == 1)
        #expect(plan.placedTileIndices.count == 4)
    }
}
