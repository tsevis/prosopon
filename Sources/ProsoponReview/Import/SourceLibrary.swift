import AppKit
import Foundation
import Observation
import ProsoponPipeline

/// A source that was remembered but cannot be opened now.
public struct MissingSource: Identifiable, Sendable, Equatable {
    public let path: String
    public let reason: String
    public var id: String { path }

    public var name: String { (path as NSString).lastPathComponent }
}

/// What has been imported: the folders and photographs somebody added, what they contain,
/// and permission to read them again next launch.
///
/// The scanning itself lives in `ProsoponPipeline` because the command line needs the
/// same answers. What is here is the part that is about *this* app: which sources are in
/// the list, remembering them, and holding the security-scoped access open for as long as
/// the window is.
@MainActor
@Observable
public final class SourceLibrary {
    public private(set) var sources: [ImageSource] = []
    public private(set) var missing: [MissingSource] = []
    public private(set) var scan: SourceScan = .empty
    /// Excluded from every scan, so a run never imports its own output as input.
    public var outputDirectory: URL? { didSet { rescan() } }

    private let bookmarks: BookmarkStore
    /// Releases itself when this object goes; see `ScopedAccess` for why it is not just
    /// an array here.
    private let access = ScopedAccess()

    public init(bookmarks: BookmarkStore = BookmarkStore(), restoring: Bool = true) {
        self.bookmarks = bookmarks
        if restoring { restore() }
    }

    // MARK: Adding and removing

    /// Adds folders and files together, which is what one open panel and one drop both
    /// hand over. Anything already in the list, or inside a folder already in it, is left
    /// alone rather than added twice.
    public func add(_ urls: [URL]) {
        var added = false
        for url in urls {
            let source = ImageSource.at(url)
            guard !contains(source) else { continue }
            beginAccess(to: source.url)
            sources.append(source)
            added = true
        }
        guard added else { return }
        persist()
    }

    public func remove(_ source: ImageSource) {
        sources.removeAll { $0.url == source.url }
        persist()
    }

    public func removeAll() {
        sources.removeAll()
        missing.removeAll()
        bookmarks.clear()
        rescan()
    }

    /// Dismisses one source that could not be opened, for good.
    ///
    /// It used to drop the row and leave the bookmark behind, so the same dead entry
    /// came back on the next launch: a button that could dismiss a thing but never
    /// remove it.
    public func forget(_ missingSource: MissingSource) {
        missing.removeAll { $0.path == missingSource.path }
        bookmarks.forget(path: missingSource.path, keeping: sources)
    }

    /// Dismisses all of them at once.
    ///
    /// Earned its place on a list of twenty dead rows, each with its own Forget. What
    /// they had in common was the cause, so clearing them one at a time was twenty
    /// clicks to recover from a single event.
    public func forgetAllMissing() {
        guard !missing.isEmpty else { return }
        missing.removeAll()
        bookmarks.forgetAllUnresolved(keeping: sources)
    }

    public func setRecursive(_ isRecursive: Bool, for source: ImageSource) {
        guard let index = sources.firstIndex(where: { $0.url == source.url }) else { return }
        sources[index].isRecursive = isRecursive
        persist()
    }

    /// True when this source, or a recursive folder above it, is already in the list.
    ///
    /// Adding a folder and then one photograph inside it is an easy thing to do by
    /// accident with a mixed drop, and the second one adds nothing.
    func contains(_ candidate: ImageSource) -> Bool {
        sources.contains { existing in
            if existing.url == candidate.url { return true }
            guard existing.isDirectory, existing.isRecursive else { return false }
            return candidate.url.path.hasPrefix(existing.url.path + "/")
        }
    }

    // MARK: What is in there

    public func rescan() {
        scan = SourceScanner.scan(sources, excluding: outputDirectory)
    }

    public func count(of source: ImageSource) -> Int { scan.countsBySource[source.url] ?? 0 }

    /// Sources the scan could not read at all, on top of the ones that never resolved.
    public var unreadableCount: Int { scan.unreadable.count + missing.count }

    /// How many of the imported photographs a run has already aligned.
    ///
    /// Matched on the source path a manifest records, so re-importing the folder an
    /// earlier run was made from correctly reports the work as done rather than offering
    /// to do it again.
    public func alreadyAligned(inRunWith alignedSourcePaths: Set<String>) -> Int {
        guard !alignedSourcePaths.isEmpty else { return 0 }
        return scan.imageURLs.count { alignedSourcePaths.contains($0.standardizedFileURL.path) }
    }

    public func reveal(_ source: ImageSource) {
        NSWorkspace.shared.activateFileViewerSelecting([source.url])
    }

    // MARK: Persistence

    private func persist() {
        bookmarks.save(sources)
        rescan()
    }

    private func restore() {
        let restored = bookmarks.restore()
        sources = restored.sources
        missing = restored.unresolved.map { MissingSource(path: $0.path, reason: $0.reason) }
        for source in sources { beginAccess(to: source.url) }
        // Something had to be recovered a way other than the one it was written with --
        // a stale bookmark, or one this build's identity cannot open. Writing it back
        // now in a form that works means the next launch does not have to.
        if restored.refreshedCount > 0 { bookmarks.save(sources) }
        rescan()
    }

    private func beginAccess(to url: URL) { access.begin(url) }
}
