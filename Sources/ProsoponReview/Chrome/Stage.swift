import Foundation

/// The three stages, left to right in the order the work actually happens.
///
/// Reading the strip should tell somebody who has never used this what the program does:
/// bring photographs in, measure them, fix the few it got wrong. The order is not a
/// preference — Analyze has nothing to do until portraits are imported, and Fine Tune has
/// nothing to show until an analysis has produced tiles.
public enum Stage: String, CaseIterable, Identifiable, Sendable {
    case importPortraits
    case analyze
    case fineTune

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .importPortraits: "Import"
        case .analyze: "Analyze"
        case .fineTune: "Fine Tune"
        }
    }

    public var symbol: String {
        switch self {
        case .importPortraits: "photo.on.rectangle.angled"
        case .analyze: "viewfinder"
        case .fineTune: "slider.horizontal.below.rectangle"
        }
    }

    /// What each stage puts on its badge.
    ///
    /// Not simply "how many things are in there". Import counts what it found, because
    /// that is the number somebody is deciding about. Fine Tune counts what **needs
    /// attention** rather than the whole queue, because finding the handful the detector
    /// got wrong is the entire point of the stage; three hundred good tiles is not a
    /// number anybody is tracking.
    public func badge(_ state: ChromeState) -> Int? {
        let count: Int
        switch self {
        case .importPortraits: count = state.imageCount
        case .analyze: count = state.tileCount
        case .fineTune: count = state.attentionCount
        }
        return count > 0 ? count : nil
    }

    /// Said in full where a badge only shows a number.
    public func help(_ state: ChromeState) -> String {
        switch self {
        case .importPortraits:
            state.imageCount == 0
                ? "Choose folders and photographs to work on"
                : "\(state.imageCount) portrait\(state.imageCount == 1 ? "" : "s") from "
                    + "\(state.sourceCount) source\(state.sourceCount == 1 ? "" : "s")"
        case .analyze:
            state.tileCount == 0
                ? "Detect faces and solve each alignment"
                : "\(state.acceptedCount) of \(state.tileCount) tiles aligned"
        case .fineTune:
            state.attentionCount == 0
                ? "Correct the tiles the detector got wrong"
                : "\(state.attentionCount) of \(state.tileCount) tiles need attention"
        }
    }

    /// Where the app should open.
    ///
    /// Launched on a run — which is what `review.sh` and `prosopon-review ~/aligned` do —
    /// there is work waiting in Fine Tune and starting anywhere else would be a step
    /// backwards. With nothing loaded, the first stage is the only one with anything in
    /// it.
    public static func opening(hasRun: Bool) -> Stage {
        hasRun ? .fineTune : .importPortraits
    }
}
