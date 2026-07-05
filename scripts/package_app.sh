#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Vessel"
VERSION="0.1.0"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

cd "$ROOT_DIR"

swift build -c release

rm -rf "$APP_BUNDLE" "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$DMG_ROOT"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Packaging/Assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"

cp -R "$APP_BUNDLE" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign --verify --deep --strict "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE" || true

echo "Built app: $APP_BUNDLE"
echo "Built dmg: $DMG_PATH"
