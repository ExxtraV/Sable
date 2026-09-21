#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${RELEASE_VERSION:?}" "${SPARKLE_PRIVATE_KEY:?}" "${GITHUB_REPOSITORY:?}" "${RUNNER_TEMP:?}"
mkdir -p dist
if [ -e dist/Sable-Markdown-Writer.zip ] || [ -e dist/appcast.xml ]; then
    echo 'Use a fresh dist directory for each release.' >&2; exit 1
fi
APP="$PWD/build/Sable Markdown Writer.app"
case "${DISTRIBUTION_MODE:-community}" in
    notarized)
        KEYCHAIN="$RUNNER_TEMP/sable.keychain-db"
        ditto -c -k --keepParent "$APP" "$RUNNER_TEMP/Sable-notary.zip"
        xcrun notarytool submit "$RUNNER_TEMP/Sable-notary.zip" --keychain-profile sable-notary --keychain "$KEYCHAIN" --wait
        xcrun stapler staple "$APP"
        xcrun stapler validate "$APP"
        spctl --assess --type execute "$APP"
        ;;
    community)
        printf '\nCommunity build: not notarized by Apple. On first launch, macOS may require approval in System Settings → Privacy & Security → Open Anyway. Update downloads are verified with Sable Markdown Writer’s Sparkle signing key.\n' >> docs/release-notes.md
        ;;
    *) echo 'Unknown distribution mode.' >&2; exit 1 ;;
esac
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" dist/Sable-Markdown-Writer.zip
python3 - <<'PYNOTES'
import html, pathlib
notes = pathlib.Path('docs/release-notes.md').read_text()
pathlib.Path('dist/Sable-Markdown-Writer.html').write_text('<!doctype html><meta charset="utf-8"><pre>' + html.escape(notes) + '</pre>')
PYNOTES
printf '%s' "$SPARKLE_PRIVATE_KEY" | .build/artifacts/sparkle/Sparkle/bin/generate_appcast --ed-key-file - --maximum-deltas 0 --release-notes-url-prefix "https://github.com/$GITHUB_REPOSITORY/releases/download/v$RELEASE_VERSION/" --download-url-prefix "https://github.com/$GITHUB_REPOSITORY/releases/download/v$RELEASE_VERSION/" dist
python3 scripts/check-appcast.py dist/appcast.xml dist/Sable-Markdown-Writer.zip
(cd dist && shasum -a 256 Sable-Markdown-Writer.zip appcast.xml > SHA256SUMS)
