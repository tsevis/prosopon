import Foundation
import ProsoponCore
import ProsoponPipeline
import Testing
@testable import ProsoponReview

/// `AppState` composes no sentences — `CommandSet` and `StatusBanner` do that, and they
/// are tested against values. What is checked here is the join: that the live session and
/// the live source library turn into the right numbers, since a wrong count there is a
/// wrong toolbar everywhere.
@MainActor
@Suite("App state")
struct AppStateTests {

    /// A library that neither reads nor writes the real defaults.
    private func isolatedSources() -> SourceLibrary {
        SourceLibrary(
            bookmarks: BookmarkStore(
                defaults: UserDefaults(suiteName: "com.tsevis.prosopon.tests.appstate")!,
                key: "prosopon.sources.\(UInt64.random(in: 0...UInt64.max))"
            )
        )
    }

    private func state(directory: URL? = nil) -> AppState {
        AppState(directory: directory, sources: isolatedSources())
    }

    @Test("an app with nothing loaded opens on Import and says so")
    func emptyLaunch() {
        let app = state()
        #expect(app.stage == .importPortraits)
        #expect(app.session == nil)
        #expect(app.chrome == ChromeState())
        #expect(app.problem == nil)
    }

    @Test("a run given on the command line opens straight into Fine Tune")
    func launchWithARun() throws {
        // What `review.sh ~/aligned` does, and the reason the opening stage is not fixed.
        let directory = try Fixture.makeRun(names: ["a", "b", "c"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = state(directory: directory)
        #expect(app.stage == .fineTune)
        #expect(app.chrome.runName == directory.lastPathComponent)
        #expect(app.chrome.tileCount == 3)
        #expect(app.chrome.acceptedCount == 3)
    }

    @Test("a folder that is not a run is complained about rather than silently ignored")
    func launchWithABadDirectory() throws {
        // The folder is the reason the app was opened. Dropping into an empty window
        // would leave somebody wondering whether it had loaded.
        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-not-a-run-\(UInt64.random(in: 0...UInt64.max))")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        let app = state(directory: empty)
        #expect(app.session == nil)
        #expect(app.problem != nil)
        #expect(app.stage == .importPortraits)
    }

    @Test("declined tiles are counted apart from accepted ones")
    func countsRejections() throws {
        // A source too small to fill the canvas fails the coverage gate, which is the
        // number the Analyze banner reports before anybody commits to a stack.
        let directory = try Fixture.makeRun(names: ["a", "b"], offsets: [.zero, Point2D(0, 300)])
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = state(directory: directory)
        let chrome = app.chrome
        #expect(chrome.tileCount == 2)
        #expect(chrome.acceptedCount == 1, "one tile should have cleared the gates")
        #expect(chrome.rejectedCount == 1, "the displaced face should not fill the canvas")

        // And that figure is what the Analyze banner reports, rather than a clean-looking
        // total that hides three unusable tiles.
        let banner = StatusBanner.message(for: .analyze, state: chrome)
        #expect(banner.kind == .caution)
        #expect(banner.text.contains("1 of 2 aligned"))
    }

    @Test("an edit shows in the chip and unlocks Save")
    func editsReachTheToolbar() throws {
        let directory = try Fixture.makeRun(names: ["a"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = state(directory: directory)
        #expect(app.chrome.editCount == 0)
        #expect(CommandSet.commands(for: .fineTune, state: app.chrome)
            .first { $0.action == .saveCorrections }?.isEnabled == false)

        app.session?.selection = app.session?.entries.first?.id
        app.session?.moveLandmark(.mouth, toCanvasPoint: Point2D(130, 210))

        #expect(app.chrome.editCount == 1)
        #expect(SubjectChip.detail(app.chrome)?.contains("1 edited") == true)
        #expect(CommandSet.commands(for: .fineTune, state: app.chrome)
            .first { $0.action == .saveCorrections }?.isEnabled == true)
    }

    @Test("opening a run moves to Fine Tune and forgets the last save message")
    func openingARun() throws {
        let first = try Fixture.makeRun(names: ["a"])
        let second = try Fixture.makeRun(names: ["b", "c"])
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let app = state(directory: first)
        app.recordSave("1 tile rewritten")
        #expect(app.chrome.lastSaveSummary != nil)

        app.open(second)
        #expect(app.stage == .fineTune)
        #expect(app.chrome.tileCount == 2)
        #expect(app.chrome.lastSaveSummary == nil, "a summary from the previous run is stale")
    }

    @Test("the run's own folder is not imported as input")
    func outputIsExcluded() throws {
        // The output folder is set to the run when one is opened, and the scan excludes
        // it -- otherwise dragging the parent folder in would import the run's own tiles
        // as portraits to align.
        let directory = try Fixture.makeRun(names: ["a", "b"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = state(directory: directory)
        #expect(app.outputDirectory == directory)

        // The fixture writes the sources and the tiles into the same folder, so importing
        // it while it is the output finds nothing.
        app.sources.add([directory])
        #expect(app.chrome.imageCount == 0)
    }

    @Test("photographs a run has already aligned are reported as done")
    func alreadyAlignedIsCounted() throws {
        let directory = try Fixture.makeRun(names: ["a", "b"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = state(directory: directory)
        let sources = app.session!.entries.map(\.sourceURL)
        // Import the sources themselves, with the run folder no longer excluded.
        app.outputDirectory = nil
        app.sources.add(sources)

        #expect(app.chrome.imageCount == 2)
        #expect(app.chrome.alreadyAlignedCount == 2)
        #expect(app.chrome.outstandingCount == 0)

        // And so the primary control says there is nothing to do rather than offering to
        // do it all again.
        let analyse = CommandSet.commands(for: .importPortraits, state: app.chrome)
            .first { $0.action == .analyse }
        #expect(analyse?.isEnabled == false)
    }

    @Test("a run with nothing to analyse is refused with a reason")
    func analysingNothing() {
        let app = state()
        app.analyse()
        #expect(app.isAnalysing == false)
        #expect(app.problem != nil)
    }
}
