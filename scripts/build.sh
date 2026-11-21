#!/bin/zsh
# Builds build/ClaudeWindow.app (universal: Apple silicon + Intel).
#
#   scripts/build.sh            build the app
#   scripts/build.sh --dmg      also make dist/ClaudeWindow-<version>.dmg
#   scripts/build.sh --install  also copy it to /Applications and open it
#
# Signing: ad-hoc by default. Set SIGN_IDENTITY="Developer ID Application: …"
# to sign for distribution (then notarize the DMG with notarytool).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=ClaudeWindow
BUILD=build
APP="$BUILD/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
SOURCES=(Sources/$APP_NAME/*.swift)
MIN_OS=14.0

echo "▸ Compiling $APP_NAME $VERSION"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/obj"
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$ARCH-apple-macos$MIN_OS" \
    -module-name $APP_NAME "${SOURCES[@]}" -o "$BUILD/obj/$APP_NAME-$ARCH"
done
lipo -create "$BUILD/obj/$APP_NAME-arm64" "$BUILD/obj/$APP_NAME-x86_64" -output "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: drawn by the app itself so it always matches the design.
if [[ ! -f Resources/AppIcon.icns || "${REDRAW_ICON:-}" == 1 ]]; then
  echo "▸ Drawing app icon"
  ICONSET="$BUILD/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  "$APP/Contents/MacOS/$APP_NAME" --render-icon "$BUILD/icon-1024.png"
  for S in 16 32 128 256 512; do
    sips -z $S $S "$BUILD/icon-1024.png" --out "$ICONSET/icon_${S}x${S}.png" >/dev/null
    sips -z $((S*2)) $((S*2)) "$BUILD/icon-1024.png" --out "$ICONSET/icon_${S}x${S}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing"
codesign --force --options runtime --timestamp=none -s "${SIGN_IDENTITY:--}" "$APP"

if [[ " $* " == *" --dmg "* ]]; then
  echo "▸ Making disk image"
  STAGE="$BUILD/dmg"
  rm -rf "$STAGE"; mkdir -p "$STAGE" dist
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  DMG="dist/$APP_NAME-$VERSION.dmg"
  rm -f "$DMG"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
  echo "  $DMG"
fi

if [[ " $* " == *" --install "* ]]; then
  echo "▸ Installing to /Applications"
  pkill -x $APP_NAME 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  open "/Applications/$APP_NAME.app"
fi

echo "✓ Built $APP"
