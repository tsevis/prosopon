import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponRender

public struct QAOptions: Sendable {
    public var spec: CanvasSpec
    /// Multiplies the deviation image so the variation is visible rather than near-black.
    public var deviationGain: Double
    /// A tile beyond this many pixels from consensus is called out as a suspect.
    public var suspectThreshold: Double

    public init(spec: CanvasSpec = .standard, deviationGain: Double = 3, suspectThreshold: Double = 2) {
        self.spec = spec
        self.deviationGain = deviationGain
        self.suspectThreshold = suspectThreshold
    }
}

public struct QAResult: Sendable {
    public let report: StackQA
    public let mean: LinearPixels
    public let deviation: LinearPixels
}

public enum QAError: Error, CustomStringConvertible {
    case noTiles
    case sizeMismatch(URL, expected: String, found: String)
    case decodeFailed(URL)

    public var description: String {
        switch self {
        case .noTiles: "no tiles to analyse"
        case .sizeMismatch(let url, let expected, let found):
            "\(url.lastPathComponent) is \(found), but the stack is \(expected)"
        case .decodeFailed(let url): "could not decode \(url.lastPathComponent)"
        }
    }
}

/// Averages an aligned stack and measures how well it registered.
///
/// The average is the point of the exercise. If alignment worked, hundreds of different
/// faces superimposed leave the eyes and mouth crisp while everything that varies
/// between people -- hair, jaw, skin -- averages into a blur. One image says whether a
/// whole batch is usable.
///
/// The alignment itself is solved analytically and puts the eyes on target to within a
/// billionth of a pixel, so a blurred average never means the arithmetic slipped: it
/// means the landmark detector was wrong on some tiles. That is why this also measures,
/// per tile, how far each landmark sits from where the rest of the stack agrees it
/// should be -- turning "the average looks soft" into a ranked list of files to fix.
public enum MeanFaceBuilder {

    public static func analyse(
        tiles: [URL],
        options: QAOptions = QAOptions(),
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> QAResult {
        guard !tiles.isEmpty else { throw QAError.noTiles }

        let side = Int(options.spec.size.rounded())
        var statistics = StackStatistics(width: side, height: side)
        var patchesByTile: [[Landmark: LuminancePatch]] = []
        var tileAcutance: [Landmark: [Double]] = [:]
        var globalAcutance: [Double] = []
        patchesByTile.reserveCapacity(tiles.count)

        for (index, url) in tiles.enumerated() {
            try autoreleasepool {
                let image = try ImageLoading.load(url)
                guard image.width == side, image.height == side else {
                    throw QAError.sizeMismatch(url, expected: "\(side)x\(side)",
                                               found: "\(image.width)x\(image.height)")
                }
                guard let pixels = LinearPixels.decode(
                    image, cropX: 0, cropY: 0, width: side, height: side
                ) else { throw QAError.decodeFailed(url) }

                statistics.add(pixels)

                var patches: [Landmark: LuminancePatch] = [:]
                for landmark in Landmark.allCases {
                    let patch = LuminancePatch.extract(
                        from: pixels,
                        centredOn: landmark.target(in: options.spec),
                        side: Registration.patchSide
                    )
                    patches[landmark] = patch
                    tileAcutance[landmark, default: []].append(patch.acutance)
                }
                patchesByTile.append(patches)

                let whole = LuminancePatch.extract(
                    from: pixels,
                    centredOn: Point2D(options.spec.size / 2, options.spec.size / 2),
                    side: side
                )
                globalAcutance.append(whole.acutance)
            }
            progress?(index + 1, tiles.count)
        }

        let mean = statistics.mean()
        let deviation = statistics.deviation(gain: options.deviationGain)

        // The average becomes the reference every tile is compared against.
        var referencePatches: [Landmark: LuminancePatch] = [:]
        var landmarkSharpness: [Landmark: SharpnessRetention] = [:]
        for landmark in Landmark.allCases {
            let patch = LuminancePatch.extract(
                from: mean,
                centredOn: landmark.target(in: options.spec),
                side: Registration.patchSide
            )
            referencePatches[landmark] = patch
            landmarkSharpness[landmark] = retention(
                meanAcutance: patch.acutance, tileValues: tileAcutance[landmark] ?? []
            )
        }

        let meanWhole = LuminancePatch.extract(
            from: mean, centredOn: Point2D(options.spec.size / 2, options.spec.size / 2), side: side
        )
        let globalSharpness = retention(meanAcutance: meanWhole.acutance, tileValues: globalAcutance)

        let measured = await measureOffsets(
            tiles: tiles, patchesByTile: patchesByTile, reference: referencePatches
        )

        return QAResult(
            report: StackQA(
                tileCount: tiles.count,
                canvasSize: options.spec.size,
                landmarkSharpness: landmarkSharpness,
                globalSharpness: globalSharpness,
                tiles: measured
            ),
            mean: mean,
            deviation: deviation
        )
    }

    private static func retention(meanAcutance: Double, tileValues: [Double]) -> SharpnessRetention {
        let average = tileValues.isEmpty ? 0 : tileValues.reduce(0, +) / Double(tileValues.count)
        return SharpnessRetention(
            meanImageAcutance: meanAcutance,
            averageTileAcutance: average,
            retention: average > 1e-9 ? meanAcutance / average : 0
        )
    }

    /// The search is independent per tile, so it fans out across cores.
    private static func measureOffsets(
        tiles: [URL],
        patchesByTile: [[Landmark: LuminancePatch]],
        reference: [Landmark: LuminancePatch]
    ) async -> [TileQA] {
        await withTaskGroup(of: (Int, TileQA).self) { group in
            for (index, url) in tiles.enumerated() {
                let patches = patchesByTile[index]
                group.addTask {
                    var offsets: [Landmark: ConsensusOffset] = [:]
                    for landmark in Landmark.allCases {
                        guard let tilePatch = patches[landmark],
                              let referencePatch = reference[landmark] else { continue }
                        offsets[landmark] = Registration.consensusOffset(
                            of: tilePatch, against: referencePatch
                        )
                    }
                    return (index, TileQA(
                        name: url.deletingPathExtension().lastPathComponent,
                        path: url.path,
                        offsets: offsets
                    ))
                }
            }

            var collected: [Int: TileQA] = [:]
            for await (index, tile) in group { collected[index] = tile }
            return tiles.indices.compactMap { collected[$0] }
        }
    }
}
