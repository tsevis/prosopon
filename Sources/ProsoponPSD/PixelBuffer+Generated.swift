import Foundation

/// The two layer contents that are drawn rather than read from disk.
///
/// The reference document builds its landmark markers out of a solid fill plus a mask
/// revealing one dot. With no mask support that arrangement has no equivalent, so the
/// marker is drawn as the thing it looks like: a small disc with transparency around it.
/// Same appearance, a few kilobytes, and no mask section in the format.
extension PixelBuffer {

    static func solid(width: Int, height: Int, depth: BitDepth, color: RGBA8) -> PixelBuffer {
        let maxValue: UInt16 = depth == .eight ? 255 : 65535
        var samples = [UInt16](repeating: 0, count: width * height * 4)
        let premultiplied = premultiply(color, maxValue: maxValue)
        for pixel in 0..<(width * height) {
            samples[pixel * 4] = premultiplied.0
            samples[pixel * 4 + 1] = premultiplied.1
            samples[pixel * 4 + 2] = premultiplied.2
            samples[pixel * 4 + 3] = premultiplied.3
        }
        return PixelBuffer(width: width, height: height, maxValue: maxValue, samples: samples)
    }

    /// A filled disc inscribed in the frame, with one pixel of analytic feathering at the
    /// edge so a 24 px marker does not read as a cog.
    static func disc(width: Int, height: Int, depth: BitDepth, color: RGBA8) -> PixelBuffer {
        let maxValue: UInt16 = depth == .eight ? 255 : 65535
        var samples = [UInt16](repeating: 0, count: width * height * 4)
        let centreX = Double(width) / 2
        let centreY = Double(height) / 2
        let radius = min(centreX, centreY)

        for row in 0..<height {
            for column in 0..<width {
                let dx = Double(column) + 0.5 - centreX
                let dy = Double(row) + 0.5 - centreY
                let distance = (dx * dx + dy * dy).squareRoot()
                let coverage = min(1, max(0, radius + 0.5 - distance))
                guard coverage > 0 else { continue }
                let faded = RGBA8(
                    red: color.red, green: color.green, blue: color.blue,
                    alpha: UInt8((Double(color.alpha) * coverage).rounded())
                )
                let premultiplied = premultiply(faded, maxValue: maxValue)
                let pixel = (row * width + column) * 4
                samples[pixel] = premultiplied.0
                samples[pixel + 1] = premultiplied.1
                samples[pixel + 2] = premultiplied.2
                samples[pixel + 3] = premultiplied.3
            }
        }
        return PixelBuffer(width: width, height: height, maxValue: maxValue, samples: samples)
    }

    /// 8-bit straight colour to premultiplied samples at the document's depth.
    private static func premultiply(_ color: RGBA8, maxValue: UInt16) -> (UInt16, UInt16, UInt16, UInt16) {
        let scale = UInt32(maxValue)
        let widen = { (value: UInt8) -> UInt32 in
            maxValue == 255 ? UInt32(value) : UInt32(value) * 257
        }
        let alpha = widen(color.alpha)
        let apply = { (value: UInt8) -> UInt16 in
            UInt16((widen(value) * alpha + scale / 2) / scale)
        }
        return (apply(color.red), apply(color.green), apply(color.blue), UInt16(alpha))
    }
}
