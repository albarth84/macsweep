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
mkdir -p "$BUILD_DIR"
# Il bundle si assembla e si firma fuori dalla cartella del progetto: se il progetto è in una
# cartella sincronizzata (iCloud Drive) il File Provider aggiunge attributi estesi dopo la firma
# e il bundle non supera più `codesign --verify --strict`.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP_DIR="$STAGE/$APP_NAME.app"

echo "▸ Compilazione release (arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "▸ Creazione bundle"
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
    <key>NSDesktopFolderUsageDescription</key>
    <string>MacSweep analizza la Scrivania. Per non ricevere una richiesta per ogni cartella, concedi l'Accesso completo al disco.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>MacSweep analizza Documenti. Per non ricevere una richiesta per ogni cartella, concedi l'Accesso completo al disco.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>MacSweep analizza Download. Per non ricevere una richiesta per ogni cartella, concedi l'Accesso completo al disco.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>MacSweep analizza le unità esterne che scegli di scansionare.</string>
    <key>NSNetworkVolumesUsageDescription</key>
    <string>MacSweep analizza i volumi di rete che scegli di scansionare.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>MacSweep usa AppleScript solo per chiedere la password di amministratore quando rimuovi file di sistema.</string>
</dict>
</plist>
PLIST

# Firma con un certificato stabile: macOS lega i permessi (es. Accesso completo al disco)
# all'identità della firma. Con la firma ad-hoc ogni build sembra un'app nuova.
SIGN_IDENTITY="${SIGN_IDENTITY:-MacSweep Self-Signed}"
if ! security find-identity -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
    if [[ "${REQUIRE_SIGNING:-0}" == "1" ]]; then
        echo "✗ Identità di firma \"$SIGN_IDENTITY\" non trovata nel portachiavi." >&2
        exit 1
    fi
    echo "⚠︎ Identità \"$SIGN_IDENTITY\" non trovata: firma ad-hoc (i permessi andranno ridati a ogni build)."
    SIGN_IDENTITY="-"
fi
echo "▸ Firma ($SIGN_IDENTITY)"
xattr -cr "$APP_DIR"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --strict --deep "$APP_DIR"

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
    /usr/bin/ditto "$APP_DIR" "$STAGING/$APP_NAME.app"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGING"
fi

rm -rf "$BUILD_DIR/$APP_NAME.app"
/usr/bin/ditto "$APP_DIR" "$BUILD_DIR/$APP_NAME.app"
echo "✓ Fatto: $BUILD_DIR/$APP_NAME.app"
