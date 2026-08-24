import Foundation
import ProsoponPipeline

/// A source as it was written down, so it can be opened again next launch.
///
/// The path is stored beside the bookmark on purpose. A bookmark that will not resolve is
/// opaque, and "a folder you once chose is no longer readable" is not a useful thing to
/// tell somebody with four of them. The path lets the row say *which* — and, since this
/// app is not sandboxed, it is also a perfectly good way to open the file when the
/// bookmark has stopped working.
struct SourceBookmark: Codable, Sendable {
    var data: Data
    var path: String
    var isDirectory: Bool
    var isRecursive: Bool
    /// False when the security-scoped bookmark could not be made and a plain one was
    /// written instead. Recorded rather than assumed, because the two behave differently
    /// the moment this app is sandboxed.
    var isSecurityScoped: Bool
}

/// What came back from the file somebody chose last time.
struct RestoredSources: Sendable {
    var sources: [ImageSource] = []
    /// Kept, not dropped. A folder that has been moved or is on a volume that is not
    /// mounted should appear in the list saying so, with a way to point at it again --
    /// silently forgetting it is how somebody loses a corpus they added months ago.
    var unresolved: [(path: String, reason: String)] = []
    /// Bookmarks that had to be recovered some way other than the one they were written
    /// with, and so are worth writing back in a form that will work next time.
    var refreshedCount: Int = 0
}

/// Remembers the folders somebody chose, and gets permission to read them again.
///
/// The app is not sandboxed today, so a plain path would work. This is written for the
/// day it is: without a security-scoped bookmark, a sandboxed build would open next
/// launch showing the same four folders and find every one of them empty — a failure with
/// no error attached to it, which is the kind this project keeps running into.
///
/// **A bookmark is not guaranteed to resolve the way it was written**, and this is not an
/// edge case. An app-scoped bookmark belongs to the code signing identity that created
/// it; this app is ad-hoc signed, so every rebuild is a new identity and every bookmark
/// written by the previous build fails with Cocoa error 259. Measured on a corpus of
/// twenty portraits: all twenty listed as missing, every file exactly where it had always
/// been. So resolution tries what was recorded, then the other kind, then the path — and
/// only calls something missing when the file is genuinely not there.
@MainActor
public final class BookmarkStore {
    private let defaults: UserDefaults
    private let key: String
    /// Entries that could not be resolved at all, held so that saving the live sources
    /// does not quietly delete them. A row saying a corpus has moved is the only chance
    /// anybody gets to notice; it goes when it is forgotten, not when something else is
    /// added.
    private var unresolved: [SourceBookmark] = []

    /// The defaults suite is injected so a test never writes into the real one.
    public init(defaults: UserDefaults = .standard, key: String = "prosopon.sources") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Writing

    func save(_ sources: [ImageSource]) {
        let written = sources.compactMap(bookmark(for:)) + unresolved
        guard let data = try? JSONEncoder().encode(written) else { return }
        defaults.set(data, forKey: key)
    }

    /// Drops one unresolved entry, so a row that has been dismissed does not come back.
    func forget(path: String, keeping sources: [ImageSource]) {
        unresolved.removeAll { $0.path == path }
        save(sources)
    }

    func forgetAllUnresolved(keeping sources: [ImageSource]) {
        unresolved.removeAll()
        save(sources)
    }

    private func bookmark(for source: ImageSource) -> SourceBookmark? {
        // Scoped first, and only if it can be read back: a bookmark this process cannot
        // resolve is not worth recording as one, and claiming a security scope that does
        // not work is how twenty present files came to be listed as missing.
        for scoped in [true, false] {
            let options: URL.BookmarkCreationOptions = scoped ? [.withSecurityScope] : []
            guard let data = try? source.url.bookmarkData(
                options: options, includingResourceValuesForKeys: nil, relativeTo: nil
            ) else { continue }
            if scoped, resolve(data, securityScoped: true) == nil { continue }
            return SourceBookmark(
                data: data, path: source.url.path,
                isDirectory: source.isDirectory, isRecursive: source.isRecursive,
                isSecurityScoped: scoped
            )
        }
        return nil
    }

    // MARK: Reading

    func restore() -> RestoredSources {
        unresolved = []
        guard let data = defaults.data(forKey: key) else { return RestoredSources() }

        let bookmarks: [SourceBookmark]
        do {
            bookmarks = try JSONDecoder().decode([SourceBookmark].self, from: data)
        } catch {
            // Not `try?`. A decode failure here means every remembered folder has
            // vanished from the interface, and this project has already lost a feature
            // for weeks to exactly that swallowed error.
            return RestoredSources(unresolved: [("remembered sources", "\(error)")])
        }

        var restored = RestoredSources()
        for bookmark in bookmarks {
            switch recover(bookmark) {
            case .asWritten(let url):
                restored.sources.append(source(bookmark, at: url))
            case .otherwise(let url):
                restored.sources.append(source(bookmark, at: url))
                restored.refreshedCount += 1
            case .gone(let reason):
                unresolved.append(bookmark)
                restored.unresolved.append((bookmark.path, reason))
            }
        }
        return restored
    }

    private enum Recovery {
        /// Resolved the way it was written, which is the ordinary case.
        case asWritten(URL)
        /// Resolved some other way, and so should be written back before next launch.
        case otherwise(URL)
        case gone(reason: String)
    }

    private func recover(_ bookmark: SourceBookmark) -> Recovery {
        if let url = resolve(bookmark.data, securityScoped: bookmark.isSecurityScoped) {
            return .asWritten(url)
        }
        // The other kind. A scoped bookmark resolves without the scope option, which is
        // what rescues one written by a build that is no longer the one running.
        if let url = resolve(bookmark.data, securityScoped: !bookmark.isSecurityScoped) {
            return .otherwise(url)
        }
        // Last, the path it was written down as. Nothing opaque left to go wrong: either
        // the file is there or it is not, and if it is not, that is the honest answer.
        let url = URL(fileURLWithPath: bookmark.path)
        if FileManager.default.fileExists(atPath: url.path) { return .otherwise(url) }
        return .gone(reason: "no file at \(bookmark.path)")
    }

    private func resolve(_ data: Data, securityScoped: Bool) -> URL? {
        var isStale = false
        let options: URL.BookmarkResolutionOptions = securityScoped ? [.withSecurityScope] : []
        return try? URL(
            resolvingBookmarkData: data, options: options,
            relativeTo: nil, bookmarkDataIsStale: &isStale
        )
    }

    private func source(_ bookmark: SourceBookmark, at url: URL) -> ImageSource {
        ImageSource(
            url: url, isDirectory: bookmark.isDirectory, isRecursive: bookmark.isRecursive
        )
    }

    func clear() {
        unresolved = []
        defaults.removeObject(forKey: key)
    }
}
