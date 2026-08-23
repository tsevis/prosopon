import CoreGraphics
import Foundation
import Metal
import ProsoponCore

/// Lanczos-3 resampling on the GPU.
///
/// A reference type because the device, queue and pipeline are built once and shared
/// across every image in a batch; all three are documented as thread-safe, so a batch
/// can drive one instance from many tasks at once.
public final class MetalLanczosRenderer: TileRenderer, @unchecked Sendable {
    public let spec: CanvasSpec

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    /// Metal does not expose the 2-D texture limit as a device property. Every family
    /// this can run on -- Apple silicon, and Mac family 2 -- caps a 2-D texture at
    /// 16384 px on a side.
    private static let maximumTextureSide = 16_384

    /// Matches `WarpParams` in the shader. The layout assertion in `init` is what keeps
    /// the two definitions honest.
    private struct WarpParams {
        var row0: SIMD4<Float>
        var row1: SIMD4<Float>
        var cropSize: SIMD2<Float>
        var kernelScale: SIMD2<Float>
        var support: SIMD2<Float>
        var canvasSize: SIMD2<UInt32>
    }

    public init(spec: CanvasSpec = .standard) throws {
        self.spec = spec

        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noMetalDevice }
        guard let queue = device.makeCommandQueue() else { throw RenderError.noMetalDevice }
        self.device = device
        self.queue = queue

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: WarpShader.source, options: nil)
        } catch {
            throw RenderError.shaderCompilationFailed("\(error)")
        }
        guard let function = library.makeFunction(name: WarpShader.functionName) else {
            throw RenderError.pipelineCreationFailed("no function named \(WarpShader.functionName)")
        }
        do {
            self.pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            throw RenderError.pipelineCreationFailed("\(error)")
        }

        assert(MemoryLayout<WarpParams>.stride == 64, "WarpParams must match the shader's layout")
    }

    public func render(_ image: CGImage, using transform: Affine2D) throws -> CGImage {
        let side = Int(spec.size.rounded())
        let plan = try WarpPlan.make(
            transform: transform,
            sourceWidth: image.width, sourceHeight: image.height,
            canvasSize: side
        )

        var output = LinearPixels.empty(width: side, height: side)
        guard !plan.isEmpty else {
            guard let empty = output.makeCGImage() else { throw RenderError.contextUnavailable }
            return empty
        }

        let limit = Self.maximumTextureSide
        let widest = max(plan.cropWidth, plan.cropHeight)
        guard widest <= limit else { throw RenderError.sourceTooLarge(side: widest, limit: limit) }

        guard let pixels = LinearPixels.decode(
            image, cropX: plan.cropX, cropY: plan.cropY,
            width: plan.cropWidth, height: plan.cropHeight
        ) else { throw RenderError.contextUnavailable }

        let sourceTexture = try makeTexture(width: plan.cropWidth, height: plan.cropHeight, writable: false)
        pixels.samples.withUnsafeBytes { raw in
            sourceTexture.replace(
                region: MTLRegionMake2D(0, 0, plan.cropWidth, plan.cropHeight),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: plan.cropWidth * 8
            )
        }

        let destinationTexture = try makeTexture(width: side, height: side, writable: true)

        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else { throw RenderError.contextUnavailable }

        var params = WarpParams(
            row0: SIMD4(Float(plan.inverse.a), Float(plan.inverse.c), Float(plan.inverse.tx), 0),
            row1: SIMD4(Float(plan.inverse.b), Float(plan.inverse.d), Float(plan.inverse.ty), 0),
            cropSize: SIMD2(Float(plan.cropWidth), Float(plan.cropHeight)),
            kernelScale: SIMD2(Float(plan.kernelScaleX), Float(plan.kernelScaleY)),
            support: SIMD2(Float(plan.supportX), Float(plan.supportY)),
            canvasSize: SIMD2(UInt32(side), UInt32(side))
        )

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(destinationTexture, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<WarpParams>.stride, index: 0)

        let groupWidth = pipeline.threadExecutionWidth
        let groupHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / groupWidth)
        let threadsPerGroup = MTLSize(width: groupWidth, height: groupHeight, depth: 1)
        let groups = MTLSize(
            width: (side + groupWidth - 1) / groupWidth,
            height: (side + groupHeight - 1) / groupHeight,
            depth: 1
        )
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw RenderError.pipelineCreationFailed("\(error)")
        }

        output.samples.withUnsafeMutableBytes { raw in
            destinationTexture.getBytes(
                raw.baseAddress!,
                bytesPerRow: side * 8,
                from: MTLRegionMake2D(0, 0, side, side),
                mipmapLevel: 0
            )
        }

        guard let result = output.makeCGImage() else { throw RenderError.contextUnavailable }
        return result
    }

    private func makeTexture(width: Int, height: Int, writable: Bool) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = writable ? [.shaderWrite, .shaderRead] : [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RenderError.textureAllocationFailed
        }
        return texture
    }
}
