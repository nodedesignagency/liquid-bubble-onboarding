# Mirror of the `holoGlobe` shader (Orbit/Bubbles/Liquid.metal) in NumPy, for the preview tools.
# Keep the two in step: same camera (GlobeMath), same calibration, same colours.
import math
import numpy as np
from PIL import Image

_land = None

def load(path):
    global _land
    _land = np.asarray(Image.open(path), np.float32) / 255.0

def _sample(u, v):
    h, w = _land.shape
    x = (u * w - 0.5) % w
    y = np.clip(v * h - 0.5, 0, h - 1.001)
    x0 = np.floor(x).astype(int); y0 = np.floor(y).astype(int); fx = x - x0; fy = y - y0
    x1 = (x0 + 1) % w; y1 = y0 + 1
    return (_land[y0, x0] * (1 - fx) * (1 - fy) + _land[y0, x1] * fx * (1 - fy)
            + _land[y1, x0] * (1 - fx) * fy + _land[y1, x1] * fx * fy)

def _ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)

# GlobePalette's floats: sea top, sea bottom, rim, land, sheen A, B, C, aura, backlight (rgb each),
# then sheen amount and backlight strength. Keep in step with GlobePalette (HoloGlobe.swift).
def _hex(x): return [((x >> 16) & 255) / 255, ((x >> 8) & 255) / 255, (x & 255) / 255]
def palette(*hexes, sheen, backlight): return sum((_hex(x) for x in hexes), []) + [sheen, backlight]
DUSK = palette(0x222EB4, 0x5C49F5, 0xA88BFF, 0xEAE4FF, 0xBB73F7, 0xEFB0C3, 0x8CADEF, 0x7B4DF5, 0xDD92E2, sheen=0.55, backlight=1.1)
AFTERGLOW = palette(0x3A44E3, 0x8759F6, 0xDD92E2, 0xFFE9E4, 0xEFB0C3, 0xE7C69D, 0xDD92E2, 0xBB73F7, 0xE7C69D, sheen=0.8, backlight=1.2)
MIDNIGHT = palette(0x1A1F7A, 0x571768, 0xBB73F7, 0xCDBDFF, 0xDD92E2, 0x8759F6, 0x8CADEF, 0x9B3DF0, 0xC843DB, sheen=0.6, backlight=1.25)
LAVENDER = palette(0x5C49F5, 0xBB73F7, 0xEFB0C3, 0xFFF4FA, 0xEFB0C3, 0xFFFFFF, 0xDD92E2, 0x8759F6, 0xEFB0C3, sheen=0.5, backlight=0.9)

def globe(px, py, cx, cy, radius, dist, lat0, lon0, roll=0.0, holo=1.0, glow=1.0, opacity=1.0, time=0.0,
          palette=None, reveal=None):
    """Premultiplied rgb and alpha. Positions in points, angles in degrees. `reveal` is
    (x, y, radius, width): only inside that circle, with a glowing ring at its edge."""
    pal = np.array(palette if palette is not None else DUSK, float)
    col3 = lambda i: pal[i * 3:i * 3 + 3]
    ocean_top, ocean_bottom, rim_c, land_base = col3(0), col3(1), col3(2), col3(3)
    sheen_a, sheen_b, sheen_c, aura_c, back_c = col3(4), col3(5), col3(6), col3(7), col3(8)
    sheen_amount, back_strength = pal[27], pal[28]
    h, w = _land.shape
    coast = _sample(np.array(2.0 / w), np.array(2.0 / h)); inland = _sample(np.array(6.0 / w), np.array(2.0 / h))
    unit = 2.2588 / max(float(inland - coast), 1e-4)
    dist = max(dist, 1.0001); radius = max(radius, 1.0)
    rr = math.radians(roll); cr, sr = math.cos(rr), math.sin(rr)
    qx0, qy0 = px - cx, py - cy
    qx = qx0 * cr + qy0 * sr; qy = -qx0 * sr + qy0 * cr
    r = np.hypot(qx, qy)
    beyond = np.maximum(r - radius, 0)
    aura = glow * (0.42 * np.exp(-beyond / (0.30 * radius)) + 0.35 * np.exp(-beyond / (0.06 * radius)))
    edge = 1 - _ss(radius - 0.6, radius + 0.6, r)
    focal = radius * math.sqrt(dist * dist - 1)
    n = np.sqrt((qx / focal) ** 2 + (qy / focal) ** 2 + 1)
    dx, dy, dz = qx / focal / n, -qy / focal / n, -1 / n
    od = dist * dz
    disc = np.maximum(od * od - (dist * dist - 1), 0)
    t = -od - np.sqrt(disc)
    Px, Py, Pz = t * dx, t * dy, dist + t * dz
    Vx, Vy, Vz = -dx, -dy, -dz
    a = -math.radians(lat0); ca, sa = math.cos(a), math.sin(a)
    b = math.radians(lon0); cb, sb = math.cos(b), math.sin(b)
    y1 = Py * ca - Pz * sa; z1 = Py * sa + Pz * ca
    Ex = Px * cb + z1 * sb; Ey = y1; Ez = -Px * sb + z1 * cb
    lat = np.arcsin(np.clip(Ey, -1, 1)); lon = np.arctan2(Ex, Ez)
    u = (lon + math.pi) / (2 * math.pi); v = (math.pi / 2 - lat) / math.pi
    sd = (_sample(u, v) - coast) * unit
    L = np.array([-0.45, 0.55, 0.70]); L = L / np.linalg.norm(L)
    ndl = Px * L[0] + Py * L[1] + Pz * L[2]
    Ltx, Lty, Ltz = L[0] - ndl * Px, L[1] - ndl * Py, L[2] - ndl * Pz
    ty1 = Lty * ca - Ltz * sa; tz1 = Lty * sa + Ltz * ca
    Tx = Ltx * cb + tz1 * sb; Ty = ty1; Tz = -Ltx * sb + tz1 * cb
    east = Tx * np.cos(lon) - Tz * np.sin(lon)
    north = -Tx * np.sin(lat) * np.sin(lon) + Ty * np.cos(lat) - Tz * np.sin(lat) * np.cos(lon)
    k = 5.0 / w
    du = east / np.maximum(np.cos(lat), 0.2) * k; dv = -north * k * 2
    toward = (_sample(u + du, v + dv) - coast) * unit
    away = (_sample(u - du, v - dv) - coast) * unit
    ndv = np.clip(Px * Vx + Py * Vy + Pz * Vz, 1e-3, 1)
    tex = (w / (2 * math.pi)) * (dist - 1) / focal / ndv
    wid = np.maximum(tex * 0.8, 0.35)
    land = _ss(-wid, wid, sd)
    fres = (1 - ndv) ** 3
    # the sea: a top-to-bottom gradient across the globe, brighter toward the limb
    vt = np.clip(0.5 - 0.5 * Py, 0, 1)[..., None]
    ocean = ocean_top + (ocean_bottom - ocean_top) * vt
    ocean = ocean + (0.18 * fres)[..., None] * rim_c
    ocean = ocean * (0.75 + 0.35 * np.clip(ndl, 0, 1))[..., None]
    phase = 1.3 * (1 - ndv) + 0.5 * Ex + 0.35 * Ey + 0.06 * time
    w4 = (0.5 + 0.5 * np.sin(2 * math.pi * phase))[..., None]
    w5 = (0.5 + 0.5 * np.sin(2 * math.pi * (phase * 0.7 + 0.31)))[..., None]
    sheen = sheen_c + (sheen_a - sheen_c) * w4
    sheen = sheen + (sheen_b - sheen) * (1 - w5)
    landc = land_base + (sheen - land_base) * sheen_amount * holo
    lit = _ss(0, 4, sd) * (1 - _ss(-2, 2, away))
    shade = _ss(0, 4, sd) * (1 - _ss(-2, 2, toward))
    landc = landc * (0.70 + 0.34 * np.clip(ndl, 0, 1))[..., None] + (0.22 * lit - 0.16 * shade)[..., None]
    shadow = (1 - land) * _ss(-1, 3, toward) * 0.55
    ocean = ocean * (1 - shadow)[..., None]
    c = ocean + (landc - ocean) * land[..., None]
    Rx, Ry, Rz = 2 * ndl * Px - L[0], 2 * ndl * Py - L[1], 2 * ndl * Pz - L[2]
    spec = np.clip(Rx * Vx + Ry * Vy + Rz * Vz, 0, 1) ** 40
    c = c + (0.22 * spec * (1 - land))[..., None] * np.array([0.85, 0.9, 1.0])
    c = c + (0.55 * fres)[..., None] * rim_c
    # a warm glow from below on the limb, away from the key light
    Bl = np.array([0.25, -0.85, -0.2]); Bl = Bl / np.linalg.norm(Bl)
    back = np.clip(Px * Bl[0] + Py * Bl[1] + Pz * Bl[2], 0, 1) ** 2 * (1 - ndv) ** 1.5
    c = c + (back_strength * back)[..., None] * back_c
    c = np.clip(c, 0, 1)
    rgb = c * edge[..., None] + aura_c * (aura * (1 - edge))[..., None]
    alpha = np.maximum(edge, np.clip(aura, 0, 1))
    if reveal is not None:
        rx, ry, rr, rw = reveal
        dr = np.hypot(px - rx, py - ry)
        inside = 1 - _ss(rr - rw, rr, dr)
        ring = np.exp(-((dr - rr + rw * 0.5) / (rw * 0.45)) ** 2) * (rr < 1e5)
        rgb = rgb * inside[..., None] + (0.9 * ring)[..., None] * np.array([0.80, 0.82, 1.0])
        alpha = np.maximum(alpha * inside, np.clip(0.9 * ring, 0, 1))
    return rgb * opacity, alpha * opacity
