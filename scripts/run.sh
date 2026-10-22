#!/usr/bin/env bash
# Builds Orbit and launches it in the iOS Simulator.
#
#   ./scripts/run.sh                  # uses the booted simulator, or the newest iPhone
#   ./scripts/run.sh "iPhone 16 Pro"  # uses a specific simulator
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="com.nodedesign.orbit"
DERIVED_DATA="build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Orbit.app"
UUID_PATTERN='[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild isn't pointing at Xcode. Install Xcode 16 or later, then run:"
  echo "  sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi

# Pick a simulator: the one asked for, else the one already booted, else the newest iPhone.
if [[ $# -gt 0 ]]; then
  DEVICE_ID=$(xcrun simctl list devices available | grep -F "$1 (" | grep -oE "$UUID_PATTERN" | tail -1 || true)
else
  DEVICE_ID=$(xcrun simctl list devices booted | grep -E '^ +iPhone' | grep -oE "$UUID_PATTERN" | head -1 || true)
  if [[ -z "$DEVICE_ID" ]]; then
    DEVICE_ID=$(xcrun simctl list devices available | grep -E '^ +iPhone' | grep -oE "$UUID_PATTERN" | tail -1 || true)
  fi
fi
if [[ -z "$DEVICE_ID" ]]; then
  echo "No matching iPhone simulator. See what's installed with: xcrun simctl list devices available"
  exit 1
fi

echo "▸ Booting simulator"
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
open -a Simulator

echo "▸ Building (the first build takes a minute)"
LOG="build/xcodebuild.log"
mkdir -p build
if ! xcodebuild \
  -project Orbit.xcodeproj \
  -scheme Orbit \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  build >"$LOG" 2>&1; then
  echo "✗ Build failed:"
  grep -E "error:" "$LOG" | sort -u | head -40
  echo "Full log: $LOG"
  exit 1
fi

echo "▸ Installing and launching"
xcrun simctl install "$DEVICE_ID" "$APP"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" >/dev/null
echo "✓ Orbit is running in the Simulator"
