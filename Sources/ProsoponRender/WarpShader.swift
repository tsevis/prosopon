import Foundation

/// The Metal source for the resampling kernel.
///
/// Compiled at runtime rather than built into a `.metallib`, because SwiftPM does not
/// compile `.metal` files outside an Xcode project. It costs about a tenth of a second
/// once per process, against a batch that runs for a minute.
///
/// This must stay in step with `Warp.resample`, which the tests compare it against
/// tap for tap.
enum WarpShader {
    static let functionName = "warpLanczos3"

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct WarpParams {
        float4 row0;          // a, c, tx  -- source x = a*dx + c*dy + tx
        float4 row1;          // b, d, ty
        float2 cropSize;
        float2 kernelScale;   // below 1 when reducing, which widens the footprint
        float2 support;       // footprint half-width, in source pixels
        uint2  canvasSize;
    };

    inline float sinc(float x) {
        if (fabs(x) < 1e-9f) { return 1.0f; }
        float t = M_PI_F * x;
        return sin(t) / t;
    }

    inline float lanczos3(float x) {
        if (fabs(x) >= 3.0f) { return 0.0f; }
        return sinc(x) * sinc(x / 3.0f);
    }

    kernel void warpLanczos3(
        texture2d<float, access::read>  source      [[texture(0)]],
        texture2d<float, access::write> destination [[texture(1)]],
        constant WarpParams&            params      [[buffer(0)]],
        uint2                           gid         [[thread_position_in_grid]])
    {
        if (gid.x >= params.canvasSize.x || gid.y >= params.canvasSize.y) { return; }

        float2 dest = float2(gid) + 0.5f;
        float2 point = float2(
            params.row0.x * dest.x + params.row0.y * dest.y + params.row0.z,
            params.row1.x * dest.x + params.row1.y * dest.y + params.row1.z
        );

        // A centre outside the photograph gets nothing, rather than an edge colour
        // smeared into space that was never photographed.
        if (point.x < 0.0f || point.y < 0.0f ||
            point.x >= params.cropSize.x || point.y >= params.cropSize.y) {
            destination.write(float4(0.0f), gid);
            return;
        }

        int lastX = int(floor(point.x + params.support.x - 0.5f));
        int firstX = int(floor(point.x - params.support.x - 0.5f)) + 1;
        int lastY = int(floor(point.y + params.support.y - 0.5f));
        int firstY = int(floor(point.y - params.support.y - 0.5f)) + 1;

        int maxX = int(params.cropSize.x) - 1;
        int maxY = int(params.cropSize.y) - 1;

        float4 total = float4(0.0f);
        float weightSum = 0.0f;

        for (int y = firstY; y <= lastY; ++y) {
            float wy = lanczos3((float(y) + 0.5f - point.y) * params.kernelScale.y);
            if (wy == 0.0f) { continue; }
            uint sy = uint(clamp(y, 0, maxY));
            for (int x = firstX; x <= lastX; ++x) {
                float wx = lanczos3((float(x) + 0.5f - point.x) * params.kernelScale.x);
                if (wx == 0.0f) { continue; }
                uint sx = uint(clamp(x, 0, maxX));
                float w = wx * wy;
                total += w * source.read(uint2(sx, sy));
                weightSum += w;
            }
        }

        if (weightSum <= 0.0f) {
            destination.write(float4(0.0f), gid);
            return;
        }

        // Renormalising absorbs the clamped taps at the source edge, so the border
        // neither darkens nor brightens.
        float4 value = total / weightSum;
        // Lanczos overshoots at edges; premultiplied data stays valid only while every
        // colour channel remains within alpha.
        float alpha = clamp(value.a, 0.0f, 1.0f);
        float3 rgb = clamp(value.rgb, 0.0f, alpha);
        destination.write(float4(rgb, alpha), gid);
    }
    """
}
