import Foundation
import ProsoponCore
import ProsoponRender

/// A small square of 8-bit luminance lifted out of a tile, used for registration.
///
/// Alignment is solved analytically and lands the eyes to within a billionth of a
/// pixel, so any real disagreement between tiles comes from the landmark detector, not
/// the solve. Comparing these patches against the stack's consensus is therefore a
/// direct measurement of detector error, tile by tile.
public struct LuminancePatch: Sendable {
    public let side: Int
    public var values: [UInt8]

    public init(side: Int, values: [UInt8]) {
        self.side = side
        self.values = values
    }

    /// Lifts a `side` x `side` square centred on `centre`, clamping at the tile edge.
    public static func extract(
        from pixels: LinearPixels, centredOn centre: Point2D, side: Int
    ) -> LuminancePatch {
        var values = [UInt8](repeating: 0, count: side * side)
        let originX = Int((centre.x - Double(side) / 2).rounded())
        let originY = Int((centre.y - Double(side) / 2).rounded())

        pixels.samples.withUnsafeBufferPointer { source in
            values.withUnsafeMutableBufferPointer { destination in
                for row in 0..<side {
                    let y = min(max(originY + row, 0), pixels.height - 1)
                    for column in 0..<side {
                        let x = min(max(originX + column, 0), pixels.width - 1)
                        let index = (y * pixels.width + x) * 4
                        let red = Double(source[index]) * 0.2126
                        let green = Double(source[index + 1]) * 0.7152
                        let blue = Double(source[index + 2]) * 0.0722
                        destination[row * side + column] = UInt8(min(255, (red + green + blue) / 257).rounded())
                    }
                }
            }
        }
        return LuminancePatch(side: side, values: values)
    }

    /// Mean gradient magnitude: how crisp this patch is.
    ///
    /// Applied to the stack's average, it is the measurement that matters. Misaligned
    /// tiles smear the average, and a smeared average has a small gradient.
    public var acutance: Double {
        guard side > 2 else { return 0 }
        var total = 0.0
        values.withUnsafeBufferPointer { data in
            for row in 1..<(side - 1) {
                for column in 1..<(side - 1) {
                    let index = row * side + column
                    let dx = Double(data[index + 1]) - Double(data[index - 1])
                    let dy = Double(data[index + side]) - Double(data[index - side])
                    total += (dx * dx + dy * dy).squareRoot()
                }
            }
        }
        return total / Double((side - 2) * (side - 2))
    }
}
