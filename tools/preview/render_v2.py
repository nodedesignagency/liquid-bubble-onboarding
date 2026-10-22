# Motion preview of the v2 onboarding (GlassOnboardingView), driven by the Swift engine's recorded
# bubbles. Mirrors GlassLiquidLayer and the `glassLiquid` shader line for line, GlassPhoto, the
# swipe (EarthLift, replayed from a scripted drag), and the screen's copy, hint and buttons.
# Keep the timings in sync with tools/engine/record.swift (v2 script) and GlassOnboardingView.
# Nunito stands in for SF Pro Rounded; the glass buttons are approximated (iOS draws real Liquid
# Glass). iPhone 17 Pro sized (402 x 874 pt).
import csv, sys, os, math, colorsys
from collections import defaultdict
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

frames_csv, assets, fonts, out_dir = sys.argv[1:5]
ONLY = [int(x) for x in os.environ.get("FRAMES", "").split(",") if x]
os.makedirs(out_dir, exist_ok=True)
S, W, H, FPS = 2, 402, 874, 30
CANVAS = np.array([0xED, 0xED, 0xEF], float) / 255           # Theme.glassCanvas
INK, INK2 = (0x1D, 0x1D, 0x1F), (0x86, 0x86, 0x8B)
SCALE = min(W / 372, H / 480, 1.3)                              # the stage is the whole screen
BLEND, LENS, GLOW_W, GLOW_S = 12.0, 0.5, 5.0, 0.4              # GlassLiquidLayer
FILL, FEATHER = 0.95, 0.86                                      # GlassPhoto
MAX_STRETCH, HALF_SPEED = 0.42, 800.0                           # GlassLiquidLayer.maxStretch, halfStretchSpeed
REVEAL, LEAVE = 2.2, 10.0                                       # record.swift's v2 script
DRAG_START = 0.9

def pt(x, y): return (W / 2 + x * SCALE, H / 2 + y * SCALE)

def spring(response, damping, t):
    """SpringCurve.progress."""
    if t <= 0: return 0.0
    w = 2 * math.pi / response
    if damping < 1:
        wd = w * math.sqrt(1 - damping * damping); env = math.exp(-damping * w * t)
        return 1 - env * (math.cos(wd * t) + damping * w / wd * math.sin(wd * t))
    return 1 - math.exp(-w * t) * (1 + w * t)

def ease(x): x = min(max(x, 0), 1); return x * x * (3 - 2 * x)

def lift(t):
    """EarthLift for a scripted drag: the finger goes up 230pt from DRAG_START and lets go at REVEAL."""
    def held(t):
        u = 230 * ease((t - DRAG_START) / (REVEAL - DRAG_START))
        return -280 * (1 - math.exp(-u / 280))
    if t < DRAG_START: return 0.0
    if t < REVEAL: return held(t)
    return held(REVEAL) * (1 - spring(0.6, 0.72, t - REVEAL))

def fade(t, start, duration):
    return ease((t - start) / duration)

def copy_state(t):
    gate = 1 - fade(t, REVEAL + 0.15, 0.35) if t < LEAVE else fade(t, LEAVE + 1.0, 0.6)
    title = fade(t, REVEAL + 0.55, 0.6) * (1 - fade(t, LEAVE, 0.4))
    subtitle = fade(t, REVEAL + 0.85, 0.6) * (1 - fade(t, LEAVE, 0.4))
    footer = fade(t, REVEAL + 1.6, 0.6) * (1 - fade(t, LEAVE, 0.4))
    hint = 1.0 if t < REVEAL else 0.0
    return gate, title, subtitle, footer, hint

f = lambda w, s: ImageFont.truetype(os.path.join(fonts, f"nunito-{w}.ttf"), int(s * S))
head_font, small_font, button_font, legal_font = f(700, 27), f(600, 13), f(700, 17), f(400, 12)

# ---- GlassPhoto ----
FACE = 360
def glass_photo(path, is_earth):
    n = FACE
    src = Image.open(path).convert("RGB")
    yy, xx = (np.mgrid[0:n, 0:n] + 0.5) / n - 0.5; rho = np.hypot(xx, yy) * 2
    if is_earth:
        g = int(round(n * FILL * 1.024)); off = (n - g) // 2
        canvas = np.zeros((n, n, 3)); globe = np.asarray(src.resize((g, g), Image.LANCZOS), float)
        canvas[off:off + g, off:off + g] = globe
    else:
        d = int(round(n * FILL)); off = (n - d) // 2
        canvas = np.zeros((n, n, 3)); canvas[off:off + d, off:off + d] = np.asarray(src.resize((d, d), Image.LANCZOS), float)
    alpha = np.clip((FILL - rho) * n / 2 + 0.5, 0, 1) * np.clip((FILL - rho) / (FILL - FEATHER), 0, 1)
    small = np.asarray(Image.fromarray(canvas.astype("uint8")).resize((32, 32), Image.BILINEAR), float) / 255
    sy, sx = (np.mgrid[0:32, 0:32] + 0.5) / 32 - 0.5; srho = np.hypot(sx, sy) * 2
    ring = small[(srho > 0.6) & (srho < 0.93)]
    w = (ring.max(axis=1) - ring.min(axis=1)) ** 2 + 1e-4
    c = (ring * w[:, None]).sum(axis=0) / w.sum()
    h, s_, v = colorsys.rgb_to_hsv(*c)
    glow = np.array(colorsys.hsv_to_rgb(h, 0.38, 1.0)) if s_ > 0.06 else np.array([0.86, 0.84, 0.98])
    return np.dstack([canvas / 255 * alpha[..., None], alpha]), glow

photos = {}
for i in range(0, 10):
    path = os.path.join(assets, "earth.imageset/earth.jpg" if i == 0 else f"friend-{i}.imageset/friend-{i}.jpg")
    photos[i] = glass_photo(path, i == 0)
DROPLET_GLOW = np.array([0.97, 0.97, 1.0])

# ---- the glassLiquid shader ----
def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)

MARGIN = 120   # points around the screen the layer also holds, like SwiftUI's maxSampleOffset margin

def sample(layer, x, y):
    h, w, _ = layer.shape
    u = np.clip((x + MARGIN) * S - 0.5, 0, w - 1.001); v = np.clip((y + MARGIN) * S - 0.5, 0, h - 1.001)
    x0 = u.astype(int); y0 = v.astype(int); fx = (u - x0)[..., None]; fy = (v - y0)[..., None]
    return (layer[y0, x0] * (1 - fx) * (1 - fy) + layer[y0, x0 + 1] * fx * (1 - fy)
            + layer[y0 + 1, x0] * (1 - fx) * fy + layer[y0 + 1, x0 + 1] * fx * fy)

def orb_height(o, px, py):
    """orbHeight: the orb's height and its gradient direction, in the metric stretched along its motion."""
    dx, dy, r = px - o[0], py - o[1], max(o[2], 0.5)
    k = math.hypot(o[4], o[5])
    if k < 1e-4:
        return (r * r - (dx * dx + dy * dy)) / r, dx / r, dy / r
    ux, uy = o[4] / k, o[5] / k; s = 1 + k
    along = dx * ux + dy * uy; ax, ay = dx - along * ux, dy - along * uy
    q = along * along / (s * s) + (ax * ax + ay * ay) * s
    return (r * r - q) / r, (along / (s * s) * ux + ax * s) / r, (along / (s * s) * uy + ay * s) / r

def glass_liquid(layer, orbs, px, py):
    blend, glow_w = BLEND * SCALE, GLOW_W * SCALE
    flat = sample(layer, px, py)
    hs = [orb_height(o, px, py) for o in orbs]
    m = np.max([h[0] for h in hs], axis=0)
    total = np.zeros_like(px); radius = np.zeros_like(px); gx = np.zeros_like(px); gy = np.zeros_like(px); glow = np.zeros(px.shape + (3,))
    for o, (b, tx, ty) in zip(orbs, hs):
        w = np.exp((b - m) / blend); r = max(o[2], 0.5)
        total += w; radius += w * r; gx += w * tx; gy += w * ty; glow += w[..., None] * o[3]
    radius /= total; gx /= total; gy /= total; glow /= total[..., None]
    b = m + blend * np.log(total)
    sd = b / np.maximum(2 * np.hypot(gx, gy), 1e-3)
    alpha = smoothstep(-0.75, 0.75, sd)
    halo = np.where(m < -12 * glow_w, 0, GLOW_S * np.exp(-np.maximum(-sd, 0) / glow_w))
    outside = flat + np.concatenate([glow * halo[..., None], halo[..., None]], -1) * (1 - flat[..., 3:4])
    h = np.sqrt(np.maximum(radius * b, 0))
    nx, ny, nz = radius * gx, radius * gy, h + 1e-3
    ln = np.sqrt(nx * nx + ny * ny + nz * nz); nx, ny, nz = nx / ln, ny / ln, nz / ln
    edge = 1 - nz
    ox, oy = -LENS * h * nx, -LENS * h * ny
    sg = sample(layer, px + ox, py + oy)
    sr = sample(layer, px + ox * (1 + 0.14 * edge), py + oy * (1 + 0.14 * edge))
    sb = sample(layer, px + ox * (1 - 0.14 * edge), py + oy * (1 - 0.14 * edge))
    c = np.stack([sr[..., 0], sg[..., 1], sb[..., 2]], -1) + (1 - sg[..., 3:4]) * CANVAS
    dl = np.maximum(np.hypot(nx, ny), 1e-4); dx, dy = nx / dl, ny / dl
    turn = np.arctan2(dy, dx) / (2 * math.pi) + edge * 0.6
    rainbow = 0.5 + 0.5 * np.cos(2 * math.pi * (turn[..., None] + np.array([0.0, 0.33, 0.67])))
    band = smoothstep(0.45, 0.8, edge) * (1 - smoothstep(0.9, 1.0, edge))
    tint = 1 + (rainbow - 1) * 0.55
    c = c + (tint - c) * (0.22 * band)[..., None]
    c = c + (np.array([0.97, 0.97, 0.99]) - c) * (0.22 * edge ** 3)[..., None]
    c = c + (CANVAS * np.array([0.86, 0.87, 0.9]) - c) * (0.35 * smoothstep(0.9, 1.0, edge))[..., None]
    L = np.array([-0.45, -0.7, 0.55]); L = L / np.linalg.norm(L)
    Hv = L + np.array([0, 0, 1.0]); Hv = Hv / np.linalg.norm(Hv)
    broad = 0.16 * np.maximum(nx * L[0] + ny * L[1] + nz * L[2], 0) ** 6 * smoothstep(0.05, 0.4, edge)
    glint = 0.9 * np.maximum(nx * Hv[0] + ny * Hv[1] + nz * Hv[2], 0) ** 140
    bottom = smoothstep(0.25, 0.95, dy)
    caustic = 0.55 * smoothstep(0.42, 0.75, edge) * (1 - smoothstep(0.82, 0.98, edge)) * bottom
    c = c + (1 - c) * np.clip(broad + glint + caustic, 0, 1)[..., None]
    inside = np.concatenate([c, np.ones(px.shape + (1,))], -1)
    a = alpha[..., None]
    return outside * (1 - a) + inside * a

# ---- the copy drawn into the layer ----
def text_layer(t):
    gate, title, subtitle, _, _ = copy_state(t)
    ov = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    def block(lines, cy, alphas):
        d = ImageDraw.Draw(ov)
        lh = 33 * S; top = cy * S - lh * len(lines) / 2
        for k, (ln, col) in enumerate(lines):
            if alphas[k] <= 0.01: continue
            layer = Image.new("RGBA", ov.size, (0, 0, 0, 0)); dl = ImageDraw.Draw(layer)
            tw = dl.textlength(ln, font=head_font)
            dl.text(((W * S - tw) / 2, top + k * lh), ln, font=head_font, fill=col + (int(255 * alphas[k]),))
            blur = (1 - alphas[k]) * 6 * S
            ov.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)) if blur > 0.3 else layer)
    block([("Everyone you love,", INK), ("in one orbit.", INK)], H * 0.4, [gate, gate])
    title_top = H / 2 + (-44 + 30) * SCALE + 26
    block([("Meet Orbit.", INK), ("Your friends, always", INK2), ("within reach.", INK2)], title_top + 52, [title, subtitle, subtitle])
    a = np.asarray(ov, float) / 255
    return np.dstack([a[..., :3] * a[..., 3:4], a[..., 3]])

def chrome(img, t):
    _, _, _, footer, hint = copy_state(t)
    d = ImageDraw.Draw(img, "RGBA")
    if hint > 0.01:
        bob = -3 + 4 * (0.5 + 0.5 * math.cos(t * math.pi / 1.1))
        cx, cy = W / 2 * S, (586 + bob) * S
        d.line([(cx - 6 * S, cy + 3 * S), (cx, cy - 3 * S), (cx + 6 * S, cy + 3 * S)], fill=INK2 + (255,), width=int(2 * S), joint="curve")
        tw = d.textlength("Swipe up to enter", font=small_font)
        d.text(((W * S - tw) / 2, 598 * S), "Swipe up to enter", font=small_font, fill=INK2 + (255,))
    if footer > 0.01:
        a = int(255 * footer); dy = (1 - footer) * 16
        for top, label in ((679, "Continue with Apple"), (745, "Continue with phone number")):
            y0, y1 = (top + dy) * S, (top + 54 + dy) * S
            d.rounded_rectangle([24 * S, y0, 378 * S, y1], radius=27 * S, fill=(255, 255, 255, int(a * 0.6)), outline=(255, 255, 255, a), width=int(1.2 * S))
            d.rounded_rectangle([30 * S, y0 + 2 * S, 372 * S, y0 + 20 * S], radius=18 * S, fill=(255, 255, 255, int(a * 0.25)))
            tw = d.textlength(label, font=button_font)
            d.text(((W * S - tw) / 2, y0 + 15 * S), label, font=button_font, fill=INK + (a,))
        legal = "By continuing, you agree to our Terms and Privacy Policy."
        tw = d.textlength(legal, font=legal_font)
        d.text(((W * S - tw) / 2, (817 + dy) * S), legal, font=legal_font, fill=INK2 + (a,))
    return img

# ---- frames ----
rows = defaultdict(list)
with open(frames_csv) as fh:
    for r in csv.DictReader(fh):
        rows[int(r["frame"])].append((int(r["id"]), float(r["x"]), float(r["y"]), float(r["r"]), float(r["depth"]), r["leaving"] == "1",
                                      float(r["vx"]), float(r["vy"])))

gy_, gx_ = np.mgrid[0:H * S, 0:W * S].astype(float)
PX, PY = (gx_ + 0.5) / S, (gy_ + 0.5) / S

for fi in sorted(rows):
    if ONLY and fi not in ONLY: continue
    t = fi / FPS
    vis = [b for b in rows[fi] if b[3] > 0.5]
    lv = (lift(t) - lift(t - 1 / 120)) * 120                     # the finger's velocity, screen pt/s
    vis = [(i, x, y + (lift(t) / SCALE if i == 0 else 0), r, dep, leaving, vx * SCALE, vy * SCALE + (lv if i == 0 else 0))
           for i, x, y, r, dep, leaving, vx, vy in vis]
    # smaller on top; bubbles melting away underneath everything
    vis.sort(key=lambda b: (not b[5], -b[4]))
    LW, LH = (W + 2 * MARGIN) * S, (H + 2 * MARGIN) * S
    layer = np.zeros((LH, LW, 4))
    orbs = []
    for i, x, y, r, _, _, vx, vy in vis:
        cx, cy = pt(x, y); rr = r * SCALE
        speed = math.hypot(vx, vy)
        amount = MAX_STRETCH * speed / (speed + HALF_SPEED) if speed > 1 else 0.0
        sx, sy = (vx / speed * amount, vy / speed * amount) if speed > 1 else (0.0, 0.0)
        orbs.append((cx, cy, rr, photos[i][1] if i <= 9 else DROPLET_GLOW, sx, sy))
        if i > 9: continue
        dpx = max(2, int(round(2 * rr * S)))
        img = np.asarray(Image.fromarray((photos[i][0] * 255).astype("uint8"), "RGBA").resize((dpx, dpx), Image.BILINEAR), float) / 255
        if amount > 0.005:
            # the photo stretched with the glass: R(a) * scale(1 + k, 1 / sqrt(1 + k)) * R(-a)
            a = math.atan2(sy, sx); ca, sa = math.cos(a), math.sin(a); s1, s2 = 1 + amount, 1 / math.sqrt(1 + amount)
            M = np.array([[ca, -sa], [sa, ca]]) @ np.diag([s1, s2]) @ np.array([[ca, sa], [-sa, ca]])
            Mi = np.linalg.inv(M); big = int(math.ceil(dpx * s1)) + 2
            im = Image.fromarray((img * 255).astype("uint8"), "RGBA")
            c0 = (dpx - 1) / 2; cb = (big - 1) / 2
            # PIL's affine maps output (x, y) to input: x_in = a*x + b*y + c, y_in = d*x + e*y + f
            coeff = (Mi[0, 0], Mi[0, 1], c0 - Mi[0, 0] * cb - Mi[0, 1] * cb, Mi[1, 0], Mi[1, 1], c0 - Mi[1, 0] * cb - Mi[1, 1] * cb)
            img = np.asarray(im.transform((big, big), Image.AFFINE, coeff, resample=Image.BILINEAR), float) / 255
            dpx = big
        X0, Y0 = int(round((cx + MARGIN) * S - dpx / 2)), int(round((cy + MARGIN) * S - dpx / 2))
        xa, ya, xb, yb = max(X0, 0), max(Y0, 0), min(X0 + dpx, LW), min(Y0 + dpx, LH)
        if xb <= xa or yb <= ya: continue
        piece = img[ya - Y0:yb - Y0, xa - X0:xb - X0]
        layer[ya:yb, xa:xb] = piece + layer[ya:yb, xa:xb] * (1 - piece[..., 3:4])
    txt = text_layer(t)
    m0 = MARGIN * S
    view = layer[m0:m0 + H * S, m0:m0 + W * S]
    view[:] = txt + view * (1 - txt[..., 3:4])
    out = view.copy()
    if orbs:
        pad = 12 * GLOW_W * SCALE
        ext = [o[2] * (1 + math.hypot(o[4], o[5])) for o in orbs]
        x0 = max(int((min(o[0] - e for o, e in zip(orbs, ext)) - pad) * S), 0); x1 = min(int((max(o[0] + e for o, e in zip(orbs, ext)) + pad) * S), W * S)
        y0 = max(int((min(o[1] - e for o, e in zip(orbs, ext)) - pad) * S), 0); y1 = min(int((max(o[1] + e for o, e in zip(orbs, ext)) + pad) * S), H * S)
        if x1 > x0 and y1 > y0:
            out[y0:y1, x0:x1] = glass_liquid(layer, orbs, PX[y0:y1, x0:x1], PY[y0:y1, x0:x1])
    rgb = out[..., :3] + CANVAS * (1 - out[..., 3:4])
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype("uint8")).convert("RGBA")
    chrome(img, t).convert("RGB").save(f"{out_dir}/f_{fi:04d}.png")
print("done")
