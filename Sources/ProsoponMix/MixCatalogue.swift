import Foundation
import ProsoponCore
import ProsoponIO

/// One aligned tile that a composite could use.
public struct MixCandidate: Sendable {
    public let tileURL: URL
    public let sourcePath: String
    public let name: String
    public let yawDegrees: Double?
    public let score: Double?

    public init(
        tileURL: URL, sourcePath: String, name: String, yawDegrees: Double?, score: Double?
    ) {
        self.tileURL = tileURL
        self.sourcePath = sourcePath
        self.name = name
        self.yawDegrees = yawDegrees
        self.score = score
    }
}

public struct MixCatalogueResult: Sendable {
    public let candidates: [MixCandidate]
    public let frontalityBasis: FrontalityBasis
    /// Set when the tiles came from an align run rather than a bare folder of images.
    public let runDirectory: URL?
    /// Tiles a run manifest named that are not on disk any more — a correction that
    /// pushed one past a gate removes its file. Reported rather than skipped in silence.
    public let missingTilePaths: [String]
}

public enum MixCatalogueError: Error, CustomStringConvertible {
    case noSuchDirectory(URL)
    case unreadableManifest(URL, String)
    case noTiles(URL)

    public var description: String {
        switch self {
        case .noSuchDirectory(let url): "no such directory: \(url.path)"
        case .unreadableManifest(let url, let reason):
            "could not read \(url.lastPathComponent): \(reason)"
        case .noTiles(let url):
            "no aligned tiles in \(url.path). A tile the gates declined has no file, so a "
                + "run where nothing cleared them leaves nothing to mix."
        }
    }
}

/// Finds the tiles a mix run can use, and what is known about each.
///
/// Prefers a run's `manifest.json`, which carries the yaw and the quality score and — more
/// importantly — says which candidates were actually written. A record with no output path
/// was declined by the gates and has no file; a record whose file has since been removed
/// was corrected past a gate later. Both are excluded here rather than failing at the
/// first attempt to open one.
public enum MixCatalogue {

    public static func read(_ directory: URL, canvasSize: Int) throws -> MixCatalogueResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw MixCatalogueError.noSuchDirectory(directory)
        }

        let manifestURL = directory.appendingPathComponent("manifest.json")
        let result = FileManager.default.fileExists(atPath: manifestURL.path)
            ? try fromRun(manifestURL, directory: directory)
            : try fromFolder(directory)

        guard !result.candidates.isEmpty else { throw MixCatalogueError.noTiles(directory) }
        return result
    }

    // MARK: From a run

    private static func fromRun(_ manifestURL: URL, directory: URL) throws -> MixCatalogueResult {
        let manifest: RunManifest
        do {
            manifest = try JSONDecoder().decode(RunManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            // Never `try?` here. A manifest that will not decode has to say so: swallowing
            // it would silently fall back to scanning the folder, and the mix would run
            // with no yaw, no score and no idea it had lost them.
            throw MixCatalogueError.unreadableManifest(manifestURL, "\(error)")
        }

        var candidates: [MixCandidate] = []
        var missing: [String] = []

        for tile in manifest.tiles {
            guard let outputPath = tile.outputPath else { continue }
            let url = resolve(outputPath, relativeTo: directory)
            guard FileManager.default.fileExists(atPath: url.path) else {
                missing.append(outputPath)
                continue
            }
            candidates.append(MixCandidate(
                tileURL: url,
                sourcePath: tile.sourcePath,
                name: url.deletingPathExtension().lastPathComponent,
                yawDegrees: tile.yawDegrees,
                score: tile.quality?.score
            ))
        }

        candidates.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return MixCatalogueResult(
            candidates: candidates,
            frontalityBasis: basis(for: manifest, candidates: candidates),
            runDirectory: directory,
            missingTilePaths: missing
        )
    }

    /// What the top quadrants can honestly be chosen on.
    ///
    /// Vision reports a yaw, but in 45-degree steps — it gave 0 for faces turned 13, 20
    /// and 37 — so a mix made from a Vision run is *not* pose-sorted, and saying it was
    /// would be worse than saying nothing. The detector name is compared as a string here
    /// rather than importing the pipeline's `DetectorChoice`, which would drag the two
    /// model backends into a target that only needs to read a manifest.
    private static func basis(for manifest: RunManifest, candidates: [MixCandidate]) -> FrontalityBasis {
        let usableYaw = manifest.detector != "vision" && candidates.contains { $0.yawDegrees != nil }
        if usableYaw { return .yaw }
        return candidates.contains { $0.score != nil } ? .score : .none
    }

    // MARK: From a folder

    private static func fromFolder(_ directory: URL) throws -> MixCatalogueResult {
        let urls = try ImageLoading.imageURLs(in: directory)
        let candidates = urls.map {
            MixCandidate(
                tileURL: $0, sourcePath: $0.path,
                name: $0.deletingPathExtension().lastPathComponent,
                yawDegrees: nil, score: nil
            )
        }
        return MixCatalogueResult(
            candidates: candidates, frontalityBasis: .none,
            runDirectory: nil, missingTilePaths: []
        )
    }

    /// A manifest records absolute paths, but a run folder that has been moved or copied
    /// still holds its tiles beside it.
    private static func resolve(_ path: String, relativeTo directory: URL) -> URL {
        let recorded = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: recorded.path) { return recorded }
        return directory.appendingPathComponent(recorded.lastPathComponent)
    }
}
