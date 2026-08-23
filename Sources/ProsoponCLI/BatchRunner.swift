import Foundation

/// Runs `pipeline.process` over many images with bounded concurrency, reporting
/// progress to stderr so stdout stays clean for piping.
enum BatchRunner {
    static func run(
        urls: [URL],
        pipeline: Pipeline,
        concurrency: Int,
        showsProgress: Bool
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
                if showsProgress {
                    progress(completed, of: urls.count)
                }
                addTask()
            }
        }

        if showsProgress { FileHandle.standardError.write(Data("\n".utf8)) }
        return urls.indices.flatMap { results[$0] ?? [] }
    }

    private static func progress(_ done: Int, of total: Int) {
        let width = 28
        let filled = total == 0 ? 0 : Int(Double(width) * Double(done) / Double(total))
        let bar = String(repeating: "#", count: filled) + String(repeating: ".", count: width - filled)
        FileHandle.standardError.write(Data("\r  [\(bar)] \(done)/\(total)".utf8))
    }
}
