import CoreGraphics
import Foundation

/// Interleaved RGBA with premultiplied alpha, one 16-bit slot per sample whatever the
/// document depth. Holding both depths in one representation keeps the compositing and
/// planar-export paths single, at the cost of 32 MB for a 2048 x 2048 tile.
struct PixelBuffer {
    let width: Int
    let height: Int
    let maxValue: UInt16
    var samples: [UInt16]

    static func transparent(width: Int, height: Int, depth: BitDepth) -> PixelBuffer {
        PixelBuffer(
            width: width, height: height,
            maxValue: depth == .eight ? 255 : 65535,
            samples: [UInt16](repeating: 0, count: width * height * 4)
        )
    }

    /// Decodes `image` into premultiplied sRGB at the requested depth.
    ///
    /// Core Graphics bitmap contexts cannot be created with straight alpha, so the data
    /// arrives premultiplied and is only divided back out at the very end, in
    /// `planarChannels`. Compositing wants premultiplied values anyway.
    static func premultipliedRGBA(from image: CGImage, depth: BitDepth) -> PixelBuffer? {
        let width = image.width
        let height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        switch depth {
        case .eight:
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(
                    data: raw.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            return PixelBuffer(width: width, height: height, maxValue: 255, samples: bytes.map(UInt16.init))

        case .sixteen:
            var samples = [UInt16](repeating: 0, count: width * height * 4)
            let drawn = samples.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(
                    data: raw.baseAddress, width: width, height: height,
                    bitsPerComponent: 16, bytesPerRow: width * 8, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder16Little.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            return PixelBuffer(width: width, height: height, maxValue: 65535, samples: samples)
        }
    }

    /// Composites `top` over the receiver, both premultiplied.
    ///
    /// With fully covered tiles this simply replaces the accumulator, but partial
    /// coverage is reachable through `--allow-partial-coverage`, and a merged composite
    /// that disagreed with what Photoshop computes from the layers would be a confusing
    /// thing to hand someone.
    mutating func composite(_ top: PixelBuffer) {
        precondition(top.samples.count == samples.count, "layer sizes must match")
        let scale = UInt32(maxValue)
        samples.withUnsafeMutableBufferPointer { destination in
            top.samples.withUnsafeBufferPointer { source in
                var index = 0
                while index < destination.count {
                    let sourceAlpha = UInt32(source[index + 3])
                    if sourceAlpha == scale {
                        destination[index] = source[index]
                        destination[index + 1] = source[index + 1]
                        destination[index + 2] = source[index + 2]
                        destination[index + 3] = source[index + 3]
                    } else if sourceAlpha > 0 {
                        let inverse = scale - sourceAlpha
                        for channel in 0..<4 {
                            let under = UInt32(destination[index + channel]) * inverse / scale
                            destination[index + channel] = UInt16(min(scale, UInt32(source[index + channel]) + under))
                        }
                    }
                    index += 4
                }
            }
        }
    }

    /// Splits into per-channel planes of big-endian samples with the alpha divided back
    /// out, which is how Photoshop stores layer pixels.
    func planarChannels(depth: BitDepth) -> [[UInt8]] {
        let pixelCount = width * height
        let bytesPerSample = depth.bytesPerSample
        var planes = (0..<4).map { _ in [UInt8](repeating: 0, count: pixelCount * bytesPerSample) }
        let scale = UInt32(maxValue)

        samples.withUnsafeBufferPointer { source in
            for channel in 0..<4 {
                planes[channel].withUnsafeMutableBufferPointer { plane in
                    for pixel in 0..<pixelCount {
                        let alpha = UInt32(source[pixel * 4 + 3])
                        let raw = UInt32(source[pixel * 4 + channel])
                        let straight: UInt32
                        if channel == 3 || alpha == scale {
                            straight = raw
                        } else if alpha == 0 {
                            straight = 0
                        } else {
                            straight = min(scale, (raw * scale + alpha / 2) / alpha)
                        }
                        if bytesPerSample == 1 {
                            plane[pixel] = UInt8(truncatingIfNeeded: straight)
                        } else {
                            plane[pixel * 2] = UInt8(truncatingIfNeeded: straight >> 8)
                            plane[pixel * 2 + 1] = UInt8(truncatingIfNeeded: straight)
                        }
                    }
                }
            }
        }
        return planes
    }
}
