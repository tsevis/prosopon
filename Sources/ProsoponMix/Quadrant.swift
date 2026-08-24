import Foundation
import ProsoponCore

/// One quarter of the canvas. Four of these, from four different photographs, make one
/// composite.
///
/// The names are the viewer's, like everything else in Prosopon: `topLeft` holds the eye
/// that appears on the left of the picture, which is the subject's right.
public enum Quadrant: String, CaseIterable, Sendable, Codable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var label: String {
        switch self {
        case .topLeft: "top left"
        case .topRight: "top right"
        case .bottomLeft: "bottom left"
        case .bottomRight: "bottom right"
        }
    }

    var isTop: Bool { self == .topLeft || self == .topRight }
}

/// The four interior joins, and why one of them is harder than the others.
///
/// The mouth target sits at (1024, 1664) — exactly on the vertical centre line, and well
/// into the bottom half. So `verticalBottom` runs straight down the middle of a mouth,
/// with the two halves coming from two different people. It only works at all because
/// both mouths are on the same pixels by construction, and it is the join the matcher
/// spends its first and best choice on.
public enum Seam: String, CaseIterable, Sendable, Codable {
    /// Between the eyes, across the bridge of the nose.
    case verticalTop
    /// Through the mouth. The hardest join in the picture.
    case verticalBottom
    /// Down the left cheek.
    case horizontalLeft
    /// Down the right cheek.
    case horizontalRight

    public var label: String {
        switch self {
        case .verticalTop: "nose bridge"
        case .verticalBottom: "mouth"
        case .horizontalLeft: "left cheek"
        case .horizontalRight: "right cheek"
        }
    }

    /// The two quadrant edges this join puts against each other.
    var sides: (SeamSide, SeamSide) {
        switch self {
        case .verticalTop: (.topLeftRight, .topRightLeft)
        case .verticalBottom: (.bottomLeftRight, .bottomRightLeft)
        case .horizontalLeft: (.topLeftBottom, .bottomLeftTop)
        case .horizontalRight: (.topRightBottom, .bottomRightTop)
        }
    }
}

/// One quadrant's interior edge — the strip of a tile that has to meet a neighbour.
///
/// There are eight rather than four, because which pixels a tile presents depends on where
/// it is placed: a tile in the top-right shows the strip just right of the centre line in
/// the *top* half, and the same tile in the bottom-right would show a different strip
/// entirely.
public enum SeamSide: String, CaseIterable, Sendable, Codable {
    case topLeftRight
    case topRightLeft
    case topLeftBottom
    case topRightBottom
    case bottomLeftTop
    case bottomRightTop
    case bottomLeftRight
    case bottomRightLeft

    /// Which quadrant a tile has to be placed in for this strip to be the one on show.
    var quadrant: Quadrant {
        switch self {
        case .topLeftRight, .topLeftBottom: .topLeft
        case .topRightLeft, .topRightBottom: .topRight
        case .bottomLeftTop, .bottomLeftRight: .bottomLeft
        case .bottomRightTop, .bottomRightLeft: .bottomRight
        }
    }

    /// True for the two strips the mouth runs through.
    var crossesTheMouth: Bool { self == .bottomLeftRight || self == .bottomRightLeft }
}

/// The canvas cut into quarters, and where every seam strip falls on it.
///
/// Derived from `CanvasSpec` rather than hard-coded, so a run re-rendered at 4096 measures
/// the same proportions. What is *not* derived is the position of the seams: they are the
/// midlines, and the mouth is on one of them by arithmetic rather than by choice.
public struct QuadrantGrid: Sendable {
    public let canvasSize: Int
    public let quadrantSize: Int
    /// How wide a seam strip is, in canvas pixels.
    public let seamWidth: Int
    /// How tall the mouth band is, centred on the mouth target.
    public let mouthBandHeight: Int
    public let mouthX: Int
    public let mouthY: Int

    public init(spec: CanvasSpec = .standard, seamWidth: Int = 16, mouthBandHeight: Int = 384) {
        canvasSize = Int(spec.size.rounded())
        quadrantSize = canvasSize / 2
        self.seamWidth = max(1, min(seamWidth, quadrantSize))
        self.mouthBandHeight = max(1, min(mouthBandHeight, canvasSize - quadrantSize))
        mouthX = Int(spec.mouth.x.rounded())
        mouthY = Int(spec.mouth.y.rounded())
    }

    /// Where a quadrant sits on the canvas.
    public func origin(of quadrant: Quadrant) -> (x: Int, y: Int) {
        switch quadrant {
        case .topLeft: (0, 0)
        case .topRight: (quadrantSize, 0)
        case .bottomLeft: (0, quadrantSize)
        case .bottomRight: (quadrantSize, quadrantSize)
        }
    }

    /// The strip of canvas a seam side occupies, as (x, y, width, height).
    public func strip(_ side: SeamSide) -> (x: Int, y: Int, width: Int, height: Int) {
        let q = quadrantSize
        let w = seamWidth
        switch side {
        case .topLeftRight: return (q - w, 0, w, q)
        case .topRightLeft: return (q, 0, w, q)
        case .bottomLeftRight: return (q - w, q, w, q)
        case .bottomRightLeft: return (q, q, w, q)
        case .topLeftBottom: return (0, q - w, q, w)
        case .topRightBottom: return (q, q - w, q, w)
        case .bottomLeftTop: return (0, q, q, w)
        case .bottomRightTop: return (q, q, q, w)
        }
    }

    /// The part of a vertical bottom strip that the mouth actually runs through.
    ///
    /// The whole strip is 1024 px of chin, neck and shoulder; the mouth is a few hundred
    /// of them, and it is the part anybody looks at. Measured separately so it can be
    /// weighted separately.
    public func mouthBand(_ side: SeamSide) -> (x: Int, y: Int, width: Int, height: Int)? {
        guard side.crossesTheMouth else { return nil }
        let full = strip(side)
        let top = max(quadrantSize, mouthY - mouthBandHeight / 2)
        let bottom = min(canvasSize, mouthY + mouthBandHeight / 2)
        guard bottom > top else { return nil }
        return (full.x, top, full.width, bottom - top)
    }

    /// True when the mouth target lies exactly on the vertical seam, in the bottom half.
    ///
    /// Not a configuration question — it is what makes the whole arrangement work, and a
    /// test asserts it rather than a comment claiming it.
    public var mouthSitsOnTheVerticalSeam: Bool {
        mouthX == quadrantSize && mouthY > quadrantSize && mouthY < canvasSize
    }
}
