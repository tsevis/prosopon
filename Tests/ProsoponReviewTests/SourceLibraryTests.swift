import CoreGraphics
import Foundation
import ProsoponIO
import ProsoponPipeline
import Testing
@testable import ProsoponReview

/// Real folders and real bookmarks against a throwaway defaults suite.
///
/// Bookmarks are the point of this code, and a bookmark is something only the system can
/// make. A test that stubbed one would be checking that the stub round-trips.
private struct Corpus {
    let root: URL
    let suiteName: String

    init() throws {
        let id = UInt64.random(in: 0...UInt64.max)
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-library-\(id)")
        suiteName = "com.tsevis.prosopon.tests.\(id)"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    struct CouldNotDraw: Error {}

    @discardableResult
    func image(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let pixels = { context.setFillColor(gray: 0.5, alpha: 1)
                             context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
                             return context.makeImage() }()
        else { throw CouldNotDraw() }
        try ImageWriting.write(pixels, to: url, format: .png)
        return url
    }

    func directory(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
@Suite("Source library")
struct SourceLibraryTests {

    private func library(_ corpus: Corpus) -> SourceLibrary {
        SourceLibrary(bookmarks: BookmarkStore(defaults: corpus.defaults))
    }

    @Test("adding a folder counts what is inside it")
    func addsAFolder() throws {
        let corpus = try Corpus(); defer { corpus.tearDown() }
        try corpus.image("portraits/a.png")
        try corpus.image("portraits/b.png")
        let folder = try corpus.directory("portraits")

        let library = library(corpus)
        library.add([folder])

        #expect(library.sources.count == 1)
        #expect(library.scan.imageCount == 2)
        #expect(library.count(of: library.sources[0]) == 2)
    }

    @Test("folders and files arrive together")
    func addsAMixture() throws {
        // One open panel with both switches on, and one drop, both hand over a mixture.
        let corpus = try Corpus(); defer { corpus.tearDown() }
        try corpus.image("portraits/a.png")
        let loose = try corpus.image("loose.png")
        let folder = try corpus.directory("portraits")

        let library = library(corpus)
        library.add([folder, loose])

        #expect(library.sources.count == 2)
        #expect(library.sources.map(\.isDirectory) == [true, false])
        #expect(library.scan.imageCount == 2)
    }

    @Test("the same folder added twice is added once")
    func doesNotAddTwice() throws {
        let corpus = try Corpus(); defer { corpus.tearDown() }
        try corpus.image("portraits/a.png")
        let folder = try corpus.directory("portraits")

        let library = library(corpus)
        library.add([folder])
        library.add([folder])
        #expect(library.sources.count == 1)
    }

    @Test("a photograph inside a folder already in the list is not added separately")
    func doesNotAddInsideAnExistingFolder() throws {
        // Easy to do by accident with a mixed drop, and it would add nothing: the file is
        // already found through its folder, and de-duplication would drop it anyway.
        let corpus = try Corpus(); defer { corpus.tearDown() }
        let inside = try corpus.image("portraits/a.png")
        let folder = try corpus.directory("portraits")

        let library = library(corpus)
        library.add([folder])
        library.add([inside])

        #expect(library.sources.count == 1)
        #expect(library.scan.imageCount == 1)
    }

    @Test("a photograph under a folder that is not recursive is a source of its own")
    func addsInsideANonRecursiveFolder() throws {
        let corpus = try Corpus(); defer { corpus.tearDown() }
        try corpus.image("portraits/top.png")
        let deep = try corpus.image("portraits/2024/deep.png")
        let folder = try corpus.directory("portraits")

        let library = library(corpus)
        library.add([folder])
        library.setRecursive(false, for: library.sources[0])
        library.add([deep])

        #expect(library.sources.count == 2, "the folder no longer reaches it")
        #expect(library.scan.imageCount == 2)
    }

    @Test("recursion can be turned off per folder, and the count follows")
    func recursionIsPerFolder() throws {
        let corpus = try Corpus(); defer { corpus.tearDown() }
        try corpus.image("portraits/top.png")
        try corpus.image("portraits/2024/deep.png")
        let folder = try corpus.directory("portraits")

        let library = library(corpus)
        library.add([folder])
        #expect(library.scan.imageCount == 2)

        library.setRecursive(false, for: library.sources[0])
        #expect(library.scan.imageCount == 1)
    }

    @Test("removing a source removes its images from the count")
    func removesASource() throws {
        let corpus = try Corpus(); defer { corpus.tearDown() }
        try corpus.image("a/one.png")
        try corpus.image("b/two.png")
        let a = try corpus.directory("a")
        let b = try corpus.directory("b")

        let library = library(corpus)
        library.add([a, b])
        #expect(library.scan.imageCount == 2)

        library.remove(library.sources[0])
        #expect(library.sources.count == 1)
        #expect(library.scan.imageCount == 1)
    }

    @Test("the output folder is not imported as input")
    func excludesOutput() throws {
        // `-o` pointing inside the input folder is an ordinary thing to do, and without
        // this a second run would align the first run's own tiles.
        let corpus = try Corpus(); defer { corpus.tearDown() }
        try corpus.image("face.png")
        try corpus.image("aligned/face.png")

        let library = library(corpus)
        library.add([corpus.root])
        #expect(library.scan.imageCount == 2)

        library.outputDirectory = corpus.root.appendingPathComponent("aligned")
        #expect(library.scan.imageCount == 1)
    }

    @Test("photographs an earlier run already aligned are counted as done")
    func countsWhatIsAlreadyAligned() throws {
        let corpus = try Corpus(); defer { corpus.tearDown() }
        let one = try corpus.image("portraits/one.png")
        try corpus.image("portraits/two.png")

        let library = library(corpus)
        library.add([try corpus.directory("portraits")])

        #expect(library.alreadyAligned(inRunWith: []) == 0)
        #expect(library.alreadyAligned(inRunWith: [one.path]) == 1)
    }

    // MARK: Remembering

    @Test("a folder chosen once opens again next launch")
    func survivesRelaunch() throws {
        // The whole reason bookmarks are here. A real bookmark, made by the system,
        // resolved by the system.
        let corpus = try Corpus(); defer { corpus.tearDown() }
        try corpus.image("portraits/a.png")
        try corpus.image("portraits/b.png")
        let folder = try corpus.directory("portraits")

        let first = library(corpus)
        first.add([folder])
        first.setRecursive(false, for: first.sources[0])

        let second = library(corpus)
        #expect(second.sources.count == 1)
        #expect(second.sources[0].url == folder.standardizedFileURL)
        #expect(second.sources[0].isDirectory)
        #expect(second.sources[0].isRecursive == false, "the recursion choice came back too")
        #expect(second.scan.imageCount == 2)
    }

    @Test("a folder that has moved is kept and named, not silently forgotten")
    func missingSourceIsKept() throws {
        // Dropping it would be the worst of both: the folder disappears from the list and
        // nothing says why, so a corpus added months ago is simply gone.
        let corpus = try Corpus(); defer { corpus.tearDown() }
        try corpus.image("gone/a.png")
        let folder = try corpus.directory("gone")

        let first = library(corpus)
        first.add([folder])
        try FileManager.default.removeItem(at: folder)

        let second = library(corpus)
        #expect(second.sources.isEmpty)
        #expect(second.missing.count == 1)
        #expect(second.missing[0].name == "gone")
        #expect(!second.missing[0].reason.isEmpty)
        #expect(second.unreadableCount == 1)
    }

    @Test("a corrupt list of remembered sources is reported rather than swallowed")
    func corruptStoreIsReported() throws {
        // A `try?` here would empty the source list with no error anywhere -- the same
        // shape as the qa.json decode that hid a dead feature in this project for weeks.
        let corpus = try Corpus(); defer { corpus.tearDown() }
        corpus.defaults.set(Data("not json".utf8), forKey: "prosopon.sources")

        let library = library(corpus)
        #expect(library.sources.isEmpty)
        #expect(library.missing.count == 1)
        #expect(library.unreadableCount == 1)
    }

    @Test("removing everything forgets it for next launch too")
    func removeAllIsRemembered() throws {
        let corpus = try Corpus(); defer { corpus.tearDown() }
        try corpus.image("portraits/a.png")

        let first = library(corpus)
        first.add([try corpus.directory("portraits")])
        first.removeAll()

        #expect(library(corpus).sources.isEmpty)
    }

    @Test("nothing is written before anything is added")
    func nothingRememberedInitially() throws {
        let corpus = try Corpus(); defer { corpus.tearDown() }
        let library = library(corpus)
        #expect(library.sources.isEmpty)
        #expect(library.missing.isEmpty)
        #expect(library.scan.isEmpty)
    }
}
