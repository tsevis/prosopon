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

    /// Reject when the head is turned further than this, in degrees.
    ///
    /// Yaw is the one distortion the aligner cannot answer. A turned head foreshortens
    /// the interocular distance, so pinning the eyes to their fixed targets scales the
    /// whole face up to compensate: the cheek and jaw come out larger than on a frontal
    /// tile, and a mosaic fragment cut from one will not meet its neighbours. Because
    /// the eye coordinates are not negotiable there is no freedom left to correct it —
    /// the scale is fully determined — so the only useful response is to decline.
    ///
    /// `.infinity` accepts any pose, which is also what happens when the detector in use
    /// reports no yaw at all.
    public var maxYawDegrees: Double

    public init(
        requiresFullCoverage: Bool = true,
        maxMagnification: Double = 2.0,
        maxMouthErrorPixels: Double = .infinity,
        maxYawDegrees: Double = .infinity
    ) {
        self.requiresFullCoverage = requiresFullCoverage
        self.maxMagnification = maxMagnification
        self.maxMouthErrorPixels = maxMouthErrorPixels
        self.maxYawDegrees = maxYawDegrees
    }

    public static let `default` = QualityThresholds()
}

// MARK: - Serialising a threshold that is switched off

/// A gate that is off is `.infinity`, and JSON has no infinity — `JSONEncoder` throws
/// rather than inventing one. So an inactive gate is written as **absent**, which is also
/// how it reads: a manifest with no `maxYawDegrees` in it did not gate on yaw.
///
/// This matters because the thresholds a run was made with now travel in its manifest.
/// Without them the review app re-solves every tile against the built-in defaults, and a
/// run aligned with `--max-magnification 8` reopens with most of its tiles marked
/// rejected — tiles whose files are sitting right there beside the manifest.
extension QualityThresholds {
    private enum CodingKeys: String, CodingKey {
        case requiresFullCoverage, maxMagnification, maxMouthErrorPixels, maxYawDegrees
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            requiresFullCoverage: try container.decodeIfPresent(
                Bool.self, forKey: .requiresFullCoverage) ?? true,
            maxMagnification: try container.decodeIfPresent(
                Double.self, forKey: .maxMagnification) ?? .infinity,
            maxMouthErrorPixels: try container.decodeIfPresent(
                Double.self, forKey: .maxMouthErrorPixels) ?? .infinity,
            maxYawDegrees: try container.decodeIfPresent(
                Double.self, forKey: .maxYawDegrees) ?? .infinity
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requiresFullCoverage, forKey: .requiresFullCoverage)
        try container.encodeIfPresent(finite(maxMagnification), forKey: .maxMagnification)
        try container.encodeIfPresent(finite(maxMouthErrorPixels), forKey: .maxMouthErrorPixels)
        try container.encodeIfPresent(finite(maxYawDegrees), forKey: .maxYawDegrees)
    }

    private func finite(_ value: Double) -> Double? { value.isFinite ? value : nil }
}

public enum RejectionReason: String, Hashable, Sendable, Codable, CaseIterable {
    case incompleteCoverage
    case excessiveMagnification
    case mouthOffTarget
    case excessiveYaw
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
    /// As reported by the detector, when it reports one at all.
    public let yawDegrees: Double?
    public let rejections: [RejectionReason]

    public var isAccepted: Bool { rejections.isEmpty }

    /// 0...1, higher is better. Full coverage and no clamping score 1; the score decays
    /// with mouth error and with how far the source had to be enlarged.
    public var score: Double {
        let coverageTerm = coverage
        let mouthTerm = 1 / (1 + mouthErrorPixels / 32)
        let sharpnessTerm = magnification <= 1 ? 1 : 1 / magnification
        // A turned head is penalised smoothly as well as gated, so that sorting by score
        // brings the most frontal tiles forward even when nothing was rejected.
        let poseTerm = yawDegrees.map { 1 / (1 + abs($0) / 45) } ?? 1
        return coverageTerm * mouthTerm * sharpnessTerm * poseTerm
    }

    public static func evaluate(
        alignment: Alignment,
        fit: SourceFit,
        yawDegrees: Double? = nil,
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
        // A detector that reports no yaw cannot fail this gate. Silence is not evidence
        // of a frontal face, and inventing a zero would be worse than admitting that.
        if let yawDegrees, abs(yawDegrees) > thresholds.maxYawDegrees {
            rejections.append(.excessiveYaw)
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
            yawDegrees: yawDegrees,
            rejections: rejections
        )
    }
}
