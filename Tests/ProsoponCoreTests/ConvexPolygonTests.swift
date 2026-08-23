import Foundation
import Testing
@testable import ProsoponCore

@Suite("ConvexPolygon")
struct ConvexPolygonTests {

    private let unitSquare = [Point2D(0, 0), Point2D(10, 0), Point2D(10, 10), Point2D(0, 10)]

    @Test("area of a square")
    func squareArea() {
        #expect(abs(ConvexPolygon.area(unitSquare) - 100) < 1e-9)
    }

    @Test("area is independent of winding")
    func areaIgnoresWinding() {
        #expect(abs(ConvexPolygon.area(unitSquare.reversed()) - 100) < 1e-9)
    }

    @Test("clipping by a containing polygon is a no-op in area")
    func clipByContainer() {
        let big = [Point2D(-5, -5), Point2D(15, -5), Point2D(15, 15), Point2D(-5, 15)]
        #expect(abs(ConvexPolygon.area(ConvexPolygon.clip(unitSquare, by: big)) - 100) < 1e-9)
    }

    @Test("half overlap gives half the area")
    func halfOverlap() {
        let right = [Point2D(5, -5), Point2D(15, -5), Point2D(15, 15), Point2D(5, 15)]
        #expect(abs(ConvexPolygon.area(ConvexPolygon.clip(unitSquare, by: right)) - 50) < 1e-9)
    }

    @Test("disjoint polygons clip to nothing")
    func disjoint() {
        let far = [Point2D(100, 100), Point2D(110, 100), Point2D(110, 110), Point2D(100, 110)]
        #expect(ConvexPolygon.area(ConvexPolygon.clip(unitSquare, by: far)) < 1e-9)
    }

    @Test("clipping is insensitive to the winding of either polygon")
    func windingInsensitive() {
        let right = [Point2D(5, -5), Point2D(15, -5), Point2D(15, 15), Point2D(5, 15)]
        let combinations = [
            ConvexPolygon.clip(unitSquare, by: right),
            ConvexPolygon.clip(unitSquare.reversed(), by: right),
            ConvexPolygon.clip(unitSquare, by: right.reversed()),
            ConvexPolygon.clip(unitSquare.reversed(), by: right.reversed()),
        ]
        for polygon in combinations {
            #expect(abs(ConvexPolygon.area(polygon) - 50) < 1e-9)
        }
    }
}
