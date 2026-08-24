import CoreGraphics
import Foundation
import ProsoponIO
import ProsoponPipeline
import Testing
@testable import ProsoponReview

/// What the app remembers between launches, and what Open is allowed to be handed.
///
/// Both of these were found on a real corpus of twenty portraits. Every one of them was
/// listed as `missing` while sitting exactly where it had always been, and choosing that
/// same folder from Open produced an alert about `manifest.json` instead of importing it.
private struct Remembered {
    let root: URL
    let suiteName: String

    init() throws {
        let id = UInt64.random(in: 0...UInt64.max)
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-remembered-\(id)")
        suiteName = "com.tsevis.prosopon.tests.remembered.\(id)"
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

    /// Writes the remembered list by hand, which is the only way to reproduce a bookmark
    /// that will not resolve the way it says it should.
    ///
    /// A plain bookmark read back with `.withSecurityScope` fails with Cocoa error 259 —
    /// the same failure, and the same error, that an app-scoped bookmark gives when the
    /// signing identity that created it has changed. That is the real cause: the app is
    /// ad-hoc signed, so every rebuild is a new identity, and every rebuild orphaned every
    /// remembered photograph.
    func rememberMislabelled(_ urls: [URL], key: String = "prosopon.sources") throws {
        let entries: [[String: Any]] = try urls.map { url in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let plain = try url.bookmarkData(
                options: [], includingResourceValuesForKeys: nil, relativeTo: nil
            )
            return [
                "data": plain.base64EncodedString(),
                "path": url.path,
                "isDirectory": isDirectory.boolValue,
                "isRecursive": true,
                // The lie. Nothing else about the entry is wrong.
                "isSecurityScoped": true,
            ]
        }
        defaults.set(try JSONSerialization.data(withJSONObject: entries), forKey: key)
    }
}

@MainActor
@Suite("Remembered sources")
struct RememberedSourcesTests {

    private func library(_ corpus: Remembered) -> SourceLibrary {
        SourceLibrary(bookmarks: BookmarkStore(defaults: corpus.defaults))
    }

    // MARK: Coming back

    @Test("a bookmark that will not resolve the way it was written still opens")
    func resolutionFallsBack() throws {
        // Twenty photographs, all present, all listed as missing. The bookmarks were
        // written by one build and read by the next, and an app-scoped bookmark belongs
        // to the identity that made it.
        let corpus = try Remembered(); defer { corpus.tearDown() }
        let one = try corpus.image("portraits/a.png")
        let two = try corpus.image("portraits/b.png")
        try corpus.rememberMislabelled([one, two])

        let library = library(corpus)

        #expect(library.missing.isEmpty, "the files are exactly where they were")
        #expect(library.sources.count == 2)
        #expect(library.scan.imageCount == 2)
    }

    @Test("a source that really has gone is still kept and named")
    func genuineLossIsNotSwallowed() throws {
        // The fallback must not go so far as to invent a source. Somebody who unplugs the
        // volume a corpus lives on should see it named, not silently dropped.
        let corpus = try Remembered(); defer { corpus.tearDown() }
        let folder = try corpus.directory("gone")
        library(corpus).add([folder])
        try FileManager.default.removeItem(at: folder)

        let second = library(corpus)
        #expect(second.sources.isEmpty)
        #expect(second.missing.count == 1)
        #expect(second.missing[0].name == "gone")
    }

    // MARK: Forgetting

    @Test("forgetting a missing source forgets it for the next launch too")
    func forgettingPersists() throws {
        // It used to drop the row and leave the bookmark, so the same dead entry came
        // back on every launch and could only ever be dismissed, never removed.
        let corpus = try Remembered(); defer { corpus.tearDown() }
        let folder = try corpus.directory("gone")
        library(corpus).add([folder])
        try FileManager.default.removeItem(at: folder)

        let second = library(corpus)
        let missing = try #require(second.missing.first)
        second.forget(missing)
        #expect(second.missing.isEmpty)

        #expect(library(corpus).missing.isEmpty, "and it stays gone")
    }

    @Test("forgetting all of them keeps the sources that still resolve")
    func forgetAllKeepsTheLiveOnes() throws {
        // Twenty dead rows and one live folder is the state this was written for; the
        // one thing Forget All must not do is take the live one with it.
        let corpus = try Remembered(); defer { corpus.tearDown() }
        let living = try corpus.directory("here")
        try corpus.image("here/a.png")
        let doomed = try corpus.directory("gone")
        library(corpus).add([living, doomed])
        try FileManager.default.removeItem(at: doomed)

        let second = library(corpus)
        #expect(second.missing.count == 1)
        #expect(second.sources.count == 1)

        second.forgetAllMissing()
        #expect(second.missing.isEmpty)
        #expect(second.sources.count == 1)
        #expect(second.scan.imageCount == 1)

        let third = library(corpus)
        #expect(third.missing.isEmpty)
        #expect(third.sources.count == 1, "the live folder survived being tidied around")
    }

    @Test("with nothing missing there is nothing to forget")
    func forgetAllOnACleanList() throws {
        let corpus = try Remembered(); defer { corpus.tearDown() }
        let folder = try corpus.directory("here")
        try corpus.image("here/a.png")

        let library = library(corpus)
        library.add([folder])
        library.forgetAllMissing()

        #expect(library.sources.count == 1)
        #expect(library.scan.imageCount == 1)
    }

    // MARK: What Open may be handed

    @Test("Open on a folder of photographs imports them instead of asking for a manifest")
    func openImportsAFolderOfPhotographs() throws {
        // What actually happened: Open, choose the folder the portraits are in, and an
        // alert saying to run `prosopon align` first — from the one screen whose whole
        // purpose is to run it. There is no manifest because it has not been aligned yet.
        let corpus = try Remembered(); defer { corpus.tearDown() }
        let folder = try corpus.directory("portraits")
        try corpus.image("portraits/a.png")
        try corpus.image("portraits/b.png")

        let app = AppState(directory: nil, sources: library(corpus))
        app.openPending()
        app.open(folder)

        #expect(app.problem == nil, "a folder of photographs is a perfectly good thing to open")
        #expect(app.session == nil)
        #expect(app.stage == .importPortraits)
        #expect(app.sources.scan.imageCount == 2)
    }

    @Test("a run is still opened as a run")
    func openStillOpensARun() throws {
        let directory = try Fixture.makeRun(names: ["a"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let corpus = try Remembered(); defer { corpus.tearDown() }

        let app = AppState(directory: nil, sources: library(corpus))
        app.openPending()
        app.open(directory)

        #expect(app.session != nil)
        #expect(app.stage == .fineTune)
        #expect(app.sources.sources.isEmpty, "a run is not imported as source material")
    }

    @Test("a folder that is neither says so, naming both things it looked for")
    func openOnAnEmptyFolder() throws {
        let corpus = try Remembered(); defer { corpus.tearDown() }
        let empty = try corpus.directory("empty")

        let app = AppState(directory: nil, sources: library(corpus))
        app.openPending()
        app.open(empty)

        let problem = try #require(app.problem)
        #expect(problem.contains("manifest.json"))
        #expect(problem.lowercased().contains("photograph"))
    }
}
