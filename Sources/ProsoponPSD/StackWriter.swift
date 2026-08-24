import CoreGraphics
import Foundation
import ProsoponIO

/// Writes aligned tiles into one layered Photoshop document.
///
/// The document is streamed rather than assembled in memory: a few hundred 2048 x 2048
/// layers is several gigabytes, and Photoshop wants each section's length declared
/// before its contents. Length fields are therefore reserved on the way past and
/// patched once the compressed size is known.
///
/// Layers are written bottom-to-top, as the format requires, so the input order is
/// reversed — `layers[0]` becomes the topmost layer in Photoshop, which is what someone
/// handed a sorted list expects to see.
public enum StackWriter {

    private static let maximumLayers = 32_767

    /// A stack of aligned tiles: every layer fills the canvas, sized from the first tile.
    ///
    /// Kept as its own entry point because it is the shape `prosopon stack` has always
    /// written and the shape `scripts/validate_psd.py` checks. It builds a document and
    /// hands it to the general path, so there is one writer underneath and not two.
    public static func write(
        layers: [StackLayer],
        to url: URL,
        options: StackOptions = .default,
        progress: ((Int, Int) -> Void)? = nil
    ) throws -> StackSummary {
        guard !layers.isEmpty else { throw PSDWriteError.noLayers }

        guard let size = ImageLoading.dimensions(of: layers[0].url) else {
            throw PSDWriteError.pixelExtractionFailed(layers[0].url)
        }
        let (width, height) = size
        let frame = LayerFrame.canvas(width: width, height: height)

        return try write(
            PSDDocument(
                width: width, height: height,
                layers: layers.map { PSDLayer(name: $0.name, frame: frame, content: .image($0.url)) }
            ),
            to: url, options: options, progress: progress
        )
    }

    /// Any document: layers carry their own frames, so a layer can occupy one quadrant of
    /// the canvas rather than all of it.
    public static func write(
        _ document: PSDDocument,
        to url: URL,
        options: StackOptions = .default,
        progress: ((Int, Int) -> Void)? = nil
    ) throws -> StackSummary {
        guard !document.layers.isEmpty else { throw PSDWriteError.noLayers }
        guard document.layers.count <= maximumLayers else {
            throw PSDWriteError.tooManyLayers(document.layers.count)
        }

        let width = document.width
        let height = document.height
        guard max(width, height) <= options.format.maxDimension else {
            throw PSDWriteError.dimensionTooLarge(options.format, side: max(width, height))
        }

        // Bottom-to-top on disk; the caller's first entry ends up on top.
        let ordered = Array(document.layers.reversed())

        let writer = try FileWriter(url: url, maximumBytes: options.format.maxFileSize)
        let patches = PatchList()

        do {
            try writeHeader(writer, width: width, height: height, options: options)
            try writeColorModeData(writer)
            try writeImageResources(writer, options: options)

            let merged = try writeLayerAndMaskSection(
                writer, layers: ordered, width: width, height: height,
                options: options, patches: patches, progress: progress
            )

            try writer.write(ChannelEncoder.encodeMerged(
                planes: merged, width: width, height: height,
                bytesPerSample: options.depth.bytesPerSample,
                compression: options.compression, format: options.format
            ))

            // Applied in one sweep at the end so streaming is never interrupted by a seek.
            try writer.flush()
            for patch in patches.sortedByOffset {
                try writer.patch(at: patch.offset, with: patch.data)
            }

            let byteCount = writer.offset
            try writer.close()

            return StackSummary(
                url: url, layerCount: document.layers.count,
                width: width, height: height, byteCount: byteCount
            )
        } catch {
            // A partial document is never openable; leaving one behind only invites
            // someone to try.
            try? writer.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    // MARK: File header

    private static func writeHeader(
        _ writer: FileWriter, width: Int, height: Int, options: StackOptions
    ) throws {
        var header = Data()
        header.appendSignature("8BPS")
        header.appendBE(options.format.version)
        header.append(Data(repeating: 0, count: 6))
        header.appendBE(UInt16(4))                       // RGB plus the composite alpha
        header.appendBE(UInt32(height))
        header.appendBE(UInt32(width))
        header.appendBE(UInt16(options.depth.rawValue))
        header.appendBE(UInt16(3))                       // colour mode: RGB
        try writer.write(header)
    }

    private static func writeColorModeData(_ writer: FileWriter) throws {
        var data = Data()
        data.appendBE(UInt32(0))                         // empty for RGB
        try writer.write(data)
    }

    // MARK: Image resources

    private static func writeImageResources(_ writer: FileWriter, options: StackOptions) throws {
        var body = Data()
        appendResource(id: 1005, data: resolutionInfo(dpi: options.dpi), to: &body)
        if let profile = CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() as Data? {
            appendResource(id: 1039, data: profile, to: &body)
        }

        var block = Data()
        block.appendBE(UInt32(body.count))
        block.append(body)
        try writer.write(block)
    }

    private static func appendResource(id: UInt16, data: Data, to block: inout Data) {
        block.appendSignature("8BIM")
        block.appendBE(id)
        block.appendBE(UInt16(0))                        // empty Pascal name, padded to even
        block.appendBE(UInt32(data.count))
        block.append(data)
        if data.count % 2 != 0 { block.appendBE(UInt8(0)) }
    }

    private static func resolutionInfo(dpi: Double) -> Data {
        let fixed = UInt32((dpi * 65536).rounded())
        var data = Data()
        data.appendBE(fixed)
        data.appendBE(UInt16(1))                         // horizontal unit: pixels per inch
        data.appendBE(UInt16(1))                         // width unit: inches
        data.appendBE(fixed)
        data.appendBE(UInt16(1))
        data.appendBE(UInt16(1))
        return data
    }
}
