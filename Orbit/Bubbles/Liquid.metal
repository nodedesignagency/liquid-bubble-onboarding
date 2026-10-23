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
/// The layer holds every photo, drawn flat where its orb is (a little inside the orb's edge, so
/// each orb has a thin rim of clear glass), and the screen's headline. This shader turns it into
/// glass:
///
/// 1. Each orb has a height `b = (r^2 - d^2) / r`, about twice the distance inside its edge near
///    the rim. The orbs are joined with a smooth maximum of those heights (`blend`, in points), so
///    a lone orb keeps its exact circle, and two orbs closer than about 0.7 x `blend` melt into one
///    shape with a neck of clear glass, then pinch apart again.
/// 2. The surface: a lone orb is an exact sphere; where orbs melt together it flows smoothly
///    between them. Its normal drives everything below.
/// 3. A fisheye lens (`lens`): the middle of each orb is magnified and its edge compressed, so
///    photos bulge like glass marbles, and text behind the glass bends.
/// 4. Light, never shadow: colour fringing and an iridescent sheen toward the rim, a fine light
///    grey edge so clear glass reads on the canvas, a soft broad highlight and a sharp glint at
///    the top left, and the bright crescent along the bottom where light focuses through.
/// 5. Outside the glass the layer shows as it is (the headline), over a soft glow in each orb's
///    own colours (`glowWidth`, `glowStrength`).
/// 6. Moving orbs stretch along their motion like drops (keeping their area), so a fast one
///    becomes a teardrop of glass and rounds off as it settles.
///
/// `orbs` holds 8 floats per orb: x, y, r (in the view's points), the glow colour r, g, b, and the
/// stretch (sx, sy): the direction of motion, with length = how much longer the orb gets (0 = round).
/// `interior` is the canvas colour, seen through clear glass. Mirrored in
/// `tools/preview/render_v2.py` (`glass_liquid`, `orb_height`).
/// One orb's height (see above) at `d` from its centre, and the direction it grows in (the
/// gradient's half, divided by r), in the metric stretched along `stretch`.
static float orbHeight(float2 d, float r, float2 stretch, thread float2 &toward) {
    const float k = length(stretch);
    if (k < 1e-4) {
        toward = d / r;
        return (r * r - dot(d, d)) / r;
    }
    const float2 u = stretch / k;
    const float s = 1.0 + k;
    const float along = dot(d, u);
    const float2 across = d - along * u;
    const float q = along * along / (s * s) + dot(across, across) * s;
    toward = (along / (s * s) * u + across * s) / r;
    return (r * r - q) / r;
}

[[ stitchable ]] half4 glassLiquid(float2 position, SwiftUI::Layer layer, float blend, float lens,
                                   float glowWidth, float glowStrength, float3 interior,
                                   device const float *orbs, int count) {
    const half4 flat = layer.sample(position);
    const int n = count / 8;
    if (n == 0) {
        return flat;
    }
    float m = -1e20;
    for (int i = 0; i < n; i++) {
        device const float *o = orbs + i * 8;
        float2 toward;
        m = max(m, orbHeight(position - float2(o[0], o[1]), max(o[2], 0.5), float2(o[6], o[7]), toward));
    }
    // Far outside everything: just the layer, no glow.
    if (m < -12.0 * glowWidth) {
        return flat;
    }
    float sum = 0.0;
    float radius = 0.0;
    float2 g = float2(0.0);
    float3 glow = float3(0.0);
    for (int i = 0; i < n; i++) {
        device const float *o = orbs + i * 8;
        const float r = max(o[2], 0.5);
        float2 toward;
        const float w = exp((orbHeight(position - float2(o[0], o[1]), r, float2(o[6], o[7]), toward) - m) / blend);
        sum += w;
        radius += w * r;
        g += w * toward;
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
    const float4 outside = float4(flat) + float4(glow * halo, halo) * (1.0 - float(flat.a));
    if (alpha <= 0.0) {
        return half4(outside);
    }

    const float h = sqrt(max(radius * b, 0.0));
    const float3 nrm = normalize(float3(radius * g, h + 1e-3));
    const float edge = 1.0 - nrm.z;                       // 0 facing you, 1 at the rim
    const float2 offset = -lens * h * nrm.xy;

    const half4 sg = layer.sample(position + offset);
    const half4 sr = layer.sample(position + offset * (1.0 + 0.14 * edge));
    const half4 sb = layer.sample(position + offset * (1.0 - 0.14 * edge));
    // The layer is premultiplied; where it is see-through, the glass shows the canvas.
    float3 c = float3(float(sr.r), float(sg.g), float(sb.b)) + (1.0 - float(sg.a)) * interior;

    const float2 dir = nrm.xy / max(length(nrm.xy), 1e-4);
    // Iridescence toward the rim, its hue turning around the orb.
    const float turn = atan2(dir.y, dir.x) / 6.2831853 + edge * 0.6;
    const float3 rainbow = 0.5 + 0.5 * cos(6.2831853 * (turn + float3(0.0, 0.33, 0.67)));
    const float band = smoothstep(0.45, 0.8, edge) * (1.0 - smoothstep(0.9, 1.0, edge));
    c = mix(c, mix(float3(1.0), rainbow, 0.55), 0.22 * band);
    // A pale reflection at the rim, and a fine light grey edge so clear glass reads on the canvas.
    c = mix(c, float3(0.97, 0.97, 0.99), 0.22 * edge * edge * edge);
    c = mix(c, interior * float3(0.86, 0.87, 0.9), 0.35 * smoothstep(0.9, 1.0, edge));

    const float3 light = normalize(float3(-0.45, -0.7, 0.55));
    const float3 halfway = normalize(light + float3(0.0, 0.0, 1.0));
    const float broad = 0.16 * pow(max(dot(nrm, light), 0.0), 6.0) * smoothstep(0.05, 0.4, edge);
    const float glint = 0.9 * pow(max(dot(nrm, halfway), 0.0), 140.0);
    const float bottom = smoothstep(0.25, 0.95, dir.y);
    const float caustic = 0.55 * smoothstep(0.42, 0.75, edge) * (1.0 - smoothstep(0.82, 0.98, edge)) * bottom;
    c = c + (1.0 - c) * clamp(broad + glint + caustic, 0.0, 1.0);

    const float4 inside = float4(c, 1.0);
    return half4(mix(outside, inside, alpha));
}
