import Foundation
import ProsoponCore

/// Why a row in the queue has no picture to show.
///
/// A tile that failed a gate is never written to disk, so there is nothing for the list
/// to load. That is correct behaviour, but an empty black square reads as a broken
/// thumbnail rather than as a deliberate refusal — and the two need to look different,
/// because only one of them is a problem.
///
/// Kept as a value with its own wording so the queue's captions can be checked without
/// putting a window on screen.
public enum TileExportState: Sendable, Equatable {
    /// Written, and the file is where the manifest says it is.
    case exported(URL)
    /// Solved, but declined by the gates. Carries what it was declined for.
    case notExported([RejectionReason])
    /// The solve itself failed, so there was never a tile to write.
    case unsolvable(String)
    /// Accepted, but no file was recorded — what `align --dry-run` leaves behind.
    case analysedOnly
    /// The manifest names a file that is no longer there. A correction that pushes a
    /// tile past a gate deletes it, so this is a state a run reaches by being used.
    case missing(URL)

    /// An SF Symbol standing in for the missing thumbnail.
    public var symbolName: String {
        switch self {
        case .exported: "photo"
        case .notExported: "square.slash"
        case .unsolvable: "exclamationmark.triangle"
        case .analysedOnly: "circle.dashed"
        case .missing: "questionmark.square.dashed"
        }
    }

    /// One short line saying what happened, in the reviewer's language rather than the
    /// gate's. `nil` when there is a picture and the picture speaks for itself.
    public var caption: String? {
        switch self {
        case .exported:
            nil
        case .notExported(let reasons):
            reasons.isEmpty
                ? "Not exported"
                : "Not exported \u{00B7} " + reasons.map(Self.phrase).joined(separator: ", ")
        case .unsolvable:
            "No tile \u{00B7} could not be solved"
        case .analysedOnly:
            "Analysed only \u{00B7} no file written"
        case .missing:
            "File missing"
        }
    }

    /// True when this state is a problem rather than a decision. A declined tile is the
    /// tool working; a missing file or a failed solve is not.
    public var isTrouble: Bool {
        switch self {
        case .exported, .notExported, .analysedOnly: false
        case .unsolvable, .missing: true
        }
    }

    static func phrase(_ reason: RejectionReason) -> String {
        switch reason {
        case .incompleteCoverage: "does not fill the canvas"
        case .excessiveMagnification: "enlarged too far"
        case .mouthOffTarget: "mouth off target"
        case .excessiveYaw: "turned too far"
        }
    }
}

extension ReviewEntry {
    /// What the queue should draw for this tile.
    ///
    /// Pure: whether the named file still exists is a separate question, answered by the
    /// row when its thumbnail comes back empty, so this stays testable without touching
    /// the filesystem.
    public var exportState: TileExportState {
        if let failure { return .unsolvable(failure) }
        guard let quality else { return .unsolvable("not solved") }
        guard quality.isAccepted else { return .notExported(quality.rejections) }
        guard let outputURL else { return .analysedOnly }
        return .exported(outputURL)
    }
}
