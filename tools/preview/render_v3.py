# Motion preview of the v3 onboarding (WorldOnboardingView), driven by the Swift engine's recorded
# bubbles. Mirrors FlatLiquidLayer and the `flatLiquid` shader, WorldPhoto's pop, the screen's copy
# and buttons, and the map's wipe and shrink into Earth.
# Keep the timings (V3_*) in sync with WorldOnboardingView and tools/engine/record.swift (v3 script).
#
# What it can't show: the MapKit zoom itself (a real 3D satellite city pulling back to the globe).
# It stands in for it with the Earth photo zooming out on black, labelled, so only the timing and
# the framing are meaningful there. The globe's size on screen is measured on the device; here it
# is assumed (GLOBE). Nunito stands in for SF Pro Rounded; Liquid Glass on Earth is approximated.
# iPhone 17 Pro sized (402 x 874 pt).
import csv, sys, os, math
from collections import defaultdict
import numpy as np
from PIL import Image, ImageDraw, ImageFont

frames_csv, assets, fonts, out_dir = sys.argv[1:5]
ONLY = [int(x) for x in os.environ.get("FRAMES", "").split(",") if x]
os.makedirs(out_dir, exist_ok=True)
S, W, H, FPS = 2, 402, 874, 30
CANVAS = np.array([1.0, 1.0, 1.0])                                   # Theme.worldCanvas
LIQUID = np.array([0xEE, 0xEE, 0xF1], float) / 255                   # Theme.worldLiquid
INK, INK2 = (0x1D, 0x1D, 0x1F), (0x86, 0x86, 0x8B)
SCALE = min(W / 372, H / 480, 1.3)                                   # the stage is the whole screen
BLEND, RIM = 38.0, 1.0                                               # FlatLiquidLayer
MARGIN = 0.26                                                        # OrbitChoreography.photoMargin
EARTH, GLOBE_R = (0.0, -125.0), 46.0                                 # bloomEarth.center, globeRadius
LIMB_CUT = 0.985                                                     # EarthZoom.limbCut
GLOBE = 150.0                                                        # assumed globe radius on screen after the zoom (measured on device)

# WorldOnboardingView's sequence (seconds from launch)
V3_FADE_IN, V3_ZOOM, V3_ZOOM_LEN = 0.6, 1.2, 4.2
V3_SPACE_TEXT, V3_WIPE, V3_SHRINK, V3_BLOOM = 4.4, 6.1, 6.3, 7.2
V3_TITLE, V3_SUBTITLE, V3_FOOTER = 7.7, 8.0, 8.8
V3_CONTINUE = 15.0
V3_UNSHRINK = V3_CONTINUE + 1.2
V3_BACK = V3_UNSHRINK + 0.9

def pt(x, y): return (W / 2 + x * SCALE, H / 2 + y * SCALE)

def spring(response, damping, t):
    """SpringCurve.progress (and SwiftUI's spring(response:dampingFraction:); .smooth is damping 1)."""
    if t <= 0: return 0.0
    w = 2 * math.pi / response
    if damping < 1:
        wd = w * math.sqrt(1 - damping * damping); env = math.exp(-damping * w * t)
        return 1 - env * (math.cos(wd * t) + damping * w / wd * math.sin(wd * t))
    return 1 - math.exp(-w * t) * (1 + w * t)

def ease(x): x = min(max(x, 0), 1); return x * x * (3 - 2 * x)
def fade(t, start, duration): return ease((t - start) / duration)

f = lambda w, s: ImageFont.truetype(os.path.join(fonts, f"nunito-{w}.ttf"), int(s * S))
head_font, button_font, legal_font, note_font = f(700, 27), f(700, 17), f(400, 12), f(600, 13)

# ---- photos ----
def load(path, n=360):
    return Image.open(path).convert("RGB").resize((n, n), Image.LANCZOS)
photos = {i: load(os.path.join(assets, f"friend-{i}.imageset/friend-{i}.jpg")) for i in range(1, 10)}
for k in range(5):
    photos[16 + k] = load(os.path.join(assets, f"place-{k + 1}.imageset/place-{k + 1}.jpg"))
earth_img = load(os.path.join(assets, "earth.imageset/earth.jpg"), 600)

def has_photo(i): return 1 <= i <= 9 or 16 <= i <= 20
def liquid_radius(i, r): return r * (1 + MARGIN) if has_photo(i) else r
def photo_radius(r, full):
    """WorldPhoto.radius(for:)"""
    if full <= 0.5: return 0.0
    return full * min(max((r / full - 0.3) / 0.7, 0), 1.12)

def disc(src, diameter_px):
    d = max(2, int(round(diameter_px)))
    img = src.resize((d, d), Image.BILINEAR)
    big = Image.new("L", (d * 4, d * 4), 0); ImageDraw.Draw(big).ellipse((0, 0, d * 4 - 1, d * 4 - 1), fill=255)
    return img, big.resize((d, d), Image.LANCZOS)

# ---- the flatLiquid shader ----
def flat_liquid(circles, px, py):
    """Returns premultiplied rgb and alpha, like the shader."""
    d = np.full(px.shape, 1e20)
    for (x, y, r) in circles:
        di = np.hypot(px - x, py - y) - r
        h = np.clip(0.5 + 0.5 * (di - d) / (BLEND * SCALE), 0, 1)
        d = di * (1 - h) + d * h - BLEND * SCALE * h * (1 - h)
    alpha = np.clip(0.5 - d / 0.6, 0, 1)
    inner = np.maximum(-d, 0)
    c = LIQUID[None, None, :] * (1 - RIM * 0.06 * np.exp(-inner / 1.6))[..., None]
    return c * alpha[..., None], alpha

# ---- the map: wipe, shrink, and a stand-in for the zoom ----
def map_state(t):
    """Opacity, the globe's radius and centre on screen, and the cut-out circle's radius (None: no cut)."""
    cx, cy = W / 2, H / 2
    ox, oy = pt(*EARTH)
    orb = GLOBE_R * SCALE
    opacity = fade(t, 0, V3_FADE_IN)
    if t < V3_ZOOM + V3_ZOOM_LEN:
        # stand-in: the globe grows from far beyond the screen to GLOBE, even in log space
        u = ease((t - V3_ZOOM) / V3_ZOOM_LEN)
        radius = 20000 * (GLOBE / 20000) ** u
        return opacity, radius, (cx, cy), None, "zoom"
    if t < V3_CONTINUE:
        wipe_p = spring(0.7, 1.0, t - V3_WIPE)
        cut = 900 + (GLOBE * LIMB_CUT - 900) * wipe_p if t >= V3_WIPE else None
        s = spring(0.85, 0.86, t - V3_SHRINK)
        k = 1 + (orb / (GLOBE * LIMB_CUT) - 1) * s
        centre = (cx + (ox - cx) * s, cy + (oy - cy) * s)
        return opacity, GLOBE * k, centre, (cut * k if cut is not None else None), "space"
    # Continue: grow back into space, uncut, then dive back in
    s = 1 - spring(0.8, 1.0, t - V3_UNSHRINK)
    k = 1 + (orb / (GLOBE * LIMB_CUT) - 1) * s
    centre = (cx + (ox - cx) * s, cy + (oy - cy) * s)
    unwipe = spring(0.7, 1.0, t - V3_UNSHRINK - 0.35)
    cut = GLOBE * LIMB_CUT + (900 - GLOBE * LIMB_CUT) * unwipe
    if t >= V3_BACK:
        u = ease((t - V3_BACK) / V3_ZOOM_LEN)
        radius = GLOBE * (20000 / GLOBE) ** u
        return 1.0, radius, (cx, cy), None, "zoom"
    return 1.0, GLOBE * k, centre, cut * k, "space"

def draw_map(img, t):
    opacity, radius, (gx, gy), cut, kind = map_state(t)
    if opacity <= 0: return
    layer = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 255))
    d = radius * 2 * S
    if d < 6000:
        e, m = disc(earth_img, d)
        layer.paste(e, (int(round(gx * S - d / 2)), int(round(gy * S - d / 2))), m)
    else:
        # deep in the zoom: a crop of the photo's middle, enlarged
        frac = 6000 / d
        n = earth_img.width; c0 = n * (1 - frac) / 2
        crop = earth_img.crop((int(c0), int(c0), int(n - c0), int(n - c0))).resize((W * S, W * S), Image.BILINEAR)
        layer.paste(crop, (0, (H * S - W * S) // 2))
    if cut is not None:
        mask = Image.new("L", (W * S * 4 // 2, H * S * 4 // 2), 0)
        q = 2
        ImageDraw.Draw(mask).ellipse(((gx - cut) * S * q, (gy - cut) * S * q, (gx + cut) * S * q, (gy + cut) * S * q), fill=255)
        mask = mask.resize((W * S, H * S), Image.LANCZOS)
    else:
        mask = Image.new("L", (W * S, H * S), 255)
    if opacity < 1:
        mask = Image.fromarray((np.asarray(mask, float) * opacity).astype("uint8"))
    img.paste(layer.convert("RGB"), (0, 0), mask)
    if kind == "zoom" and t < V3_ZOOM + V3_ZOOM_LEN * 0.55 or (t > V3_BACK + V3_ZOOM_LEN * 0.45):
        dr = ImageDraw.Draw(img)
        note = "stand-in for MapKit: 3D Paris pulling back to the globe"
        tw = dr.textlength(note, font=note_font)
        dr.rounded_rectangle(((W * S - tw) / 2 - 12 * S, 70 * S, (W * S + tw) / 2 + 12 * S, 96 * S), radius=13 * S, fill=(0, 0, 0))
        dr.text(((W * S - tw) / 2, 75 * S), note, font=note_font, fill=(255, 255, 255))

def draw_glass(img, t):
    a = fade(t, V3_BLOOM, 0.4) * (1 - fade(t, V3_UNSHRINK, 0.25))
    if a <= 0: return
    ox, oy = pt(*EARTH); r = GLOBE_R * SCALE
    over = Image.new("RGBA", img.size, (0, 0, 0, 0)); dr = ImageDraw.Draw(over)
    # the iOS 17-25 fallback: a soft highlight top left and a bright rim (iOS 26 draws Liquid Glass)
    for k in range(12, 0, -1):
        rr = r * 0.42 * k / 12
        dr.ellipse(((ox - r * 0.36 - rr) * S, (oy - r * 0.52 - rr) * S, (ox - r * 0.36 + rr) * S, (oy - r * 0.52 + rr) * S),
                   fill=(255, 255, 255, int(255 * 0.32 * a * (1 - k / 12) ** 1.5 / 1.0)))
    dr.ellipse(((ox - r) * S, (oy - r) * S, (ox + r) * S, (oy + r) * S), outline=(255, 255, 255, int(150 * a)), width=max(1, int(1.2 * S)))
    img.alpha_composite(over) if img.mode == "RGBA" else img.paste(over, (0, 0), over)

def put_text(img, x, y, line, font, color, alpha):
    """Text at `alpha`, through a mask: Pillow's RGBA drawing ignores a fill's alpha for text."""
    if alpha <= 0.002: return
    probe = ImageDraw.Draw(img)
    x0, y0, x1, y1 = [int(v) for v in probe.textbbox((x, y), line, font=font)]
    x0 -= 2; y0 -= 2; x1 += 2; y1 += 2
    mask = Image.new("L", (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(mask).text((x - x0, y - y0), line, font=font, fill=int(255 * min(alpha, 1)))
    img.paste(Image.new("RGB", mask.size, color[:3]), (x0, y0), mask)

def chrome(img, t):
    d = ImageDraw.Draw(img, "RGBA")
    # space text, white over the sky
    a = fade(t, V3_SPACE_TEXT, 0.7) * (1 - fade(t, V3_WIPE, 0.3))
    for j, line in enumerate(["Everyone you love,", "in one orbit."]):
        tw = d.textlength(line, font=head_font)
        put_text(img, (W * S - tw) / 2, (H * 0.17 - 34 + j * 34) * S, line, head_font, (255, 255, 255), a)
    gone = 1 - fade(t, V3_CONTINUE, 0.4)
    title_top = H / 2 + (EARTH[1] + 205) * SCALE
    lines = [("Meet Orbit.", INK, fade(t, V3_TITLE, 0.6)), ("Your friends, always", INK2, fade(t, V3_SUBTITLE, 0.6)),
             ("within reach.", INK2, fade(t, V3_SUBTITLE, 0.6))]
    for j, (line, col, op) in enumerate(lines):
        tw = d.textlength(line, font=head_font)
        put_text(img, (W * S - tw) / 2, (title_top + j * 34) * S, line, head_font, col, op * gone)
    fa = fade(t, V3_FOOTER, 0.6) * gone
    if fa > 0:
        dy = 16 * (1 - fa); al = int(255 * fa)
        for j, (label, bg, fg) in enumerate([("Continue with Apple", INK, (255, 255, 255)),
                                             ("Continue with phone number", (0xEE, 0xEE, 0xF1), INK)]):
            y0 = 874 - 34 - 8 - 18 - 6 - 12 - 54 - (66 * (1 - j)) + dy
            d.rounded_rectangle((24 * S, y0 * S, (W - 24) * S, (y0 + 54) * S), radius=27 * S, fill=bg + (al,))
            tw = d.textlength(label, font=button_font)
            put_text(img, (W * S - tw) / 2, (y0 + 16) * S, label, button_font, fg, fa)
        legal = "By continuing, you agree to our Terms and Privacy Policy."
        tw = d.textlength(legal, font=legal_font)
        put_text(img, (W * S - tw) / 2, (874 - 34 - 8 - 16 + dy) * S, legal, legal_font, INK2, fa)
    return img

# ---- frames ----
rows = defaultdict(list)
with open(frames_csv) as fh:
    for r in csv.DictReader(fh):
        rows[int(r["frame"])].append((int(r["id"]), float(r["x"]), float(r["y"]), float(r["r"]), float(r["depth"]),
                                      r["leaving"] == "1", float(r["full"])))

gy_, gx_ = np.mgrid[0:H * S, 0:W * S].astype(float)
PX, PY = (gx_ + 0.5) / S, (gy_ + 0.5) / S

for fi in sorted(rows):
    if ONLY and fi not in ONLY: continue
    t = fi / FPS
    vis = [b for b in rows[fi] if b[3] > 0.5]
    rgb = np.ones((H * S, W * S, 3)) * CANVAS
    if vis:
        circles = [(*pt(x, y), liquid_radius(i, r) * SCALE) for i, x, y, r, _, _, _ in vis]
        pad = BLEND * SCALE
        x0 = max(int((min(c[0] - c[2] for c in circles) - pad) * S), 0); x1 = min(int((max(c[0] + c[2] for c in circles) + pad) * S), W * S)
        y0 = max(int((min(c[1] - c[2] for c in circles) - pad) * S), 0); y1 = min(int((max(c[1] + c[2] for c in circles) + pad) * S), H * S)
        if x1 > x0 and y1 > y0:
            col, al = flat_liquid(circles, PX[y0:y1, x0:x1], PY[y0:y1, x0:x1])
            rgb[y0:y1, x0:x1] = col + rgb[y0:y1, x0:x1] * (1 - al[..., None])
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype("uint8"))
    # photos: bigger on top, leaving ones underneath
    for i, x, y, r, dep, leaving, full in sorted(vis, key=lambda b: (not b[5], b[4])):
        if not has_photo(i): continue
        pr = photo_radius(r, full) * SCALE
        if pr < 0.25: continue
        cx, cy = pt(x, y)
        p, m = disc(photos[i], pr * 2 * S)
        img.paste(p, (int(round(cx * S - p.width / 2)), int(round(cy * S - p.height / 2))), m)
    draw_map(img, t)
    img = img.convert("RGBA")
    draw_glass(img, t)
    # Text is blended onto an RGB image: drawn into RGBA, a see-through fill replaces the pixels.
    chrome(img.convert("RGB"), t).save(f"{out_dir}/f_{fi:04d}.png")
print("done")
