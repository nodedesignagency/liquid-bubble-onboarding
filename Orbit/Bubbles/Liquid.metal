#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

/// The liquid behind the photos, evaluated per pixel (used through `.colorEffect` in `GooLayer`).
///
/// It is a Gaussian blur cut by a soft threshold, like the reference, only computed directly:
/// every photo is a disc and every thread between two photos a capsule, each with the wide, soft
/// shoulder a blur would give it (`softness`), summed into one field. Where two come close the
/// shoulders add up, so the iso-line between neighbours rounds off and they share one outline
/// with shallow scallops, and a bubble pulling away from its parent drags a neck of liquid with
/// it. The field is then cut at 0.5 over a short ramp (`edge`), which is the visible soft edge.
/// Inside, the colour is flat and pale.
///
/// `shapes` holds 9 floats per shape: kind (0 disc, 1 capsule), x1, y1, x2, y2, radius, r, g, b.
/// Positions and radii are in the view's points; a disc's radius is where its edge sits.
[[ stitchable ]] half4 liquid(float2 position, half4 color, float softness, float edge,
                              device const float *shapes, int count) {
    float field = 0.0;
    float3 tint = float3(0.0);
    const int n = count / 9;
    for (int i = 0; i < n; i++) {
        device const float *s = shapes + i * 9;
        const float2 a = float2(s[1], s[2]);
        float radius = s[5];
        float d;
        if (s[0] < 0.5) {
            d = distance(position, a);
        } else {
            const float2 ab = float2(s[3], s[4]) - a;
            const float t = clamp(dot(position - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
            d = distance(position, a + ab * t);
            // Thinnest in the middle, so a thread lets go there first.
            radius *= 0.75 + 0.25 * abs(2.0 * t - 1.0);
        }
        const float w = 1.0 / (1.0 + exp(clamp(1.702 * (d - radius) / softness, -30.0, 30.0)));
        field += w;
        tint += w * float3(s[6], s[7], s[8]);
    }
    if (field < 1e-4) {
        return half4(0.0);
    }
    const float alpha = smoothstep(0.5 - edge, 0.5 + edge, field);
    tint /= field;
    return half4(half3(tint * alpha), half(alpha));
}
