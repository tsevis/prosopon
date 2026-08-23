import Foundation

/// Thresholds a candidate tile must clear to enter the aligned stack.
public struct QualityThresholds: Hashable, Sendable, Codable {
    /// Reject anything that does not fill the whole canvas. Mosaic tiles cannot have
    /// transparent corners, so this defaults to on.
    public var requiresFullCoverage: Bool

    /// Reject when the source has to be enlarged by more than this factor. Deliberately
    /// permissive by default: the magnification is always reported, so it is better to
    /// let the operator sort on the number than to silently discard usable photos.
    public var maxMagnification: Double

    /// Reject when the mouth misses its target by more than this many canvas pixels.
    /// `.infinity` accepts every residual.
    public var maxMouthErrorPixels: Double

    public init(
        requiresFullCoverage: Bool = true,
        maxMagnification: Double = 2.0,
        maxMouthErrorPixels: Double = .infinity
    ) {
        self.requiresFullCoverage = requiresFullCoverage
        self.maxMagnification = maxMagnification
        self.maxMouthErrorPixels = maxMouthErrorPixels
    }

    public static let `default` = QualityThresholds()
}

public enum RejectionReason: String, Hashable, Sendable, Codable, CaseIterable {
    case incompleteCoverage
    case excessiveMagnification
    case mouthOffTarget
}

/// Everything known about one candidate tile, in a form that sorts and serialises.
public struct QualityReport: Hashable, Sendable, Codable {
    public let coverage: Double
    public let magnification: Double
    public let mouthErrorPixels: Double
    public let appliedStretchPercent: Double
    public let requestedStretchPercent: Double
    public let stretchWasClamped: Bool
    public let shearWasClamped: Bool
    public let rollCorrectionDegrees: Double
    public let rejections: [RejectionReason]

    public var isAccepted: Bool { rejections.isEmpty }

    /// 0...1, higher is better. Full coverage and no clamping score 1; the score decays
    /// with mouth error and with how far the source had to be enlarged.
    public var score: Double {
        let coverageTerm = coverage
        let mouthTerm = 1 / (1 + mouthErrorPixels / 32)
        let sharpnessTerm = magnification <= 1 ? 1 : 1 / magnification
        return coverageTerm * mouthTerm * sharpnessTerm
    }

    public static func evaluate(
        alignment: Alignment,
        fit: SourceFit,
        thresholds: QualityThresholds = .default
    ) -> QualityReport {
        let mouthError = alignment.mouthResidual.length
        var rejections: [RejectionReason] = []

        if thresholds.requiresFullCoverage && !fit.isFullyCovered {
            rejections.append(.incompleteCoverage)
        }
        if alignment.magnification > thresholds.maxMagnification {
            rejections.append(.excessiveMagnification)
        }
        if mouthError > thresholds.maxMouthErrorPixels {
            rejections.append(.mouthOffTarget)
        }

        return QualityReport(
            coverage: fit.coverage,
            magnification: alignment.magnification,
            mouthErrorPixels: mouthError,
            appliedStretchPercent: alignment.appliedStretchPercent,
            requestedStretchPercent: alignment.requestedStretchPercent,
            stretchWasClamped: alignment.stretchWasClamped,
            shearWasClamped: alignment.shearWasClamped,
            rollCorrectionDegrees: alignment.rollCorrectionDegrees,
            rejections: rejections
        )
    }
}
