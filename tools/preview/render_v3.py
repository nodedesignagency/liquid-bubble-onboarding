# Motion preview of the v3 onboarding (WorldOnboardingView), driven by the Swift engine's recorded
# bubbles. Mirrors the globe (`globe.py`, the `holoGlobe` shader), its path (ZoomPath), the glass
# network's outline (WorldGlass, GlassNeck), the pins and photos (WorldPhoto), the dot grid, the
# copy and the buttons. Keep the timings (V3_*) in sync with WorldOnboardingView and
# tools/engine/record.swift (v3 script).
#
# What it can't show: the city (MapKit's 3D Paris) and the satellite snapshots the zoom starts
# from. Those parts are labelled stand-ins (the globe itself, zoomed as close as the snapshots
# would be), so only the motion and framing are meaningful there. The glass is drawn the way it
# looks before iOS 26 (a dark outline); on iOS 26 it is real Liquid Glass. The globe's scale at
# the handover (METERS_PER_POINT) is measured on the device; here it is assumed. Nunito stands in
# for SF Pro Rounded. iPhone 17 Pro sized (402 x 874 pt).
import csv, sys, os, math
from collections import defaultdict
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import globe as holo

frames_csv, assets, fonts, out_dir = sys.argv[1:5]
ONLY = [int(x) for x in os.environ.get("FRAMES", "").split(",") if x]
os.makedirs(out_dir, exist_ok=True)
holo.load(os.path.join(assets, "land-sdf.imageset/land-sdf.png"))
S, W, H, FPS = 2, 402, 874, 30
SCALE = min(W / 372, H / 480, 1.3)
CANVAS = np.array([0x04, 0x04, 0x06], float) / 255                  # Theme.worldCanvas
INK, INK2 = (0xF5, 0xF5, 0xF7), (0x8E, 0x8E, 0x93)                  # Theme.worldInk, worldInkSecondary
GLASS = (0x16, 0x16, 0x1A)                                           # Theme.worldGlass
EARTH = (0.0, -120.0); GLOBE_R = 84.0                                 # OrbitChoreography.bloomEarth, globeRadius
GLOBE_VIEW = (25.0, 12.0, 9.0)                                       # globeView: latitude, longitude, distance
CITY = (48.8584, 2.2945)                                             # EarthZoom.city
PHOTO_FRACTION = 28.0 / 33.0
FRIENDS = [1, 2, 3, 4]
EARTH_RADIUS = 6371000.0
METERS_PER_POINT = 4.0                                               # assumed handover scale
START_ROLL = 30.0                                                    # 360 - EarthZoom.heading

# WorldOnboardingView's sequence, with the city rendered and the imagery in at once
V3_COVER = 0.8                       # the city fades in
V3_RISE = 1.5                        # hold, then MapKit flattens and rises (EarthZoom.rise)
V3_ZOOM = V3_RISE + 1.35             # the zoom out (EarthZoom.zoomOut)
V3_ZOOM_LEN = 3.6
V3_SPACE_TEXT = V3_ZOOM + V3_ZOOM_LEN * 0.78
V3_PINS = V3_SPACE_TEXT + V3_ZOOM_LEN * 0.22 + 0.15
V3_BLOOM = V3_PINS + 1.4
V3_TITLE, V3_SUBTITLE, V3_FOOTER = V3_BLOOM + 0.35, V3_BLOOM + 0.65, V3_BLOOM + 1.25
V3_CONTINUE = 14.0
V3_BACK = V3_CONTINUE + 1.0
V3_BACK_LEN = 3.0
DRIFT = 1.2                          # degrees per second once the friends are in orbit

def pt(x, y): return (W / 2 + x * SCALE, H / 2 + y * SCALE)
def ease(x): x = min(max(x, 0), 1); return x * x * (3 - 2 * x)
def fade(t, start, duration): return ease((t - start) / duration)

# ---- ZoomPath ----
REST = dict(center=pt(*EARTH), radius=GLOBE_R * SCALE, distance=GLOBE_VIEW[2], lat=GLOBE_VIEW[0], lon=GLOBE_VIEW[1])
FOCAL = REST["radius"] * math.sqrt(REST["distance"] ** 2 - 1)
END_SCALE = EARTH_RADIUS * (REST["distance"] - 1) / FOCAL
DIAG = math.hypot(W, H)
span = METERS_PER_POINT * DIAG * 1.45
while span * 3.2 <= 4.6e6: span *= 3.2
COARSEST = span / 800                                                 # metres per point of the coarsest snapshot
GLOBE_TO = max(COARSEST * 800 * 0.8 / DIAG, METERS_PER_POINT * 1.5)
GLOBE_FROM = GLOBE_TO / 1.6

def zscale(u): return math.exp(math.log(METERS_PER_POINT) + (math.log(END_SCALE) - math.log(METERS_PER_POINT)) * ease(u))
def between(s, a, b): return ease((math.log(s) - math.log(a)) / max(math.log(b) - math.log(a), 1e-6))
def depth(s): return (math.log(s) - math.log(METERS_PER_POINT)) / (math.log(END_SCALE) - math.log(METERS_PER_POINT))

def globe_on_path(u, rest_lon):
    s = zscale(u)
    dist = 1 + s * FOCAL / EARTH_RADIUS
    radius = FOCAL / math.sqrt(dist * dist - 1)
    k = between(s, GLOBE_TO, END_SCALE)
    cx = W / 2 + (REST["center"][0] - W / 2) * k; cy = H / 2 + (REST["center"][1] - H / 2) * k
    return dict(cx=cx, cy=cy, radius=radius, dist=dist, lat=CITY[0] + (REST["lat"] - CITY[0]) * k,
                lon=CITY[1] + (rest_lon - CITY[1]) * k, roll=START_ROLL * (1 - ease(depth(s) / 0.75)),
                glow=k, opacity=between(s, GLOBE_FROM, GLOBE_TO))

def lon_at(t):
    if t < V3_BLOOM: return REST["lon"]
    return REST["lon"] - DRIFT * (min(t, V3_BACK) - V3_BLOOM)

def globe_state(t):
    """The globe, and whether we are in the city or the snapshots (labelled stand-ins)."""
    if t < V3_ZOOM:
        return None, "city"
    if t < V3_ZOOM + V3_ZOOM_LEN:
        g = globe_on_path((t - V3_ZOOM) / V3_ZOOM_LEN, REST["lon"])
        return g, "snapshots" if g["opacity"] < 1 else None
    if t < V3_BACK:
        return dict(cx=REST["center"][0], cy=REST["center"][1], radius=REST["radius"], dist=REST["distance"],
                    lat=REST["lat"], lon=lon_at(t), roll=0, glow=1, opacity=1), None
    u = 1 - min((t - V3_BACK) / V3_BACK_LEN, 1)
    if u <= 0: return None, "city"
    g = globe_on_path(u, lon_at(t))
    return g, "snapshots" if g["opacity"] < 1 else None

# ---- GlassNeck ----
def neck(c1, r1, c2, r2, v=0.45, handle=2.4):
    d = math.dist(c1, c2)
    if r1 <= 0.5 or r2 <= 0.5 or d > r1 + r2 * 2.5 or d <= abs(r1 - r2): return None
    cl = lambda x: min(max(x, -1), 1)
    u1 = u2 = 0.0
    if d < r1 + r2:
        u1 = math.acos(cl((r1 * r1 + d * d - r2 * r2) / (2 * r1 * d))); u2 = math.acos(cl((r2 * r2 + d * d - r1 * r1) / (2 * r2 * d)))
    ang = math.atan2(c2[1] - c1[1], c2[0] - c1[0]); spread = math.acos(cl((r1 - r2) / d))
    a1 = ang + u1 + (spread - u1) * v; a2 = ang - u1 - (spread - u1) * v
    a3 = ang + math.pi - u2 - (math.pi - u2 - spread) * v; a4 = ang - math.pi + u2 + (math.pi - u2 - spread) * v
    at = lambda c, a, r: (c[0] + r * math.cos(a), c[1] + r * math.sin(a))
    p1, p2, p3, p4 = at(c1, a1, r1), at(c1, a2, r1), at(c2, a3, r2), at(c2, a4, r2)
    total = r1 + r2
    d2 = min(v * handle, math.dist(p1, p3) / total) * min(1, d * 2 / total)
    h1, h2 = at(p1, a1 - math.pi / 2, r1 * d2), at(p2, a2 + math.pi / 2, r1 * d2)
    h3, h4 = at(p3, a3 + math.pi / 2, r2 * d2), at(p4, a4 - math.pi / 2, r2 * d2)
    def bez(a, b, c, e, n=24):
        return [((1-t)**3*a[0]+3*(1-t)**2*t*b[0]+3*(1-t)*t*t*c[0]+t**3*e[0], (1-t)**3*a[1]+3*(1-t)**2*t*b[1]+3*(1-t)*t*t*c[1]+t**3*e[1])
                for t in [i / n for i in range(n + 1)]]
    return bez(p1, h1, h3, p3) + bez(p4, h4, h2, p2) + [c1]

# ---- drawing ----
f = lambda w, s: ImageFont.truetype(os.path.join(fonts, f"nunito-{w}.ttf"), int(s * S))
head_font, button_font, legal_font, note_font = f(700, 27), f(700, 17), f(400, 12), f(600, 13)
photos = {i: Image.open(os.path.join(assets, f"friend-{i}.imageset/friend-{i}.jpg")).convert("RGB").resize((360, 360), Image.LANCZOS) for i in FRIENDS}

def put_text(img, x, y, line, font, color, alpha):
    """Text at `alpha`, through a mask: Pillow's RGBA drawing ignores a fill's alpha for text."""
    if alpha <= 0.002: return
    x0, y0, x1, y1 = [int(v) for v in ImageDraw.Draw(img).textbbox((x, y), line, font=font)]
    x0 -= 2; y0 -= 2; x1 += 2; y1 += 2
    mask = Image.new("L", (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(mask).text((x - x0, y - y0), line, font=font, fill=int(255 * min(alpha, 1)))
    img.paste(Image.new("RGB", mask.size, color[:3]), (x0, y0), mask)

def disc(img, src, c, r, edge):
    D = max(2, int(round(r * 2 * S)))
    p = src.resize((D, D), Image.BILINEAR)
    m = Image.new("L", (D * 4, D * 4), 0); ImageDraw.Draw(m).ellipse((0, 0, D * 4 - 1, D * 4 - 1), fill=255); m = m.resize((D, D), Image.LANCZOS)
    x, y = int(round(c[0] * S - D / 2)), int(round(c[1] * S - D / 2))
    img.paste(p, (x, y), m)
    if edge > 0.01:
        lw = max(1.5, r * 2 * 0.09) * S
        ring = Image.new("L", (D * 4, D * 4), 0); dr = ImageDraw.Draw(ring)
        dr.ellipse((0, 0, D * 4 - 1, D * 4 - 1), fill=255)
        if D * 4 - 1 - lw * 8 > 0:
            dr.ellipse((lw * 4, lw * 4, D * 4 - 1 - lw * 4, D * 4 - 1 - lw * 4), fill=0)
        ring = ring.resize((D, D), Image.LANCZOS)
        ring = Image.fromarray((np.asarray(ring, float) * edge).astype(np.uint8))
        img.paste(Image.new("RGB", (D, D), (255, 255, 255)), (x, y), ring)

gy_, gx_ = np.mgrid[0:H * S, 0:W * S].astype(np.float32)
PX, PY = (gx_ + 0.5) / S, (gy_ + 0.5) / S
GX = (PX % 18) - 9; GY = (PY % 18) - 9
DOTS = np.clip(1.0 - np.hypot(GX, GY) / 0.9, 0, 1)
FOCUS = pt(*EARTH)
FALL = 1 - np.minimum(np.hypot(PX - FOCUS[0], PY - FOCUS[1]) / (max(W, H) * 0.62), 1)

def grid_opacity(t):
    return fade(t, V3_BLOOM, 1.0) * (1 - fade(t, V3_CONTINUE, 0.8))

rows = defaultdict(list)
with open(frames_csv) as fh:
    for r in csv.DictReader(fh):
        rows[int(r["frame"])].append((int(r["id"]), float(r["x"]), float(r["y"]), float(r["r"]), float(r["depth"]),
                                      r["leaving"] == "1", float(r["full"]), r["appearing"] == "1"))

for fi in sorted(rows):
    if ONLY and fi not in ONLY: continue
    t = fi / FPS
    rgb = np.ones((H * S, W * S, 3)) * CANVAS
    rgb = rgb + (DOTS * FALL * 0.11 * grid_opacity(t))[..., None]
    g, standin = globe_state(t)
    bubbles = {b[0]: b for b in rows[fi]}
    # the glass (the outline it has before iOS 26)
    glass = Image.new("L", (W * S * 2, H * S * 2), 0); gd = ImageDraw.Draw(glass); q = S * 2
    e = bubbles.get(0)
    if e and e[3] > 0.5:
        ec = pt(e[1], e[2]); er = e[3] * SCALE
        gd.ellipse(((ec[0] - er) * q, (ec[1] - er) * q, (ec[0] + er) * q, (ec[1] + er) * q), fill=255)
        for i in FRIENDS:
            b = bubbles.get(i)
            if not b or b[3] <= 0.5: continue
            c = pt(b[1], b[2]); r = b[3] * SCALE
            gd.ellipse(((c[0] - r) * q, (c[1] - r) * q, (c[0] + r) * q, (c[1] + r) * q), fill=255)
            n = neck(ec, er, c, r)
            if n: gd.polygon([(x * q, y * q) for x, y in n], fill=255)
    gm8 = glass.resize((W * S, H * S), Image.LANCZOS)
    gm = np.asarray(gm8, np.float32) / 255
    if gm.max() > 0:
        inner = np.asarray(gm8.filter(ImageFilter.MinFilter(3)), np.float32) / 255
        rim = np.clip(gm - inner, 0, 1)
        rgb = rgb * (1 - gm[..., None]) + np.array(GLASS) / 255 * gm[..., None]
        rgb = rgb + (rim * 0.14)[..., None]
    # the globe
    if g is not None:
        grgb, ga = holo.globe(PX, PY, g["cx"], g["cy"], g["radius"], g["dist"], g["lat"], g["lon"], roll=g["roll"],
                              glow=g["glow"], opacity=g["opacity"] if standin != "snapshots" else 1.0, time=t)
        rgb = grgb + rgb * (1 - ga[..., None])
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
    if standin == "city":
        cover = fade(t, 0, V3_COVER) if t < V3_ZOOM else 1.0
        ImageDraw.Draw(img).rectangle((0, 0, W * S, H * S), fill=tuple(int(c * 255 + (60 - c * 255) * cover) for c in CANVAS))
        put_text(img, 40 * S, 410 * S, "stand-in: MapKit 3D Paris", note_font, (230, 230, 235), cover)
    elif standin == "snapshots":
        put_text(img, 40 * S, 80 * S, "stand-in: satellite snapshots, then this globe", note_font, (230, 230, 235), 1)
    # photos, on top of the globe
    for i in FRIENDS:
        b = bubbles.get(i)
        if not b or b[3] <= 0.5 or b[6] <= 0.5: continue
        if b[7] or b[5]:
            grown = b[3] / b[6]
            pr = b[6] * PHOTO_FRACTION * min(max((grown - 0.3) / 0.7, 0), 1.12) * SCALE
        else:
            pr = b[3] * PHOTO_FRACTION * SCALE
        if pr < 0.25: continue
        edge = min(max((24 - b[3]) / 8, 0), 1)
        disc(img, photos[i], pt(b[1], b[2]), pr, edge)
    # copy and buttons
    title_top = H / 2 + (EARTH[1] + 182) * SCALE
    space = fade(t, V3_SPACE_TEXT, 0.7) * (1 - fade(t, V3_BLOOM, 0.5))
    d = ImageDraw.Draw(img)
    for j, line in enumerate(["Everyone you love,", "in one orbit."]):
        tw = d.textlength(line, font=head_font)
        put_text(img, (W * S - tw) / 2, (title_top + 18 + j * 34) * S, line, head_font, INK, space)
    gone = 1 - fade(t, V3_CONTINUE, 0.4)
    for j, (line, col, op) in enumerate([("Meet Orbit.", INK, fade(t, V3_TITLE, 0.6)), ("Your friends, always", INK2, fade(t, V3_SUBTITLE, 0.6)),
                                         ("within reach.", INK2, fade(t, V3_SUBTITLE, 0.6))]):
        tw = d.textlength(line, font=head_font)
        put_text(img, (W * S - tw) / 2, (title_top + j * 34) * S, line, head_font, col, op * gone)
    fa = fade(t, V3_FOOTER, 0.6) * gone
    if fa > 0:
        dy = 16 * (1 - fa)
        for j, (label, bg, fg) in enumerate([("Continue with Apple", (255, 255, 255), (4, 4, 6)), ("Continue with phone number", GLASS, INK)]):
            y0 = 874 - 34 - 8 - 18 - 6 - 12 - 54 - (66 * (1 - j)) + dy
            box = Image.new("L", (W * S, H * S), 0)
            ImageDraw.Draw(box).rounded_rectangle((24 * S, y0 * S, (W - 24) * S, (y0 + 54) * S), radius=27 * S, fill=int(255 * fa))
            img.paste(Image.new("RGB", img.size, bg), (0, 0), box)
            tw = d.textlength(label, font=button_font)
            put_text(img, (W * S - tw) / 2, (y0 + 16) * S, label, button_font, fg, fa)
        legal = "By continuing, you agree to our Terms and Privacy Policy."
        tw = d.textlength(legal, font=legal_font)
        put_text(img, (W * S - tw) / 2, (874 - 34 - 8 - 16 + dy) * S, legal, legal_font, INK2, fa)
    img.save(f"{out_dir}/f_{fi:04d}.png")
print("done")
