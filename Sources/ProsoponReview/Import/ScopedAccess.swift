import Foundation

/// Holds security-scoped access open for as long as it lives, and closes it exactly once.
///
/// Its own object rather than a field on `SourceLibrary` because the release has to happen
/// in a `deinit`, and a `deinit` on a `@MainActor` type is not main-actor isolated — it
/// cannot touch that type's own state. A separate box with a lock can be torn down from
/// wherever the last reference happens to go.
///
/// Unbalanced `startAccessingSecurityScopedResource` leaks a kernel resource, and in a
/// sandboxed process it counts against a per-process limit that is not large.
final class ScopedAccess: @unchecked Sendable {
    private let lock = NSLock()
    private var open: [URL] = []

    /// Ignores a URL that does not need scoping — a plain bookmark, or a path in a
    /// process with no sandbox — since there is then nothing to release either.
    func begin(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        lock.lock(); defer { lock.unlock() }
        open.append(url)
    }

    func releaseAll() {
        lock.lock()
        let urls = open
        open.removeAll()
        lock.unlock()
        for url in urls { url.stopAccessingSecurityScopedResource() }
    }

    var openCount: Int {
        lock.lock(); defer { lock.unlock() }
        return open.count
    }

    deinit { releaseAll() }
}
