import Foundation
import ProsoponCore
import Testing
@testable import ProsoponMix

/// The quartering, and the one fact about it that is not a preference.
@Suite("Quadrant geometry")
struct QuadrantGeometryTests {

    private let grid = QuadrantGrid()

    @Test("the mouth target lands exactly on the vertical seam, in the bottom half")
    func mouthIsOnTheSeam() {
        // This is the hardest join in the picture and the reason the arrangement works at
        // all: the two bottom quadrants each carry half a mouth, from two different
        // people, and they meet only because both mouths are on the same pixels by
        // construction. Anyone who "helpfully" moves the seam off the mouth fails here.
        #expect(grid.mouthSitsOnTheVerticalSeam)
        #expect(grid.mouthX == 1024)
        #expect(grid.mouthY == 1664)
        #expect(grid.quadrantSize == 1024)
    }

    @Test("the eyes sit well inside the two top quadrants")
    func eyesAreInTheTopQuadrants() {
        let spec = CanvasSpec.standard
        #expect(spec.viewerLeftEye.x < Double(grid.quadrantSize))
        #expect(spec.viewerLeftEye.y < Double(grid.quadrantSize))
        #expect(spec.viewerRightEye.x > Double(grid.quadrantSize))
        #expect(spec.viewerRightEye.y < Double(grid.quadrantSize))
    }

    @Test("each quadrant starts where the last one ends")
    func origins() {
        #expect(grid.origin(of: .topLeft) == (0, 0))
        #expect(grid.origin(of: .topRight) == (1024, 0))
        #expect(grid.origin(of: .bottomLeft) == (0, 1024))
        #expect(grid.origin(of: .bottomRight) == (1024, 1024))
    }

    @Test("the two halves of the mouth seam are adjacent and on opposite sides of it")
    func mouthSeamStrips() {
        let left = grid.strip(.bottomLeftRight)
        let right = grid.strip(.bottomRightLeft)
        #expect(left.x + left.width == grid.quadrantSize, "the left strip ends at the seam")
        #expect(right.x == grid.quadrantSize, "the right strip starts at it")
        #expect(left.y == grid.quadrantSize && right.y == grid.quadrantSize)
        #expect(left.height == grid.quadrantSize && right.height == grid.quadrantSize)
    }

    @Test("the mouth band is a slice of the seam that the mouth actually runs through")
    func mouthBand() throws {
        let band = try #require(grid.mouthBand(.bottomLeftRight))
        #expect(band.y < grid.mouthY && band.y + band.height > grid.mouthY)
        #expect(band.y >= grid.quadrantSize, "it stays inside the bottom half")
        #expect(band.height < grid.quadrantSize, "and it is a band, not the whole strip")
        #expect(grid.mouthBand(.topLeftRight) == nil, "the top seam has no mouth on it")
    }

    @Test("every seam strip falls inside the canvas", arguments: SeamSide.allCases)
    func stripsAreOnCanvas(side: SeamSide) {
        let strip = grid.strip(side)
        #expect(strip.x >= 0 && strip.y >= 0)
        #expect(strip.x + strip.width <= grid.canvasSize)
        #expect(strip.y + strip.height <= grid.canvasSize)
        #expect(strip.width > 0 && strip.height > 0)
    }

    @Test("every seam names the two quadrants it joins", arguments: Seam.allCases)
    func seamsPairQuadrants(seam: Seam) {
        let (first, second) = seam.sides
        #expect(first.quadrant != second.quadrant)
    }

    @Test("only the two bottom vertical strips cross the mouth")
    func onlyTheBottomSeamHasAMouth() {
        let crossing = SeamSide.allCases.filter(\.crossesTheMouth)
        #expect(Set(crossing) == [.bottomLeftRight, .bottomRightLeft])
    }

    @Test("the proportions follow the canvas rather than being hard-coded")
    func scaledCanvas() {
        // A run re-rendered at 4096 from stored transforms quarters the same way.
        let large = QuadrantGrid(spec: CanvasSpec.standard.scaled(toSize: 4096))
        #expect(large.canvasSize == 4096)
        #expect(large.quadrantSize == 2048)
        #expect(large.mouthSitsOnTheVerticalSeam)
    }
}
