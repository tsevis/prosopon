import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponRender
import Testing
@testable import ProsoponQA

@Suite("Registration")
struct RegistrationTests {

    /// A textured patch, shifted by a known amount at draw time so the displacement is
    /// exact rather than resampled.
    private func patch(shiftedBy shift: Point2D) throws -> LuminancePatch {
        let side = Registration.patchSide
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))

        // Core Graphics counts y upward; every coordinate in Prosopon counts it down.
        // Without this the shifts under test would arrive negated.
        context.translateBy(x: 0, y: Double(side))
        context.scaleBy(x: 1, y: -1)

        let centre = Point2D(Double(side) / 2 + shift.x, Double(side) / 2 + shift.y)
        for (radius, tone) in [(30.0, 0.1), (22.0, 0.9), (14.0, 0.15), (7.0, 0.95)] {
            context.setFillColor(red: tone, green: tone, blue: tone, alpha: 1)
            context.fillEllipse(in: CGRect(
                x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2
            ))
        }
        context.setFillColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1)
        context.fillEllipse(in: CGRect(x: centre.x + 3, y: centre.y - 9, width: 8, height: 8))

        let image = try #require(context.makeImage())
        let pixels = try #require(LinearPixels.decode(image, cropX: 0, cropY: 0, width: side, height: side))
        return LuminancePatch.extract(
            from: pixels,
            centredOn: Point2D(Double(side) / 2, Double(side) / 2),
            side: side
        )
    }

    @Test("a matching patch reports no displacement and near-perfect correlation")
    func identicalPatchesAgree() throws {
        let reference = try patch(shiftedBy: .zero)
        let offset = Registration.consensusOffset(of: reference, against: reference)
        #expect(abs(offset.dx) < 0.05)
        #expect(abs(offset.dy) < 0.05)
        #expect(offset.correlation > 0.999)
        #expect(!offset.clipped)
    }

    @Test("a whole-pixel shift is recovered", arguments: [
        Point2D(3, 0), Point2D(-4, 0), Point2D(0, 5), Point2D(0, -2), Point2D(3, -4), Point2D(-6, 6),
    ])
    func integerShiftIsRecovered(shift: Point2D) throws {
        let reference = try patch(shiftedBy: .zero)
        let moved = try patch(shiftedBy: shift)
        let offset = Registration.consensusOffset(of: moved, against: reference)

        // A positive dx means this tile's feature sits to the right of the reference.
        #expect(abs(offset.dx - shift.x) < 0.3, "dx \(offset.dx) for a shift of \(shift.x)")
        #expect(abs(offset.dy - shift.y) < 0.3, "dy \(offset.dy) for a shift of \(shift.y)")
        #expect(offset.correlation > 0.95)
        #expect(!offset.clipped)
    }

    @Test("a sub-pixel shift is recovered by the parabolic fit", arguments: [
        Point2D(0.5, 0), Point2D(-1.5, 0), Point2D(0, 2.25), Point2D(1.75, -0.5),
    ])
    func subPixelShiftIsRecovered(shift: Point2D) throws {
        // Rounding every measurement to a whole pixel would put a floor of half a pixel
        // on everything this tool reports, so the fit has to earn its place.
        let reference = try patch(shiftedBy: .zero)
        let moved = try patch(shiftedBy: shift)
        let offset = Registration.consensusOffset(of: moved, against: reference)
        #expect(abs(offset.dx - shift.x) < 0.35, "dx \(offset.dx) for a shift of \(shift.x)")
        #expect(abs(offset.dy - shift.y) < 0.35, "dy \(offset.dy) for a shift of \(shift.y)")
    }

    @Test("a shift past the search window is flagged rather than reported as a small one")
    func shiftBeyondSearchIsClipped() throws {
        let reference = try patch(shiftedBy: .zero)
        let moved = try patch(shiftedBy: Point2D(Double(Registration.searchRadius) + 6, 0))
        let offset = Registration.consensusOffset(of: moved, against: reference)
        #expect(offset.clipped, "a displacement outside the window must say so")
        #expect(abs(offset.dx) == Double(Registration.searchRadius))
    }

    @Test("brightness differences do not read as displacement")
    func toleratesExposureDifference() throws {
        // Correlation rather than plain difference, so a tile that is merely darker than
        // the average is not mistaken for a misaligned one.
        let reference = try patch(shiftedBy: .zero)
        var darker = reference
        darker.values = reference.values.map { UInt8(Double($0) * 0.6) }
        let offset = Registration.consensusOffset(of: darker, against: reference)
        #expect(abs(offset.dx) < 0.05)
        #expect(abs(offset.dy) < 0.05)
        #expect(offset.correlation > 0.99)
    }

    @Test("a featureless patch reports nothing rather than a confident wrong answer")
    func flatPatchIsRefused() {
        let flat = LuminancePatch(
            side: Registration.patchSide,
            values: [UInt8](repeating: 120, count: Registration.patchSide * Registration.patchSide)
        )
        #expect(Registration.consensusOffset(of: flat, against: flat).correlation <= 0)
    }
}
