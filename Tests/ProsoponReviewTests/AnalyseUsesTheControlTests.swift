import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponPipeline
import Testing
@testable import ProsoponReview

/// What Analyse actually writes, as opposed to what the screen claims it will.
///
/// The other tests around this check that the control *holds* the right value. This one
/// presses the button: it runs `analyse()` and reads the manifest that comes out. Both
/// halves are needed, because every version of this fault so far has been a value that
/// was correct in one place and never reached the other.
@MainActor
@Suite("Analyse uses the control")
struct AnalyseUsesTheControlTests {

    private struct Corpus {
        let root: URL
        let sources: URL
        let output: URL
        let suite: String

        init() throws {
            let id = UInt64.random(in: 0...UInt64.max)
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("prosopon-analyse-\(id)")
            sources = root.appendingPathComponent("in")
            output = root.appendingPathComponent("out")
            suite = "com.tsevis.prosopon.tests.analyse.\(id)"
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: root)
            UserDefaults().removePersistentDomain(forName: suite)
        }

        struct CouldNotDraw: Error {}

        func photograph(_ name: String) throws {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { throw CouldNotDraw() }
            context.setFillColor(gray: 0.6, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            guard let image = context.makeImage() else { throw CouldNotDraw() }
            try ImageWriting.write(image, to: sources.appendingPathComponent(name), format: .png)
        }
    }

    /// Runs `analyse()` to completion, or gives up rather than hanging the suite.
    private func analyseAndWait(_ app: AppState) async throws {
        app.analyse()
        for _ in 0..<600 {
            if !app.isAnalysing { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("analyse did not finish")
    }

    @Test("the run is written at the stretch the control is set to")
    func analyseWritesTheControlsStretch() async throws {
        // The end of the chain the app kept breaking: a value the screen holds, the run
        // it is supposed to produce, and nothing in between quietly substituting a
        // default. Detection on a flat image finds no face, which does not matter — the
        // manifest records the settings the run was made under either way, and those are
        // what is being asked about.
        let corpus = try Corpus(); defer { corpus.tearDown() }
        try corpus.photograph("a.png")

        let app = AppState(
            sources: SourceLibrary(restoring: false),
            defaults: UserDefaults(suiteName: corpus.suite)!
        )
        app.sources.add([corpus.sources])
        app.outputDirectory = corpus.output
        app.maxStretch = 0.12
        app.maxMagnification = 3.5

        try await analyseAndWait(app)

        let url = corpus.output.appendingPathComponent("manifest.json")
        let manifest = try JSONDecoder().decode(
            RunManifest.self, from: Data(contentsOf: url)
        )
        #expect(manifest.maxStretch == 0.12, "the run was made at what the slider said")
        #expect(manifest.thresholds.maxMagnification == 3.5)
    }

    @Test("analysing into a folder that already holds a run continues it, not the defaults")
    func analyseIntoAnExistingRunKeepsItsSettings() async throws {
        // This is Analyse Again, and it is the press that destroyed a corpus three times:
        // the folder said 12 per cent, the app had never been told, and the built-in 5
        // won. Nothing is set on the app here on purpose — pointing at the folder has to
        // be enough.
        let corpus = try Corpus(); defer { corpus.tearDown() }
        try corpus.photograph("a.png")

        let existing = try Fixture.makeRun(
            names: ["a"],
            thresholds: QualityThresholds(maxMagnification: 3.5),
            solveOptions: SolveOptions(maxStretch: 0.12)
        )
        defer { try? FileManager.default.removeItem(at: existing) }

        let app = AppState(
            sources: SourceLibrary(restoring: false),
            defaults: UserDefaults(suiteName: corpus.suite)!
        )
        app.sources.add([corpus.sources])
        app.outputDirectory = existing

        #expect(app.maxStretch == 0.12, "adopted from the folder before anything is run")

        try await analyseAndWait(app)

        let manifest = try JSONDecoder().decode(
            RunManifest.self,
            from: Data(contentsOf: existing.appendingPathComponent("manifest.json"))
        )
        #expect(manifest.maxStretch == 0.12, "the re-run did not revert to the default")
        #expect(manifest.thresholds.maxMagnification == 3.5)
    }
}
