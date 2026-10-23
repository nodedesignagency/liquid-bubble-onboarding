# Rasterizes Natural Earth land polygons (public domain) into the equirectangular signed distance
# field v3's globe draws its continents from (`land-sdf` in the asset catalog, `holoGlobe` in
# Liquid.metal): 0.5 at the coast, brighter inland, darker at sea, 24 px from the coast to either end.
#
#   curl -o ne_10m_land.geojson https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_land.geojson
#   python3 tools/globe/landsdf.py ne_10m_land.geojson Orbit/Assets.xcassets/land-sdf.imageset/land-sdf.png
#
# Needs NumPy, Pillow and SciPy.
import json, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt
src, out = sys.argv[1], sys.argv[2]
W, H = 8192, 4096          # rasterized here, saved at half size
OW, OH = 4096, 2048
RANGE = 24.0               # output pixels from the coast to full black / white
geo = json.load(open(src))
mask = Image.new('L', (W, H), 0)
d = ImageDraw.Draw(mask)
def ring(coords):
    return [((lon + 180) / 360 * W, (90 - lat) / 180 * H) for lon, lat in coords]
for f in geo['features']:
    g = f['geometry']
    polys = g['coordinates'] if g['type'] == 'MultiPolygon' else [g['coordinates']]
    for poly in polys:
        d.polygon(ring(poly[0]), fill=255)
        for hole in poly[1:]:
            d.polygon(ring(hole), fill=0)
m = np.asarray(mask) > 127
# wrap horizontally so distances cross the date line
pad = 256
mw = np.concatenate([m[:, -pad:], m, m[:, :pad]], axis=1)
inside = distance_transform_edt(mw)[:, pad:-pad]
outside = distance_transform_edt(~mw)[:, pad:-pad]
sd = (inside - outside) * (OW / W)       # in output pixels, positive on land
img = Image.fromarray((np.clip(0.5 + sd / (2 * RANGE), 0, 1) * 255).round().astype(np.uint8))
img = img.resize((OW, OH), Image.LANCZOS)
# Calibration: two 4x4 blocks in the top-left corner (the Arctic Ocean, at the pole) hold 128 (the
# coast) and 140 (2.26 px inland), so the shader reads the coast level and scale from the texture
# itself, whatever colour conversion the image goes through on its way to the GPU.
a = np.asarray(img).copy()
a[0:4, 0:4] = 128
a[0:4, 4:8] = 140
Image.fromarray(a).save(out, optimize=True)
print('land fraction', m.mean())
