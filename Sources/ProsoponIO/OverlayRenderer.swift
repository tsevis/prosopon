import CoreGraphics
import Foundation
import ProsoponCore

/// Draws the verification overlay from the project's reference images on top of an
/// aligned tile: the 128 px grid, cyan crosshairs through the three targets, and a
/// translucent yellow disc over each landmark.
///
/// If a disc is not centred on the feature underneath it, the alignment is wrong — and
/// that reads instantly across a contact sheet in a way that numbers do not.
public struct OverlayRenderer: Sendable {
    public let spec: CanvasSpec

    public init(spec: CanvasSpec = .standard) {
        self.spec = spec
    }

    public func draw(over tile: CGImage) -> CGImage? {
        let side = Int(spec.size.rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.draw(tile, in: CGRect(x: 0, y: 0, width: spec.size, height: spec.size))

        // Switch to the project's top-left, y-down space for everything below.
        context.translateBy(x: 0, y: spec.size)
        context.scaleBy(x: 1, y: -1)

        drawGrid(in: context)
        drawCrosshairs(in: context)
        drawLandmarkDiscs(in: context)

        return context.makeImage()
    }

    private func drawGrid(in context: CGContext) {
        context.setStrokeColor(red: 0.62, green: 0.55, blue: 0.85, alpha: 0.35)
        context.setLineWidth(1)
        var offset = spec.gridStep
        while offset < spec.size {
            context.move(to: CGPoint(x: offset, y: 0))
            context.addLine(to: CGPoint(x: offset, y: spec.size))
            context.move(to: CGPoint(x: 0, y: offset))
            context.addLine(to: CGPoint(x: spec.size, y: offset))
            offset += spec.gridStep
        }
        context.strokePath()
    }

    private func drawCrosshairs(in context: CGContext) {
        context.setStrokeColor(red: 0.25, green: 0.9, blue: 0.95, alpha: 0.9)
        context.setLineWidth(2)
        let verticals = [spec.viewerLeftEye.x, spec.mouth.x, spec.viewerRightEye.x]
        let horizontals = [spec.eyeLineY, spec.mouth.y]
        for x in verticals {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: spec.size))
        }
        for y in horizontals {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: spec.size, y: y))
        }
        context.strokePath()
    }

    private func drawLandmarkDiscs(in context: CGContext) {
        context.setFillColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 0.55)
        let radius = spec.gridStep * 0.55
        for target in [spec.viewerLeftEye, spec.viewerRightEye, spec.mouth] {
            context.fillEllipse(in: CGRect(
                x: target.x - radius, y: target.y - radius,
                width: radius * 2, height: radius * 2
            ))
        }
    }
}
