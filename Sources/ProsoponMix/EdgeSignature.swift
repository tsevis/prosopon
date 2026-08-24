import Foundation

/// What one seam strip looks like, reduced to four numbers.
///
/// Two decisions are folded into this type, and both are measurable rather than matters
/// of taste:
///
/// - **The mean is taken in linear light.** Averaging gamma-encoded values is averaging
///   the wrong quantity; a strip half in shadow and half lit averages too dark in sRGB.
/// - **The comparison is made in CIE Lab.** Tone matching is a perceptual question, and
///   equal distances in Lab are roughly equal differences to the eye, which is not true
///   of RGB. So the average is computed in linear light and then converted, once.
///
/// `texture` is the standard deviation of L* over the strip. Two strips can share a mean
/// and still refuse to join — a smooth cheek meeting stubble is the case that motivated
/// it — so it enters the distance with a small weight of its own.
public struct EdgeSignature: Sendable, Codable, Equatable {
    public var lightness: Double
    public var greenRed: Double
    public var blueYellow: Double
    public var texture: Double

    public init(lightness: Double, greenRed: Double, blueYellow: Double, texture: Double) {
        self.lightness = lightness
        self.greenRed = greenRed
        self.blueYellow = blueYellow
        self.texture = texture
    }

    /// How much the texture term counts against a unit of Lab distance.
    ///
    /// Low on purpose: a mismatch in tone is a visible step at the seam, while a mismatch
    /// in texture is a change of surface that a viewer will often read as part of the
    /// face. It breaks ties rather than driving the choice.
    static let textureWeight = 0.5

    /// ΔE76 plus the weighted texture difference. Zero for two identical strips.
    public func distance(to other: EdgeSignature) -> Double {
        let dL = lightness - other.lightness
        let da = greenRed - other.greenRed
        let db = blueYellow - other.blueYellow
        let deltaE = (dL * dL + da * da + db * db).squareRoot()
        return deltaE + Self.textureWeight * abs(texture - other.texture)
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
