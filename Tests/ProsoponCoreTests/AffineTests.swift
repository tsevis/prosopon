import Foundation
import Testing
@testable import ProsoponCore

private let epsilon = 1e-9

@Suite("Affine2D")
struct AffineTests {

    @Test("identity leaves points alone")
    func identity() {
        let p = Point2D(37, -12)
        #expect(Affine2D.identity.apply(to: p) == p)
    }

    @Test("concatenation applies the receiver first")
    func concatenationOrder() {
        let move = Affine2D.translation(10, 0)
        let double = Affine2D.scale(x: 2, y: 2)

        // move first, then scale: (0,0) -> (10,0) -> (20,0)
        let moveThenScale = move.concatenating(double).apply(to: .zero)
        #expect(abs(moveThenScale.x - 20) < epsilon)

        // scale first, then move: (0,0) -> (0,0) -> (10,0)
        let scaleThenMove = double.concatenating(move).apply(to: .zero)
        #expect(abs(scaleThenMove.x - 10) < epsilon)
    }

    @Test("inverse round-trips an arbitrary point")
    func inverseRoundTrip() throws {
        let t = Affine2D(a: 1.3, b: 0.4, c: -0.2, d: 0.9, tx: 17, ty: -6)
        let inverse = try #require(t.inverted)
        let p = Point2D(123, 456)
        let back = inverse.apply(to: t.apply(to: p))
        #expect(abs(back.x - p.x) < 1e-9)
        #expect(abs(back.y - p.y) < 1e-9)
    }

    @Test("singular values of a uniform scale are both the scale")
    func singularValuesUniform() {
        let (hi, lo) = Affine2D.scale(x: 3, y: 3).singularValues
        #expect(abs(hi - 3) < epsilon)
        #expect(abs(lo - 3) < epsilon)
    }

    @Test("singular values recover both axes of a non-uniform scale")
    func singularValuesAnisotropic() {
        let (hi, lo) = Affine2D.scale(x: 4, y: 2).singularValues
        #expect(abs(hi - 4) < epsilon)
        #expect(abs(lo - 2) < epsilon)
    }

    @Test("rotation does not change singular values")
    func singularValuesRotationInvariant() {
        let angle = 0.7
        let rotation = Affine2D(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle), tx: 0, ty: 0)
        let combined = Affine2D.scale(x: 4, y: 2).concatenating(rotation)
        let (hi, lo) = combined.singularValues
        #expect(abs(hi - 4) < 1e-9)
        #expect(abs(lo - 2) < 1e-9)
    }
}
