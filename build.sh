#!/bin/bash
# Compila Macropad.app en ./build (sin Xcode: solo las herramientas de línea de comandos).
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Macropad.app
# Variables: ARCHS="arm64 x86_64" (binario universal; por defecto solo la de este Mac), SIGN=adhoc (ignora certificados
# del llavero; lo usa release.sh), VERSION=1.0
ARCHS=${ARCHS:-$(uname -m)}; VERSION=${VERSION:-1.0}
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/tmp

bins=()
for a in $ARCHS; do swiftc -O -target "$a-apple-macos13.0" Sources/*.swift -o "build/tmp/Macropad-$a"; bins+=("build/tmp/Macropad-$a"); done
if [ ${#bins[@]} -gt 1 ]; then lipo -create "${bins[@]}" -output "$APP/Contents/MacOS/Macropad"; else cp "${bins[0]}" "$APP/Contents/MacOS/Macropad"; fi
cp -R Resources/ui "$APP/Contents/Resources/ui"

# icono
swiftc -O tools/make-icon.swift -o build/tmp/make-icon
build/tmp/make-icon build/tmp/AppIcon.iconset && iconutil -c icns build/tmp/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# versión (rama · commit · fecha) para la etiqueta de la interfaz
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?"); COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "sin-commit")
DATE=$(git log -1 --format=%cI 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S%z); DIRTY=0; [ -n "$(git status --porcelain 2>/dev/null)" ] && DIRTY=1
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.bugus.macropad</string>
  <key>CFBundleName</key><string>Macropad</string>
  <key>CFBundleDisplayName</key><string>Macropad</string>
  <key>CFBundleExecutable</key><string>Macropad</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>MPBranch</key><string>$BRANCH</string>
  <key>MPCommit</key><string>$COMMIT</string>
  <key>MPDate</key><string>$DATE</string>
  <key>MPDirty</key><string>$DIRTY</string>
</dict></plist>
PLIST

# Firma: si hay un certificado de desarrollo se usa (los permisos de macOS sobreviven a recompilar); si no, firma ad-hoc.
IDENT=""; [ "${SIGN:-}" = adhoc ] || IDENT=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"/{print $2; exit}')
if [ -n "${IDENT:-}" ]; then codesign --force --deep -s "$IDENT" "$APP" && echo "Firmada con: $IDENT"
else codesign --force --deep -s - "$APP" && echo "Firmada ad-hoc (macOS pedirá de nuevo los permisos tras cada recompilación)"; fi
echo "OK → $APP"
