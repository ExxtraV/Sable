#!/bin/sh
# Builds a drag-to-install disk image: the app beside a shortcut to the Applications folder.
# Usage: make-dmg.sh "path/to/App.app" output.dmg ["Volume Name"]
set -eu
APP="${1:?path to the .app}"
OUT="${2:?output .dmg path}"
NAME="${3:-Sable Markdown Writer}"
[ -d "$APP" ] || { echo "Not an app bundle: $APP" >&2; exit 1; }
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT"
echo "$OUT"
