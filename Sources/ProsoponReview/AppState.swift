import Foundation
import Observation
import ProsoponCore
import ProsoponPipeline
import ProsoponRender
import ProsoponVision

/// The whole application: which stage is showing, what has been imported, what the last
/// analysis produced, and what the reviewer has changed since.
///
/// It owns the three long-lived pieces and turns them into one flat `ChromeState` for the
/// toolbar. Everything the toolbar *says* is decided in `CommandSet` and `StatusBanner`
/// from that value, so this type is left holding objects and running work rather than
/// composing sentences.
@MainActor
@Observable
public final class AppState {
    public var stage: Stage
    public let sources: SourceLibrary
    public private(set) var session: ReviewSession?

    public private(set) var isAnalysing = false
    public private(set) var progress: BatchRunner.Progress?
    public private(set) var isSaving = false
    /// Shown once, in an alert, then cleared. A message that outlives its cause is worse
    /// than none.
    public var problem: String?
    public private(set) var lastSaveSummary: String?

    /// Where an analysis writes. Defaults beside the sources once there are some, because
    /// asking for an output folder before anybody has chosen an input is a question out
    /// of order.
    public var outputDirectory: URL? {
        didSet { sources.outputDirectory = outputDirectory }
    }

    public var detector = DetectorChoice.vision

    private var analysisTask: Task<Void, Never>?

    public init(directory: URL? = nil, sources: SourceLibrary = SourceLibrary()) {
        self.sources = sources

        // A folder given on the command line is the reason the app was opened, so a
        // failure to read it has to be said rather than dropping into an empty window.
        var opened: ReviewSession?
        var failure: String?
        if let directory {
            do { opened = try ReviewSession(directory: directory) }
            catch { failure = "\(error)" }
        }

        session = opened
        problem = failure
        outputDirectory = opened == nil ? nil : directory
        stage = Stage.opening(hasRun: opened != nil)
        sources.outputDirectory = outputDirectory
    }

    // MARK: What the chrome shows

    public var chrome: ChromeState {
        ChromeState(
            sourceCount: sources.sources.count,
            imageCount: sources.scan.imageCount,
            alreadyAlignedCount: sources.alreadyAligned(inRunWith: alignedSourcePaths),
            unreadableSourceCount: sources.unreadableCount,
            runName: session?.directory.lastPathComponent,
            tileCount: session?.entries.count ?? 0,
            acceptedCount: session?.entries.count { $0.quality?.isAccepted == true } ?? 0,
            attentionCount: attentionCount,
            isAnalysing: isAnalysing,
            progress: progress,
            editCount: session?.editCount ?? 0,
            isSaving: isSaving,
            lastSaveSummary: lastSaveSummary,
            qaReportProblem: session?.qaReportProblem
        )
    }

    /// The same reading the queue uses to put a tile at the top: something is wrong with
    /// it, or it sits further from the stack consensus than the rest.
    private var attentionCount: Int {
        session?.entries.count { entry in
            entry.failure != nil
                || entry.quality?.isAccepted == false
                || entry.consensusMatched == false
                || (entry.consensusDisplacement ?? 0) > 2
        } ?? 0
    }

    /// The photographs this run has aligned, by source path, so the import grid can say
    /// which ones a run would leave alone.
    public var alignedSourcePaths: Set<String> {
        guard let session else { return [] }
        return Set(session.entries.compactMap { entry in
            entry.outputURL == nil ? nil : entry.sourceURL.standardizedFileURL.path
        })
    }

    // MARK: Opening a run

    public func open(_ directory: URL) {
        do {
            session = try ReviewSession(directory: directory)
            outputDirectory = directory
            lastSaveSummary = nil
            stage = .fineTune
        } catch {
            problem = "\(error)"
        }
    }

    public func recordSave(_ summary: String) {
        lastSaveSummary = summary
        session?.recordSave(summary)
    }

    public func setSaving(_ saving: Bool) { isSaving = saving }

    // MARK: Analysing

    /// Runs detection and alignment over everything imported that this run has not
    /// already done, then opens the result.
    public func analyse() {
        guard !isAnalysing else { return }
        guard let directory = outputDirectory ?? defaultOutputDirectory() else {
            problem = "Choose a folder for the aligned tiles first."
            return
        }

        let urls = sources.scan.imageURLs
        guard !urls.isEmpty else {
            problem = "There are no portraits to analyse yet."
            return
        }

        stage = .analyze
        isAnalysing = true
        progress = BatchRunner.Progress(completed: 0, total: urls.count)

        let spec = CanvasSpec.standard
        let solveOptions = SolveOptions.default
        // Read off `self` here rather than inside the task, which holds it weakly.
        let choice = detector
        let detectorName = choice.rawValue

        analysisTask = Task { [weak self] in
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                let pipeline = try Self.makePipeline(
                    spec: spec, solveOptions: solveOptions,
                    detector: choice, directory: directory
                )
                let tiles = await BatchRunner.run(
                    urls: urls, pipeline: pipeline,
                    concurrency: max(1, ProcessInfo.processInfo.activeProcessorCount),
                    onProgress: { [weak self] progress in
                        Task { @MainActor in self?.progress = progress }
                    }
                )
                guard !Task.isCancelled else {
                    await self?.finishAnalysis(directory: nil, problem: nil)
                    return
                }
                try RunWriter.write(
                    tiles, to: directory, spec: spec, solveOptions: solveOptions,
                    detector: detectorName, resampler: Resampler.lanczos.rawValue
                )
                await self?.finishAnalysis(directory: directory, problem: nil)
            } catch {
                await self?.finishAnalysis(directory: nil, problem: "\(error)")
            }
        }
    }

    public func cancelAnalysis() {
        analysisTask?.cancel()
    }

    private func finishAnalysis(directory: URL?, problem: String?) {
        isAnalysing = false
        progress = nil
        analysisTask = nil
        if let problem { self.problem = problem }
        guard let directory else { return }
        do {
            session = try ReviewSession(directory: directory)
            lastSaveSummary = nil
        } catch {
            // A run where nothing cleared the gates writes a manifest with no usable
            // tiles, and the session refuses to open it. Saying so is better than leaving
            // Fine Tune showing the previous run's queue as though it were this one's.
            session = nil
            self.problem = "\(error)"
        }
    }

    /// Built off the main actor's back: compiling the Metal shader and loading two ONNX
    /// models is a per-run cost, not a per-image one.
    private nonisolated static func makePipeline(
        spec: CanvasSpec, solveOptions: SolveOptions,
        detector: DetectorChoice, directory: URL
    ) throws -> Pipeline {
        Pipeline(
            spec: spec,
            solveOptions: solveOptions,
            thresholds: .default,
            selection: .all,
            detector: try detector.make(),
            renderer: try Resampler.lanczos.makeRenderer(spec: spec),
            output: OutputPlan(directory: directory, format: .png, depth: .eight)
        )
    }

    /// `~/Pictures/Prosopon/<source folder> aligned`, so the first run needs no decision.
    private func defaultOutputDirectory() -> URL? {
        guard let first = sources.sources.first else { return nil }
        let name = first.isDirectory
            ? first.url.lastPathComponent
            : first.url.deletingLastPathComponent().lastPathComponent
        let base = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let directory = base.appendingPathComponent("Prosopon").appendingPathComponent("\(name) aligned")
        outputDirectory = directory
        return directory
    }
}
