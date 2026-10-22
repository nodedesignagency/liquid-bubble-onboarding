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

/// Turns a square photo into a glass orb (used through `.layerEffect` in `BubbleStage`).
///
/// The photo sits a little behind a glass sphere: each pixel looks through the sphere's front
/// surface, refracts, and lands on the photo, so the middle is gently magnified and the picture
/// bends round toward the rim. The rim splits colour a touch and reflects the pale surroundings,
/// and the light is a soft window reflection along the top rim, a small glint at the top left
/// and the bright crescent where light focuses through the ball at the bottom. No shadows.
/// Outside the circle it is clear, with an antialiased edge.
///
/// `bounds` is the view's rect (`.boundingRect`); `depth` is how far behind the glass the photo
/// sits (more is a stronger lens). Mirrored in `tools/preview/render.py` (`orb`).
[[ stitchable ]] half4 glassOrb(float2 position, SwiftUI::Layer layer, float4 bounds, float depth) {
    const float2 size = bounds.zw;
    const float radius = 0.5 * min(size.x, size.y);
    if (radius < 1.0) {
        return half4(0.0h);
    }
    const float2 centre = bounds.xy + 0.5 * size;
    const float2 p = (position - centre) / radius;   // -1...1 across the orb, y down
    const float rho2 = dot(p, p);
    const float rho = sqrt(rho2);
    const float alpha = 1.0 - smoothstep(1.0 - 0.6 / radius, 1.0, rho);
    if (alpha <= 0.0) {
        return half4(0.0h);
    }

    // Refraction through the front of the sphere (normal (p, z), view ray (0, 0, -1)).
    const float z = sqrt(max(1.0 - rho2, 0.0));
    const float eta = 1.0 / 1.45;
    const float cost = sqrt(max(1.0 - eta * eta * (1.0 - z * z), 0.0));
    const float f = eta * z - cost;
    const float rz = -eta + f * z;
    const float t = (z + depth) / max(-rz, 0.2);
    const float2 uv = p * (1.0 + f * t);

    // A touch of colour fringing toward the rim.
    const float edge = 1.0 - z;
    const float ca = 0.012 * edge * edge;
    float3 c = float3(float(layer.sample(centre + uv * (1.0 + ca) * radius).r),
                      float(layer.sample(centre + uv * radius).g),
                      float(layer.sample(centre + uv * (1.0 - ca) * radius).b));

    // Fresnel: the rim reflects the pale surroundings.
    c = mix(c, float3(0.97, 0.94, 1.0), 0.45 * edge * edge * edge);

    // Light.
    const float along = p.y / max(rho, 1e-4);          // -1 at the top of the rim, 1 at the bottom
    const float top = 1.0 - smoothstep(-0.85, 0.15, along);
    const float sheen = 0.42 * smoothstep(0.62, 0.9, rho) * (1.0 - smoothstep(0.9, 0.99, rho)) * top;
    const float2 g = p - float2(-0.42, -0.62);
    const float glint = 0.75 * exp(-(g.x * g.x / 0.012 + g.y * g.y / 0.004));
    const float bottom = smoothstep(0.35, 0.95, along);
    const float caustic = 0.42 * smoothstep(0.74, 0.9, rho) * (1.0 - smoothstep(0.9, 0.975, rho)) * bottom;
    const float light = clamp(sheen + glint + caustic, 0.0, 1.0);
    c = c + (1.0 - c) * light;

    return half4(half3(c * alpha), half(alpha));
}

/// v2: the glass orbs are the liquid themselves (used through `.layerEffect` in `GlassLiquidLayer`).
///
/// The layer holds every photo, drawn flat where its orb is. This shader turns them into glass:
///
/// 1. Each orb has a height `b = (r^2 - d^2) / r`, about twice the distance inside its edge near
///    the rim. The orbs are joined with a smooth maximum of those heights (`blend`, in points), so
///    a lone orb keeps its exact circle, and two orbs closer than about 0.7 x `blend` melt into one
///    shape with a smooth neck, then pinch apart again.
/// 2. The surface: a lone orb is an exact sphere (height `sqrt(r^2 - d^2)`); where orbs melt
///    together it flows smoothly between them. Its normal drives everything below.
/// 3. A fisheye lens (`lens`): the middle of each photo is magnified and its edge compressed, so
///    the picture bulges like a glass marble and reaches the glass's edge.
/// 4. Light, never shadow: a little colour fringing and a pale reflection toward the rim, a sheen
///    along the top rim, a small sharp glint, and the bright crescent along the bottom where
///    light focuses through the glass.
/// 5. Outside, a soft glow in each orb's own colours (`glowWidth`, `glowStrength`), always light.
///
/// `orbs` holds 6 floats per orb: x, y, r (in the view's points) and the glow colour r, g, b.
/// Mirrored in `tools/preview/render.py` (`glass_liquid`).
[[ stitchable ]] half4 glassLiquid(float2 position, SwiftUI::Layer layer, float blend, float lens,
                                   float glowWidth, float glowStrength,
                                   device const float *orbs, int count) {
    const int n = count / 6;
    if (n == 0) {
        return half4(0.0h);
    }
    float m = -1e20;
    for (int i = 0; i < n; i++) {
        device const float *o = orbs + i * 6;
        const float2 d = position - float2(o[0], o[1]);
        const float r = max(o[2], 0.5);
        m = max(m, (r * r - dot(d, d)) / r);
    }
    // Far outside everything: nothing to draw, not even glow.
    if (m < -12.0 * glowWidth) {
        return half4(0.0h);
    }
    float sum = 0.0;
    float radius = 0.0;
    float2 g = float2(0.0);
    float3 glow = float3(0.0);
    for (int i = 0; i < n; i++) {
        device const float *o = orbs + i * 6;
        const float2 d = position - float2(o[0], o[1]);
        const float r = max(o[2], 0.5);
        const float w = exp(((r * r - dot(d, d)) / r - m) / blend);
        sum += w;
        radius += w * r;
        g += w * d / r;
        glow += w * float3(o[3], o[4], o[5]);
    }
    radius /= sum;
    g /= sum;
    glow /= sum;
    const float b = m + blend * log(sum);
    // Distance to the outline in points, positive inside.
    const float sd = b / max(2.0 * length(g), 1e-3);
    const float alpha = smoothstep(-0.75, 0.75, sd);
    const float halo = glowStrength * exp(-max(-sd, 0.0) / glowWidth);
    if (alpha <= 0.0) {
        return half4(half3(glow * halo), half(halo));
    }

    const float h = sqrt(max(radius * b, 0.0));
    const float3 nrm = normalize(float3(radius * g, h + 1e-3));
    const float edge = 1.0 - nrm.z;                       // 0 facing you, 1 at the rim
    const float2 offset = -lens * h * nrm.xy;

    const half4 sg = layer.sample(position + offset);
    const half4 sr = layer.sample(position + offset * (1.0 + 0.12 * edge));
    const half4 sb = layer.sample(position + offset * (1.0 - 0.12 * edge));
    // The layer is premultiplied; anywhere it is see-through, the glass shows its own pale interior.
    const float3 interior = float3(0.95, 0.95, 0.97);
    float3 c = float3(float(sr.r), float(sg.g), float(sb.b)) + (1.0 - float(sg.a)) * interior;

    c = mix(c, float3(0.97, 0.96, 1.0), 0.28 * edge * edge * edge);
    const float2 dir = nrm.xy / max(length(nrm.xy), 1e-4);
    const float3 halfway = normalize(normalize(float3(0.55, -0.75, 0.55)) + float3(0.0, 0.0, 1.0));
    const float glint = 0.85 * pow(max(dot(nrm, halfway), 0.0), 120.0);
    const float top = 1.0 - smoothstep(-0.85, 0.1, dir.y);
    const float sheen = 0.30 * smoothstep(0.30, 0.65, edge) * (1.0 - smoothstep(0.65, 0.95, edge)) * top;
    const float bottom = smoothstep(0.25, 0.95, dir.y);
    const float caustic = 0.55 * smoothstep(0.42, 0.75, edge) * (1.0 - smoothstep(0.80, 0.98, edge)) * bottom;
    c = c + (1.0 - c) * clamp(glint + sheen + caustic, 0.0, 1.0);

    const float3 premultiplied = c * alpha + glow * halo * (1.0 - alpha);
    return half4(half3(premultiplied), half(alpha + halo * (1.0 - alpha)));
}
