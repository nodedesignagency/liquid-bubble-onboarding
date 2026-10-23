# Motion preview of the v3 onboarding (WorldOnboardingView), driven by the Swift engine's recorded
# bubbles. Mirrors the gate's dome, the globe (`globe.py`, the `holoGlobe` shader), its path and
# ring sweep (ZoomPath), the glass network's outline (WorldGlass, GlassNeck), the pins and photos
# (WorldPhoto), the dot grid, the copy, the buttons, and a finger showing the swipe and the taps.
# Keep the timings (V3_*) in sync with WorldOnboardingView and tools/engine/record.swift (v3 script).
#
# What it can't show: the city (MapKit's 3D Paris) and the satellite snapshots the zoom is drawn
# from. The city is a labelled stand-in; the snapshots (flat at first, then on the sphere) are the
# globe itself in plain stand-in satellite colours (`globe.py`'s `satellite`), dissolving into the
# hologram, so the motion and framing are meaningful but not the imagery. Glass is drawn the way it looks before iOS 26 (a dark outline, a frosted
# dome); on iOS 26 it is real Liquid Glass. The globe's scale at the handover (METERS_PER_POINT) is
# measured on the device; here it is assumed. Nunito stands in for SF Pro Rounded. iPhone 17 Pro
# sized (402 x 874 pt).
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
S, W, H, FPS = int(os.environ.get("PREVIEW_SCALE", "2")), 402, 874, 30
SCALE = min(W / 372, H / 480, 1.3)
CANVAS = np.array([0x04, 0x04, 0x06], float) / 255                  # Theme.worldCanvas
INK, INK2 = (0xF5, 0xF5, 0xF7), (0x8E, 0x8E, 0x93)                  # Theme.worldInk, worldInkSecondary
GLASS = (0x16, 0x16, 0x1A)                                           # Theme.worldGlass
HUB = (0.0, -120.0); HUB_R = 91.0; GLOBE_R = 84.0                     # OrbitChoreography.bloomEarth, globeRadius
GLOBE_VIEW = (25.0, 12.0, 9.0)                                       # globeView: latitude, longitude, distance
CITY = (48.8584, 2.2945)                                             # EarthZoom.city
COPY_TOP = 66.0                                                      # WorldOnboardingView.copyTop
EARTH_RADIUS = 6371000.0
METERS_PER_POINT = 4.0                                               # assumed handover scale
START_ROLL = 30.0                                                    # 360 - EarthZoom.heading
NAMES = {1: "Maya", 2: "Kwame", 3: "Ines", 4: "Kai", 5: "Amara", 6: "Zoe", 7: "Omar", 8: "Layla", 9: "Lena"}  # Person.samples
CITIES = {1: "London", 2: "Lagos", 3: "Johannesburg", 4: "Istanbul", 5: "Nairobi", 6: "Dubai", 7: "Berlin", 8: "Cairo", 9: "Lisbon"}
MOMENTS = range(16, 40)                                               # OrbitChoreography.momentIDs
def moment_of(i): return ((i - 16) // 4 + 1, (i - 16) % 4 + 1)       # OrbitChoreography.moment(_:)
def has_photo(i): return 1 <= i <= 9 or i in MOMENTS                 # WorldPhoto.hasPhoto
# The globe's colours (GlobePalette): PALETTE=aurora (default), dusk, afterglow, midnight or lavender.
PALETTE = {"aurora": holo.AURORA, "dusk": holo.DUSK, "afterglow": holo.AFTERGLOW, "midnight": holo.MIDNIGHT,
           "lavender": holo.LAVENDER}[os.environ.get("PALETTE", "aurora")]

# WorldOnboardingView's sequence, with the city rendered and the imagery in at once
V3_COVER = 0.8                       # the city fades in, the gate's shade with it
V3_DOME = 0.45                       # the dome starts rising (showDome(after: 0.45))
V3_DRAG = 1.5                        # the finger lands on the dome and swipes up
V3_PASS = 2.3                        # and lets go: the dome sweeps off
V3_ZOOM = V3_PASS + 0.3 + 1.35       # the map rises (EarthZoom.rise), then the zoom out
V3_ZOOM_LEN = 5.0                    # EarthZoom.zoomOut
V3_SPACE_TEXT = V3_ZOOM + V3_ZOOM_LEN * 0.8
V3_PINS = V3_ZOOM + V3_ZOOM_LEN + 0.15
V3_BLOOM = V3_PINS + 1.4
V3_FOOTER = V3_BLOOM + 1.2
TAPS = [(13.2, 6), (16.0, 0), (17.6, 4), (20.0, 0)]                 # record.swift: Zoe, Earth, Kai, Earth
V3_CONTINUE = 21.0
V3_BACK = V3_CONTINUE + 1.0
V3_BACK_LEN = 3.6                    # EarthZoom.zoomBack
V3_SETTLE = V3_BACK + V3_BACK_LEN    # the map tilts back up to the tower (EarthZoom.rise)
V3_DOME_AGAIN = V3_SETTLE + 1.3 * 0.6
DRIFT = 1.2                          # degrees per second once the friends are in orbit

def pt(x, y): return (W / 2 + x * SCALE, H / 2 + y * SCALE)
def ease(x): x = min(max(x, 0), 1); return x * x * (3 - 2 * x)
def fade(t, start, duration): return ease((t - start) / duration)

def spring(response, damping, t):                                    # SpringCurve.progress
    if t <= 0: return 0.0
    w = 2 * math.pi / response
    if damping < 1:
        wd = w * math.sqrt(1 - damping * damping); env = math.exp(-damping * w * t)
        return 1 - env * (math.cos(wd * t) + damping * w / wd * math.sin(wd * t))
    return 1 - math.exp(-w * t) * (1 + w * t)

# ---- ZoomPath ----
REST = dict(center=pt(*HUB), radius=GLOBE_R * SCALE, distance=GLOBE_VIEW[2], lat=GLOBE_VIEW[0], lon=GLOBE_VIEW[1])
FOCAL = REST["radius"] * math.sqrt(REST["distance"] ** 2 - 1)
END_SCALE = EARTH_RADIUS * (REST["distance"] - 1) / FOCAL
DIAG = math.hypot(W, H)
SCREEN_CENTER = (W / 2, H / 2)
SPANS = []                                                            # ZoomImagery.fetch
span = METERS_PER_POINT * DIAG * 1.45
while span <= 6.0e6: SPANS.append(span); span *= 3.2
LAYERS = SPANS[-3:]                                                   # the globe's regional snapshots (and the world)
def scale_for_radius(r): return EARTH_RADIUS * (math.sqrt(1 + (FOCAL / r) ** 2) - 1) / FOCAL
_finer = [x for x in SPANS if x < LAYERS[0] * 0.9]
SPHERE_FROM = max((_finer[-1] * 0.8 / DIAG / 0.5 if _finer else METERS_PER_POINT * 1.5) * 1.05, METERS_PER_POINT * 1.2)
SPHERE_TO = SPHERE_FROM * 1.3
DISSOLVE_FROM = max(scale_for_radius(290), SPHERE_TO * 1.2)
DISSOLVE_TO = scale_for_radius(145)
DRIFT_FROM = math.sqrt(DISSOLVE_FROM * DISSOLVE_TO)
TOTAL = math.log(END_SCALE) - math.log(METERS_PER_POINT)
_middle = (math.log(DRIFT_FROM) - math.log(METERS_PER_POINT)) / TOTAL
def _profile(dip):
    cum = [0.0]
    for step in range(256):
        u = (step + 0.5) / 256
        cum.append(cum[-1] + 6 * u * (1 - u) * (1 - 0.8 * math.exp(-((u - dip) / 0.13) ** 2)))
    return [c / cum[-1] for c in cum]
lo, hi = 0.1, 0.95
for _ in range(30):
    mid = (lo + hi) / 2
    if _profile(mid)[int(mid * 256)] < _middle: lo = mid
    else: hi = mid
DEPTHS = _profile((lo + hi) / 2)

def depth_at(u):
    x = min(max(u, 0), 1) * 256; i = min(int(x), 255); fr = x - i
    return DEPTHS[i] * (1 - fr) + DEPTHS[i + 1] * fr
def zscale(u): return math.exp(math.log(METERS_PER_POINT) + TOTAL * depth_at(u))
def between(s, a, b): return ease((math.log(s) - math.log(a)) / max(math.log(b) - math.log(a), 1e-6))
def roll_at(u): return START_ROLL * (1 - ease(depth_at(u) / 0.75))
def shows_snapshots(u): return zscale(u) < SPHERE_TO

def globe_on_path(u, rest_lon):
    s = zscale(u)
    dist = 1 + s * FOCAL / EARTH_RADIUS
    radius = FOCAL / math.sqrt(dist * dist - 1)
    k = between(s, DRIFT_FROM, END_SCALE)
    h = between(s, DISSOLVE_FROM, DISSOLVE_TO)
    return dict(cx=SCREEN_CENTER[0] + (REST["center"][0] - SCREEN_CENTER[0]) * k,
                cy=SCREEN_CENTER[1] + (REST["center"][1] - SCREEN_CENTER[1]) * k,
                radius=radius, dist=dist, lat=CITY[0] + (REST["lat"] - CITY[0]) * k,
                lon=CITY[1] + (rest_lon - CITY[1]) * k, roll=roll_at(u), glow=h, satellite=1 - h,
                opacity=between(s, SPHERE_FROM, SPHERE_TO))

def lon_at(t):
    if t < V3_BLOOM: return REST["lon"]
    return REST["lon"] - DRIFT * (min(t, V3_BACK) - V3_BLOOM)

def progress(t):
    """0 at the handover, 1 at rest; None before the zoom."""
    if t < V3_ZOOM: return None
    if t >= V3_BACK: return 1 - min((t - V3_BACK) / V3_BACK_LEN, 1)
    return min((t - V3_ZOOM) / V3_ZOOM_LEN, 1)

def stack_opacity(t, u):
    if u is None or not shows_snapshots(u): return 0.0
    if t >= V3_BACK: return ease((V3_BACK_LEN - (t - V3_BACK)) / 0.6)
    return ease((t - V3_ZOOM) / 0.6)
def nudge(t):                                                         # WorldOnboardingView.nudge
    phase = (t % 2.4) / 0.8
    return math.sin(math.pi * phase) * 4 if phase < 1 else 0.0

# ---- the gate ----
DOME_R = W * 0.62; DOME_TOP = H * 0.76
DOME_HIDDEN = H - DOME_TOP + 90; DOME_GONE = -(DOME_TOP + DOME_R * 2 + 40)
def drag_translation(t): return -170 * ease((t - V3_DRAG) / (V3_PASS - V3_DRAG))
def lift(translation):                                                # EarthLift.move
    up = max(-translation, 0); down = max(translation, 0)
    return -280 * (1 - math.exp(-up / 280)) + 30 * (1 - math.exp(-down / 120))
def dome_offset(t):
    if V3_PASS <= t < V3_DOME_AGAIN:
        start = lift(drag_translation(V3_PASS))
        return start + (DOME_GONE - start) * spring(0.7, 0.92, t - V3_PASS)
    shown_at = V3_DOME_AGAIN if t >= V3_DOME_AGAIN else V3_DOME
    offset = DOME_HIDDEN * (1 - spring(0.8, 0.8, t - shown_at))
    if V3_DRAG <= t < V3_PASS: offset += lift(drag_translation(t))
    return offset
def hint_opacity(t):
    if V3_PASS <= t < V3_DOME_AGAIN: return 1 - ease((t - V3_PASS) / 0.2)
    shown_at = V3_DOME_AGAIN if t >= V3_DOME_AGAIN else V3_DOME
    return ease((t - shown_at - 0.5) / 0.6)
def gate_shade(t):
    if t < V3_PASS: return 1 - (1 - min(t / V3_COVER, 1)) ** 2
    if t < V3_SETTLE: return 1 - ease((t - V3_PASS) / 0.7)
    return ease((t - V3_SETTLE) / 1.3)

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

# ---- copy ----
def headline_at(t):
    """(key, since) of the headline showing at t, and (key, gone at) of the one before it."""
    events = [(V3_SPACE_TEXT, "space"), (V3_BLOOM, "meet")] + [(tt, f"focus{i}" if i else "meet") for tt, i in TAPS] + [(V3_CONTINUE, None)]
    current, previous = (None, 0.0), (None, 0.0)
    for start, key in events:
        if t >= start: previous, current = (current[0], start), (key, start)
    return current, previous
def headline_lines(key):
    """The lines, and how many of them are the title."""
    if key == "space": return [("Everyone you love,", INK), ("in one orbit.", INK)], 2
    if key == "meet": return [("Meet Orbit.", INK), ("Your friends, always", INK2), ("within reach.", INK2)], 1
    i = int(key[5:])
    return [(f"{NAMES[i]}'s orbit.", INK), (f"This week in {CITIES[i]}.", INK2), ("Tap Earth to come back.", INK2)], 1

# ---- drawing ----
f = lambda w, s: ImageFont.truetype(os.path.join(fonts, f"nunito-{w}.ttf"), int(s * S))
head_font, button_font, legal_font, note_font, hint_font = f(700, 27), f(700, 17), f(400, 12), f(600, 13), f(700, 15)
photos = {i: Image.open(os.path.join(assets, f"friend-{i}.imageset/friend-{i}.jpg")).convert("RGB").resize((360, 360), Image.LANCZOS)
          for i in range(1, 10)}
for i in MOMENTS:
    friend, n = moment_of(i)
    path = os.path.join(assets, f"moment-{friend}-{n}.imageset/moment-{friend}-{n}.jpg")
    photos[i] = (Image.open(path).convert("RGB").resize((360, 360), Image.LANCZOS) if os.path.exists(path)
                 else Image.new("RGB", (360, 360), (90, 110, 120)))

def put_text(img, x, y, line, font, color, alpha):
    """Text at `alpha`, through a mask: Pillow's RGBA drawing ignores a fill's alpha for text."""
    if alpha <= 0.002: return
    x0, y0, x1, y1 = [int(v) for v in ImageDraw.Draw(img).textbbox((x, y), line, font=font)]
    x0 -= 2; y0 -= 2; x1 += 2; y1 += 2
    mask = Image.new("L", (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(mask).text((x - x0, y - y0), line, font=font, fill=int(255 * min(alpha, 1)))
    img.paste(Image.new("RGB", mask.size, color[:3]), (x0, y0), mask)

def shadowed_text(img, x, y, line, font, alpha):
    """White text with a soft dark shadow, as the gate's hint has over the bright city."""
    if alpha <= 0.002: return
    x0, y0, x1, y1 = [int(v) for v in ImageDraw.Draw(img).textbbox((x, y), line, font=font)]
    pad = 14 * S
    mask = Image.new("L", (x1 - x0 + 2 * pad, y1 - y0 + 2 * pad), 0)
    ImageDraw.Draw(mask).text((x - x0 + pad, y - y0 + pad + S), line, font=font, fill=255)
    shadow = mask.filter(ImageFilter.GaussianBlur(5 * S)).point(lambda v: int(v * 0.45 * alpha))
    img.paste(Image.new("RGB", mask.size, (0, 0, 0)), (x0 - pad, y0 - pad), shadow)
    put_text(img, x, y, line, font, (255, 255, 255), alpha)

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

def photo_radius(b):                                                  # WorldPhoto.radius(for:)
    _, _, _, r, _, leaving, full, appearing, _ = b
    glass_to_photo = lambda g: g - min(5, g * 0.15)
    if not (appearing or leaving): return glass_to_photo(r)
    if full <= 0.5: return 0
    return glass_to_photo(full) * min(max((r / full - 0.3) / 0.7, 0), 1.12)

def pin_edge(b):                                                      # WorldPhoto.pinEdge(for:)
    _, _, _, r, _, _, full, appearing, vanishing = b
    return min(max((24 - (full if appearing or vanishing else r)) / 8, 0), 1)

gy_, gx_ = np.mgrid[0:H * S, 0:W * S].astype(np.float32)
PX, PY = (gx_ + 0.5) / S, (gy_ + 0.5) / S
GX = (PX % 18) - 9; GY = (PY % 18) - 9
DOTS = np.clip(1.0 - np.hypot(GX, GY) / 0.9, 0, 1)
FOCUS = pt(*HUB)
FALL = 1 - np.minimum(np.hypot(PX - FOCUS[0], PY - FOCUS[1]) / (max(W, H) * 0.62), 1)
# The city's stand-in: a bright sky over warm stone, so the dome's glass has something to show.
_v = (PY / H)[..., None]
CITY_RGB = (np.array([0.80, 0.86, 0.92]) * (1 - _v) + np.array([0.55, 0.52, 0.47]) * _v)
SHADE = np.maximum(0.32 * np.clip(1 - PY / 130, 0, 1), 0.34 * np.clip((PY - H * 0.58) / (H * 0.42), 0, 1))

def grid_opacity(t):
    return fade(t, V3_BLOOM, 1.0) * (1 - fade(t, V3_CONTINUE, 0.8))

rows = defaultdict(list)
with open(frames_csv) as fh:
    for r in csv.DictReader(fh):
        rows[int(r["frame"])].append((int(r["id"]), float(r["x"]), float(r["y"]), float(r["r"]), float(r["depth"]),
                                      r["leaving"] == "1", float(r["full"]), r["appearing"] == "1", r["vanishing"] == "1"))
positions = {fi: {b[0]: b for b in bs} for fi, bs in rows.items()}

for fi in sorted(rows):
    if ONLY and fi not in ONLY: continue
    t = fi / FPS
    bubbles = positions[fi]
    rgb = np.ones((H * S, W * S, 3)) * CANVAS
    rgb = rgb + (DOTS * FALL * 0.11 * grid_opacity(t))[..., None]
    u = progress(t)
    stack = stack_opacity(t, u)
    labels = []
    # the city, under its cover at first
    if u is None or (stack < 1 and u < 0.2):
        cover = 1 - (1 - min(t / V3_COVER, 1)) ** 2 if t < V3_ZOOM else 1.0
        rgb = CANVAS + (CITY_RGB - CANVAS) * cover
        labels.append(("stand-in: MapKit's 3D Paris, the Eiffel Tower", 0.5 * H, (40, 40, 48)))
    # the flat snapshots (stand-in: the real Earth's colours on the globe, which they match)
    if u is not None and stack > 0:
        s = zscale(u)
        dist = 1 + s * FOCAL / EARTH_RADIUS; radius = FOCAL / math.sqrt(dist * dist - 1)
        srgb, sa = holo.globe(PX, PY, SCREEN_CENTER[0], SCREEN_CENTER[1], radius, dist, CITY[0], CITY[1], roll=roll_at(u),
                              glow=0, palette=PALETTE, satellite=1)
        rgb = rgb * (1 - stack) + (srgb + rgb * (1 - sa[..., None])) * stack
    if u is not None and 0 < u < 1 and zscale(u) < DISSOLVE_FROM:
        labels.append(("stand-in: satellite snapshots", 0.12 * H, (230, 230, 235)))
    # the gate's shade over the city
    shade = gate_shade(t)
    if shade > 0.001: rgb = rgb * (1 - (SHADE * shade)[..., None])
    # the glass (the outline it has before iOS 26): a ring for everyone, a neck from the middle
    shown = [b for b in bubbles.values() if b[3] > 0.5 and (b[0] == 0 or has_photo(b[0]))]
    glass = Image.new("L", (W * S * 2, H * S * 2), 0); gd = ImageDraw.Draw(glass); q = S * 2
    if shown:
        hub = max(shown, key=lambda b: b[3])
        hc = pt(hub[1], hub[2]); hr = hub[3] * SCALE
        for b in shown:
            c = pt(b[1], b[2]); r = b[3] * SCALE
            gd.ellipse(((c[0] - r) * q, (c[1] - r) * q, (c[0] + r) * q, (c[1] + r) * q), fill=255)
            if b[0] != hub[0]:
                n = neck(hc, hr, c, r)
                if n: gd.polygon([(x * q, y * q) for x, y in n], fill=255)
    gm8 = glass.resize((W * S, H * S), Image.LANCZOS)
    gm = np.asarray(gm8, np.float32) / 255
    if gm.max() > 0:
        inner = np.asarray(gm8.filter(ImageFilter.MinFilter(3)), np.float32) / 255
        rim = np.clip(gm - inner, 0, 1)
        rgb = rgb * (1 - gm[..., None]) + np.array(GLASS) / 255 * gm[..., None]
        rgb = rgb + (rim * 0.14)[..., None]
    # the globe: on its path, else inside Earth's glass wherever Earth is
    g = None
    if u is not None and u < 1:
        g = globe_on_path(u, lon_at(t))
    elif u is not None:
        g = dict(cx=REST["center"][0], cy=REST["center"][1], radius=REST["radius"], dist=REST["distance"],
                 lat=REST["lat"], lon=lon_at(t), roll=0, glow=1, opacity=1, satellite=0)
        e = bubbles.get(0)
        if e and e[3] > 0.5:
            g["cx"], g["cy"] = pt(e[1], e[2])
            glass_r = e[6] if (e[7] or e[8]) else e[3]
            g["radius"] = glass_r * GLOBE_R / HUB_R * SCALE
    # photos melting back into Earth slip under the globe (but over the glass)
    leaving = sorted((b for b in bubbles.values() if has_photo(b[0]) and b[3] > 0.5 and b[5] and not b[7]), key=lambda b: b[4])
    if any(photo_radius(b) >= 0.25 for b in leaving):
        under = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
        for b in leaving:
            pr = photo_radius(b)
            if pr >= 0.25: disc(under, photos[b[0]], pt(b[1], b[2]), pr * SCALE, pin_edge(b))
        rgb = np.asarray(under, np.float32) / 255
    if g is not None and g["opacity"] > 0:
        reach = g["radius"] * 3
        x0 = max(int((g["cx"] - reach) * S), 0); x1 = min(int((g["cx"] + reach) * S) + 1, W * S)
        y0 = max(int((g["cy"] - reach) * S), 0); y1 = min(int((g["cy"] + reach) * S) + 1, H * S)
        if x1 > x0 and y1 > y0:
            grgb, ga = holo.globe(PX[y0:y1, x0:x1], PY[y0:y1, x0:x1], g["cx"], g["cy"], g["radius"], g["dist"], g["lat"], g["lon"],
                                  roll=g["roll"], glow=g["glow"], opacity=g["opacity"], time=t,
                                  palette=PALETTE, satellite=g["satellite"])
            rgb[y0:y1, x0:x1] = grgb + rgb[y0:y1, x0:x1] * (1 - ga[..., None])
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
    for text, y, col in labels:
        put_text(img, 40 * S, y * S, text, note_font, col, 0.8)
    # photos, on top of the globe; budding, they form on top (the ones melting away are drawn above)
    order = sorted((b for b in bubbles.values() if has_photo(b[0]) and b[3] > 0.5 and (b[7] or not b[5])),
                   key=lambda b: (1000 + b[4]) if b[7] else b[4])
    for b in order:
        pr = photo_radius(b)
        if pr < 0.25: continue
        disc(img, photos[b[0]], pt(b[1], b[2]), pr * SCALE, pin_edge(b))
    # the copy: the old headline fades out as the new one eases in, title first
    d = ImageDraw.Draw(img)
    top = H / 2 + COPY_TOP * SCALE
    (key, start), (old, went) = headline_at(t)
    for k, alpha_of in [(old, lambda j, tl: 1 - ease((t - went) / 0.35)),
                        (key, lambda j, tl: ease((t - start - (0.2 if j < tl else 0.45)) / 0.6))]:
        if k is None: continue
        lines, title_lines = headline_lines(k)
        y = top
        for j, (line, col) in enumerate(lines):
            tw = d.textlength(line, font=head_font)
            put_text(img, (W * S - tw) / 2, (y + 2) * S, line, head_font, col, alpha_of(j, title_lines))
            y += 34 + (4 if j == title_lines - 1 else 0)
    # the buttons
    fa = fade(t, V3_FOOTER, 0.6) * (1 - fade(t, V3_CONTINUE, 0.4))
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
    # the gate: the dome of glass (frosted here) and its hint
    offset = dome_offset(t)
    dome_cy = DOME_TOP + DOME_R + offset
    if dome_cy - DOME_R < H and dome_cy + DOME_R > 0 and (t < V3_PASS + 1.4 or t >= V3_DOME_AGAIN):
        box = (int((W / 2 - DOME_R) * S), int((dome_cy - DOME_R) * S), int((W / 2 + DOME_R) * S), int((dome_cy + DOME_R) * S))
        big = Image.new("L", ((box[2] - box[0]) * 2, (box[3] - box[1]) * 2), 0)
        ImageDraw.Draw(big).ellipse((0, 0, big.size[0] - 1, big.size[1] - 1), fill=255)
        mask = big.resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS)
        frosted = img.filter(ImageFilter.GaussianBlur(10 * S))
        frosted = Image.blend(frosted, Image.new("RGB", img.size, (255, 255, 255)), 0.10)
        canvas = Image.new("L", img.size, 0); canvas.paste(mask, box[:2])
        img.paste(frosted, (0, 0), canvas)
        # window light along the top rim, fading by the middle
        rim = Image.new("L", big.size, 0)
        ImageDraw.Draw(rim).ellipse((0, 0, big.size[0] - 1, big.size[1] - 1), outline=255, width=int(3 * S))
        rim = np.asarray(rim.resize(mask.size, Image.LANCZOS), np.float32)
        ramp = np.clip(1 - np.linspace(0, 1, mask.size[1]) * 2, 0, 1)[:, None] * 0.6
        rim_canvas = Image.new("L", img.size, 0); rim_canvas.paste(Image.fromarray((rim * ramp).astype(np.uint8)), box[:2])
        img.paste(Image.new("RGB", img.size, (255, 255, 255)), (0, 0), rim_canvas)
        ha = hint_opacity(t)
        if ha > 0.002:
            # like Wabi's: the words on the glass, under a soft rounded handle that lifts now and then
            hy = DOME_TOP + offset + 58
            cy = hy - 15.5 - nudge(t)
            handle = Image.new("L", img.size, 0)
            ImageDraw.Draw(handle).rounded_rectangle(((W / 2 - 18) * S, (cy - 2.5) * S, (W / 2 + 18) * S, (cy + 2.5) * S),
                                                     radius=2.5 * S, fill=int(255 * 0.75 * ha))
            img.paste(Image.new("RGB", img.size, (255, 255, 255)), (0, 0), handle)
            line = "Swipe up to enter"
            tw = ImageDraw.Draw(img).textlength(line, font=hint_font)
            shadowed_text(img, (W * S - tw) / 2, (hy - 1) * S, line, hint_font, ha * 0.92)
    # the finger: the swipe, the taps on Zoe, Earth, Kai and Earth, and "Continue with Apple"
    touches = []
    if V3_DRAG - 0.1 <= t <= V3_PASS + 0.15:
        a = min(fade(t, V3_DRAG - 0.1, 0.1), 1 - fade(t, V3_PASS, 0.15))
        touches.append((W / 2, DOME_TOP + 70 + drag_translation(min(t, V3_PASS)), a))
    for tt, who in TAPS + [(V3_CONTINUE, None)]:
        if tt - 0.2 <= t <= tt + 0.25:
            a = min(fade(t, tt - 0.2, 0.1), 1 - fade(t, tt + 0.1, 0.15))
            if who is None:
                touches.append((W / 2, 874 - 34 - 8 - 18 - 6 - 12 - 54 - 66 + 27, a))
            else:
                b = positions[int(round((tt - 0.05) * FPS))].get(who)
                if b: touches.append((*pt(b[1], b[2]), a))
    for x, y, a in touches:
        layer = Image.new("L", img.size, 0)
        ImageDraw.Draw(layer).ellipse(((x - 20) * S, (y - 20) * S, (x + 20) * S, (y + 20) * S), fill=int(95 * a))
        img.paste(Image.new("RGB", img.size, (255, 255, 255)), (0, 0), layer)
        ring = Image.new("L", img.size, 0)
        ImageDraw.Draw(ring).ellipse(((x - 20) * S, (y - 20) * S, (x + 20) * S, (y + 20) * S), outline=int(200 * a), width=int(1.5 * S))
        img.paste(Image.new("RGB", img.size, (255, 255, 255)), (0, 0), ring)
    img.save(f"{out_dir}/f_{fi:04d}.png")
print("done")
