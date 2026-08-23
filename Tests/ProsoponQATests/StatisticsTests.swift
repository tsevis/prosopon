import Foundation
import ProsoponRender
import Testing
@testable import ProsoponQA

@Suite("Stack statistics")
struct StatisticsTests {

    private func pixels(_ values: [UInt16], width: Int, height: Int) -> LinearPixels {
        var image = LinearPixels.empty(width: width, height: height)
        for (index, value) in values.enumerated() {
            image.samples[index * 4] = value
            image.samples[index * 4 + 1] = value
            image.samples[index * 4 + 2] = value
            image.samples[index * 4 + 3] = 65535
        }
        return image
    }

    @Test("the mean matches a direct average")
    func meanIsCorrect() {
        var statistics = StackStatistics(width: 2, height: 1)
        let frames: [[UInt16]] = [[100, 200], [300, 400], [500, 900]]
        for frame in frames { statistics.add(pixels(frame, width: 2, height: 1)) }

        let mean = statistics.mean()
        #expect(mean.samples[0] == 300, "average of 100, 300, 500")
        #expect(mean.samples[4] == 500, "average of 200, 400, 900")
        #expect(mean.samples[3] == 65535, "the average of full-coverage tiles is opaque")
    }

    @Test("the deviation matches a direct standard deviation")
    func deviationIsCorrect() {
        var statistics = StackStatistics(width: 1, height: 1)
        for value in [UInt16(100), 200, 300] { statistics.add(pixels([value], width: 1, height: 1)) }

        // Population sigma of 100, 200, 300 is 81.6497; the image is scaled by the gain.
        let deviation = statistics.deviation(gain: 1)
        #expect(abs(Int(deviation.samples[0]) - 82) <= 1)
    }

    @Test("a stack of identical tiles has no deviation at all")
    func identicalStackIsFlat() {
        var statistics = StackStatistics(width: 4, height: 4)
        for _ in 0..<5 { statistics.add(pixels([UInt16](repeating: 4242, count: 16), width: 4, height: 4)) }
        #expect(statistics.deviation(gain: 10).samples.allSatisfy { $0 == 0 || $0 == 65535 })
        #expect(statistics.mean().samples[0] == 4242)
    }

    @Test("an empty stack yields an empty mean rather than dividing by zero")
    func emptyStack() {
        let statistics = StackStatistics(width: 2, height: 2)
        #expect(statistics.count == 0)
        #expect(statistics.mean().samples.allSatisfy { $0 == 0 })
        #expect(statistics.deviation().samples.allSatisfy { $0 == 0 })
    }
}

@Suite("Luminance patch")
struct LuminancePatchTests {

    @Test("acutance falls when detail is blurred away")
    func acutanceRespondsToBlur() {
        let side = 32
        var sharp = [UInt8](repeating: 0, count: side * side)
        for row in 0..<side {
            for column in 0..<side {
                sharp[row * side + column] = (column / 2) % 2 == 0 ? 255 : 0
            }
        }
        // A three-tap box blur across the stripes.
        var blurred = sharp
        for row in 0..<side {
            for column in 1..<(side - 1) {
                let total = Int(sharp[row * side + column - 1])
                    + Int(sharp[row * side + column])
                    + Int(sharp[row * side + column + 1])
                blurred[row * side + column] = UInt8(total / 3)
            }
        }

        let sharpAcutance = LuminancePatch(side: side, values: sharp).acutance
        let blurredAcutance = LuminancePatch(side: side, values: blurred).acutance
        #expect(blurredAcutance < sharpAcutance * 0.8,
                "blurring should cost acutance: \(blurredAcutance) against \(sharpAcutance)")
    }

    @Test("a flat patch has no acutance")
    func flatPatchIsZero() {
        #expect(LuminancePatch(side: 16, values: [UInt8](repeating: 128, count: 256)).acutance == 0)
    }
}
