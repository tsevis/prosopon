import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import Testing
@testable import ProsoponPipeline

/// Real directories on disk, because a directory is what this code reads. A synthesised
/// listing would only ever prove that the test and the code agree about a shape neither
/// of them got from the filesystem.
struct Tree {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-scan-\(UInt64.random(in: 0...UInt64.max))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func image(_ relativePath: String, side: Int = 8) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // Written by the same writer `align` uses, so these are files ImageIO would
        // actually open rather than bytes named `.png`.
        try ImageWriting.write(try Self.pixels(side: side), to: url, format: .png)
        return url
    }

    @discardableResult
    func file(_ relativePath: String, contents: String = "not an image") throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        return url
    }

    func directory(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    struct CouldNotDraw: Error {}

    /// Plain `guard` rather than `#require`: this runs from a helper outside any test,
    /// where the macro traps instead of recording a failure.
    static func pixels(side: Int = 8) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw CouldNotDraw() }
        context.setFillColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage() else { throw CouldNotDraw() }
        return image
    }
}

@Suite("Source scanner")
struct SourceScannerTests {

    @Test("a folder yields its images and ignores everything else")
    func findsImages() throws {
        let tree = try Tree(); defer { tree.remove() }
        try tree.image("a.png")
        try tree.image("b.PNG")
        try tree.file("notes.txt")
        try tree.file("report.csv")

        let scan = SourceScanner.scan([.at(tree.root)])
        #expect(scan.imageCount == 2)
        #expect(scan.imageURLs.map(\.lastPathComponent) == ["a.png", "b.PNG"])
    }

    @Test("recursion is a choice, and it is visible in the count")
    func recursionIsAChoice() throws {
        // These corpora nest, and the command line's positional arguments have always
        // meant one level. Both readings have to stay available.
        let tree = try Tree(); defer { tree.remove() }
        try tree.image("top.png")
        try tree.image("2024/spring/deep.png")
        try tree.image("2024/other.png")

        let deep = SourceScanner.scan([.at(tree.root, isRecursive: true)])
        let shallow = SourceScanner.scan([.at(tree.root, isRecursive: false)])

        #expect(deep.imageCount == 3)
        #expect(shallow.imageCount == 1)
        #expect(shallow.imageURLs.map(\.lastPathComponent) == ["top.png"])
    }

    @Test("a file added twice is aligned once")
    func deduplicates() throws {
        // A photograph reachable both on its own and through its folder would otherwise
        // become two identical tiles in the stack.
        let tree = try Tree(); defer { tree.remove() }
        let loose = try tree.image("portraits/one.png")
        try tree.image("portraits/two.png")

        let scan = SourceScanner.scan([
            .at(tree.root.appendingPathComponent("portraits")),
            .at(loose),
        ])
        #expect(scan.imageCount == 2)

        // The per-source counts report what each source contains, before the overlap was
        // removed -- so they can exceed the total, and the source list still adds up.
        #expect(scan.countsBySource[tree.root.appendingPathComponent("portraits")] == 2)
        #expect(scan.countsBySource[loose] == 1)
    }

    @Test("the same file reached by two spellings is still one file")
    func deduplicatesAcrossPathSpellings() throws {
        let tree = try Tree(); defer { tree.remove() }
        let direct = try tree.image("one.png")
        let roundabout = tree.root
            .appendingPathComponent("sub")
            .appendingPathComponent("..")
            .appendingPathComponent("one.png")
        _ = try tree.directory("sub")

        let scan = SourceScanner.scan([.at(direct), .at(roundabout)])
        #expect(scan.imageCount == 1)
    }

    @Test("the output folder is not imported as input")
    func excludesTheOutputFolder() throws {
        // `prosopon align ~/portraits -o ~/portraits/aligned` is an ordinary thing to
        // type. Without this, a second run would align the first run's own tiles.
        let tree = try Tree(); defer { tree.remove() }
        try tree.image("face.png")
        try tree.image("aligned/face.png")

        let all = SourceScanner.scan([.at(tree.root)])
        let excluded = SourceScanner.scan(
            [.at(tree.root)], excluding: tree.root.appendingPathComponent("aligned")
        )

        #expect(all.imageCount == 2)
        #expect(excluded.imageCount == 1)
        #expect(excluded.imageURLs.first?.lastPathComponent == "face.png")
    }

    @Test("a folder that is not there is reported, not counted as empty")
    func missingFolderIsReported() throws {
        // The enumerator returns nil for a missing directory, and an empty result reads
        // exactly like an empty folder -- which is how a corpus on an unmounted volume
        // would silently come back as "0 images found".
        let tree = try Tree(); defer { tree.remove() }
        let gone = tree.root.appendingPathComponent("moved-away")

        let scan = SourceScanner.scan([ImageSource(url: gone, isDirectory: true)])
        #expect(scan.isEmpty)
        #expect(scan.unreadable[gone] != nil)
        #expect(scan.countsBySource[gone] == nil)
    }

    @Test("a package is not descended into")
    func skipsPackages() throws {
        let tree = try Tree(); defer { tree.remove() }
        try tree.image("real.png")
        try tree.image("Something.app/Contents/Resources/icon.png")

        let scan = SourceScanner.scan([.at(tree.root)])
        #expect(scan.imageURLs.map(\.lastPathComponent) == ["real.png"])
    }

    @Test("hidden files are left alone")
    func skipsHiddenFiles() throws {
        let tree = try Tree(); defer { tree.remove() }
        try tree.image("visible.png")
        try tree.image(".hidden.png")

        let scan = SourceScanner.scan([.at(tree.root)])
        #expect(scan.imageURLs.map(\.lastPathComponent) == ["visible.png"])
    }

    @Test("a single file that is not an image contributes nothing")
    func nonImageFileIsIgnored() throws {
        let tree = try Tree(); defer { tree.remove() }
        let text = try tree.file("readme.md")

        let scan = SourceScanner.scan([.at(text)])
        #expect(scan.isEmpty)
        #expect(scan.unreadable.isEmpty, "a text file is not a fault, just not a portrait")
    }

    @Test("the order does not depend on the order the filesystem happened to enumerate")
    func stableOrdering() throws {
        let tree = try Tree(); defer { tree.remove() }
        for name in ["b.png", "a.png", "c.png", "10.png", "2.png"] { try tree.image(name) }

        let first = SourceScanner.scan([.at(tree.root)]).imageURLs
        let second = SourceScanner.scan([.at(tree.root)]).imageURLs
        #expect(first == second)
        #expect(first.map(\.lastPathComponent) == ["2.png", "10.png", "a.png", "b.png", "c.png"])
    }

    @Test("classification asks the filesystem rather than the caller")
    func classifiesByAsking() throws {
        let tree = try Tree(); defer { tree.remove() }
        let file = try tree.image("one.png")

        #expect(ImageSource.at(tree.root).isDirectory)
        #expect(!ImageSource.at(file).isDirectory)
    }
}
