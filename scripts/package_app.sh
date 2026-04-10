#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacClipper"
BUILD_DIR="$ROOT/.build/release"
DIST_DIR="$ROOT/dist/$APP_NAME.app"
EXECUTABLE="$BUILD_DIR/$APP_NAME"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/AppResources/Info.plist")"

find_sparkle_framework() {
  local candidates=()

  if [[ -d "$ROOT/.build/arm64-apple-macosx/release/Sparkle.framework" ]]; then
    candidates+=("$ROOT/.build/arm64-apple-macosx/release/Sparkle.framework")
  fi

  if [[ -d "$ROOT/.build/release/Sparkle.framework" ]]; then
    candidates+=("$ROOT/.build/release/Sparkle.framework")
  fi

  if [[ -d "$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]]; then
    candidates+=("$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework")
  fi

  if (( ${#candidates[@]} == 0 )); then
    local discovered
    discovered="$(find "$ROOT/.build" -path '*/Sparkle.framework' -type d | head -n 1)"
    if [[ -n "$discovered" ]]; then
      candidates+=("$discovered")
    fi
  fi

  if (( ${#candidates[@]} == 0 )); then
    echo "Unable to locate Sparkle.framework after build." >&2
    return 1
  fi

  printf '%s\n' "${candidates[1]}"
}

cd "$ROOT"
swift "$ROOT/scripts/generate_app_icon.swift"
swift build -c release

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/Contents/MacOS" "$DIST_DIR/Contents/Resources" "$DIST_DIR/Contents/Frameworks"
cp "$EXECUTABLE" "$DIST_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/AppResources/Info.plist" "$DIST_DIR/Contents/Info.plist"
cp "$ROOT/AppResources/AppIcon.icns" "$DIST_DIR/Contents/Resources/AppIcon.icns"

SPARKLE_FRAMEWORK="$(find_sparkle_framework)"
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$DIST_DIR/Contents/Frameworks/Sparkle.framework"

chmod +x "$DIST_DIR/Contents/MacOS/$APP_NAME"

SIGNING_IDENTITY="${MACCLIPPER_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$DIST_DIR"
  echo "Built and signed $DIST_DIR with $SIGNING_IDENTITY"
else
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" --requirements "=designated => identifier \"$BUNDLE_ID\"" "$DIST_DIR"
  echo "Built and ad-hoc signed $DIST_DIR with stable identifier $BUNDLE_ID"
fi
