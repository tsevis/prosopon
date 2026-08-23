import Foundation
import Testing
@testable import ProsoponCore

@Suite("CanvasSpec")
struct CanvasSpecTests {

    @Test("the standard canvas matches the specification exactly")
    func standardConstants() {
        let spec = CanvasSpec.standard
        #expect(spec.size == 2048)
        #expect(spec.gridStep == 128)
        #expect(spec.viewerLeftEye == Point2D(512, 512))
        #expect(spec.viewerRightEye == Point2D(1536, 512))
        #expect(spec.mouth == Point2D(1024, 1664))
        #expect(spec.interocularDistance == 1024)
        #expect(spec.eyeLineY == 512)
        #expect(spec.mouthDrop == 1152)
        #expect(spec.mouthDropRatio == 1.125)
    }

    @Test("all three targets land on grid intersections")
    func targetsAreOnTheGrid() {
        let spec = CanvasSpec.standard
        for point in [spec.viewerLeftEye, spec.viewerRightEye, spec.mouth] {
            #expect(point.x.truncatingRemainder(dividingBy: spec.gridStep) == 0)
            #expect(point.y.truncatingRemainder(dividingBy: spec.gridStep) == 0)
        }
    }

    @Test("scaling to 4096 preserves every proportion")
    func scalingPreservesProportions() {
        let big = CanvasSpec.standard.scaled(toSize: 4096)
        #expect(big.viewerLeftEye == Point2D(1024, 1024))
        #expect(big.viewerRightEye == Point2D(3072, 1024))
        #expect(big.mouth == Point2D(2048, 3328))
        #expect(big.mouthDropRatio == CanvasSpec.standard.mouthDropRatio)
    }
}
