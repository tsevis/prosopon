import Foundation
import ProsoponPipeline

/// A source as it was written down, so it can be opened again next launch.
///
/// The path is stored beside the bookmark on purpose. A bookmark that will not resolve is
/// opaque, and "a folder you once chose is no longer readable" is not a useful thing to
/// tell somebody with four of them. The path lets the row say *which*.
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
    /// Bookmarks macOS says have gone stale and were rewritten.
    var refreshedCount: Int = 0
}

/// Remembers the folders somebody chose, and gets permission to read them again.
///
/// The app is not sandboxed today, so a plain path would work. This is written for the
/// day it is: without a security-scoped bookmark, a sandboxed build would open next
/// launch showing the same four folders and find every one of them empty — a failure with
/// no error attached to it, which is the kind this project keeps running into.
@MainActor
public final class BookmarkStore {
    private let defaults: UserDefaults
    private let key: String

    /// The defaults suite is injected so a test never writes into the real one.
    public init(defaults: UserDefaults = .standard, key: String = "prosopon.sources") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Writing

    func save(_ sources: [ImageSource]) {
        let bookmarks = sources.compactMap(bookmark(for:))
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: key)
    }

    private func bookmark(for source: ImageSource) -> SourceBookmark? {
        // Scoped first; a plain bookmark still survives a rename or a move, which is most
        // of the value outside a sandbox.
        for scoped in [true, false] {
            let options: URL.BookmarkCreationOptions = scoped ? [.withSecurityScope] : []
            guard let data = try? source.url.bookmarkData(
                options: options, includingResourceValuesForKeys: nil, relativeTo: nil
            ) else { continue }
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
            var isStale = false
            let options: URL.BookmarkResolutionOptions =
                bookmark.isSecurityScoped ? [.withSecurityScope] : []
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmark.data, options: options,
                    relativeTo: nil, bookmarkDataIsStale: &isStale
                )
                restored.sources.append(ImageSource(
                    url: url,
                    isDirectory: bookmark.isDirectory,
                    isRecursive: bookmark.isRecursive
                ))
                if isStale { restored.refreshedCount += 1 }
            } catch {
                restored.unresolved.append((bookmark.path, "\(error)"))
            }
        }
        return restored
    }

    func clear() { defaults.removeObject(forKey: key) }
}
