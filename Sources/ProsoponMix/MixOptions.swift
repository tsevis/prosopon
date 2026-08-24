import Foundation
import ProsoponIO
import ProsoponPSD

/// Everything a mix run can be told, and what it does when it is told nothing.
public struct MixOptions: Sendable {
    /// Seeds the shuffle of both pools and every fallback pick, so a run reproduces.
    public var seed: UInt64
    /// How wide a seam strip is, in canvas pixels.
    public var seamWidth: Int
    /// How tall the mouth band is, centred on the mouth target.
    public var mouthBandHeight: Int
    /// The resolution tiles are decoded at for measurement.
    public var measureSize: Int

    /// `.psd` by default rather than `stack`'s `.psb`: a quartered composite is about
    /// 30 MB, nowhere near the 2 GB a `.psd` can address, and `.psd` is what everything
    /// else opens.
    public var format: DocumentFormat
    public var depth: BitDepth
    public var compression: Compression
    public var dpi: Double

    /// The three hidden landmark markers, which are what let a join be checked by eye.
    public var includesMarkers: Bool
    /// The white background under the four quadrants.
    public var includesBackground: Bool

    /// A small flattened image per composite, for looking at without opening Photoshop.
    public var previewSize: Int?
    /// A full-size flattened export beside the document, when the composites are final
    /// and the layers are not going to be touched.
    public var flatFormat: ImageFormat?

    /// Stop after this many composites. The plan still covers the whole corpus, so the
    /// manifest says what the rest would have been.
    public var limit: Int?
    /// Measure and plan, write the manifest, write no documents. Worth doing first on a
    /// corpus that would take 19 GB.
    public var isDryRun: Bool
    public var concurrency: Int

    public init(
        seed: UInt64 = 1,
        seamWidth: Int = 16,
        mouthBandHeight: Int = 384,
        measureSize: Int = 1024,
        format: DocumentFormat = .psd,
        depth: BitDepth = .eight,
        compression: Compression = .rle,
        dpi: Double = 72,
        includesMarkers: Bool = true,
        includesBackground: Bool = true,
        previewSize: Int? = 512,
        flatFormat: ImageFormat? = nil,
        limit: Int? = nil,
        isDryRun: Bool = false,
        concurrency: Int = max(1, ProcessInfo.processInfo.activeProcessorCount)
    ) {
        self.seed = seed
        self.seamWidth = seamWidth
        self.mouthBandHeight = mouthBandHeight
        self.measureSize = measureSize
        self.format = format
        self.depth = depth
        self.compression = compression
        self.dpi = dpi
        self.includesMarkers = includesMarkers
        self.includesBackground = includesBackground
        self.previewSize = previewSize
        self.flatFormat = flatFormat
        self.limit = limit
        self.isDryRun = isDryRun
        self.concurrency = concurrency
    }

    public static let `default` = MixOptions()

    var stackOptions: StackOptions {
        StackOptions(format: format, depth: depth, compression: compression, dpi: dpi)
    }
}

/// The colour and size of the three hidden landmark markers.
///
/// Olive, like the fill layers in the reference document. Without mask support a marker
/// cannot be a fill revealed through a dot, so it is drawn as the dot — same appearance on
/// screen, a few kilobytes on disk, and no mask section anywhere in the format.
public enum MarkerStyle {
    public static let color = RGBA8(red: 128, green: 128, blue: 0)
    /// 24 px across on the 2048 canvas: visible when you turn it on, small enough to see
    /// what is under it.
    public static let diameter = 24
}
