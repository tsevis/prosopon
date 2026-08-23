import Foundation
import Testing
@testable import ProsoponCore

/// Builds landmarks for a synthetic face, so tests can dial proportion, roll, scale and
/// position independently.
private func syntheticFace(
    interocular d: Double = 400,
    mouthDropRatio ratio: Double = 1.125,
    mouthOffsetX: Double = 0,
    rollDegrees: Double = 0,
    center: Point2D = Point2D(1000, 800)
) -> FaceLandmarks {
    let theta = rollDegrees * .pi / 180
    let (c, s) = (cos(theta), sin(theta))
    func place(_ x: Double, _ y: Double) -> Point2D {
        Point2D(center.x + x * c - y * s, center.y + x * s + y * c)
    }
    return FaceLandmarks(
        viewerLeftEye: place(-d / 2, 0),
        viewerRightEye: place(d / 2, 0),
        mouth: place(mouthOffsetX, ratio * d)
    )
}

@Suite("AlignmentSolver")
struct AlignmentSolverTests {

    // MARK: The invariant everything else depends on

    @Test("both eyes land exactly on target, whatever the face")
    func eyesAreAlwaysExact() throws {
        let cases: [FaceLandmarks] = [
            syntheticFace(),
            syntheticFace(mouthDropRatio: 0.80),          // stretch clamps hard
            syntheticFace(mouthDropRatio: 1.60),          // squash clamps hard
            syntheticFace(mouthOffsetX: 90),              // shear clamps
            syntheticFace(rollDegrees: 23),
            syntheticFace(mouthDropRatio: 1.02, mouthOffsetX: -40, rollDegrees: -14),
            syntheticFace(interocular: 37, center: Point2D(5, 900)),
            syntheticFace(interocular: 3100, center: Point2D(-400, 120)),
        ]
        for face in cases {
            let alignment = try AlignmentSolver.solve(landmarks: face)
            #expect(alignment.eyeResidual < 1e-6, "eye residual \(alignment.eyeResidual)")
        }
    }

    @Test("a randomised sweep never moves the eyes")
    func eyesExactUnderRandomInput() throws {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let face = syntheticFace(
                interocular: .random(in: 20...2000, using: &generator),
                mouthDropRatio: .random(in: 0.7...1.8, using: &generator),
                mouthOffsetX: .random(in: -200...200, using: &generator),
                rollDegrees: .random(in: -45...45, using: &generator),
                center: Point2D(
                    .random(in: -500...4000, using: &generator),
                    .random(in: -500...4000, using: &generator)
                )
            )
            let alignment = try AlignmentSolver.solve(landmarks: face)
            #expect(alignment.eyeResidual < 1e-6)
        }
    }

    // MARK: Mouth placement

    @Test("a face already at 1.125 needs no correction and lands all three points")
    func canonicalFaceIsExact() throws {
        let alignment = try AlignmentSolver.solve(landmarks: syntheticFace(mouthDropRatio: 1.125))
        #expect(abs(alignment.appliedStretch - 1) < 1e-9)
        #expect(abs(alignment.appliedShear) < 1e-9)
        #expect(alignment.mouthResidual.length < 1e-6)
        #expect(!alignment.stretchWasClamped)
    }

    @Test("a face inside the 5 percent budget lands the mouth exactly")
    func withinBudgetIsExact() throws {
        // 1.125 / 1.08 = 1.0417, a 4.17 percent stretch: inside the cap.
        let alignment = try AlignmentSolver.solve(landmarks: syntheticFace(mouthDropRatio: 1.08))
        #expect(!alignment.stretchWasClamped)
        #expect(alignment.appliedStretchPercent > 4.1 && alignment.appliedStretchPercent < 4.2)
        #expect(alignment.mouthResidual.length < 1e-6)
    }

    @Test("beyond the budget the stretch clamps and the mouth lands high by a predictable amount")
    func beyondBudgetClamps() throws {
        // 1.125 / 1.00 = 1.125 wanted, 1.05 allowed.
        let alignment = try AlignmentSolver.solve(landmarks: syntheticFace(mouthDropRatio: 1.00))
        #expect(alignment.stretchWasClamped)
        #expect(abs(alignment.requestedStretch - 1.125) < 1e-9)
        #expect(abs(alignment.appliedStretch - 1.05) < 1e-9)

        // Similarity puts the mouth 1024 px below the eye line; 1.05 of that is 1075.2,
        // against a 1152 target, so the mouth sits 76.8 px high.
        #expect(abs(alignment.mouthResidual.y + 76.8) < 1e-6)
        #expect(alignment.mouthResidual.y < 0, "a clamped stretch leaves the mouth above target")
    }

    @Test("squash clamps symmetrically in ratio")
    func squashClampsSymmetrically() throws {
        let alignment = try AlignmentSolver.solve(landmarks: syntheticFace(mouthDropRatio: 1.6))
        #expect(alignment.stretchWasClamped)
        #expect(abs(alignment.appliedStretch - 1 / 1.05) < 1e-9)
    }

    @Test("shear slides the mouth onto the centre line without disturbing the eyes")
    func shearCentresTheMouth() throws {
        // 30 px off-centre on a 400 px interocular: 76.8 px in canvas space, over a
        // 1152 px drop. That is a shear of 0.0667 -- clamped to 0.05.
        let modest = try AlignmentSolver.solve(landmarks: syntheticFace(mouthOffsetX: 10))
        #expect(!modest.shearWasClamped)
        #expect(abs(modest.mouthResidual.x) < 1e-6)
        #expect(modest.eyeResidual < 1e-6)

        let extreme = try AlignmentSolver.solve(landmarks: syntheticFace(mouthOffsetX: 100))
        #expect(extreme.shearWasClamped)
        #expect(abs(extreme.appliedShear) == 0.05)
        #expect(extreme.eyeResidual < 1e-6)
    }

    @Test("horizontal correction can be switched off")
    func shearIsOptional() throws {
        let options = SolveOptions(maxStretch: 0.05, maxShear: 0.05, correctsHorizontalMouthOffset: false)
        let alignment = try AlignmentSolver.solve(landmarks: syntheticFace(mouthOffsetX: 20), options: options)
        #expect(alignment.appliedShear == 0)
        #expect(alignment.requestedShear == 0)
        #expect(abs(alignment.mouthResidual.x) > 1)
    }

    // MARK: Rigid mode

    @Test("rigid mode is a pure similarity: eyes exact, mouth uncorrected")
    func rigidModeIsSimilarity() throws {
        let face = syntheticFace(mouthDropRatio: 1.00)
        let alignment = try AlignmentSolver.solve(landmarks: face, options: .rigid)
        #expect(alignment.appliedStretch == 1)
        #expect(alignment.appliedShear == 0)
        #expect(alignment.eyeResidual < 1e-6)
        // 1.125 - 1.00 of an interocular distance, in canvas pixels.
        #expect(abs(alignment.mouthResidual.y + 128) < 1e-6)
        let (hi, lo) = alignment.transform.singularValues
        #expect(abs(hi - lo) < 1e-9, "a similarity has equal singular values")
    }

    // MARK: Roll

    @Test("roll is removed and reported")
    func rollIsRemoved() throws {
        let alignment = try AlignmentSolver.solve(landmarks: syntheticFace(rollDegrees: 20))
        #expect(alignment.eyeResidual < 1e-6)
        #expect(abs(abs(alignment.rollCorrectionDegrees) - 20) < 1e-6)
    }

    @Test("scale is recovered from the interocular distance")
    func scaleIsRecovered() throws {
        let alignment = try AlignmentSolver.solve(landmarks: syntheticFace(interocular: 512))
        // 1024 target over 512 source: everything doubles.
        #expect(abs(alignment.magnification - 2) < 1e-6)
    }

    // MARK: Failures

    @Test("coincident eyes are rejected")
    func degenerateEyesThrow() {
        let face = FaceLandmarks(
            viewerLeftEye: Point2D(100, 100),
            viewerRightEye: Point2D(100, 100),
            mouth: Point2D(100, 300)
        )
        #expect(throws: AlignmentFailure.self) { try AlignmentSolver.solve(landmarks: face) }
    }

    @Test("a mouth above the eye line is rejected")
    func upsideDownFaceThrows() {
        let face = FaceLandmarks(
            viewerLeftEye: Point2D(100, 500),
            viewerRightEye: Point2D(500, 500),
            mouth: Point2D(300, 100)
        )
        #expect(throws: AlignmentFailure.self) { try AlignmentSolver.solve(landmarks: face) }
    }

    // MARK: The 5 percent rule, read off the transform

    @Test("applied anisotropy never exceeds 5 percent")
    func anisotropyIsBounded() throws {
        for ratio in stride(from: 0.6, through: 2.0, by: 0.02) {
            let alignment = try AlignmentSolver.solve(
                landmarks: syntheticFace(mouthDropRatio: ratio),
                options: SolveOptions(maxStretch: 0.05, maxShear: 0, correctsHorizontalMouthOffset: false)
            )
            let (hi, lo) = alignment.transform.singularValues
            #expect(hi / lo <= 1.05 + 1e-9, "ratio \(ratio) gave anisotropy \(hi / lo)")
        }
    }
}
