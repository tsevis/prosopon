import Foundation
import Testing
@testable import ProsoponMix

/// The assignment: who goes where, and the invariants that have to hold over a whole batch
/// rather than over one composite.
@Suite("Mix planner")
struct MixPlannerTests {

    // MARK: Building measurements

    /// A tile whose seam strips are flat greys at the lightnesses given. Enough to drive
    /// the matcher, and readable in a test in a way real photographs are not.
    private func tile(
        _ name: String,
        yaw: Double? = nil,
        score: Double? = nil,
        edges: [SeamSide: Double] = [:],
        mouth: [SeamSide: Double] = [:]
    ) -> TileMeasurement {
        func signatures(_ values: [SeamSide: Double]) -> [SeamSide: EdgeSignature] {
            values.mapValues {
                EdgeSignature(lightness: $0, greenRed: 0, blueYellow: 0, texture: 0)
            }
        }
        return TileMeasurement(
            tileURL: URL(fileURLWithPath: "/tmp/\(name).png"),
            sourcePath: "/tmp/source/\(name).jpg",
            name: name,
            yawDegrees: yaw,
            score: score,
            edges: signatures(edges),
            mouthEdges: signatures(mouth)
        )
    }

    /// `count` tiles, every strip present, lightnesses spread so nothing ties.
    private func spread(_ count: Int, yawFrom: (Int) -> Double? = { _ in nil }) -> [TileMeasurement] {
        (0..<count).map { index in
            var edges: [SeamSide: Double] = [:]
            for (offset, side) in SeamSide.allCases.enumerated() {
                edges[side] = Double((index * 7 + offset * 13) % 100)
            }
            return tile(
                String(format: "tile%02d", index),
                yaw: yawFrom(index),
                edges: edges,
                mouth: [
                    .bottomLeftRight: Double((index * 11) % 100),
                    .bottomRightLeft: Double((index * 17) % 100),
                ]
            )
        }
    }

    // MARK: Every image once, and only once

    @Test("every tile is placed exactly once across the whole batch")
    func everyTileUsedOnce() {
        // The rule for the piece: no face appears twice anywhere in a run. Checked over
        // the batch, not over one composite, because a per-composite check would pass a
        // planner that reused a tile in the next one.
        let measurements = spread(16)
        let plan = MixPlanner.plan(measurements, seed: 1, frontalityBasis: .none)

        #expect(plan.composites.count == 4)
        let placed = plan.placedTileIndices
        #expect(placed.count == 16)
        #expect(Set(placed).count == 16, "a tile was used twice")
        #expect(plan.unusedTileIndices.isEmpty)
        #expect(plan.composites.allSatisfy { $0.quadrants.count == 4 })
        #expect(Set(plan.composites.flatMap { $0.quadrants.map(\.quadrant) }).count == 4)
    }

    @Test("a remainder is left out and named rather than dropped in silence",
          arguments: [(13, 3, 1), (14, 3, 2), (15, 3, 3), (16, 4, 0)])
    func remainder(count: Int, composites: Int, leftOver: Int) {
        let measurements = spread(count)
        let plan = MixPlanner.plan(measurements, seed: 1, frontalityBasis: .none)

        #expect(plan.composites.count == composites)
        #expect(plan.unusedTileIndices.count == leftOver)

        // Placed and unused together account for every tile, once each.
        let all = Set(plan.placedTileIndices).union(plan.unusedTileIndices)
        #expect(all == Set(measurements.indices))
        #expect(Set(plan.placedTileIndices).isDisjoint(with: Set(plan.unusedTileIndices)))
    }

    @Test("fewer than four tiles makes no composite at all")
    func tooFewToCompose() {
        let plan = MixPlanner.plan(spread(3), seed: 1, frontalityBasis: .none)
        #expect(plan.composites.isEmpty)
        #expect(plan.unusedTileIndices == [0, 1, 2])
    }

    // MARK: Reproducibility

    @Test("the same seed produces the same batch")
    func seedIsReproducible() {
        let measurements = spread(20)
        let first = MixPlanner.plan(measurements, seed: 7, frontalityBasis: .none)
        let second = MixPlanner.plan(measurements, seed: 7, frontalityBasis: .none)
        #expect(first.placedTileIndices == second.placedTileIndices)
        #expect(first.unusedTileIndices == second.unusedTileIndices)
    }

    @Test("a different seed produces a different batch")
    func seedChangesTheBatch() {
        // Otherwise the seed is decoration. Every tile here has identical strips, so the
        // costs all tie and the shuffle is the only thing deciding -- which is exactly the
        // case where a seed that did nothing would go unnoticed.
        let flat = (0..<16).map { index in
            tile(
                String(format: "tile%02d", index),
                edges: Dictionary(uniqueKeysWithValues: SeamSide.allCases.map { ($0, 50.0) }),
                mouth: [.bottomLeftRight: 50, .bottomRightLeft: 50]
            )
        }
        let first = MixPlanner.plan(flat, seed: 1, frontalityBasis: .none)
        let second = MixPlanner.plan(flat, seed: 2, frontalityBasis: .none)
        #expect(first.placedTileIndices != second.placedTileIndices)
    }

    // MARK: What drives the choice

    @Test("the most frontal half of the corpus fills the top quadrants")
    func frontalFacesGoOnTop() {
        // The eyes are up there and it is where a viewer looks first, so frontality is
        // settled by splitting the pool before any matching happens rather than by a term
        // in the cost that a strong tone match could outvote.
        let measurements = spread(8) { index in index < 4 ? Double(index) : Double(30 + index) }
        let plan = MixPlanner.plan(measurements, seed: 3, frontalityBasis: .yaw)

        let onTop = Set(plan.composites.flatMap { composite in
            composite.quadrants.filter { $0.quadrant.isTop }.map(\.tileIndex)
        })
        #expect(onTop == [0, 1, 2, 3], "the four turned faces should be underneath")
    }

    @Test("with no usable frontality measurement the top pool is just the seeded order")
    func noFrontalityStillPlaces() {
        let plan = MixPlanner.plan(spread(8), seed: 5, frontalityBasis: .none)
        #expect(plan.composites.count == 2)
        #expect(Set(plan.placedTileIndices).count == 8)
    }

    @Test("the mouth band decides the bottom pair even when the rest of the seam disagrees")
    func mouthBandOutweighsTheRestOfTheSeam() {
        // Two tiles whose mouths meet, and two whose backdrops meet. The strip runs the
        // whole 1024 px of the bottom half -- chin, neck, shoulder -- so left unweighted a
        // matching backdrop would outvote a matching mouth, which is backwards.
        var tiles: [TileMeasurement] = []
        for index in 0..<4 {
            tiles.append(tile(
                "top\(index)", yaw: 0,
                edges: Dictionary(uniqueKeysWithValues: SeamSide.allCases.map { ($0, 50.0) })
            ))
        }
        // Mouths pair (0,1) and (2,3); whole strips pair across those pairs instead.
        let mouthValue = [0.0, 0.0, 50.0, 50.0]
        let stripLeft = [0.0, 0.0, 40.0, 40.0]
        let stripRight = [40.0, 40.0, 0.0, 0.0]
        for index in 0..<4 {
            var edges = Dictionary(uniqueKeysWithValues: SeamSide.allCases.map { ($0, 50.0) })
            edges[.bottomLeftRight] = stripLeft[index]
            edges[.bottomRightLeft] = stripRight[index]
            tiles.append(tile(
                "bottom\(index)", yaw: 40,
                edges: edges,
                mouth: [.bottomLeftRight: mouthValue[index], .bottomRightLeft: mouthValue[index]]
            ))
        }

        let plan = MixPlanner.plan(tiles, seed: 1, frontalityBasis: .yaw)
        let mouthPairs: Set<Set<Int>> = [[4, 5], [6, 7]]
        for composite in plan.composites {
            let bottom = Set([
                composite.tileIndex(for: .bottomLeft),
                composite.tileIndex(for: .bottomRight),
            ].compactMap { $0 })
            #expect(mouthPairs.contains(bottom),
                    "the bottom pair \(bottom.sorted()) matched on the backdrop, not the mouth")
        }
    }

    @Test("each quadrant records what it was matched on")
    func reasonsAreRecorded() throws {
        let plan = MixPlanner.plan(spread(8), seed: 1, frontalityBasis: .none)
        let composite = try #require(plan.composites.first)
        let reasons = Dictionary(
            uniqueKeysWithValues: composite.quadrants.map { ($0.quadrant, $0.reason) }
        )
        #expect(reasons[.bottomLeft] == .seed)
        #expect(reasons[.bottomRight] == .mouthSeam)
        #expect(reasons[.topLeft] == .cheekSeam)
        #expect(reasons[.topRight] == .cheekAndBridge)

        // A seed pick was not chosen by cost, so it has none; the rest do.
        #expect(composite.quadrants.first { $0.quadrant == .bottomLeft }?.cost == nil)
        #expect(composite.quadrants.first { $0.quadrant == .bottomRight }?.cost != nil)
    }

    @Test("every join is measured and recorded")
    func seamCostsRecorded() {
        let plan = MixPlanner.plan(spread(8), seed: 1, frontalityBasis: .none)
        for composite in plan.composites {
            #expect(Set(composite.seamCosts.keys) == Set(Seam.allCases))
            #expect(composite.seamCosts.values.allSatisfy { $0.isFinite })
            #expect(composite.mouthBandCost.isFinite)
        }
    }

    // MARK: When matching cannot answer

    @Test("a tile with no measurable strips is still used, and says it was not matched")
    func unmeasurableTilesFallBack() {
        // Falling back to the seeded order rather than dropping the tile: every image is
        // used exactly once, and a composite that cannot be matched is still a composite.
        let blank = (0..<8).map { tile("blank\($0)") }
        let plan = MixPlanner.plan(blank, seed: 1, frontalityBasis: .none)

        #expect(plan.composites.count == 2)
        #expect(Set(plan.placedTileIndices).count == 8)

        let reasons = Set(plan.composites.flatMap { $0.quadrants.map(\.reason) })
        #expect(reasons.contains(.randomFallback))
        #expect(!reasons.contains(.mouthSeam), "there was nothing to match on")
    }

    @Test("a corpus where only some tiles measure still places all of them")
    func mixedMeasurability() {
        var tiles = spread(6)
        tiles.append(contentsOf: [tile("blankA"), tile("blankB")])
        let plan = MixPlanner.plan(tiles, seed: 2, frontalityBasis: .none)
        #expect(Set(plan.placedTileIndices).count == 8)
    }
}

/// Two faces found in one photograph are two tiles with the same source.
@Suite("Mix planner, one photograph per composite")
struct MixPlannerSourceTests {

    private func tile(_ name: String, source: String) -> TileMeasurement {
        // Identical strips throughout, so tone gives the matcher no reason to prefer one
        // candidate over another and the source constraint is the only thing acting.
        let flat = Dictionary(uniqueKeysWithValues: SeamSide.allCases.map {
            ($0, EdgeSignature(lightness: 50, greenRed: 0, blueYellow: 0, texture: 0))
        })
        return TileMeasurement(
            tileURL: URL(fileURLWithPath: "/tmp/\(name).png"),
            sourcePath: source, name: name, yawDegrees: nil, score: nil,
            edges: flat,
            mouthEdges: [
                .bottomLeftRight: EdgeSignature(lightness: 50, greenRed: 0, blueYellow: 0, texture: 0),
                .bottomRightLeft: EdgeSignature(lightness: 50, greenRed: 0, blueYellow: 0, texture: 0),
            ]
        )
    }

    @Test("two faces from the same photograph do not share a composite")
    func sameSourceIsRefused() {
        // Quartering a portrait with itself is not the piece. A group photograph yields
        // one tile per face, all with the same source path, and nothing else distinguishes
        // them here — so a planner that only matched on tone would pair them every time.
        var tiles: [TileMeasurement] = []
        for group in 0..<4 {
            for face in 0..<2 {
                tiles.append(tile("group\(group)_f\(face)", source: "/photos/group\(group).jpg"))
            }
        }

        let plan = MixPlanner.plan(tiles, seed: 1, frontalityBasis: .none)
        #expect(plan.composites.count == 2)
        for composite in plan.composites {
            let sources = composite.quadrants.map { tiles[$0.tileIndex].sourcePath }
            #expect(Set(sources).count == 4, "one photograph filled \(sources.count - Set(sources).count + 1) quadrants")
        }
    }

    @Test("when every remaining tile shares a source the composite is still made")
    func refusalDoesNotStrandATile() {
        // Four faces from one photograph and nothing else: the constraint cannot be
        // honoured, so it gives way rather than leaving tiles unused. Every image is used
        // exactly once whatever happens, and the quadrant says it was not matched.
        let tiles = (0..<4).map { tile("crowd_f\($0)", source: "/photos/crowd.jpg") }
        let plan = MixPlanner.plan(tiles, seed: 1, frontalityBasis: .none)

        #expect(plan.composites.count == 1)
        #expect(plan.unusedTileIndices.isEmpty)
        #expect(Set(plan.placedTileIndices).count == 4)
        #expect(plan.composites[0].quadrants.contains { $0.reason == .randomFallback })
    }
}
