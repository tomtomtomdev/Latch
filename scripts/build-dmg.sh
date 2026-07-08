#!/usr/bin/env bash
#
# build-dmg.sh — build an unsigned Latch.app and package it into a DMG.
#
# Usage:
#   scripts/build-dmg.sh [output-dir]
#
# Produces:  <output-dir>/Latch-<version>.dmg   (defaults to ./build)
#
# Unsigned: code signing is disabled so this runs without a Developer ID.
# Recipients must right-click → Open (or clear the quarantine flag) since the
# app is neither signed nor notarized.

set -euo pipefail

# --- config -----------------------------------------------------------------
PROJECT="Latch.xcodeproj"
SCHEME="Latch"
CONFIG="Release"
APP_NAME="Latch"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/build}"
DERIVED="$OUT_DIR/DerivedData"
STAGE="$OUT_DIR/dmg-stage"

cd "$ROOT_DIR"

# --- build ------------------------------------------------------------------
echo "▸ Building $SCHEME ($CONFIG, unsigned)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build

APP_PATH="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "✗ Build product not found at: $APP_PATH" >&2
  exit 1
fi

# --- version (for the dmg filename) ----------------------------------------
PLIST="$APP_PATH/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || echo 0.0.0)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null || echo 0)"
DMG_PATH="$OUT_DIR/${APP_NAME}-${VERSION}(${BUILD}).dmg"

# --- stage ------------------------------------------------------------------
echo "▸ Staging DMG contents…"
rm -rf "$STAGE" "$DMG_PATH"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# --- package ----------------------------------------------------------------
echo "▸ Creating DMG…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH"

rm -rf "$STAGE"

echo "✓ $DMG_PATH"
