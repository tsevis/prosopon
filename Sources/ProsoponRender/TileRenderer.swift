import CoreGraphics
import Foundation
import ProsoponCore

/// Turns a source photograph plus a solved transform into one canvas-sized tile.
public protocol TileRenderer: Sendable {
    var spec: CanvasSpec { get }
    /// The returned image is in **linear** light, tagged as such, so that writing it
    /// through `ImageWriting` re-encodes it to sRGB exactly once.
    func render(_ image: CGImage, using transform: Affine2D) throws -> CGImage
}

public enum Resampler: String, Sendable, CaseIterable {
    /// Lanczos-3 on the GPU. Sharper than Core Graphics on enlargement and, unlike a
    /// fixed-footprint filter, correctly widens its kernel when the source is reduced.
    case lanczos
    /// The same Lanczos-3 on the CPU. Deterministic, and the reference the GPU is
    /// checked against; roughly an order of magnitude slower.
    case lanczosCPU = "lanczos-cpu"
    /// Core Graphics' own `.high` interpolation.
    case coreGraphics = "coregraphics"

    public func makeRenderer(spec: CanvasSpec = .standard) throws -> any TileRenderer {
        switch self {
        case .lanczos: try MetalLanczosRenderer(spec: spec)
        case .lanczosCPU: CPULanczosRenderer(spec: spec)
        case .coreGraphics: CoreGraphicsRenderer(spec: spec)
        }
    }
}

public enum RenderError: Error, CustomStringConvertible {
    case contextUnavailable
    case noMetalDevice
    case shaderCompilationFailed(String)
    case pipelineCreationFailed(String)
    case textureAllocationFailed
    case sourceTooLarge(side: Int, limit: Int)
    case degenerateTransform

    public var description: String {
        switch self {
        case .contextUnavailable:
            "could not create the drawing context"
        case .noMetalDevice:
            "no Metal device is available; use --resampler coregraphics"
        case .shaderCompilationFailed(let message):
            "the warp shader failed to compile: \(message)"
        case .pipelineCreationFailed(let message):
            "could not build the compute pipeline: \(message)"
        case .textureAllocationFailed:
            "could not allocate a GPU texture"
        case .sourceTooLarge(let side, let limit):
            "the region needed from the source is \(side) px, past this GPU's \(limit) px texture limit"
        case .degenerateTransform:
            "the transform is not invertible"
        }
    }
}
