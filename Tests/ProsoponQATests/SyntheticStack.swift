import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import Testing

/// Builds stacks of synthetic "faces" whose landmark positions are known exactly, so a
/// measured displacement can be checked against the one that was put there.
enum SyntheticStack {

    static let side = 512.0
    static var spec: CanvasSpec { CanvasSpec.standard.scaled(toSize: side) }

    /// One tile: textured landmark targets at the canvas positions plus `jitter`, over a
    /// background that differs from tile to tile the way real faces do.
    static func tile(index: Int, jitter: Point2D) throws -> CGImage {
        let pixels = Int(side)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))

        context.setFillColor(red: 0.55, green: 0.48, blue: 0.44, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))

        // Per-tile background detail. Individual faces differ here, so this is what the
        // average is supposed to blur away.
        var state = UInt64(index &* 2_654_435_761 &+ 12345)
        func random() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 10000) / 10000
        }
        // Fine and dense, so that averaging a dozen tiles genuinely flattens it. Coarse
        // blobs survive a small stack and would leave the whole canvas looking as sharp
        // as the landmarks, which is the very contrast being measured.
        for _ in 0..<4000 {
            context.setFillColor(red: random(), green: random() * 0.7, blue: random() * 0.5, alpha: 0.8)
            let size = 2 + random() * 7
            context.fillEllipse(in: CGRect(x: random() * side, y: random() * side, width: size, height: size))
        }

        // Work in the project's top-left space for the landmark positions.
        context.translateBy(x: 0, y: side)
        context.scaleBy(x: 1, y: -1)

        for landmark in [spec.viewerLeftEye, spec.viewerRightEye, spec.mouth] {
            let centre = landmark + jitter
            // Concentric rings give the correlation something to lock onto, and the
            // off-centre dot breaks the rotational symmetry.
            for (radius, tone) in [(34.0, 0.15), (26.0, 0.85), (17.0, 0.1), (9.0, 0.95)] {
                context.setFillColor(red: tone, green: tone, blue: tone, alpha: 1)
                context.fillEllipse(in: CGRect(
                    x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2
                ))
            }
            context.setFillColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
            context.fillEllipse(in: CGRect(x: centre.x + 2, y: centre.y - 8, width: 7, height: 7))
        }

        return try #require(context.makeImage())
    }

    /// Writes a stack into a fresh temporary directory and returns the file URLs.
    static func write(jitters: [Point2D]) throws -> (directory: URL, urls: [URL]) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-qa-\(UInt64.random(in: 0...UInt64.max))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var urls: [URL] = []
        for (index, jitter) in jitters.enumerated() {
            let url = directory.appendingPathComponent(String(format: "t%02d.png", index))
            try ImageWriting.write(try tile(index: index, jitter: jitter), to: url, format: .png)
            urls.append(url)
        }
        return (directory, urls)
    }

    static func meanJitter(_ jitters: [Point2D]) -> Point2D {
        let count = Double(jitters.count)
        return Point2D(
            jitters.reduce(0) { $0 + $1.x } / count,
            jitters.reduce(0) { $0 + $1.y } / count
        )
    }
}
