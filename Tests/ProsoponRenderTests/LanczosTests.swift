import Foundation
import ProsoponCore
import Testing
@testable import ProsoponRender

@Suite("Lanczos kernel")
struct LanczosTests {

    @Test("the kernel is one at the centre")
    func unitAtOrigin() {
        #expect(abs(Lanczos.weight(0) - 1) < 1e-12)
    }

    @Test("the kernel vanishes at every other integer, which is what makes identity exact")
    func zeroAtIntegers() {
        for k in [-2, -1, 1, 2] {
            #expect(abs(Lanczos.weight(Double(k))) < 1e-9, "L(\(k)) should be 0")
        }
    }

    @Test("support ends at three")
    func compactSupport() {
        #expect(Lanczos.weight(3) == 0)
        #expect(Lanczos.weight(-3) == 0)
        #expect(Lanczos.weight(4.7) == 0)
        #expect(Lanczos.weight(-100) == 0)
    }

    @Test("the kernel is symmetric")
    func symmetry() {
        for x in stride(from: 0.0, through: 3.0, by: 0.05) {
            #expect(abs(Lanczos.weight(x) - Lanczos.weight(-x)) < 1e-12)
        }
    }

    @Test("the kernel goes negative between the first and second zero, as a windowed sinc does")
    func hasNegativeLobes() {
        #expect(Lanczos.weight(1.5) < 0)
        #expect(Lanczos.weight(2.5) > 0)
    }
}

@Suite("WarpPlan")
struct WarpPlanTests {

    private func plan(scale: Double, canvas: Int = 256, source: Int = 4000) throws -> WarpPlan {
        try WarpPlan.make(
            transform: Affine2D.scale(x: scale, y: scale),
            sourceWidth: source, sourceHeight: source, canvasSize: canvas
        )
    }

    @Test("enlarging keeps the kernel at its natural width")
    func magnificationUsesNaturalSupport() throws {
        let made = try plan(scale: 2)
        #expect(made.kernelScaleX == 1)
        #expect(made.supportX == 3)
    }

    @Test("reducing widens the footprint by the inverse of the scale")
    func minificationWidensSupport() throws {
        // Halving the size means one output pixel covers two source pixels, so the
        // three-lobe footprint has to reach six source pixels rather than three. A
        // fixed footprint here is exactly what aliases.
        let made = try plan(scale: 0.5)
        #expect(abs(made.kernelScaleX - 0.5) < 1e-12)
        #expect(abs(made.supportX - 6) < 1e-12)

        let quarter = try plan(scale: 0.25)
        #expect(abs(quarter.supportX - 12) < 1e-12)
    }

    @Test("the footprint is capped so extreme reduction cannot explode the tap count")
    func supportIsCapped() throws {
        let made = try plan(scale: 0.001)
        #expect(made.supportX <= WarpPlan.maximumSupport + 1e-9)
    }

    @Test("rotation is measured per source axis, not from the matrix diagonal")
    func supportUnderRotation() throws {
        // A pure rotation neither enlarges nor reduces, whatever the diagonal says.
        let angle = 0.6
        let rotation = Affine2D(
            a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle), tx: 0, ty: 0
        )
        let made = try WarpPlan.make(
            transform: rotation, sourceWidth: 2000, sourceHeight: 2000, canvasSize: 256
        )
        #expect(abs(made.kernelScaleX - 1) < 1e-9)
        #expect(abs(made.kernelScaleY - 1) < 1e-9)
    }

    @Test("only the region the canvas reaches is cropped from the source")
    func cropIsLimitedToWhatIsNeeded() throws {
        // A 256 canvas at 1:1 from a 4000 px source needs 256 px plus filter margin,
        // not the whole photograph.
        let made = try WarpPlan.make(
            transform: Affine2D.translation(-1000, -1000),
            sourceWidth: 4000, sourceHeight: 4000, canvasSize: 256
        )
        #expect(made.cropX == 996)
        #expect(made.cropY == 996)
        #expect(made.cropWidth <= 256 + 16)
        #expect(made.cropHeight <= 256 + 16)
    }

    @Test("a non-invertible transform is refused")
    func degenerateTransformThrows() {
        #expect(throws: RenderError.self) {
            try WarpPlan.make(
                transform: Affine2D.scale(x: 0, y: 1),
                sourceWidth: 100, sourceHeight: 100, canvasSize: 64
            )
        }
    }
}
