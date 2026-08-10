#!/bin/bash
# Assembles HMCL Launcher.app from the SwiftPM build product.
# Usage: scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="HMCL Launcher"
BUNDLE="$ROOT/build/$APP_NAME.app"

cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/HMCLLauncher"
[ -x "$BIN" ] || { echo "no executable at $BIN" >&2; exit 1; }

echo "==> assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$BIN" "$BUNDLE/Contents/MacOS/HMCLLauncher"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# Info.plist declares CFBundleIconFile, so regenerate the icon if it is missing.
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
  echo "==> generating icon"
  swift "$ROOT/scripts/make-icon.swift"
fi
cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"

# Apple Silicon refuses to execute code with no signature at all, so ad-hoc sign.
# Swap "-" for a Developer ID identity when you start notarizing.
echo "==> codesign (ad-hoc)"
codesign --force --deep --sign - "$BUNDLE"
codesign --verify --verbose=2 "$BUNDLE"

echo "==> built $BUNDLE"
