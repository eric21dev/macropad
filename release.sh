#!/bin/bash
# Crea build/Macropad-<versión>.dmg: binario universal (Apple Silicon + Intel), firma ad-hoc y acceso directo a Aplicaciones.
#   ./release.sh [versión]
set -euo pipefail
cd "$(dirname "$0")"
VERSION=${1:-1.0}
ARCHS="arm64 x86_64" SIGN=adhoc VERSION=$VERSION ./build.sh
rm -rf build/dmg && mkdir -p build/dmg
ditto build/Macropad.app build/dmg/Macropad.app
ln -s /Applications build/dmg/Applications
cp tools/dmg-leeme.txt build/dmg/LEEME.txt
DMG="build/Macropad-$VERSION.dmg"; rm -f "$DMG"
hdiutil create -volname "Macropad $VERSION" -srcfolder build/dmg -ov -format UDZO "$DMG" >/dev/null
echo "OK → $DMG"; shasum -a 256 "$DMG"
