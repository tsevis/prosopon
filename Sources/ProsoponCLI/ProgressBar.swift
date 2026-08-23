import Foundation
import ProsoponPipeline

/// The batch's progress, drawn on stderr so stdout stays clean for piping.
///
/// `BatchRunner` reports two numbers and knows nothing about how they are shown; this is
/// the command line's way of showing them, and the app has its own.
enum ProgressBar {
    private static let width = 28

    static let draw: @Sendable (BatchRunner.Progress) -> Void = { progress in
        let filled = Int(Double(width) * progress.fraction)
        let bar = String(repeating: "#", count: filled)
            + String(repeating: ".", count: width - filled)
        FileHandle.standardError.write(
            Data("\r  [\(bar)] \(progress.completed)/\(progress.total)".utf8)
        )
    }

    static func finish() {
        FileHandle.standardError.write(Data("\n".utf8))
    }
}
