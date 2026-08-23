import Foundation
import ProsoponCore

/// Runs `pipeline.process` over many images with bounded concurrency.
///
/// Progress is reported as two numbers rather than drawn. The command line renders them
/// as a bar on stderr so stdout stays clean for piping; the app puts the same pair into
/// a progress view. Neither of those is this type's business, and the version that wrote
/// to stderr directly could only ever have one caller.
public enum BatchRunner {

    /// Where a batch had got to. Reported after every image finishes.
    public struct Progress: Sendable, Equatable {
        public let completed: Int
        public let total: Int

        public var fraction: Double { total == 0 ? 1 : Double(completed) / Double(total) }
        public var isFinished: Bool { completed >= total }
    }

    public static func run(
        urls: [URL],
        pipeline: Pipeline,
        concurrency: Int,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async -> [TileRecord] {
        var results: [Int: [TileRecord]] = [:]
        var completed = 0

        await withTaskGroup(of: (Int, [TileRecord]).self) { group in
            var next = 0
            func addTask() {
                guard next < urls.count else { return }
                let index = next
                let url = urls[index]
                next += 1
                group.addTask { (index, pipeline.process(url)) }
            }

            for _ in 0..<min(concurrency, urls.count) { addTask() }

            while let (index, records) = await group.next() {
                results[index] = records
                completed += 1
                onProgress?(Progress(completed: completed, total: urls.count))
                addTask()
            }
        }

        // Results are collected by index and flattened in input order, so a batch is
        // reproducible whatever order the task group happened to finish in.
        return urls.indices.flatMap { results[$0] ?? [] }
    }
}
