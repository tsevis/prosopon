import Foundation

/// A buffered, append-only file writer that can go back and patch a field.
///
/// Photoshop declares the length of a section before its contents, and those lengths are
/// only known once the contents have been compressed. Rather than hold a multi-gigabyte
/// document in memory to measure it, the writer reserves each length field, streams the
/// contents straight to disk, and patches the reserved bytes afterwards.
final class FileWriter {
    private let handle: FileHandle
    private var buffer: Data
    private let flushThreshold: Int
    /// Stops a `.psd` from growing past what its 32-bit section lengths can address.
    /// Checked while streaming rather than afterwards, so the failure arrives in seconds
    /// instead of after writing gigabytes that could never have been opened.
    private let maximumBytes: UInt64?
    let url: URL
    private(set) var offset: UInt64 = 0

    init(url: URL, maximumBytes: UInt64? = nil, flushThreshold: Int = 4 << 20) throws {
        self.url = url
        self.maximumBytes = maximumBytes
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            throw PSDWriteError.cannotOpen(url)
        }
        try handle.truncate(atOffset: 0)
        self.handle = handle
        self.flushThreshold = flushThreshold
        self.buffer = Data(capacity: flushThreshold + (1 << 16))
    }

    func write(_ data: Data) throws {
        buffer.append(data)
        offset += UInt64(data.count)
        if let maximumBytes, offset > maximumBytes {
            throw PSDWriteError.exceededLimit(bytes: offset, limit: maximumBytes)
        }
        if buffer.count >= flushThreshold { try flush() }
    }

    func write(_ bytes: [UInt8]) throws {
        try write(Data(bytes))
    }

    func writeZeros(_ count: Int) throws {
        try write(Data(repeating: 0, count: count))
    }

    /// Reserves `count` zero bytes and returns the offset they start at, for later patching.
    func reserve(_ count: Int) throws -> UInt64 {
        let start = offset
        try writeZeros(count)
        return start
    }

    /// Overwrites bytes already streamed out. Flushes first so the target is on disk.
    func patch(at target: UInt64, with data: Data) throws {
        try flush()
        try handle.seek(toOffset: target)
        try handle.write(contentsOf: data)
        try handle.seekToEnd()
    }

    /// Pads so the run of bytes written since `bodyStart` is a multiple of `alignment`.
    ///
    /// Note that this aligns the section's *length*, not the file offset. The two are
    /// only the same when the section happens to begin on an aligned boundary, and a
    /// section length is what every reader actually consumes.
    func padSection(from bodyStart: UInt64, to alignment: Int) throws {
        let remainder = Int((offset - bodyStart) % UInt64(alignment))
        if remainder != 0 { try writeZeros(alignment - remainder) }
    }

    func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    func close() throws {
        try flush()
        try handle.close()
    }
}

public enum PSDWriteError: Error, CustomStringConvertible {
    case cannotOpen(URL)
    case noLayers
    case dimensionMismatch(URL, expected: String, found: String)
    case exceededLimit(bytes: UInt64, limit: UInt64)
    case dimensionTooLarge(DocumentFormat, side: Int)
    case tooManyLayers(Int)
    case pixelExtractionFailed(URL)

    public var description: String {
        switch self {
        case .cannotOpen(let url):
            "cannot open \(url.path) for writing"
        case .noLayers:
            "no layers to write"
        case .dimensionMismatch(let url, let expected, let found):
            "\(url.lastPathComponent) is \(found), but the stack is \(expected)"
        case .exceededLimit(let bytes, let limit):
            """
            the document passed \(bytes / (1 << 20)) MB, beyond the \(limit / (1 << 20)) MB \
            a .psd can address. Use --format psb, or --batch-size to split the stack.
            """
        case .dimensionTooLarge(let format, let side):
            "\(side) px exceeds the \(format.maxDimension) px limit of .\(format.rawValue)"
        case .tooManyLayers(let count):
            "\(count) layers exceeds Photoshop's limit of 32767 in a single document"
        case .pixelExtractionFailed(let url):
            "could not read pixels from \(url.lastPathComponent)"
        }
    }
}
