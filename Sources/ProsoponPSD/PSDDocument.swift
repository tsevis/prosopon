import Foundation

/// One layer's rectangle on the canvas, in the document's top-left-origin pixel space.
///
/// A Photoshop layer record already declares its own bounding rectangle, which is what
/// makes a quadrant composite possible without any mask code: a 1024 x 1024 layer sitting
/// at (1024, 1024) *is* the bottom-right quadrant, and costs a quarter of what a
/// full-canvas layer masked down to the same quarter would.
public struct LayerFrame: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static func canvas(width: Int, height: Int) -> LayerFrame {
        LayerFrame(x: 0, y: 0, width: width, height: height)
    }

    public var isEmpty: Bool { width <= 0 || height <= 0 }
}

/// Straight (non-premultiplied) 8-bit colour. Widened to the document depth on the way in.
public struct RGBA8: Sendable, Equatable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = RGBA8(red: 255, green: 255, blue: 255)
}

/// Where a layer's pixels come from.
///
/// Photographic layers are read from disk one at a time so a multi-gigabyte batch never
/// has to fit in memory. The two generated cases exist because the reference document's
/// landmark markers are solid-colour fills, and without mask support a marker is drawn as
/// what it actually looks like rather than as a fill plus a mask that reveals a dot.
public enum LayerContent: Sendable {
    /// Decoded from a file, which must match the layer's frame exactly.
    case image(URL)
    /// One region of a file, taken with its top-left corner at (`x`, `y`) and the layer's
    /// frame for its size.
    ///
    /// This is what makes a quartered composite possible without writing intermediate
    /// files: the aligned tile on disk is the whole 2048 x 2048 face, and the layer wants
    /// one 1024 x 1024 quarter of it.
    case croppedImage(URL, x: Int, y: Int)
    /// A flat colour filling the frame.
    case solid(RGBA8)
    /// A filled, antialiased disc inscribed in the frame, transparent outside it.
    case disc(RGBA8)
}

public struct PSDLayer: Sendable {
    public var name: String
    public var frame: LayerFrame
    public var content: LayerContent
    /// Hidden layers are written with their pixels intact but do **not** contribute to the
    /// merged composite, which is what Photoshop computes and therefore what the stored
    /// composite has to agree with.
    public var isVisible: Bool
    /// Transparency locked, as Photoshop's Background layer is.
    public var isLocked: Bool

    public init(
        name: String,
        frame: LayerFrame,
        content: LayerContent,
        isVisible: Bool = true,
        isLocked: Bool = false
    ) {
        self.name = name
        self.frame = frame
        self.content = content
        self.isVisible = isVisible
        self.isLocked = isLocked
    }
}

/// A whole document: a canvas and the layers on it, topmost first.
///
/// The order matches how a layer stack reads on screen and how `StackWriter` has always
/// taken its input; the writer reverses it, because the format stores layers bottom to top.
public struct PSDDocument: Sendable {
    public var width: Int
    public var height: Int
    public var layers: [PSDLayer]

    public init(width: Int, height: Int, layers: [PSDLayer]) {
        self.width = width
        self.height = height
        self.layers = layers
    }
}
