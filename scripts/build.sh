#!/bin/zsh
# Builds "Porter.app" into ./build, then packages a DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Porter"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "==> Cleaning"
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "==> Compiling Swift sources (universal)"
for ARCH in arm64 x86_64; do
    swiftc \
        -swift-version 5 \
        -O \
        -parse-as-library \
        -target "$ARCH-apple-macosx13.0" \
        -o "$BUILD_DIR/$APP_NAME-$ARCH" \
        Sources/*.swift
done
lipo -create "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64" \
    -output "$APP_DIR/Contents/MacOS/$APP_NAME"
rm -f "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"

echo "==> Bundling"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

echo "==> Generating icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift "$BUILD_DIR/icon-1024.png" 1024
for SIZE in 16 32 64 128 256 512; do
    sips -z $SIZE $SIZE "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z $DOUBLE $DOUBLE "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "==> Code signing (ad hoc)"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Creating DMG"
DMG_STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO \
    "$BUILD_DIR/Porter.dmg" >/dev/null
rm -rf "$DMG_STAGING"

echo ""
echo "Done:"
echo "  App: $APP_DIR"
echo "  DMG: $BUILD_DIR/Porter.dmg"
echo ""
echo "Install with: ./install.sh   (or open the DMG and drag to Applications)"
