import Foundation

/// A 2-D affine transform, laid out to match `CGAffineTransform` exactly so that
/// bridging to Core Graphics is a field-for-field copy.
///
///     x' = a * x + c * y + tx
///     y' = b * x + d * y + ty
public struct Affine2D: Hashable, Sendable, Codable {
    public var a, b, c, d, tx, ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    public static let identity = Affine2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(_ dx: Double, _ dy: Double) -> Affine2D {
        Affine2D(a: 1, b: 0, c: 0, d: 1, tx: dx, ty: dy)
    }

    public static func scale(x sx: Double, y sy: Double) -> Affine2D {
        Affine2D(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    public func apply(to p: Point2D) -> Point2D {
        Point2D(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty)
    }

    /// `self` first, then `later`. Same argument order as `CGAffineTransformConcat`.
    public func concatenating(_ later: Affine2D) -> Affine2D {
        Affine2D(
            a: a * later.a + b * later.c,
            b: a * later.b + b * later.d,
            c: c * later.a + d * later.c,
            d: c * later.b + d * later.d,
            tx: tx * later.a + ty * later.c + later.tx,
            ty: tx * later.b + ty * later.d + later.ty
        )
    }

    public var determinant: Double { a * d - b * c }

    public var inverted: Affine2D? {
        let det = determinant
        guard abs(det) > .ulpOfOne else { return nil }
        return Affine2D(
            a: d / det,
            b: -b / det,
            c: -c / det,
            d: a / det,
            tx: (c * ty - d * tx) / det,
            ty: (b * tx - a * ty) / det
        )
    }

    /// Singular values of the 2x2 linear part, largest first.
    ///
    /// These are the true per-axis scale factors of the mapping, independent of how
    /// rotation and shear are distributed. `singularValues.0` is the direction of
    /// greatest magnification, which is what governs softness in the output.
    public var singularValues: (Double, Double) {
        let frobenius = a * a + b * b + c * c + d * d
        let twiceDet = 2 * abs(determinant)
        let hi = (max(0, frobenius + twiceDet)).squareRoot()
        let lo = (max(0, frobenius - twiceDet)).squareRoot()
        return ((hi + lo) / 2, (hi - lo) / 2)
    }
}
