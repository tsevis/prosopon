import ArgumentParser
import ProsoponRender
import Foundation
import ProsoponCore
import ProsoponIO

/// Flags shared by every subcommand that has to find images and solve alignments.
struct SharedOptions: ParsableArguments {
    @Argument(help: "Image files, or directories of images.")
    var inputs: [String] = []

    @Option(name: .long, help: "Maximum stretch, as a fraction. 0.05 is the 5 percent rule.")
    var maxStretch: Double = 0.05

    @Option(name: .long, help: "Maximum shear, as horizontal drift per unit of vertical drop.")
    var maxShear: Double = 0.05

    @Flag(name: .long, help: "Leave the mouth's horizontal offset uncorrected.")
    var noShear: Bool = false

    @Option(name: .long, help: "Which faces to use in each photograph: all, largest, central.")
    var faces: FaceSelection = .all

    @Flag(name: .long, help: "Take the eye centre from the pupil rather than the canthus midpoint.")
    var usePupils: Bool = false

    @Option(name: .long, help: "Discard detections below this confidence.")
    var minConfidence: Double = 0.3

    @Option(name: .long, help: "Concurrent images. Defaults to the core count.")
    var jobs: Int?

    var solveOptions: SolveOptions {
        SolveOptions(
            maxStretch: maxStretch,
            maxShear: maxShear,
            correctsHorizontalMouthOffset: !noShear
        )
    }

    var concurrency: Int {
        max(1, jobs ?? ProcessInfo.processInfo.activeProcessorCount)
    }

    /// Expands directories into their contained images, keeping explicit files as given.
    func resolvedInputs() throws -> [URL] {
        var urls: [URL] = []
        for input in inputs {
            let url = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw ValidationError("no such file or directory: \(input)")
            }
            if isDirectory.boolValue {
                urls.append(contentsOf: try ImageLoading.imageURLs(in: url))
            } else {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else {
            throw ValidationError("no readable images found in the given inputs")
        }
        return urls
    }
}

extension Resampler: ExpressibleByArgument {}
