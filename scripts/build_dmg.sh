#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacClipper"
VOL_NAME="MacClipper Installer"
DIST_DIR="$ROOT/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
FINAL_DMG="$DIST_DIR/$APP_NAME.dmg"
TEMP_DMG="$DIST_DIR/$APP_NAME-temp.dmg"
STAGING_DIR="$DIST_DIR/dmg-staging"
BACKGROUND_NAME="dmg-background.png"

cd "$ROOT"
"$ROOT/scripts/package_app.sh"
swift "$ROOT/scripts/generate_dmg_background.swift"

rm -rf "$STAGING_DIR" "$TEMP_DMG" "$FINAL_DMG"
mkdir -p "$STAGING_DIR/.background"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$ROOT/AppResources/$BACKGROUND_NAME" "$STAGING_DIR/.background/$BACKGROUND_NAME"

hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGING_DIR" -fs HFS+ -format UDRW -ov "$TEMP_DMG" >/dev/null

MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG")
DEVICE=$(echo "$MOUNT_OUTPUT" | awk '/Apple_HFS/ {print $1}')
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | sed -n 's#.*\(/Volumes/.*\)#\1#p' | tail -n 1)

if [[ -z "$DEVICE" || -z "$MOUNT_POINT" ]]; then
  echo "Failed to mount temporary DMG"
  exit 1
fi

APPLESCRIPT=$(cat <<EOF
 tell application "Finder"
   tell disk "$VOL_NAME"
     open
     set current view of container window to icon view
     set toolbar visible of container window to false
     set statusbar visible of container window to false
    set bounds of container window to {120, 120, 1320, 840}
     set viewOptions to the icon view options of container window
     set arrangement of viewOptions to not arranged
     set icon size of viewOptions to 128
     set text size of viewOptions to 14
     set background picture of viewOptions to file ".background:$BACKGROUND_NAME"
     set position of item "$APP_NAME.app" of container window to {240, 300}
     set position of item "Applications" of container window to {720, 300}
     update without registering applications
     delay 1
     close
     open
     delay 1
   end tell
 end tell
EOF
)

osascript -e "$APPLESCRIPT" >/dev/null || true
sync
sleep 2
hdiutil detach "$DEVICE" >/dev/null
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$FINAL_DMG" >/dev/null
rm -f "$TEMP_DMG"
rm -rf "$STAGING_DIR"

echo "Built $FINAL_DMG"
