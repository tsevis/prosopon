import Testing
@testable import ProsoponMix

/// What a seam signature can and cannot tell apart.
///
/// The whole point of the profile is the first test here: two strips that a mean calls
/// identical, and an eye calls a broken join.
@Suite("Seam profiles")
struct SeamProfileTests {

    /// A strip running from `first` to `last`, evenly, in L* alone.
    private func ramp(from first: Double, to last: Double, count: Int = 16) -> EdgeSignature {
        let samples = (0..<count).map { index -> LabSample in
            let t = count == 1 ? 0 : Double(index) / Double(count - 1)
            return LabSample(lightness: first + (last - first) * t, greenRed: 0, blueYellow: 0)
        }
        let mean = samples.map(\.lightness).reduce(0, +) / Double(samples.count)
        return EdgeSignature(
            lightness: mean, greenRed: 0, blueYellow: 0, texture: 0, profile: samples
        )
    }

    @Test("two strips running in opposite directions are not a match")
    func opposedRampsAreNotAMatch() {
        // The failure the profile exists for. One side lightens down the seam, the other
        // darkens; their means are identical, so the old distance called this perfect.
        let lightening = ramp(from: 40, to: 60)
        let darkening = ramp(from: 60, to: 40)

        #expect(lightening.meanDistance(to: darkening) < 0.001, "the means agree exactly")
        #expect(lightening.distance(to: darkening) > 10, "the join does not")
    }

    @Test("a strip matches itself exactly")
    func identicalStripsCostNothing() {
        let strip = ramp(from: 40, to: 60)
        #expect(strip.distance(to: strip) == 0)
    }

    @Test("a constant step is cheaper than a reversal of the same size")
    func aStepBeatsADivergence() {
        // Both are wrong, and they are wrong differently: a step is a visible line, a
        // divergence is the two halves drifting apart. The second should cost more.
        let base = ramp(from: 40, to: 60)
        let stepped = ramp(from: 50, to: 70)
        let reversed = ramp(from: 60, to: 40)

        #expect(base.distance(to: stepped) < base.distance(to: reversed))
    }

    @Test("the worst point along a join is reported, not just the average")
    func worstDisagreementFindsTheEnd() {
        let flat = ramp(from: 50, to: 50)
        let sloped = ramp(from: 50, to: 70)
        // They agree at one end and are 20 apart at the other.
        #expect(sloped.worstDisagreement(with: flat) > 19)
        #expect(sloped.worstDisagreement(with: flat) < 21)
    }

    @Test("a signature with no profile still compares, on its mean")
    func fallsBackWhenThereIsNoProfile() {
        // Older measurements carry no profile. They must still be comparable rather than
        // scoring infinity and silently losing every match.
        let a = EdgeSignature(lightness: 50, greenRed: 2, blueYellow: 3, texture: 1)
        let b = EdgeSignature(lightness: 54, greenRed: 2, blueYellow: 3, texture: 1)
        #expect(a.distance(to: b) == 4)
    }

    @Test("texture still breaks ties between strips that otherwise agree")
    func textureStillCounts() {
        var smooth = ramp(from: 50, to: 50)
        var rough = ramp(from: 50, to: 50)
        smooth.texture = 1
        rough.texture = 9
        #expect(smooth.distance(to: rough) == EdgeSignature.textureWeight * 8)
    }
}
