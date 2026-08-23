import Foundation

/// The words in the info panel, kept apart from the view that lays them out so they can
/// be read, corrected and checked without a window.
public enum AboutText {

    public static let story: [String] = [
        "Prosopon maps portrait photographs onto one fixed grid, so that fragments of "
            + "different faces can be cut apart and recombined. Two thousand and forty-eight "
            + "pixels square, sixteen cells across: the viewer's left eye lands on "
            + "(512, 512), the right on (1536, 512), the mouth on (1024, 1664). Every "
            + "photograph, every time.",

        "Those three coordinates are not adjustable, and that is the whole point. A "
            + "fragment of one photograph only meets a fragment of another cleanly when "
            + "both put the same feature on the same pixel. A landmark convention that is "
            + "slightly wrong but applied identically to every face costs nothing; one that "
            + "wobbles from photograph to photograph shows up as a step at every seam.",

        "Three points impose six constraints. A similarity transform has four degrees of "
            + "freedom, so it can pin both eyes exactly and nothing else; a full affine has "
            + "six and hits all three, but with unbounded distortion. Prosopon sits between "
            + "them: the eyes are solved exactly, then a vertical stretch and a shear "
            + "pivoted on the eye line bring the mouth in, capped at five per cent. Because "
            + "both pivot on the line the eyes already sit on, the eyes stay exact for free.",

        "Some faces do not fit, and are declined rather than forced. A photograph too "
            + "small to fill the canvas would leave an empty corner no mosaic can use. A "
            + "turned head foreshortens the distance between the eyes, so pinning them to "
            + "their fixed targets scales the whole face up and the jaw comes out larger "
            + "than on a frontal tile — and since the eye coordinates are not negotiable, "
            + "there is no freedom left to correct it. Declining is the only useful answer.",

        "The detector is wrong on a handful out of hundreds, so it can be corrected by "
            + "hand: drag a marker onto the feature as it actually appears, and the "
            + "correction travels back through the transform. Only the tiles that changed "
            + "are re-rendered.",

        "Everything happens on this Mac. Face detection is Apple's Vision framework or "
            + "InsightFace through ONNX Runtime, both running locally on the Neural Engine; "
            + "no photograph is uploaded, no account is required, and there is no network "
            + "call to disable because there is not one to begin with.",
    ]

    public static let legal: [String] = [
        "Face detection uses Apple's Vision framework, or the InsightFace buffalo_l models "
            + "(det_10g, 2d106det and 1k3d68) run through ONNX Runtime with the CoreML "
            + "execution provider. The InsightFace models are the work of Jia Guo and "
            + "Jiankang Deng and are licensed for non-commercial research use; Prosopon "
            + "ships none of them and reads whichever copy is already installed.",

        "ONNX Runtime is Copyright (c) Microsoft Corporation, MIT licence. "
            + "swift-argument-parser is Copyright (c) Apple Inc., Apache 2.0.",

        "The layered .psd and .psb writer is a hand-written implementation of Adobe's "
            + "published file format specification, and is checked against psd-tools "
            + "(MIT licence) rather than against its own assumptions.",

        "Resampling is Lanczos-3 in linear light, implemented as a Metal compute kernel "
            + "with a CPU reference the GPU is measured against, tap for tap.",
    ]

    public static let credit = "Made by \(Brand.makerName)"
}
