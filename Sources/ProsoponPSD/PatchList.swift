import Foundation

/// Deferred edits to length fields that were reserved while streaming.
///
/// Collected rather than applied in place: patching mid-stream would force the write
/// buffer to flush and the file pointer to seek on every one of the four-per-layer
/// channel lengths, turning a sequential write into thousands of small scattered ones.
final class PatchList {
    private(set) var entries: [(offset: UInt64, data: Data)] = []

    func add(at offset: UInt64, _ data: Data) {
        entries.append((offset, data))
    }

    var sortedByOffset: [(offset: UInt64, data: Data)] {
        entries.sorted { $0.offset < $1.offset }
    }
}
