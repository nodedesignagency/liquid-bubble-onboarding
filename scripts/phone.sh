#!/usr/bin/env bash
# Gets the latest version, builds it and puts it on your iPhone, then opens it. No Xcode
# clicking: after an update Xcode loses the signing team, its Run fails, and the phone keeps the
# old build.
#
#   ./scripts/phone.sh                     # the iPhone plugged into this Mac (unlocked)
#   TEAM=ABCDE12345 ./scripts/phone.sh     # if it can't find your signing team
set -euo pipefail

cd "$(dirname "$0")/.."

BRANCH="claude/nice-cori-ypokiu"
BUNDLE_ID="com.nodedesign.orbit"
DERIVED_DATA="build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/Orbit.app"
UUID_PATTERN='[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'

echo "▸ Getting the latest version"
git fetch -q origin "$BRANCH"
git reset -q --hard "origin/$BRANCH"
echo "  $(git log --oneline -1)"

# Your team: the one in your Apple Development certificate (Xcode made it when you first ran on
# the phone), unless given.
TEAM="${TEAM:-}"
if [[ -z "$TEAM" ]]; then
  TEAM=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | grep -oE 'OU ?= ?[A-Z0-9]{10}' | grep -oE '[A-Z0-9]{10}$' | head -1 || true)
fi
if [[ -z "$TEAM" ]]; then
  echo "✗ Couldn't find your signing team. In Xcode: Settings > Accounts, pick your Apple ID and"
  echo "  copy the Team ID, then run:  TEAM=<that id> ./scripts/phone.sh"
  exit 1
fi

DEVICE=$(xcrun devicectl list devices 2>/dev/null | grep -i iphone | grep -vi unavailable \
  | grep -oE "$UUID_PATTERN" | head -1 || true)
if [[ -z "$DEVICE" ]]; then
  echo "✗ No iPhone found. Plug it in, unlock it, tap Trust if it asks, and run this again."
  exit 1
fi

echo "▸ Building for the iPhone (the first build takes a minute)"
LOG="build/xcodebuild-phone.log"
mkdir -p build
if ! xcodebuild \
  -project Orbit.xcodeproj \
  -scheme Orbit \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  build >"$LOG" 2>&1; then
  echo "✗ Build failed:"
  grep -E "error:" "$LOG" | sort -u | head -40
  echo "Full log: $LOG"
  exit 1
fi

echo "▸ Installing on the iPhone"
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null
echo "▸ Opening Orbit"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 \
  || echo "  (unlock the phone and open Orbit from the home screen)"
echo "✓ Build $(git log --format=%h -1) is on the iPhone"
