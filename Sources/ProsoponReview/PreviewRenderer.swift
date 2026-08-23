import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponRender

/// Renders interactive previews, and caches the decoded source behind them.
///
/// A drag re-renders on every frame, so the source must not be decoded again each time:
/// a 6000 px JPEG costs a couple of hundred milliseconds to decode and a few
/// milliseconds to warp. One decoded image is held for the tile being worked on.
///
/// Previews are rendered against a reduced canvas rather than the full 2048. The solve
/// takes the spec as a parameter, so a preview and the eventual export come from the
/// same landmarks through the same code, only at different sizes.
public final class PreviewRenderer: @unchecked Sendable {
    public let previewSpec: CanvasSpec
    private let renderer: any TileRenderer
    private let lock = NSLock()
    private var cachedURL: URL?
    private var cachedImage: CGImage?

    public init(previewSize: Double = 768, resampler: Resampler = .lanczos) throws {
        self.previewSpec = CanvasSpec.standard.scaled(toSize: previewSize)
        // A preview that fails to build is not worth failing the whole app over.
        self.renderer = (try? resampler.makeRenderer(spec: previewSpec))
            ?? CoreGraphicsRenderer(spec: previewSpec)
    }

    public func source(for url: URL) throws -> CGImage {
        lock.lock()
        if cachedURL == url, let cachedImage {
            lock.unlock()
            return cachedImage
        }
        lock.unlock()

        let image = try ImageLoading.load(url)
        lock.lock()
        cachedURL = url
        cachedImage = image
        lock.unlock()
        return image
    }

    /// A preview of `entry` as currently solved, at `previewSpec` size.
    public func preview(of entry: ReviewEntry) throws -> CGImage? {
        guard let alignment = solveForPreview(entry) else { return nil }
        return try renderer.render(try source(for: entry.sourceURL), using: alignment.transform)
    }

    /// The solve at preview scale. The landmarks are the same; only the canvas differs.
    public func solveForPreview(_ entry: ReviewEntry, options: SolveOptions = .default) -> Alignment? {
        try? AlignmentSolver.solve(landmarks: entry.landmarks, spec: previewSpec, options: options)
    }

    public func discardCache() {
        lock.lock()
        cachedURL = nil
        cachedImage = nil
        lock.unlock()
    }
}
