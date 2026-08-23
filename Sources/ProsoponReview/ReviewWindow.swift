import ProsoponCore
import ProsoponIO
import ProsoponRender
import SwiftUI
import UniformTypeIdentifiers

/// The whole app: a queue on the left, the tile being worked on to the right.
public struct ReviewWindow: View {
    @State private var session: ReviewSession?
    @State private var loadError: String?
    @State private var saveMessage: String?
    @State private var isSaving = false

    private let thumbnails = ThumbnailCache()
    @State private var renderer: PreviewRenderer?

    public init(directory: URL? = nil) {
        if let directory { _session = State(initialValue: try? ReviewSession(directory: directory)) }
    }

    public var body: some View {
        Group {
            if let session, let renderer {
                NavigationSplitView {
                    TileListView(session: session, thumbnails: thumbnails)
                        .navigationSplitViewColumnWidth(min: 240, ideal: 290)
                } detail: {
                    TileDetailView(session: session, renderer: renderer)
                }
                .toolbar { toolbar(session) }
                .navigationTitle(session.directory.lastPathComponent)
                .navigationSubtitle(subtitle(session))
            } else {
                welcome
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .onAppear { if renderer == nil { renderer = try? PreviewRenderer() } }
        .alert("Could not open", isPresented: .constant(loadError != nil)) {
            Button("OK") { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.square").font(.system(size: 52)).foregroundStyle(.secondary)
            Text("Prosopon Review").font(.title2)
            Text("Open a folder written by `prosopon align`.\nIt needs the manifest.json from that run.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Folder\u{2026}") { openFolder() }
                .keyboardShortcut("o")
        }
        .padding(48)
    }

    @ToolbarContentBuilder
    private func toolbar(_ session: ReviewSession) -> some ToolbarContent {
        ToolbarItemGroup {
            Button { session.selectPrevious() } label: { Image(systemName: "chevron.up") }
                .keyboardShortcut(.upArrow, modifiers: [])
                .help("Previous tile")
            Button { session.selectNext() } label: { Image(systemName: "chevron.down") }
                .keyboardShortcut(.downArrow, modifiers: [])
                .help("Next tile")

            Button("Revert") { session.revertSelected() }
                .disabled(session.selected?.isEdited != true)
                .keyboardShortcut("z")

            Button(isSaving ? "Saving\u{2026}" : "Save \(session.editCount) correction\(session.editCount == 1 ? "" : "s")") {
                save(session)
            }
            .disabled(session.editCount == 0 || isSaving)
            .keyboardShortcut("s")

            Button("Open\u{2026}") { openFolder() }
        }
    }

    private func subtitle(_ session: ReviewSession) -> String {
        var parts = ["\(session.entries.count) tiles"]
        if session.editCount > 0 { parts.append("\(session.editCount) edited") }
        if let message = saveMessage { parts.append(message) }
        return parts.joined(separator: "  \u{00B7}  ")
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            session = try ReviewSession(directory: url)
            saveMessage = nil
            Task { await thumbnails.invalidateAll() }
        } catch {
            loadError = "\(error)"
        }
    }

    /// Corrections are written over the run they came from, so a later `stack` or `qa`
    /// picks them up without any further step.
    private func save(_ session: ReviewSession) {
        isSaving = true
        let entries = session.entries
        let directory = session.directory
        let spec = session.spec
        let options = session.options
        let resampler = Resampler(rawValue: session.resampler) ?? .lanczos

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
                do {
                    let summary = try CorrectionWriter.save(
                        entries: entries, directory: directory,
                        spec: spec, options: options, resampler: resampler
                    )
                    return .success(summary.describedOutcome)
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let message):
                saveMessage = message
                session.recordSave(message)
                await thumbnails.invalidateAll()
            case .failure(let error):
                loadError = "\(error)"
            }
            isSaving = false
        }
    }
}
