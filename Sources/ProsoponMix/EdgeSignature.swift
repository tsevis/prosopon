import Foundation

/// One sample of a seam strip: its colour at one point along the join.
public struct LabSample: Sendable, Codable, Equatable {
    public var lightness: Double
    public var greenRed: Double
    public var blueYellow: Double

    public init(lightness: Double, greenRed: Double, blueYellow: Double) {
        self.lightness = lightness
        self.greenRed = greenRed
        self.blueYellow = blueYellow
    }

    /// ΔE76 between two samples.
    public func distance(to other: LabSample) -> Double {
        let dL = lightness - other.lightness
        let da = greenRed - other.greenRed
        let db = blueYellow - other.blueYellow
        return (dL * dL + da * da + db * db).squareRoot()
    }

    static func - (lhs: LabSample, rhs: LabSample) -> LabSample {
        LabSample(
            lightness: lhs.lightness - rhs.lightness,
            greenRed: lhs.greenRed - rhs.greenRed,
            blueYellow: lhs.blueYellow - rhs.blueYellow
        )
    }
}

/// What one seam strip looks like, along its whole length.
///
/// Three decisions are folded into this type, and all three are measurable rather than
/// matters of taste:
///
/// - **The mean is taken in linear light.** Averaging gamma-encoded values is averaging
///   the wrong quantity; a strip half in shadow and half lit averages too dark in sRGB.
/// - **The comparison is made in CIE Lab.** Tone matching is a perceptual question, and
///   equal distances in Lab are roughly equal differences to the eye, which is not true
///   of RGB. So the average is computed in linear light and then converted, once.
/// - **The strip is kept as a profile, not a single colour.** This is the one that
///   decides whether a join reads as continuous. A seam is 1024 px long and a face
///   changes a great deal over that distance: jaw, neck, shoulder, backdrop. Two strips
///   whose means agree can run in opposite directions — one lightening downwards, the
///   other darkening — and a mean cannot tell them from a perfect match.
///
/// `texture` is the standard deviation of L* over the strip. Two strips can share a
/// profile and still refuse to join — a smooth cheek meeting stubble is the case that
/// motivated it — so it enters the distance with a small weight of its own.
public struct EdgeSignature: Sendable, Codable, Equatable {
    public var lightness: Double
    public var greenRed: Double
    public var blueYellow: Double
    public var texture: Double
    /// Colour at points along the seam, in order. Empty for a signature written before
    /// profiles existed, which is why every use of it is guarded.
    public var profile: [LabSample]

    public init(
        lightness: Double,
        greenRed: Double,
        blueYellow: Double,
        texture: Double,
        profile: [LabSample] = []
    ) {
        self.lightness = lightness
        self.greenRed = greenRed
        self.blueYellow = blueYellow
        self.texture = texture
        self.profile = profile
    }

    /// How many points a strip is sampled at.
    ///
    /// Sixteen over 1024 px is one sample every 64 px — fine enough to catch a jaw
    /// meeting a neck, coarse enough that a single stray highlight does not move it.
    public static let profileLength = 16

    /// How much the texture term counts against a unit of Lab distance.
    ///
    /// Low on purpose: a mismatch in tone is a visible step at the seam, while a mismatch
    /// in texture is a change of surface that a viewer will often read as part of the
    /// face. It breaks ties rather than driving the choice.
    static let textureWeight = 0.5

    /// How much disagreeing *slopes* count.
    ///
    /// Separate from the level term because they fail differently. A constant offset
    /// between two strips is a step at the seam, which is bad; a difference in how they
    /// change along it is the join drifting apart towards one end, which reads as two
    /// pictures rather than one face and is worse for its size.
    static let slopeWeight = 1.5

    /// The distance that decides a join.
    ///
    /// Level and slope, plus texture. Falls back to the means alone when either side has
    /// no profile, so a signature from an older measurement still compares.
    public func distance(to other: EdgeSignature) -> Double {
        let texturePart = Self.textureWeight * abs(texture - other.texture)

        guard profile.count == other.profile.count, profile.count > 1 else {
            return meanDistance(to: other) + texturePart
        }

        var level = 0.0
        for (a, b) in zip(profile, other.profile) { level += a.distance(to: b) }
        level /= Double(profile.count)

        // The change from each sample to the next, compared between the two strips. This
        // is what a mean cannot see.
        var slope = 0.0
        for index in 1..<profile.count {
            let stepA = profile[index] - profile[index - 1]
            let stepB = other.profile[index] - other.profile[index - 1]
            slope += stepA.distance(to: stepB)
        }
        slope /= Double(profile.count - 1)

        return level + Self.slopeWeight * slope + texturePart
    }

    /// ΔE76 between the two strip means. What the whole distance used to be.
    func meanDistance(to other: EdgeSignature) -> Double {
        let dL = lightness - other.lightness
        let da = greenRed - other.greenRed
        let db = blueYellow - other.blueYellow
        return (dL * dL + da * da + db * db).squareRoot()
    }

    /// The worst disagreement anywhere along the join, in ΔE.
    ///
    /// Reported rather than matched on: it is the number that says "this seam breaks at
    /// the chin" where an average says the seam is fine.
    public func worstDisagreement(with other: EdgeSignature) -> Double {
        guard profile.count == other.profile.count, !profile.isEmpty else {
            return meanDistance(to: other)
        }
        return zip(profile, other.profile).map { $0.distance(to: $1) }.max() ?? 0
    }
}

/// sRGB to CIE Lab, by way of linear light and XYZ under D65.
enum ColorConversion {

    /// One 8-bit sRGB component to linear.
    static func linear(_ encoded: UInt8) -> Double {
        let value = Double(encoded) / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// Linear sRGB to Lab. The white point is D65, which is sRGB's own.
    static func lab(linearRed r: Double, green g: Double, blue b: Double) -> (Double, Double, Double) {
        let x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b

        let fx = f(x / 0.95047)
        let fy = f(y / 1.00000)
        let fz = f(z / 1.08883)

        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// L* alone, which is all the texture term needs.
    static func lightness(linearRed r: Double, green g: Double, blue b: Double) -> Double {
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        return 116 * f(y) - 16
    }

    private static func f(_ t: Double) -> Double {
        t > 0.008856451679035631 ? cbrt(t) : (903.2962962962963 * t + 16) / 116
    }
}
