#!/usr/bin/env bash
# Renders a motion preview of the onboarding from the run recorded by tools/engine/run.sh.
# Needs python3 with Pillow and NumPy, plus ffmpeg and curl.
#
#   tools/preview/run.sh                         # video: build/preview/onboarding-preview.mp4
#   FRAMES=75,175,300,420 tools/preview/run.sh   # just those frames, as PNGs in build/preview/frames
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=build/preview
FONTS=$OUT/fonts
mkdir -p "$FONTS"

# Nunito stands in for SF Pro Rounded, which can't be downloaded.
if [[ ! -f $FONTS/nunito-700.ttf ]]; then
  curl -sS -A "Mozilla/4.0" "https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700" \
    | python3 -c 'import re, sys; [print(w, u) for w, u in re.findall(r"font-weight: (\d+);\s*src: url\((https://[^)]+)\)", sys.stdin.read())]' \
    | while read -r weight url; do curl -sS -o "$FONTS/nunito-$weight.ttf" "$url"; done
fi

# VERSION=v2 tools/preview/run.sh renders v2 (default v1).
VERSION="${VERSION:-v1}"
SUFFIX=$([[ $VERSION == v2 ]] && echo "-v2" || echo "")
rm -rf "$OUT/frames"
VERSION=$VERSION python3 tools/preview/render.py "build/engine/frames$SUFFIX.csv" "build/engine/threads$SUFFIX.csv" \
  Orbit/Assets.xcassets "$FONTS" "$OUT/frames"
if [[ -z "${FRAMES:-}" ]]; then
  ffmpeg -v error -y -framerate 30 -i "$OUT/frames/f_%04d.png" -vf "scale=600:-2,format=yuv420p" \
    -c:v libx264 -crf 19 -movflags +faststart "$OUT/onboarding-preview$SUFFIX.mp4"
  echo "Wrote $OUT/onboarding-preview$SUFFIX.mp4"
fi
