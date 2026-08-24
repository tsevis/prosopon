import Foundation
import ProsoponIO

/// One thing somebody added: a folder of portraits, or a single photograph.
///
/// A folder carries its own recursion setting rather than the scan carrying one for all
/// of them, because a corpus is usually one deep tree beside a handful of loose files
/// and a single switch would be wrong for one of the two.
public struct ImageSource: Sendable, Hashable, Codable, Identifiable {
    public var url: URL
    public var isDirectory: Bool
    public var isRecursive: Bool

    public var id: URL { url }

    public init(url: URL, isDirectory: Bool, isRecursive: Bool = true) {
        self.url = url.standardizedFileURL
        self.isDirectory = isDirectory
        self.isRecursive = isRecursive
    }

    /// Classifies by asking the filesystem, so a caller handed a mixed drop or a mixed
    /// open panel does not have to.
    public static func at(_ url: URL, isRecursive: Bool = true) -> ImageSource {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return ImageSource(url: url, isDirectory: isDirectory.boolValue, isRecursive: isRecursive)
    }
}

/// What a set of sources actually contains.
public struct SourceScan: Sendable, Equatable {
    /// Every recognised image, de-duplicated and in a stable order.
    public let imageURLs: [URL]
    /// How many each source contributed, before de-duplication removed any overlap.
    public let countsBySource: [URL: Int]
    /// Sources that could not be read at all, with the reason. A folder that has been
    /// moved or unmounted is a thing to say out loud, not to quietly count as empty.
    public let unreadable: [URL: String]
    /// Folders deliberately left out, with the reason. Separate from `unreadable`
    /// because nothing went wrong: a mix folder is output, and refusing it silently
    /// would leave somebody staring at "0 images found" with no idea why.
    public let excluded: [URL: String]

    public var imageCount: Int { imageURLs.count }
    public var isEmpty: Bool { imageURLs.isEmpty }

    public static let empty = SourceScan(imageURLs: [], countsBySource: [:], unreadable: [:])

    public init(
        imageURLs: [URL],
        countsBySource: [URL: Int],
        unreadable: [URL: String],
        excluded: [URL: String] = [:]
    ) {
        self.imageURLs = imageURLs
        self.countsBySource = countsBySource
        self.unreadable = unreadable
        self.excluded = excluded
    }
}

/// Turns what somebody added into the list of photographs to work on.
///
/// `ImageLoading.imageURLs(in:)` reads one directory level, which is what the command
/// line's positional arguments have always meant. Three things are needed on top of it
/// before a folder can be added once and reused:
///
/// - **recursion**, because these corpora nest;
/// - **de-duplication**, because a file can arrive both on its own and inside a folder,
///   and aligning it twice would put two identical tiles in the stack;
/// - **an exclusion**, because the output folder frequently sits inside the input one,
///   and a second run would otherwise import the first run's own tiles as portraits.
public enum SourceScanner {

    public static func scan(_ sources: [ImageSource], excluding excluded: URL? = nil) -> SourceScan {
        let excludedPath = excluded?.standardizedFileURL.path
        var seen: Set<String> = []
        var collected: [URL] = []
        var counts: [URL: Int] = [:]
        var unreadable: [URL: String] = [:]
        var excluded: [URL: String] = [:]

        for source in sources {
            if source.isDirectory, isMixFolder(source.url) {
                excluded[source.url] = mixFolderReason
                counts[source.url] = 0
                continue
            }
            let found: [URL]
            do {
                found = try images(in: source)
            } catch {
                unreadable[source.url] = "\(error)"
                continue
            }

            counts[source.url] = found.count
            for url in found {
                let path = url.standardizedFileURL.path
                if let excludedPath, path.hasPrefix(excludedPath + "/") { continue }
                // First source to claim a file keeps it, so the order sources were added
                // in decides the attribution rather than the enumeration order.
                if seen.insert(path).inserted { collected.append(url) }
            }
        }

        collected.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return SourceScan(
            imageURLs: collected, countsBySource: counts,
            unreadable: unreadable, excluded: excluded
        )
    }

    /// What a mix folder is recognised by.
    ///
    /// The manifest, not the file names. A composite is 2048 x 2048 with eyes and a mouth
    /// roughly where a portrait's are, and there is no reliable way to tell one from a
    /// photograph by looking at the pixels — on a real corpus the gates caught 101 of 102
    /// and let one through. The manifest beside them is unambiguous.
    static let mixManifestName = "mix-manifest.json"

    static let mixFolderReason = "a mix folder \u{2014} these are composites this app made, "
        + "not photographs to align"

    static func isMixFolder(_ directory: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(mixManifestName).path
        )
    }

    /// Every recognised image one source stands for.
    public static func images(in source: ImageSource) throws -> [URL] {
        guard source.isDirectory else {
            return ImageLoading.recognisedExtensions.contains(source.url.pathExtension.lowercased())
                ? [source.url]
                : []
        }
        guard source.isRecursive else {
            return try ImageLoading.imageURLs(in: source.url)
        }
        return try imageURLs(under: source.url)
    }

    /// Depth-first through a tree, skipping hidden files and the innards of packages.
    ///
    /// A `.photoslibrary` or an `.app` is a directory as far as the filesystem is
    /// concerned and full of images nobody meant to align, so descending into one is
    /// never what was asked for.
    public static func imageURLs(under directory: URL) throws -> [URL] {
        let manager = FileManager.default
        // Fail loudly on a folder that is not there. The enumerator returns nil for a
        // missing directory and an empty result reads exactly like an empty folder,
        // which is how a moved corpus would come back as "0 images found".
        guard manager.fileExists(atPath: directory.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: directory.path])
        }
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: directory.path])
        }

        var found: [URL] = []
        // Directories holding a mix manifest are skipped whole, previews and all. The
        // enumerator is told to skip descendants rather than filtered afterwards, so a
        // mix folder with thousands of composites in it costs nothing to pass over.
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                if isMixFolder(url) { enumerator.skipDescendants() }
                continue
            }
            guard ImageLoading.recognisedExtensions.contains(url.pathExtension.lowercased())
            else { continue }
            found.append(url)
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
