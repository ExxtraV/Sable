#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${RELEASE_VERSION:?}" "${SPARKLE_PRIVATE_KEY:?}" "${GITHUB_REPOSITORY:?}" "${RUNNER_TEMP:?}"
mkdir -p dist
if [ -e dist/New-Quill.zip ] || [ -e dist/appcast.xml ]; then
    echo 'Use a fresh dist directory for each release.' >&2; exit 1
fi
APP="$PWD/build/Quill.app"
KEYCHAIN="$RUNNER_TEMP/new-quill.keychain-db"
ditto -c -k --keepParent "$APP" "$RUNNER_TEMP/New-Quill-notary.zip"
xcrun notarytool submit "$RUNNER_TEMP/New-Quill-notary.zip" --keychain-profile new-quill-notary --keychain "$KEYCHAIN" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute "$APP"
ditto -c -k --keepParent "$APP" dist/New-Quill.zip
python3 - <<'PYNOTES'
import html, pathlib
notes = pathlib.Path('docs/release-notes.md').read_text()
pathlib.Path('dist/New-Quill.html').write_text('<!doctype html><meta charset="utf-8"><pre>' + html.escape(notes) + '</pre>')
PYNOTES
printf '%s' "$SPARKLE_PRIVATE_KEY" | .build/artifacts/sparkle/Sparkle/bin/generate_appcast --ed-key-file - --maximum-deltas 0 --release-notes-url-prefix "https://github.com/$GITHUB_REPOSITORY/releases/download/v$RELEASE_VERSION/" --download-url-prefix "https://github.com/$GITHUB_REPOSITORY/releases/download/v$RELEASE_VERSION/" dist
python3 scripts/check-appcast.py dist/appcast.xml dist/New-Quill.zip
(cd dist && shasum -a 256 New-Quill.zip appcast.xml > SHA256SUMS)
