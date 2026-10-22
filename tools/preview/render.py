# Motion preview of the onboarding, driven by the Swift engine's recorded bubbles and threads.
# Keep `steps` (copy and timings) in sync with Onboarding/OnboardingStep.swift and tools/engine/record.swift.
# Mirrors GooLayer (the `liquid` shader: soft discs and capsules summed, no threshold), SoftPhoto, and the chrome.
# Nunito stands in for SF Pro Rounded. iPhone 17 Pro sized (402 x 874 pt).
import csv, sys, os, math
from collections import defaultdict
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

frames_csv, threads_csv, assets, fonts, out_dir = sys.argv[1:6]
ONLY = [int(x) for x in os.environ.get("FRAMES", "").split(",") if x]
os.makedirs(out_dir, exist_ok=True)
S, W, H, FPS = 2, 402, 874, 30
BG = np.array([0xFA, 0xFA, 0xFA], float)
LIQ = np.array([0xED, 0xDD, 0xFA], float)   # Theme.liquid, the wash the photo rims melt into
SOFT, EDGE = 10.3, 0.312                   # GooLayer.softness (reference pt) and edge
INK, INK2, HAIR = (0x1D, 0x1D, 0x1F), (0x86, 0x86, 0x8B), (0xDB, 0xDB, 0xDC)
SLOT = (194, 748)
scale = min(W / 372, (SLOT[1] - SLOT[0]) / 480, 1.3)
ox, oy = W / 2, (SLOT[0] + SLOT[1]) / 2

steps = [(0.0, "It starts with you", "Your orbit begins with a single bubble."),
         (3.0, "Bump to connect", "Tap phones with a friend to join bubbles."),
         (6.8, "Your circle grows", "Friends of friends, one bubble away."),
         (10.6, "Your world, in orbit", "Everyone you love, wherever they are.")]
LEAVE = 15.0

f = lambda w, s: ImageFont.truetype(os.path.join(fonts, f"nunito-{w}.ttf"), int(s * S))
title_font, sub_font, btn_font, skip_font = f(700, 30), f(400, 17), f(700, 17), f(600, 16)

def radial_alpha(n, a, b):
    yy, xx = (np.mgrid[0:n, 0:n] + 0.5) / n - 0.5
    return np.clip((b - np.hypot(xx, yy) * 2) / (b - a), 0, 1)

def soft_photo(im):
    """Mirror of SoftPhoto: the sharp photo under a feathered circular mask (alpha 1 to 77% of the radius,
    0 at the edge). A mask, not a blur."""
    n = im.width
    alpha = radial_alpha(n, 0.77, 1.0)[..., None]
    return Image.fromarray(np.dstack([np.asarray(im, float), alpha * 255]).astype("uint8"), "RGBA")

FACE = 320
faces = {}
for i in range(0, 10):
    path = os.path.join(assets, "earth.imageset/earth.jpg" if i == 0 else f"friend-{i}.imageset/friend-{i}.jpg")
    faces[i] = soft_photo(Image.open(path).convert("RGB").resize((FACE, FACE), Image.LANCZOS))

rows = defaultdict(list)
with open(frames_csv) as fh:
    for r in csv.DictReader(fh):
        tint = np.array([float(r["tr"]), float(r["tg"]), float(r["tb"])]) * 255
        rows[int(r["frame"])].append((int(r["id"]), float(r["x"]), float(r["y"]), float(r["r"]), tint))
threads = defaultdict(list)
with open(threads_csv) as fh:
    for r in csv.DictReader(fh):
        threads[int(r["frame"])].append((int(r["a"]), int(r["b"]), float(r["strength"])))

def ease(x): x = min(max(x, 0), 1); return x * x * (3 - 2 * x)
def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)
def halo(r): return min(8.4, 1.5 + r * 0.157)   # OrbitChoreography.haloWidth
def pt(x, y): return (ox + x * scale, oy + y * scale)   # reference space -> screen points

gy, gx = np.mgrid[0:H * S, 0:W * S].astype(float)
PX, PY = (gx + 0.5) / S, (gy + 0.5) / S     # every pixel's position in points, like the shader's
base = np.broadcast_to(BG, (H * S, W * S, 3))

def shoulder(d, radius):
    """Alpha of a disc of `radius` with a Gaussian-like soft edge, at distance d. Same formula as Liquid.metal."""
    return 1 / (1 + np.exp(np.clip(1.702 * (d - radius) / (SOFT * scale), -30, 30)))

def wrap(draw, text, font, maxw):
    words, lines, line = text.split(), [], ""
    for w_ in words:
        t = (line + " " + w_).strip()
        if draw.textlength(t, font=font) <= maxw: line = t
        else: lines.append(line); line = w_
    return lines + [line]

def header_layer(j, alpha, blur):
    ov = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0)); od = ImageDraw.Draw(ov)
    _, title, sub = steps[j]
    tw = od.textlength(title, font=title_font); od.text(((W * S - tw) / 2, 110 * S), title, font=title_font, fill=INK + (int(255 * alpha),))
    y = 156 * S
    for ln in wrap(od, sub, sub_font, 338 * S):
        tw = od.textlength(ln, font=sub_font); od.text(((W * S - tw) / 2, y), ln, font=sub_font, fill=INK2 + (int(255 * alpha),)); y += 23 * S
    return ov.filter(ImageFilter.GaussianBlur(blur * S)) if blur > 0.2 else ov

for fi in sorted(rows):
    if ONLY and fi not in ONLY: continue
    t = fi / FPS
    bubbles = {b[0]: b for b in rows[fi]}

    # The liquid: one field of soft discs (photos) and capsules (threads), tinted by whoever contributes.
    field = np.zeros((H * S, W * S)); tint = np.zeros((H * S, W * S, 3))
    def add(w, color):
        global field, tint
        field = field + w; tint = tint + w[..., None] * color
    for i, x, y, r, color in bubbles.values():
        if r <= 0.5: continue
        cx, cy = pt(x, y)
        add(shoulder(np.hypot(PX - cx, PY - cy), (r + halo(r)) * scale), color)
    for a, b, s_ in threads.get(fi, []):
        A, B = bubbles[a], bubbles[b]
        if A[3] <= 1 or B[3] <= 1: continue
        (ax, ay), (bx, by) = pt(A[1], A[2]), pt(B[1], B[2])
        vx, vy = bx - ax, by - ay
        u = np.clip(((PX - ax) * vx + (PY - ay) * vy) / max(vx * vx + vy * vy, 1e-4), 0, 1)
        radius = 8 * min(s_, 1.2) * scale * (0.75 + 0.25 * np.abs(2 * u - 1))
        add(shoulder(np.hypot(PX - (ax + u * vx), PY - (ay + u * vy)), radius), (A[4] + B[4]) / 2)
    alpha = smoothstep(0.5 - EDGE, 0.5 + EDGE, field)[..., None]
    color = tint / np.maximum(field, 1e-9)[..., None]
    frame = Image.fromarray((color * alpha + base * (1 - alpha)).astype("uint8")).convert("RGBA")

    # Photos: Earth just above the liquid, then everyone else, bigger on top.
    order = sorted(bubbles.values(), key=lambda b: -1 if b[0] == 0 else b[3])
    for i, x, y, r, _ in order:
        if r <= 0.5: continue
        dpx = max(1, int(round(2 * r * scale * S))); cx, cy = pt(x, y); cx, cy = cx * S, cy * S
        if -dpx < cx < W * S + dpx and -dpx < cy < H * S + dpx:
            frame.alpha_composite(faces[i].resize((dpx, dpx), Image.LANCZOS), (int(cx - dpx / 2), int(cy - dpx / 2)))

    leave = 1 - ease((t - LEAVE) / 0.4)
    idx = max(i for i, s_ in enumerate(steps) if s_[0] <= t)
    p = ease((t - steps[idx][0]) / 0.45) if idx > 0 else 1
    if leave > 0.01:
        if idx > 0 and p < 1: frame.alpha_composite(header_layer(idx - 1, (1 - p) * leave, p * 6))
        frame.alpha_composite(header_layer(idx, p * leave, (1 - p) * 6))
    ov = Image.new("RGBA", frame.size, (0, 0, 0, 0)); od = ImageDraw.Draw(ov)
    back_a = (ease((t - steps[1][0]) / 0.5) if t >= steps[1][0] else 0) * leave
    if back_a > 0.01:
        cx, cy = 30 * S, 84 * S
        od.line([cx + 4 * S, cy - 8 * S, cx - 4 * S, cy, cx + 4 * S, cy + 8 * S], fill=INK + (int(255 * back_a),), width=int(2.4 * S), joint="curve")
    skip_a = (1 - ease((t - steps[3][0]) / 0.5)) * leave
    if skip_a > 0.01:
        tw = od.textlength("Skip", font=skip_font); od.text((382 * S - tw, 73 * S), "Skip", font=skip_font, fill=INK2 + (int(255 * skip_a),))
    # Dots.
    x = W * S / 2 - (18 + 3 * 6 + 3 * 6) * S / 2
    for i in range(4):
        w_ = (18 if i == idx else 6) * S
        od.rounded_rectangle([x, 748 * S, x + w_, 754 * S], radius=3 * S, fill=(INK if i == idx else HAIR) + (int(255 * leave),)); x += w_ + 6 * S
    od.rounded_rectangle([24 * S, 776 * S, 378 * S, 832 * S], radius=28 * S, fill=INK + (int(255 * leave),))
    last = ease((t - steps[3][0]) / 0.35)
    for label, a in (("Continue", 1 - last), ("Get started", last)):
        if a * leave <= 0.01: continue
        tw = od.textlength(label, font=btn_font); od.text(((W * S - tw) / 2, 793 * S), label, font=btn_font, fill=(255, 255, 255, int(255 * a * leave)))
    frame.alpha_composite(ov)
    frame.convert("RGB").save(f"{out_dir}/f_{fi:04d}.png")
print("done")
