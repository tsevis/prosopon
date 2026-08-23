import Foundation
import ProsoponRender

/// Running per-pixel mean and standard deviation over a stack of aligned tiles.
///
/// Accumulated in one pass so the stack never has to be held in memory: three hundred
/// 2048 x 2048 tiles is several gigabytes, while two accumulators are a fixed 200 MB
/// whatever the corpus size.
public struct StackStatistics {
    public let width: Int
    public let height: Int
    public private(set) var count: Int = 0

    /// Doubles rather than floats: summing three hundred 16-bit samples reaches 2e7,
    /// which is already past where a 24-bit mantissa stops counting exactly.
    private var sum: [Double]
    private var sumOfSquares: [Double]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        let channels = width * height * 3
        self.sum = [Double](repeating: 0, count: channels)
        self.sumOfSquares = [Double](repeating: 0, count: channels)
    }

    /// Adds one tile. Alpha is ignored: tiles that reach this point fill the canvas.
    public mutating func add(_ pixels: LinearPixels) {
        precondition(pixels.width == width && pixels.height == height, "tile size must match the stack")
        pixels.samples.withUnsafeBufferPointer { source in
            sum.withUnsafeMutableBufferPointer { total in
                sumOfSquares.withUnsafeMutableBufferPointer { squares in
                    var pixel = 0
                    let pixelCount = width * height
                    while pixel < pixelCount {
                        for channel in 0..<3 {
                            let value = Double(source[pixel * 4 + channel])
                            let index = pixel * 3 + channel
                            total[index] += value
                            squares[index] += value * value
                        }
                        pixel += 1
                    }
                }
            }
        }
        count += 1
    }

    /// The average tile, as linear samples ready to be written or measured.
    public func mean() -> LinearPixels {
        var output = LinearPixels.empty(width: width, height: height)
        guard count > 0 else { return output }
        let divisor = Double(count)
        output.samples.withUnsafeMutableBufferPointer { destination in
            for pixel in 0..<(width * height) {
                for channel in 0..<3 {
                    destination[pixel * 4 + channel] = clampToSample(sum[pixel * 3 + channel] / divisor)
                }
                destination[pixel * 4 + 3] = 65535
            }
        }
        return output
    }

    /// Per-pixel standard deviation across the stack, scaled for viewing.
    ///
    /// Where the stack agrees this is dark, and where the faces genuinely differ it is
    /// bright. Read together with the mean it separates the two ways a region can look
    /// soft: blurred because the faces differ, or blurred because they are misaligned.
    ///
    /// The values are a measurement, not a photograph, so they are written out as they
    /// stand. Sending them through the linear-to-sRGB transfer the way a real image
    /// requires would brighten a sigma of 0.05 to 0.25 and leave `gain` meaning nothing.
    public func deviation(gain: Double = 3) -> LinearPixels {
        var output = LinearPixels.empty(width: width, height: height)
        guard count > 1 else { return output }
        let divisor = Double(count)
        output.samples.withUnsafeMutableBufferPointer { destination in
            for pixel in 0..<(width * height) {
                for channel in 0..<3 {
                    let index = pixel * 3 + channel
                    let average = sum[index] / divisor
                    let variance = max(0, sumOfSquares[index] / divisor - average * average)
                    destination[pixel * 4 + channel] = clampToSample(variance.squareRoot() * gain)
                }
                destination[pixel * 4 + 3] = 65535
            }
        }
        return output
    }

    private func clampToSample(_ value: Double) -> UInt16 {
        UInt16(min(max(value, 0), 65535).rounded())
    }
}
