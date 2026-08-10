#!/bin/bash
# Builds a drag-to-Applications disk image.
# Usage: scripts/make-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="HMCL Launcher"
VOLUME="HMCL Launcher"
APP="$ROOT/build/$APP_NAME.app"
DIST="$ROOT/dist"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Resources/Info.plist")"
DMG="$DIST/HMCL-Launcher-$VERSION.dmg"

cd "$ROOT"
"$ROOT/scripts/build-app.sh" release

echo "==> staging"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$DIST"
rm -f "$DMG"

echo "==> creating writable image"
RW="$STAGE/../rw-$$.dmg"
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLUME" \
  -fs HFS+ -format UDRW -ov "$RW"

echo "==> mounting"
MOUNT_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW")"
DEVICE="$(echo "$MOUNT_OUT" | grep '^/dev/' | head -1 | awk '{print $1}')"
MOUNTPOINT="/Volumes/$VOLUME"

# Icon positions and window size are stored in the volume's .DS_Store, and only
# Finder writes that. Scripting Finder needs Automation permission, which a
# fresh machine or a CI runner will not have — so this is best effort. Without
# it you still get a working image with the app and an Applications shortcut,
# just in the default list view.
echo "==> arranging window (needs Finder automation permission)"
if osascript <<APPLESCRIPT 2>/dev/null
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 150, 800, 520}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set position of item "$APP_NAME.app" of container window to {150, 190}
    set position of item "Applications" of container window to {450, 190}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT
then
  echo "    window arranged"
else
  echo "    skipped: no Finder automation permission, image still works"
fi

sync
echo "==> detaching"
hdiutil detach "$DEVICE" -quiet || hdiutil detach "$DEVICE" -force -quiet

echo "==> compressing"
hdiutil convert "$RW" -quiet -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW"

echo "==> built $DMG"
echo "    $(du -h "$DMG" | cut -f1)"
