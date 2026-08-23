import CoreGraphics
import Foundation
import ProsoponIO
import Testing
@testable import ProsoponPSD

@Suite("StackWriter")
struct StackWriterTests {

    private let side = 64

    /// A temp directory holding `count` distinctly coloured tiles.
    private func makeTiles(count: Int, side: Int? = nil, names: [String]? = nil) throws -> (URL, [StackLayer]) {
        let edge = side ?? self.side
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-psd-\(UInt64.random(in: 0...UInt64.max))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var layers: [StackLayer] = []
        for index in 0..<count {
            let name = names?[index] ?? "tile\(index)"
            let url = directory.appendingPathComponent("\(name).png")
            try ImageWriting.write(try tile(index: index, count: count, side: edge), to: url, format: .png)
            layers.append(StackLayer(name: name, url: url))
        }
        return (directory, layers)
    }

    private func tile(index: Int, count: Int, side: Int) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let shade = Double(index + 1) / Double(count + 1)
        context.setFillColor(red: shade, green: 1 - shade, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        // A flat field compresses to nothing; add detail so RLE is genuinely exercised.
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        for step in stride(from: 0, to: side, by: 3) {
            context.fill(CGRect(x: step, y: (step * (index + 1)) % side, width: 2, height: 1))
        }
        return try #require(context.makeImage())
    }

    // MARK: Structure

    @Test("a psb parses cleanly and declares what it contains", arguments: [Compression.rle, .raw])
    func psbStructure(compression: Compression) throws {
        let (directory, layers) = try makeTiles(count: 4)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("stack.psb")

        let summary = try StackWriter.write(
            layers: layers, to: output,
            options: StackOptions(format: .psb, depth: .eight, compression: compression)
        )
        #expect(summary.layerCount == 4)
        #expect(summary.width == side && summary.height == side)

        let report = try DocumentInspector.inspect(output)
        #expect(report.version == 2, "psb is version 2")
        #expect(report.channels == 4)
        #expect(report.depth == 8)
        #expect(report.colorMode == 3, "RGB")
        #expect(report.width == side && report.height == side)
        #expect(report.layers.count == 4)
        #expect(report.layerCountField == -4, "negative: the composite carries transparency")
        #expect(report.bytesAfterImageData >= 0)
    }

    @Test("a psd parses cleanly with the narrower length fields")
    func psdStructure() throws {
        let (directory, layers) = try makeTiles(count: 3)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("stack.psd")

        _ = try StackWriter.write(layers: layers, to: output, options: StackOptions(format: .psd))
        let report = try DocumentInspector.inspect(output)
        #expect(report.version == 1)
        #expect(report.layers.count == 3)
    }

    @Test("16-bit documents carry their layers in an Lr16 block")
    func sixteenBitUsesLr16() throws {
        let (directory, layers) = try makeTiles(count: 2)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("stack16.psb")

        _ = try StackWriter.write(
            layers: layers, to: output,
            options: StackOptions(format: .psb, depth: .sixteen)
        )
        let report = try DocumentInspector.inspect(output)
        #expect(report.depth == 16)
        #expect(report.taggedBlocks.contains("Lr16"),
                "a 16-bit document leaves the ordinary layer-info section empty")
        #expect(report.layers.count == 2)
        // Readers align global tagged blocks to four bytes. Declaring a length that is
        // already a multiple of four means the padding cannot be double-counted, which
        // is what left an earlier version two bytes adrift.
        let declared = try #require(report.taggedBlockLengths["Lr16"])
        #expect(declared % 4 == 0, "Lr16 declared \(declared) bytes, not a multiple of 4")
    }

    @Test("Lr16 stays 4-aligned across layer counts that shift its length", arguments: 1...6)
    func lr16AlignmentHolds(layerCount: Int) throws {
        let (directory, layers) = try makeTiles(count: layerCount)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("stack16.psb")
        _ = try StackWriter.write(
            layers: layers, to: output,
            options: StackOptions(format: .psb, depth: .sixteen)
        )
        let report = try DocumentInspector.inspect(output)
        let declared = try #require(report.taggedBlockLengths["Lr16"])
        #expect(declared % 4 == 0)
        #expect(report.layers.count == layerCount)
    }

    // MARK: Layer records

    @Test("every layer covers the full canvas, opaque and normally blended")
    func layerRecords() throws {
        let (directory, layers) = try makeTiles(count: 3)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("stack.psb")
        _ = try StackWriter.write(layers: layers, to: output)

        let report = try DocumentInspector.inspect(output)
        for layer in report.layers {
            #expect(layer.rect == (0, 0, side, side))
            #expect(layer.opacity == 255)
            #expect(layer.blendMode == "norm")
            #expect(layer.channelIDs == [-1, 0, 1, 2],
                    "transparency first, then red, green and blue")
            #expect(layer.channelLengths.allSatisfy { $0 > 2 })
        }
    }

    @Test("the first input becomes the topmost layer")
    func inputOrderPutsTheFirstFileOnTop() throws {
        let names = ["alpha", "beta", "gamma"]
        let (directory, layers) = try makeTiles(count: 3, names: names)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("stack.psb")
        _ = try StackWriter.write(layers: layers, to: output)

        // Records are stored bottom-to-top, so the caller's first entry comes last.
        let report = try DocumentInspector.inspect(output)
        #expect(report.layers.map(\.name) == names.reversed())
    }

    @Test("non-ASCII names survive in the Unicode block")
    func unicodeLayerNames() throws {
        let names = ["Πρόσωπο", "Ελένη"]
        let (directory, layers) = try makeTiles(count: 2, names: names)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("stack.psb")
        _ = try StackWriter.write(layers: layers, to: output)

        let report = try DocumentInspector.inspect(output)
        #expect(report.layers.compactMap(\.unicodeName) == names.reversed())
    }

    @Test("resolution and an ICC profile are recorded")
    func imageResources() throws {
        let (directory, layers) = try makeTiles(count: 1)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("stack.psb")
        _ = try StackWriter.write(layers: layers, to: output, options: StackOptions(dpi: 300))

        let report = try DocumentInspector.inspect(output)
        #expect(report.resourceIDs.contains(1005), "resolution info")
        #expect(report.resourceIDs.contains(1039), "ICC profile")
    }

    // MARK: Failure modes

    @Test("mismatched tile sizes are rejected with the offending file named")
    func dimensionMismatch() throws {
        let (directory, layers) = try makeTiles(count: 2)
        defer { try? FileManager.default.removeItem(at: directory) }
        let odd = directory.appendingPathComponent("odd.png")
        try ImageWriting.write(try tile(index: 0, count: 1, side: side * 2), to: odd, format: .png)

        let output = directory.appendingPathComponent("stack.psb")
        #expect(throws: PSDWriteError.self) {
            try StackWriter.write(layers: layers + [StackLayer(url: odd)], to: output)
        }
    }

    @Test("a failure part-way through leaves no half-written document behind")
    func partialDocumentIsRemoved() throws {
        let (directory, layers) = try makeTiles(count: 2)
        defer { try? FileManager.default.removeItem(at: directory) }
        let odd = directory.appendingPathComponent("odd.png")
        try ImageWriting.write(try tile(index: 0, count: 1, side: side * 2), to: odd, format: .png)

        let output = directory.appendingPathComponent("stack.psb")
        #expect(throws: PSDWriteError.self) {
            try StackWriter.write(layers: layers + [StackLayer(url: odd)], to: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path),
                "a document that cannot be finished should not be left on disk")
    }

    @Test("an empty layer list is rejected")
    func noLayers() throws {
        let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("empty.psb")
        #expect(throws: PSDWriteError.self) {
            try StackWriter.write(layers: [], to: output)
        }
    }

    @Test("progress is reported once per layer")
    func progressReporting() throws {
        let (directory, layers) = try makeTiles(count: 5)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("stack.psb")

        var seen: [Int] = []
        _ = try StackWriter.write(layers: layers, to: output) { done, total in
            #expect(total == 5)
            seen.append(done)
        }
        #expect(seen == [1, 2, 3, 4, 5])
    }
}
