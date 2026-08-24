import AppKit
import ProsoponCore
import ProsoponIO
import ProsoponMix
import ProsoponPipeline
import ProsoponRender
import SwiftUI

/// The window: the stages, one line of commands, one line of plain language, and the work.
///
/// The three strips are the same shape in every stage; only the panel below them changes.
/// Every action available anywhere lives in the command bar, which is what keeps a window
/// with four stages and a dozen actions still reading as one simple thing.
public struct ReviewWindow: View {
    @State private var state: AppState
    @State private var renderer: PreviewRenderer?
    @State private var showingAbout = false
    @State private var isDropTarget = false

    private let thumbnails = ThumbnailCache()

    public init(directory: URL? = nil) {
        _state = State(initialValue: AppState(directory: directory))
    }

    public var body: some View {
        // A window on screen before any manifest is read. See `AppState.openPending`:
        // decoding one during scene construction races with the window being created,
        // and the losing side of that race is a live process with no window at all.
        if state.isOpening {
            OpeningView()
                .frame(minWidth: 1000, minHeight: 700)
                .background(Theme.ground)
                .task { state.openPending() }
        } else {
            workspace
        }
    }

    private var workspace: some View {
        @Bindable var state = state

        return VStack(spacing: 0) {
            StageStrip(selection: $state.stage, state: state.chrome)
            CommandBar(commands: commands, perform: perform) {
                SubjectChipView(
                    state: state.chrome,
                    onOpenRun: openRun,
                    onRevealRun: revealRun
                )
            }
            AnalysisProgressStrip(state: state.chrome)
            BannerView(banner: StatusBanner.message(for: state.stage, state: state.chrome))
            content
        }
        .background(Theme.ground)
        .frame(minWidth: 1000, minHeight: 700)
        .onAppear { if renderer == nil { renderer = try? PreviewRenderer() } }
        // Folders and photographs together, which is what a Finder drag hands over.
        .dropDestination(for: URL.self) { urls, _ in
            state.sources.add(urls)
            if state.stage == .fineTune, state.session == nil { state.stage = .importPortraits }
            return true
        } isTargeted: { isDropTarget = $0 }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showingAbout) {
            AboutView { showingAbout = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .prosoponShowAbout)) { _ in
            showingAbout = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .prosoponAddSources)) { _ in
            addSources()
        }
        // Safe here, where it was not before: this view only exists once the window is
        // up, so the panel is raised onto a window rather than instead of one.
        .task { if AboutPresentation.wanted() { showingAbout = true } }
        .onChange(of: showingAbout) { _, showing in
            if !showing { AboutPresentation.remember() }
        }
        .alert(Brand.name, isPresented: Binding(
            get: { state.problem != nil },
            set: { if !$0 { state.problem = nil } }
        )) {
            Button("OK", role: .cancel) { state.problem = nil }
        } message: {
            Text(state.problem ?? "")
        }
    }

    // MARK: The work itself

    @ViewBuilder
    private var content: some View {
        switch state.stage {
        case .importPortraits:
            ImportView(
                state: state,
                alignedPaths: state.alignedSourcePaths,
                thumbnails: thumbnails,
                onAdd: addSources
            )
        case .analyze:
            AnalyzeView(state: state, onChooseOutput: chooseOutput)
        case .fineTune:
            fineTune
        case .mix:
            MixView(state: state, thumbnails: thumbnails, onChooseOutput: chooseMixOutput)
        }
    }

    @ViewBuilder
    private var fineTune: some View {
        if let session = state.session, let renderer {
            // The queue and the tile, unchanged: worst first on the left, the draggable
            // landmarks on the right.
            NavigationSplitView {
                TileListView(session: session, thumbnails: thumbnails)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 290)
            } detail: {
                TileDetailView(session: session, renderer: renderer)
            }
        } else {
            EmptyStateView(
                symbol: "slider.horizontal.below.rectangle",
                title: "No run open",
                message: "Analyze some portraits, or open a folder an earlier run wrote. "
                    + "It needs the manifest.json from that run."
            ) {
                Button("Open Run\u{2026}", action: openRun).buttonStyle(.prosoponSecondary)
            }
        }
    }

    // MARK: Commands

    private var commands: [Command] {
        CommandSet.commands(for: state.stage, state: state.chrome)
    }

    private func perform(_ action: ChromeAction) {
        switch action {
        case .addSources: addSources()
        case .removeAllSources: state.sources.removeAll()
        case .chooseOutputFolder: chooseOutput()
        case .analyse: state.analyse()
        case .cancelAnalysis: state.cancelAnalysis()
        case .openRun: openRun()
        case .revertTile: state.session?.revertSelected()
        case .saveCorrections: save()
        case .goToAnalyze: state.stage = .analyze
        case .goToFineTune: state.stage = .fineTune
        case .goToMix: state.stage = .mix
        case .chooseMixFolder: chooseMixOutput()
        case .mix: state.mix()
        case .cancelMix: state.cancelMix()
        }
    }

    // MARK: Panels

    /// One panel taking folders and files at once, which is what Apple's own applications
    /// do and what saves a second trip when a corpus is a folder plus a few strays.
    private func addSources() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.message = "Choose folders of portraits, individual photographs, or both."
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        state.sources.add(panel.urls)
        state.stage = .importPortraits
    }

    private func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Where should the aligned tiles and the manifest be written?"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.outputDirectory = url
    }

    private func chooseMixOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Where should the composites and the mix manifest be written?"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.mixOutputDirectory = url
        // Opening a folder that already holds a mix shows it, rather than presenting an
        // empty stage beside a folder full of composites.
        if MixManifest.exists(in: url) { state.loadMix(from: url) }
    }

    private func openRun() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder written by an earlier run \u{2014} the one holding "
            + "manifest.json."
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.open(url)
        Task { await thumbnails.invalidateAll() }
    }

    private func revealRun() {
        guard let directory = state.session?.directory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    // MARK: Saving

    /// Corrections are written over the run they came from, so a later `stack` or `qa`
    /// picks them up without any further step.
    private func save() {
        guard let session = state.session else { return }
        state.setSaving(true)

        let entries = session.entries
        let directory = session.directory
        let spec = session.spec
        let options = session.options
        let resampler = Resampler(rawValue: session.resampler) ?? .lanczos
        let depth = OutputDepth(rawValue: session.bitDepth) ?? .sixteen

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CorrectionWriter.Summary, Error> in
                do {
                    return .success(try CorrectionWriter.save(
                        entries: entries, directory: directory,
                        spec: spec, options: options, resampler: resampler, depth: depth
                    ))
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let summary):
                // Before the message, so the count the banner reads has already fallen.
                session.markSaved(summary.written)
                state.recordSave(summary.describedOutcome)
                await thumbnails.invalidateAll()
            case .failure(let error):
                state.problem = "\(error)"
            }
            state.setSaving(false)
        }
    }
}

public extension Notification.Name {
    static let prosoponShowAbout = Notification.Name("ProsoponShowAbout")
    static let prosoponAddSources = Notification.Name("ProsoponAddSources")
}

/// Shows the info panel once, the first time this version is run.
enum AboutPresentation {
    private static let key = "prosopon.about.seen"

    static func wanted() -> Bool {
        UserDefaults.standard.string(forKey: key) != Brand.version
    }

    static func remember() {
        UserDefaults.standard.set(Brand.version, forKey: key)
    }
}

/// Shown for the moment between the window appearing and the run being read.
///
/// Usually too brief to notice, and that is fine — its job is not to be looked at but to
/// exist, so that there is a window before there is any work.
private struct OpeningView: View {
    var body: some View {
        EmptyStateView(
            symbol: "square.grid.3x3.topleft.filled",
            title: "Opening the run",
            message: "Reading the manifest and, if one was written, the QA report beside it."
        ) {
            ProgressView().controlSize(.small)
        }
    }
}
