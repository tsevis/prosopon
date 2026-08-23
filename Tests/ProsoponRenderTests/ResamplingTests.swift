import CoreGraphics
import Foundation
import ProsoponCore
import Testing
@testable import ProsoponRender

/// Quality and agreement checks for the two Lanczos implementations.
@Suite("Resampling")
struct ResamplingTests {

    private let side = 256
    private var spec: CanvasSpec { CanvasSpec.standard.scaled(toSize: 256) }

    static let gpuAvailable = (try? MetalLanczosRenderer()) != nil

    // MARK: Source images

    /// Deterministic pseudo-random detail, so every run resamples the same thing.
    private func noiseImage(_ size: Int) throws -> CGImage {
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt8 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return UInt8truncating(state >> 33)
        }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for pixel in 0..<(size * size) {
            bytes[pixel * 4] = next()
            bytes[pixel * 4 + 1] = next()
            bytes[pixel * 4 + 2] = next()
            bytes[pixel * 4 + 3] = 255
        }
        return try image(from: bytes, size: size)
    }

    /// A one-pixel checkerboard: the highest frequency the grid can hold, and the
    /// pattern that aliases into visible moire the instant a filter is too narrow.
    private func checkerboard(_ size: Int) throws -> CGImage {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let value: UInt8 = (x + y) % 2 == 0 ? 255 : 0
                let index = (y * size + x) * 4
                bytes[index] = value; bytes[index + 1] = value; bytes[index + 2] = value
                bytes[index + 3] = 255
            }
        }
        return try image(from: bytes, size: size)
    }

    /// A horizontal sinusoid of the given period, for measuring how much contrast a
    /// resampler gives away at the worst possible sub-pixel offset.
    private func sinusoid(_ size: Int, period: Double) throws -> CGImage {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let phase = 2 * Double.pi * Double(x) / period
                let value = UInt8(((sin(phase) * 0.45 + 0.5) * 255).rounded())
                let index = (y * size + x) * 4
                bytes[index] = value; bytes[index + 1] = value; bytes[index + 2] = value
                bytes[index + 3] = 255
            }
        }
        return try image(from: bytes, size: size)
    }

    private func UInt8truncating(_ value: UInt64) -> UInt8 { UInt8(truncatingIfNeeded: value) }

    private func image(from bytes: [UInt8], size: Int) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let destination = try #require(context.data)
        bytes.withUnsafeBytes { destination.copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
        return try #require(context.makeImage())
    }

    // MARK: Reading results back

    /// Linear 16-bit samples of a rendered tile, as the renderer produced them.
    private func linearSamples(_ image: CGImage) throws -> [UInt16] {
        let pixels = try #require(LinearPixels.decode(
            image, cropX: 0, cropY: 0, width: image.width, height: image.height
        ))
        return pixels.samples
    }

    private func luminance(_ samples: [UInt16], width: Int) -> [Double] {
        var result = [Double]()
        result.reserveCapacity(samples.count / 4)
        var index = 0
        while index < samples.count {
            let red: Double = Double(samples[index]) * 0.2126
            let green: Double = Double(samples[index + 1]) * 0.7152
            let blue: Double = Double(samples[index + 2]) * 0.0722
            result.append((red + green + blue) / 65535.0)
            index += 4
        }
        return result
    }

    // MARK: Exactness

    @Test("an identity transform reproduces the source exactly")
    func identityIsLossless() throws {
        // Lanczos is 1 at the centre tap and 0 at every other integer, so a transform
        // that lands each output pixel on a source pixel centre must be a pass-through.
        // Anything that shifts sampling by half a pixel, or gets the tap alignment
        // wrong, shows up here immediately as blur.
        let source = try noiseImage(side)
        let reference = try linearSamples(source)

        for resampler in RenderGeometryTests.renderers where resampler != .coreGraphics {
            let rendered = try resampler.makeRenderer(spec: spec)
                .render(source, using: .identity)
            let got = try linearSamples(rendered)
            let worst = zip(got, reference).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(worst <= 1, "\(resampler.rawValue) drifted by \(worst)/65535 under identity")
        }
    }

    @Test("an integer translation shifts the image exactly")
    func integerTranslationIsLossless() throws {
        let source = try noiseImage(side)
        let reference = try linearSamples(source)
        let shift = 7

        for resampler in RenderGeometryTests.renderers where resampler != .coreGraphics {
            let rendered = try resampler.makeRenderer(spec: spec)
                .render(source, using: .translation(Double(-shift), 0))
            let got = try linearSamples(rendered)

            var worst = 0
            for y in 0..<side {
                for x in 0..<(side - shift) {
                    let a = (y * side + x) * 4
                    let b = (y * side + x + shift) * 4
                    worst = max(worst, abs(Int(got[a]) - Int(reference[b])))
                }
            }
            #expect(worst <= 1, "\(resampler.rawValue) drifted by \(worst)/65535 under translation")
        }
    }

    // MARK: The GPU against its reference

    @Test("the GPU kernel agrees with the CPU reference", .enabled(if: gpuAvailable))
    func gpuMatchesCPU() throws {
        let source = try noiseImage(512)
        let angle = 0.37
        let scale = 1.7
        let transform = Affine2D(
            a: scale * cos(angle), b: scale * sin(angle),
            c: -scale * sin(angle), d: scale * cos(angle),
            tx: 31.4, ty: -12.6
        )

        let gpu = try linearSamples(MetalLanczosRenderer(spec: spec).render(source, using: transform))
        let cpu = try linearSamples(CPULanczosRenderer(spec: spec).render(source, using: transform))

        let deltas = zip(gpu, cpu).map { abs(Int($0) - Int($1)) }
        let worst = deltas.max() ?? 0
        let mean = Double(deltas.reduce(0, +)) / Double(deltas.count)
        // The shader accumulates in 32-bit float where the reference uses Double, so
        // exact equality is not on offer. Measured: 2/65535 worst, 0.09 mean.
        #expect(worst <= 6, "worst disagreement \(worst)/65535")
        #expect(mean < 0.5, "mean disagreement \(mean)/65535")
    }

    @Test("the GPU kernel agrees with the CPU reference when reducing", .enabled(if: gpuAvailable))
    func gpuMatchesCPUWhenMinifying() throws {
        let source = try noiseImage(1024)
        let transform = Affine2D.scale(x: 0.3, y: 0.3)

        let gpu = try linearSamples(MetalLanczosRenderer(spec: spec).render(source, using: transform))
        let cpu = try linearSamples(CPULanczosRenderer(spec: spec).render(source, using: transform))
        let worst = zip(gpu, cpu).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 6, "worst disagreement \(worst)/65535 over a wide footprint")
    }

    // MARK: Filtering quality

    @Test("reducing a one-pixel checkerboard averages it away instead of aliasing")
    func minificationDoesNotAlias() throws {
        // A checkerboard reduced fourfold should approach flat mid-grey. A filter whose
        // footprint stays three source pixels wide instead samples the pattern almost
        // at random and returns visible moire.
        let source = try checkerboard(1024)
        let rendered = try Resampler.lanczosCPU.makeRenderer(spec: spec)
            .render(source, using: .scale(x: 0.25, y: 0.25))
        let values = luminance(try linearSamples(rendered), width: side)

        // Sample the interior, away from the border where the footprint is clamped.
        let interior = (32..<(side - 32)).flatMap { y in
            (32..<(side - 32)).map { x in values[y * side + x] }
        }
        let mean = interior.reduce(0, +) / Double(interior.count)
        let deviation = (interior.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
            / Double(interior.count)).squareRoot()

        // Measured sigma is around 1e-15: the pattern is averaged away completely.
        #expect(deviation < 0.001, "residual pattern after reduction: sigma \(deviation)")
        #expect(mean > 0.15 && mean < 0.85, "mean drifted to \(mean)")
    }

    @Test("a half-pixel shift keeps almost all of a mid-frequency signal")
    func retainsContrastUnderSubPixelShift() throws {
        // Half a pixel is the worst case for any interpolator, so it is where resamplers
        // separate. Amplitude is read from the signal's own frequency bin rather than
        // from the largest sample: at a half-pixel offset the samples straddle the peak,
        // so even flawless reconstruction returns a smaller maximum, and measuring the
        // maximum would score a perfect resampler at cos(pi/8) = 0.924.
        let period = 8.0
        let source = try sinusoid(512, period: period)

        func amplitudeAtSignalFrequency(_ resampler: Resampler, shift: Double) throws -> Double {
            let rendered = try resampler.makeRenderer(spec: spec)
                .render(source, using: .translation(shift, 0))
            let values = luminance(try linearSamples(rendered), width: side)
            // 128 samples is exactly sixteen periods, so the bin is leakage-free.
            let row = (64..<192).map { values[128 * side + $0] }
            var real = 0.0
            var imaginary = 0.0
            for (index, value) in row.enumerated() {
                let phase = 2 * Double.pi * Double(index) / period
                real += value * cos(phase)
                imaginary += value * sin(phase)
            }
            return 2 * (real * real + imaginary * imaginary).squareRoot() / Double(row.count)
        }

        let baseline = try amplitudeAtSignalFrequency(.lanczosCPU, shift: 0)
        let lanczos = try amplitudeAtSignalFrequency(.lanczosCPU, shift: -0.5)
        let coreGraphics = try amplitudeAtSignalFrequency(.coreGraphics, shift: -0.5)

        let lanczosRetention = lanczos / baseline
        let coreGraphicsRetention = coreGraphics / baseline

        // Lanczos-3's negative lobes make it slightly better than flat here: measured
        // 1.007. Core Graphics measures 0.9239, which is cos(pi/8) to five decimals --
        // the exact response of bilinear interpolation at this frequency. Losing 7.6 %
        // of the mid-frequency contrast on every tile is the reason this renderer exists.
        #expect(lanczosRetention > 0.99,
                "Lanczos kept \(lanczosRetention) of the signal")
        #expect(coreGraphicsRetention < 0.97,
                "Core Graphics unexpectedly kept \(coreGraphicsRetention); the comparison below is moot")
        #expect(lanczosRetention >= coreGraphicsRetention - 1e-6,
                "Lanczos kept \(lanczosRetention), Core Graphics kept \(coreGraphicsRetention)")
    }

    @Test("magnifying preserves the signal's amplitude")
    func magnificationIsFaithful() throws {
        // Enlarging adds no information, so a faithful resampler leaves the amplitude of
        // whatever was already there untouched. Reading the signal's own frequency bin
        // sidesteps the sRGB transfer curve, which distorts a sinusoid's shape but does
        // so identically for every renderer.
        let period = 16.0
        let factor = 4.0
        let source = try sinusoid(256, period: period)

        func binAmplitude(_ row: [Double], period: Double) -> Double {
            var real = 0.0
            var imaginary = 0.0
            for (index, value) in row.enumerated() {
                let phase = 2 * Double.pi * Double(index) / period
                real += value * cos(phase)
                imaginary += value * sin(phase)
            }
            return 2 * (real * real + imaginary * imaginary).squareRoot() / Double(row.count)
        }

        let sourcePixels = try linearSamples(source)
        let sourceRow = (0..<256).map { luminance(sourcePixels, width: 256)[128 * 256 + $0] }
        let reference = binAmplitude(sourceRow, period: period)

        func rendered(_ resampler: Resampler) throws -> Double {
            let tile = try resampler.makeRenderer(spec: spec)
                .render(source, using: .scale(x: factor, y: factor))
            let values = luminance(try linearSamples(tile), width: side)
            // Sixteen periods at the magnified scale, clear of the edges.
            let row = (16..<(16 + 128)).map { values[128 * side + $0] }
            return binAmplitude(row, period: period * factor)
        }

        let lanczos = try rendered(.lanczosCPU) / reference
        let coreGraphics = try rendered(.coreGraphics) / reference

        // Measured: Lanczos is off by 0.03 %, Core Graphics by 1.02 %. Note that a
        // Laplacian-variance "sharpness" reading prefers Core Graphics here -- that
        // proxy rewards ringing and blockiness, and what it is measuring is the error.
        #expect(abs(lanczos - 1) < 0.005, "Lanczos scaled the amplitude to \(lanczos)")
        #expect(abs(lanczos - 1) <= abs(coreGraphics - 1) + 1e-6,
                "Lanczos \(lanczos) vs Core Graphics \(coreGraphics)")
    }
}
