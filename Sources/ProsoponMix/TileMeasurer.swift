import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO

public enum MixMeasureError: Error, CustomStringConvertible {
    case unreadableTile(URL, String)
    case wrongShape(URL, found: String, expected: String)

    public var description: String {
        switch self {
        case .unreadableTile(let url, let reason):
            "could not measure \(url.lastPathComponent): \(reason)"
        case .wrongShape(let url, let found, let expected):
            "\(url.lastPathComponent) is \(found); the mix canvas is \(expected)"
        }
    }
}

/// Reads one aligned tile and reduces its eight seam strips to signatures.
///
/// Decoded at `measureSize` rather than at full resolution. A strip mean survives a
/// careful downsample — it is a mean — and at 2,560 tiles the difference between decoding
/// 2048 px and 1024 px is the difference between minutes and seconds. The strips are
/// specified in canvas pixels and scaled on the way in, so `--seam-width` means the same
/// thing whatever the measurement resolution.
public struct TileMeasurer: Sendable {
    public let grid: QuadrantGrid
    public let measureSize: Int

    public init(grid: QuadrantGrid, measureSize: Int = 1024) {
        self.grid = grid
        self.measureSize = max(64, min(measureSize, grid.canvasSize))
    }

    public init(grid: QuadrantGrid, options: MixOptions) {
        self.init(grid: grid, measureSize: options.measureSize)
    }

    public func measure(_ candidate: MixCandidate) throws -> TileMeasurement {
        try measure(
            tileURL: candidate.tileURL, sourcePath: candidate.sourcePath,
            name: candidate.name, yawDegrees: candidate.yawDegrees, score: candidate.score
        )
    }

    public func measure(
        tileURL: URL, sourcePath: String, name: String, yawDegrees: Double?, score: Double?
    ) throws -> TileMeasurement {
        let image: CGImage
        do {
            image = try ImageLoading.thumbnail(tileURL, maxPixelSize: measureSize)
        } catch {
            throw MixMeasureError.unreadableTile(tileURL, "\(error)")
        }
        guard image.width == image.height, image.width > 0 else {
            throw MixMeasureError.wrongShape(
                tileURL,
                found: "\(image.width)x\(image.height)",
                expected: "\(grid.canvasSize)x\(grid.canvasSize)"
            )
        }

        guard let pixels = Self.rgba(from: image) else {
            throw MixMeasureError.unreadableTile(tileURL, "the tile would not decode to RGBA")
        }
        let scale = Double(image.width) / Double(grid.canvasSize)

        var edges: [SeamSide: EdgeSignature] = [:]
        var mouthEdges: [SeamSide: EdgeSignature] = [:]
        for side in SeamSide.allCases {
            edges[side] = signature(of: grid.strip(side), in: pixels, width: image.width, scale: scale)
            if let band = grid.mouthBand(side) {
                mouthEdges[side] = signature(of: band, in: pixels, width: image.width, scale: scale)
            }
        }

        return TileMeasurement(
            tileURL: tileURL, sourcePath: sourcePath, name: name,
            yawDegrees: yawDegrees, score: score,
            edges: edges, mouthEdges: mouthEdges
        )
    }

    /// Mean linear colour over a rectangle, converted once to Lab, plus σ(L*).
    private func signature(
        of rect: (x: Int, y: Int, width: Int, height: Int),
        in pixels: [UInt8],
        width imageWidth: Int,
        scale: Double
    ) -> EdgeSignature {
        let x0 = clamp(Int((Double(rect.x) * scale).rounded(.down)), imageWidth)
        let y0 = clamp(Int((Double(rect.y) * scale).rounded(.down)), imageWidth)
        let x1 = max(x0 + 1, clamp(Int((Double(rect.x + rect.width) * scale).rounded(.up)), imageWidth))
        let y1 = max(y0 + 1, clamp(Int((Double(rect.y + rect.height) * scale).rounded(.up)), imageWidth))

        var sumRed = 0.0, sumGreen = 0.0, sumBlue = 0.0
        var sumLightness = 0.0, sumLightnessSquared = 0.0
        var count = 0.0

        for row in y0..<y1 {
            let rowStart = row * imageWidth
            for column in x0..<x1 {
                let pixel = (rowStart + column) * 4
                let red = ColorConversion.linear(pixels[pixel])
                let green = ColorConversion.linear(pixels[pixel + 1])
                let blue = ColorConversion.linear(pixels[pixel + 2])
                sumRed += red
                sumGreen += green
                sumBlue += blue
                let lightness = ColorConversion.lightness(linearRed: red, green: green, blue: blue)
                sumLightness += lightness
                sumLightnessSquared += lightness * lightness
                count += 1
            }
        }

        guard count > 0 else {
            return EdgeSignature(lightness: 0, greenRed: 0, blueYellow: 0, texture: 0)
        }
        let lab = ColorConversion.lab(
            linearRed: sumRed / count, green: sumGreen / count, blue: sumBlue / count
        )
        let meanLightness = sumLightness / count
        let variance = max(0, sumLightnessSquared / count - meanLightness * meanLightness)

        return EdgeSignature(
            lightness: lab.0, greenRed: lab.1, blueYellow: lab.2, texture: variance.squareRoot()
        )
    }

    private func clamp(_ value: Int, _ limit: Int) -> Int { max(0, min(value, limit)) }

    /// 8-bit RGBA in sRGB, premultiplied — Core Graphics bitmap contexts cannot be made
    /// with straight alpha. It costs nothing here: full coverage is a hard gate, so an
    /// aligned tile is opaque everywhere, and a partial one reads its empty region as
    /// black in the mean, which is a fair thing for a seam strip to be penalised for.
    private static func rgba(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
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
        return drawn ? bytes : nil
    }
}
