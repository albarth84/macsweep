#!/usr/bin/env bash
# Compila MacSweep e crea build/MacSweep.app (e opzionalmente un .dmg).
# Uso: scripts/build-app.sh [--dmg] [--zip]
# La versione viene da $VERSION o dal file VERSION.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="MacSweep"
BUNDLE_ID="io.github.albarth84.macsweep"
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "▸ Compilazione release (arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "▸ Creazione bundle $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>MacSweep usa AppleScript solo per chiedere la password di amministratore quando rimuovi file di sistema.</string>
</dict>
</plist>
PLIST

echo "▸ Firma ad-hoc"
codesign --force --deep --sign - "$APP_DIR"

if [[ " $* " == *" --zip "* ]]; then
    ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"
    echo "▸ Creazione $ZIP"
    rm -f "$ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP"
fi

if [[ " $* " == *" --dmg "* ]]; then
    DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
    echo "▸ Creazione $DMG"
    rm -f "$DMG"
    STAGING="$(mktemp -d)"
    cp -R "$APP_DIR" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGING"
fi

echo "✓ Fatto: $APP_DIR"
