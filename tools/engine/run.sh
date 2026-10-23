#!/usr/bin/env bash
# Type-checks and tests the animation engine and choreography with any Swift toolchain (Linux
# included, no Xcode needed), then records a scripted run for tools/preview/run.sh.
#
#   SWIFTC=/path/to/swiftc tools/engine/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

SWIFTC="${SWIFTC:-swiftc}"
WORK=build/engine
rm -rf "$WORK" && mkdir -p "$WORK/checks" "$WORK/record"

# The engine only touches SwiftUI for Color, which Shim.swift stands in for.
for f in Orbit/Bubbles/BubbleEngine.swift Orbit/Bubbles/OrbitChoreography.swift Orbit/Bubbles/SpringCurve.swift; do
  sed 's/^import SwiftUI$/import Foundation/; s/^import CoreGraphics$/import Foundation/' "$f" > "$WORK/$(basename "$f")"
done
ENGINE=("$WORK/BubbleEngine.swift" "$WORK/OrbitChoreography.swift" "$WORK/SpringCurve.swift" tools/engine/Shim.swift)

# Top-level code has to live in a file called main.swift.
cp tools/engine/checks.swift "$WORK/checks/main.swift"
cp tools/engine/record.swift "$WORK/record/main.swift"

"$SWIFTC" -swift-version 5 -O "${ENGINE[@]}" "$WORK/checks/main.swift" -o "$WORK/checks/checks"
"$WORK/checks/checks"
"$SWIFTC" -swift-version 5 -O "${ENGINE[@]}" "$WORK/record/main.swift" -o "$WORK/record/record"
"$WORK/record/record" "$WORK/frames.csv" "$WORK/threads.csv" v1
"$WORK/record/record" "$WORK/frames-v2.csv" "$WORK/threads-v2.csv" v2
"$WORK/record/record" "$WORK/frames-v3.csv" "$WORK/threads-v3.csv" v3
echo "Recorded $WORK/frames.csv and $WORK/threads.csv (v1), $WORK/frames-v2.csv (v2), $WORK/frames-v3.csv (v3)"
