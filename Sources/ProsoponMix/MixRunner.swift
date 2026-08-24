import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponPSD

public enum MixWriteError: Error, CustomStringConvertible {
    case wrongTileSize(URL, found: String, expected: String)
    case previewFailed(String)

    public var description: String {
        switch self {
        case .wrongTileSize(let url, let found, let expected):
            "\(url.lastPathComponent) is \(found); every tile in a mix must be \(expected)"
        case .previewFailed(let reason):
            "could not assemble the flattened composite: \(reason)"
        }
    }
}

/// What a mix run produced, in the shape a summary line wants.
public struct MixSummary: Sendable {
    public let directory: URL
    public let tileCount: Int
    public let compositeCount: Int
    public let writtenCount: Int
    public let unusedCount: Int
    public let missingTileCount: Int
    public let frontalityBasis: FrontalityBasis
    public let byteCount: UInt64
    public let manifestURL: URL

    /// One sentence, for the banner and for the end of a command-line run.
    public var describedOutcome: String {
        var line = "\(compositeCount) composite\(compositeCount == 1 ? "" : "s") from \(tileCount) tiles"
        if writtenCount != compositeCount { line += ", \(writtenCount) written" }
        if unusedCount > 0 {
            line += " \u{2014} \(unusedCount) tile\(unusedCount == 1 ? "" : "s") left over, "
                + "a composite needs exactly four"
        }
        return line
    }
}

/// Measure, plan, write. The whole of a mix run, shared by the command line and the app.
///
/// Two passes over the tiles rather than one: the assignment cannot be made until every
/// tile has been measured, and holding hundreds of decoded 2048 x 2048 images to avoid a
/// second decode is not a trade worth making. The measuring pass reads thumbnails, so it
/// costs a fraction of the writing pass.
public enum MixRunner {

    public struct Progress: Sendable, Equatable {
        public enum Phase: String, Sendable { case measuring, composing }
        public let phase: Phase
        public let completed: Int
        public let total: Int

        public init(phase: Phase, completed: Int, total: Int) {
            self.phase = phase
            self.completed = completed
            self.total = total
        }

        public var fraction: Double { total == 0 ? 1 : Double(completed) / Double(total) }
    }

    public static func run(
        input: URL,
        output: URL,
        spec: CanvasSpec = .standard,
        options: MixOptions = .default,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> MixSummary {
        let grid = QuadrantGrid(
            spec: spec, seamWidth: options.seamWidth, mouthBandHeight: options.mouthBandHeight
        )
        let catalogue = try MixCatalogue.read(input, canvasSize: grid.canvasSize)

        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let measurements = try await measure(
            catalogue.candidates, grid: grid, options: options, onProgress: onProgress
        )
        let plan = MixPlanner.plan(
            measurements, seed: options.seed, frontalityBasis: catalogue.frontalityBasis
        )

        let written: [Int: StackSummary] = options.isDryRun
            ? [:]
            : try await write(
                plan: plan, measurements: measurements, grid: grid, spec: spec,
                output: output, options: options, onProgress: onProgress
            )

        let manifest = manifest(
            plan: plan, measurements: measurements, written: written,
            grid: grid, options: options, catalogue: catalogue
        )
        let manifestURL = output.appendingPathComponent("mix-manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL)
        try Data(MixReport.render(manifest).utf8)
            .write(to: output.appendingPathComponent("mix-report.csv"))

        return MixSummary(
            directory: output,
            tileCount: measurements.count,
            compositeCount: plan.composites.count,
            writtenCount: written.count,
            unusedCount: plan.unusedTileIndices.count,
            missingTileCount: catalogue.missingTilePaths.count,
            frontalityBasis: plan.frontalityBasis,
            byteCount: written.values.reduce(0) { $0 + $1.byteCount },
            manifestURL: manifestURL
        )
    }

    // MARK: Measuring

    private static func measure(
        _ candidates: [MixCandidate],
        grid: QuadrantGrid,
        options: MixOptions,
        onProgress: (@Sendable (Progress) -> Void)?
    ) async throws -> [TileMeasurement] {
        let measurer = TileMeasurer(grid: grid, options: options)

        var results: [Int: TileMeasurement] = [:]
        var failure: Error?
        var completed = 0

        await withTaskGroup(of: (Int, Result<TileMeasurement, Error>).self) { group in
            var next = 0
            func addTask() {
                guard next < candidates.count else { return }
                let index = next
                let candidate = candidates[index]
                next += 1
                group.addTask {
                    (index, Result { try measurer.measure(candidate) })
                }
            }

            for _ in 0..<min(options.concurrency, candidates.count) { addTask() }

            while let (index, result) = await group.next() {
                switch result {
                case .success(let measurement): results[index] = measurement
                case .failure(let error): failure = failure ?? error
                }
                completed += 1
                onProgress?(Progress(phase: .measuring, completed: completed, total: candidates.count))
                addTask()
            }
        }

        if let failure { throw failure }
        // Collected by index and flattened in input order, so the plan does not depend on
        // which measurement happened to finish first.
        return candidates.indices.compactMap { results[$0] }
    }

    // MARK: Writing

    private static func write(
        plan: MixPlan,
        measurements: [TileMeasurement],
        grid: QuadrantGrid,
        spec: CanvasSpec,
        output: URL,
        options: MixOptions,
        onProgress: (@Sendable (Progress) -> Void)?
    ) async throws -> [Int: StackSummary] {
        let composites = options.limit.map { Array(plan.composites.prefix($0)) } ?? plan.composites
        guard !composites.isEmpty else { return [:] }

        if options.previewSize != nil {
            try FileManager.default.createDirectory(
                at: output.appendingPathComponent("previews"), withIntermediateDirectories: true
            )
        }

        var written: [Int: StackSummary] = [:]
        var failure: Error?
        var completed = 0

        await withTaskGroup(of: (Int, Result<StackSummary, Error>).self) { group in
            var next = 0
            func addTask() {
                guard next < composites.count else { return }
                let composite = composites[next]
                next += 1
                group.addTask {
                    (composite.index, Result {
                        try writeOne(
                            composite, measurements: measurements, grid: grid, spec: spec,
                            output: output, options: options
                        )
                    })
                }
            }

            // A composite holds a full-canvas accumulator plus one quadrant at a time, so
            // the footprint is bounded by the concurrency rather than by the batch.
            for _ in 0..<min(options.concurrency, composites.count) { addTask() }

            while let (index, result) = await group.next() {
                switch result {
                case .success(let summary): written[index] = summary
                case .failure(let error): failure = failure ?? error
                }
                completed += 1
                onProgress?(Progress(phase: .composing, completed: completed, total: composites.count))
                addTask()
            }
        }

        if let failure { throw failure }
        return written
    }

    private static func writeOne(
        _ composite: CompositePlan,
        measurements: [TileMeasurement],
        grid: QuadrantGrid,
        spec: CanvasSpec,
        output: URL,
        options: MixOptions
    ) throws -> StackSummary {
        var tiles: [Quadrant: URL] = [:]
        var names: [Quadrant: String] = [:]
        for assignment in composite.quadrants {
            let tile = measurements[assignment.tileIndex]
            try checkSize(tile.tileURL, grid: grid)
            tiles[assignment.quadrant] = tile.tileURL
            names[assignment.quadrant] = tile.name
        }

        let document = CompositeDocument.make(
            tiles: tiles, names: names, grid: grid, spec: spec, options: options
        )
        let summary = try StackWriter.write(
            document,
            to: documentURL(output, index: composite.index, options: options),
            options: options.stackOptions
        )

        if let previewSize = options.previewSize {
            let image = try CompositeImage.render(tiles: tiles, grid: grid, size: previewSize)
            try ImageWriting.write(
                image, to: previewURL(output, index: composite.index), format: .png, depth: .eight
            )
        }
        if let flatFormat = options.flatFormat {
            let image = try CompositeImage.render(tiles: tiles, grid: grid, size: grid.canvasSize)
            try ImageWriting.write(
                image, to: flatURL(output, index: composite.index, format: flatFormat),
                format: flatFormat, depth: .eight
            )
        }
        return summary
    }

    /// Every tile has to be the canvas it was aligned onto, or the quadrant crops come
    /// from the wrong pixels. Checked by name here so the message says which file.
    private static func checkSize(_ url: URL, grid: QuadrantGrid) throws {
        guard let size = ImageLoading.dimensions(of: url) else {
            throw MixMeasureError.unreadableTile(url, "no readable dimensions")
        }
        guard size.width == grid.canvasSize, size.height == grid.canvasSize else {
            throw MixWriteError.wrongTileSize(
                url,
                found: "\(size.width)x\(size.height)",
                expected: "\(grid.canvasSize)x\(grid.canvasSize)"
            )
        }
    }

    // MARK: Names

    static func stem(_ index: Int) -> String { String(format: "mix-%04d", index + 1) }

    static func documentURL(_ output: URL, index: Int, options: MixOptions) -> URL {
        output.appendingPathComponent("\(stem(index)).\(options.format.rawValue)")
    }

    static func previewURL(_ output: URL, index: Int) -> URL {
        output.appendingPathComponent("previews").appendingPathComponent("\(stem(index)).png")
    }

    static func flatURL(_ output: URL, index: Int, format: ImageFormat) -> URL {
        output.appendingPathComponent("\(stem(index))-flat.\(format.fileExtension)")
    }

    // MARK: The manifest

    private static func manifest(
        plan: MixPlan,
        measurements: [TileMeasurement],
        written: [Int: StackSummary],
        grid: QuadrantGrid,
        options: MixOptions,
        catalogue: MixCatalogueResult
    ) -> MixManifest {
        let composites = plan.composites.map { composite -> CompositeRecord in
            let wasWritten = written[composite.index] != nil
            var seams: [String: Double] = [:]
            for (seam, cost) in composite.seamCosts where cost.isFinite {
                seams[seam.rawValue] = cost
            }
            return CompositeRecord(
                index: composite.index,
                // Recorded relative to the manifest, so a mix folder that is moved or
                // copied still describes itself.
                documentPath: wasWritten
                    ? "\(stem(composite.index)).\(options.format.rawValue)" : nil,
                previewPath: wasWritten && options.previewSize != nil
                    ? "previews/\(stem(composite.index)).png" : nil,
                flatPath: (options.flatFormat.map { format in
                    wasWritten ? "\(stem(composite.index))-flat.\(format.fileExtension)" : nil
                }) ?? nil,
                mouthSeam: encodable(composite.mouthBandCost),
                seams: seams,
                quadrants: composite.quadrants.map { assignment in
                    let tile = measurements[assignment.tileIndex]
                    return QuadrantRecord(
                        quadrant: assignment.quadrant,
                        name: tile.name,
                        tilePath: tile.tileURL.path,
                        sourcePath: tile.sourcePath,
                        yawDegrees: encodable(tile.yawDegrees),
                        score: encodable(tile.score),
                        chosenBy: assignment.reason,
                        cost: encodable(assignment.cost)
                    )
                }
            )
        }

        var unused = plan.unusedTileIndices.map { index in
            UnusedTile(
                tilePath: measurements[index].tileURL.path,
                name: measurements[index].name,
                reason: "fewer than four tiles remained; a composite needs exactly four"
            )
        }
        unused.append(contentsOf: catalogue.missingTilePaths.map {
            UnusedTile(
                tilePath: $0, name: URL(fileURLWithPath: $0).lastPathComponent,
                reason: "named in the run manifest but not on disk"
            )
        })

        return MixManifest(
            canvasSize: grid.canvasSize,
            quadrantSize: grid.quadrantSize,
            seed: options.seed,
            seamWidth: grid.seamWidth,
            mouthBandHeight: grid.mouthBandHeight,
            measureSize: options.measureSize,
            frontalityBasis: plan.frontalityBasis,
            frontalityNote: plan.frontalityBasis.explanation,
            sourceRun: catalogue.runDirectory?.path,
            tileCount: measurements.count,
            composites: composites,
            unused: unused
        )
    }
}
