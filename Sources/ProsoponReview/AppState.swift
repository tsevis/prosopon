import Foundation
import Observation
import ProsoponCore
import ProsoponIO
import ProsoponMix
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
        didSet {
            sources.outputDirectory = outputDirectory
            adoptThresholdsOfRunAtOutput()
        }
    }

    public var detector = DetectorChoice.vision

    /// How far a source may be enlarged onto the canvas before its tile is declined.
    ///
    /// A setting rather than a constant because it is the gate that actually bites. A
    /// 2048 canvas wants a face about a thousand pixels across; a corpus shot smaller than
    /// that needs two or three times enlargement, and at the built-in 2.0 the app declined
    /// seventeen of twenty portraits with no control anywhere to say otherwise. The tiles
    /// are soft and the metrics say so — that is a judgement for whoever is looking at
    /// them, not one to make on their behalf by refusing to write the file.
    /// The gate the next run will be made under.
    ///
    /// Written down, because it is the only thing standing between a corpus and Analyse
    /// writing it away, and a value that resets to the built-in default on every launch
    /// means each launch destroys what the last one made. That is not hypothetical: the
    /// same twenty portraits were aligned at 3.5 and thrown away at 2.0 twice, once
    /// because a reopened run did not set it and once because the app had been started
    /// with no run at all.
    ///
    /// It also follows whatever run is in play — one opened for review, or one already
    /// sitting in the output folder — so the control always describes what pressing it
    /// would actually do.
    public var maxMagnification: Double = QualityThresholds.default.maxMagnification {
        didSet {
            guard maxMagnification != oldValue else { return }
            defaults.set(maxMagnification, forKey: Self.magnificationKey)
        }
    }

    /// How far a face may be stretched vertically to bring its mouth onto the target.
    ///
    /// The setting that decides whether the mouth lands on the seam at all, which on a
    /// quartered portrait is the join everything else is judged by. Measured on 204
    /// portraits: at the built-in 5 per cent, 68 tiles finished more than 20 px off
    /// target and 26 more than 50; at 12 per cent, 4 and 1. The cost is real but narrow —
    /// the median tile is stretched 4.9 per cent either way, because the extra range is
    /// only ever spent where the mouth was missing.
    ///
    /// Written down and adopted from whatever run is in play, for the same reason the
    /// magnification gate is: a value that resets to the default on every launch means
    /// each launch quietly re-makes what the last one settled.
    public var maxStretch: Double = SolveOptions.default.maxStretch {
        didSet {
            guard maxStretch != oldValue else { return }
            defaults.set(maxStretch, forKey: Self.stretchKey)
        }
    }

    /// How far a face may be sheared to bring its mouth onto the target horizontally.
    ///
    /// The other half of placing a mouth, and useless without the first. Shear is the
    /// only linear operation that can slide the mouth sideways while both eyes stay
    /// pinned, so it owns the x axis exactly as stretch owns the y. Measured on 204
    /// portraits: at 25 per cent stretch with the default 5 per cent shear the worst
    /// mouth still finished 32.5 px off target, and every one of those pixels was
    /// horizontal; at 20 per cent shear the worst was 0.0.
    public var maxShear: Double = SolveOptions.default.maxShear {
        didSet {
            guard maxShear != oldValue else { return }
            defaults.set(maxShear, forKey: Self.shearKey)
        }
    }

    /// What Analyse would run with.
    ///
    /// A shear budget of nothing *is* "leave the horizontal offset alone" — there is no
    /// separate switch, and the run writer records it the same way, so the two have to
    /// agree or a reopened run reads back as something it was not.
    public var solveOptions: SolveOptions {
        SolveOptions(
            maxStretch: maxStretch,
            maxShear: maxShear,
            correctsHorizontalMouthOffset: maxShear > 0
        )
    }

    static let magnificationKey = "prosopon.maxMagnification"
    static let stretchKey = "prosopon.maxStretch"
    static let shearKey = "prosopon.maxShear"
    private let defaults: UserDefaults

    // MARK: The mix

    /// Where composites are written. Defaults to a `mixed` folder inside the run, so the
    /// finished work sits beside the material it was made from.
    public var mixOutputDirectory: URL?
    /// Seeds the shuffle. Exposed because trying another one is the normal way to get a
    /// different batch out of the same corpus.
    public var mixSeed: UInt64 = 1
    public private(set) var isMixing = false
    public private(set) var mixProgress: MixRunner.Progress?
    public private(set) var lastMixSummary: String?
    /// The last mix, read back from the manifest it wrote. Nil until one has been read.
    public private(set) var mixManifest: MixManifest?
    /// Where that manifest was read from, which is where its preview paths are relative to.
    public private(set) var mixDirectory: URL?

    private var mixTask: Task<Void, Never>?

    private var analysisTask: Task<Void, Never>?

    /// A run named on the command line, not yet read. See `openPending`.
    private var pendingDirectory: URL?
    /// True between construction and that run being read.
    public private(set) var isOpening: Bool

    public init(
        directory: URL? = nil,
        sources: SourceLibrary = SourceLibrary(),
        defaults: UserDefaults = .standard
    ) {
        self.sources = sources
        self.defaults = defaults
        // `object(forKey:)` rather than `double(forKey:)`: the latter answers 0 for a key
        // that was never written, and a gate of zero declines everything.
        if let remembered = defaults.object(forKey: Self.magnificationKey) as? Double {
            maxMagnification = remembered
        }
        if let remembered = defaults.object(forKey: Self.stretchKey) as? Double {
            maxStretch = remembered
        }
        if let remembered = defaults.object(forKey: Self.shearKey) as? Double {
            maxShear = remembered
        }
        pendingDirectory = directory
        isOpening = directory != nil
        // Named now rather than after the load, so the strip does not start on Import and
        // jump to Fine Tune a moment later.
        stage = Stage.opening(hasRun: directory != nil)
    }

    /// Reads the run named on the command line.
    ///
    /// **Deliberately not done in `init`.** Decoding a manifest and a QA report is
    /// synchronous disk work, and doing it while the scene is being constructed races
    /// with the window being created — measured on this machine as a window that appears
    /// on one launch and not the next, from the same build and the same arguments, with
    /// the process alive and idle in its event loop either way. Nino recorded the same
    /// thing and both it and CrewListr answer it the same way: put a window on screen
    /// first, then load into it.
    public func openPending() {
        defer { isOpening = false }
        guard let directory = pendingDirectory else { return }
        pendingDirectory = nil
        // A folder given on the command line is the reason the app was opened, so a
        // failure to read it has to be said rather than dropping into an empty window.
        open(directory)
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
            correctedCount: session?.correctedCount ?? 0,
            isSaving: isSaving,
            lastSaveSummary: lastSaveSummary,
            qaReportProblem: session?.qaReportProblem,
            mixTileCount: mixTileCount,
            compositeCount: mixManifest?.composites.count ?? 0,
            mixLeftOverCount: mixManifest?.unused.count ?? 0,
            isMixing: isMixing,
            mixProgress: mixProgress,
            lastMixSummary: lastMixSummary
        )
    }

    /// Tiles a mix could actually use: the ones written, not the whole queue. A candidate
    /// the gates declined has no file, and a correction that pushed one past a gate
    /// removed its file and cleared its path.
    public var mixTileCount: Int {
        session?.entries.count { $0.outputURL != nil } ?? 0
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

    /// Opens whatever somebody chose, rather than one of the two things it could be.
    ///
    /// A folder holding `manifest.json` is a run and is opened as one. A folder holding
    /// photographs is source material and is imported. Insisting on the first is how
    /// choosing a folder of portraits produced an alert saying to run `prosopon align`
    /// first — advice given by the one screen whose whole purpose is to run it, about the
    /// very folder it would have run on.
    public func open(_ directory: URL) {
        if ReviewSession.isRun(directory) {
            openRun(directory)
        } else if containsPhotographs(directory) {
            sources.add([directory])
            stage = .importPortraits
        } else {
            problem = "\(directory.lastPathComponent) holds neither a manifest.json from an "
                + "earlier run nor any photographs Prosopon can read."
        }
    }

    private func openRun(_ directory: URL) {
        do {
            let opened = try ReviewSession(directory: directory)
            session = opened
            outputDirectory = directory
            // The control adopts the gate this run was made with. Leaving it on the
            // built-in default is how Analyse Again re-ran twenty portraits at 2.0 and
            // discarded seventeen of them: the manifest said 3.5, the review honoured
            // it, and the one button on that screen quietly disagreed with both.
            maxMagnification = opened.thresholds.maxMagnification
            maxStretch = opened.options.maxStretch
            maxShear = opened.options.maxShear
            lastSaveSummary = nil
            stage = .fineTune
        } catch {
            problem = "\(error)"
        }
    }

    /// Asked of the folder itself, not of the library, so a folder with nothing in it is
    /// never added and then found to be empty.
    private func containsPhotographs(_ directory: URL) -> Bool {
        !SourceScanner.scan([ImageSource.at(directory)]).isEmpty
    }

    public func recordSave(_ summary: String) {
        lastSaveSummary = summary
        session?.recordSave(summary)
    }

    public func setSaving(_ saving: Bool) { isSaving = saving }

    // MARK: Mixing

    /// Composes the run's tiles into quartered portraits.
    ///
    /// Runs off the main actor for the same reason the analysis does: it decodes every
    /// tile twice and writes tens of megabytes per composite, and a window that stops
    /// redrawing while it does is a window that looks broken.
    public func mix() {
        guard !isMixing else { return }
        guard let session else {
            problem = "Open or analyse a run first \u{2014} a mix is made from aligned tiles."
            return
        }
        guard mixTileCount >= 4 else {
            problem = "A composite takes exactly four tiles, and this run has \(mixTileCount)."
            return
        }

        let input = session.directory
        let output = mixOutputDirectory ?? input.appendingPathComponent("mixed")
        mixOutputDirectory = output

        stage = .mix
        isMixing = true
        mixProgress = MixRunner.Progress(phase: .measuring, completed: 0, total: mixTileCount)

        // Read off `self` here rather than inside the task, which holds it weakly.
        let options = MixOptions(seed: mixSeed)
        let spec = session.spec

        mixTask = Task { [weak self] in
            do {
                let summary = try await MixRunner.run(
                    input: input, output: output, spec: spec, options: options,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in self?.mixProgress = progress }
                    }
                )
                guard !Task.isCancelled else {
                    await MainActor.run { self?.finishMix(directory: nil, summary: nil, problem: nil) }
                    return
                }
                await MainActor.run {
                    self?.finishMix(directory: output, summary: summary.describedOutcome, problem: nil)
                }
            } catch {
                await MainActor.run {
                    self?.finishMix(directory: nil, summary: nil, problem: "\(error)")
                }
            }
        }
    }

    public func cancelMix() {
        mixTask?.cancel()
    }

    /// Loads the manifest a mix left behind, so the stage shows what it made.
    ///
    /// A manifest that is there and will not decode is reported rather than swallowed: an
    /// empty Mix stage beside a folder full of composites, with no error anywhere, is the
    /// shape of failure this project keeps meeting.
    public func loadMix(from directory: URL) {
        guard MixManifest.exists(in: directory) else {
            problem = "\(directory.lastPathComponent) has no \(MixManifest.fileName) \u{2014} "
                + "that is what `prosopon mix` writes."
            return
        }
        do {
            mixManifest = try MixManifest.read(in: directory)
            mixDirectory = directory
            mixOutputDirectory = directory
            stage = .mix
        } catch {
            problem = "\(error)"
        }
    }

    private func finishMix(directory: URL?, summary: String?, problem: String?) {
        isMixing = false
        mixProgress = nil
        mixTask = nil
        if let problem { self.problem = problem }
        lastMixSummary = summary
        guard let directory else { return }
        do {
            mixManifest = try MixManifest.read(in: directory)
            mixDirectory = directory
        } catch {
            mixManifest = nil
            self.problem = "The composites were written but \(MixManifest.fileName) "
                + "could not be read back: \(error)"
        }
    }

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
        let solveOptions = self.solveOptions
        let thresholds = QualityThresholds(maxMagnification: maxMagnification)
        // Read off `self` here rather than inside the task, which holds it weakly.
        let choice = detector
        let detectorName = choice.rawValue

        analysisTask = Task { [weak self] in
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                let pipeline = try Self.makePipeline(
                    spec: spec, solveOptions: solveOptions, thresholds: thresholds,
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
                    await MainActor.run { self?.finishAnalysis(directory: nil, problem: nil) }
                    return
                }
                try RunWriter.write(
                    tiles, to: directory, spec: spec, solveOptions: solveOptions,
                    thresholds: thresholds, bitDepth: OutputDepth.eight.rawValue,
                    detector: detectorName, resampler: Resampler.lanczos.rawValue
                )
                await MainActor.run { self?.finishAnalysis(directory: directory, problem: nil) }
            } catch {
                await MainActor.run { self?.finishAnalysis(directory: nil, problem: "\(error)") }
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
        spec: CanvasSpec, solveOptions: SolveOptions, thresholds: QualityThresholds,
        detector: DetectorChoice, directory: URL
    ) throws -> Pipeline {
        Pipeline(
            spec: spec,
            solveOptions: solveOptions,
            thresholds: thresholds,
            selection: .all,
            detector: try detector.make(),
            renderer: try Resampler.lanczos.makeRenderer(spec: spec),
            output: OutputPlan(directory: directory, format: .png, depth: .eight)
        )
    }

    /// `~/Pictures/Prosopon/<source folder> aligned`, so the first run needs no decision.
    /// Takes the gate from a run that is already in the output folder.
    ///
    /// Reads the manifest directly rather than opening a session: this runs on every
    /// change of the output folder, including the one `defaultOutputDirectory` makes,
    /// and opening a whole run to read one number would be work nobody asked for.
    private func adoptThresholdsOfRunAtOutput() {
        guard let directory = outputDirectory else { return }
        let url = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(RunManifest.self, from: data)
        else { return }
        maxMagnification = manifest.thresholds.maxMagnification
        maxStretch = manifest.maxStretch
        maxShear = manifest.maxShear
    }

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
