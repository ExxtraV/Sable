#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${RELEASE_VERSION:?}" "${SPARKLE_PRIVATE_KEY:?}" "${GITHUB_REPOSITORY:?}" "${RUNNER_TEMP:?}"
mkdir -p dist
if [ -e dist/Sable-Markdown-Writer.zip ] || [ -e dist/appcast.xml ]; then
    echo 'Use a fresh dist directory for each release.' >&2; exit 1
fi
CHANNEL="${RELEASE_CHANNEL:-stable}"
case "$CHANNEL" in stable|beta) ;; *) echo 'Unknown release channel.' >&2; exit 1 ;; esac
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
# Betas are tagged with the beta channel; stable items carry no tag, so every user can see them.
set -- --ed-key-file - --maximum-deltas 0 --release-notes-url-prefix "https://github.com/$GITHUB_REPOSITORY/releases/download/v$RELEASE_VERSION/" --download-url-prefix "https://github.com/$GITHUB_REPOSITORY/releases/download/v$RELEASE_VERSION/"
if [ "$CHANNEL" = beta ]; then set -- "$@" --channel beta; fi
printf '%s' "$SPARKLE_PRIVATE_KEY" | .build/artifacts/sparkle/Sparkle/bin/generate_appcast "$@" dist
python3 scripts/check-appcast.py dist/appcast.xml dist/Sable-Markdown-Writer.zip "$CHANNEL"
# A stable release becomes "latest", so its appcast is the live feed: carry the previous stable items forward and
# drop superseded betas. A beta keeps its one-item appcast; publish-beta-feed.yml merges it into the live feed
# after you publish the prerelease, so nothing reaches opted-in users before you have reviewed the draft.
if [ "$CHANNEL" = stable ] && [ -s "${LIVE_APPCAST:-/nonexistent}" ]; then
    python3 scripts/merge-appcast.py "$LIVE_APPCAST" dist/appcast.xml "$RUNNER_TEMP/merged-appcast.xml"
    cp "$RUNNER_TEMP/merged-appcast.xml" dist/appcast.xml
fi
# The disk image is for first-time installs from the website; updates keep using the zip. It is built only now,
# after the appcast, because the appcast generator would list a .dmg in dist/ as a second copy of this update.
DMG="dist/Sable-Markdown-Writer.dmg"
sh scripts/make-dmg.sh "$APP" "$DMG" "Sable Markdown Writer"
if [ "${DISTRIBUTION_MODE:-community}" = notarized ]; then
    KEYCHAIN="$RUNNER_TEMP/sable.keychain-db"
    codesign --force --sign "${SIGNING_IDENTITY:?}" --timestamp "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile sable-notary --keychain "$KEYCHAIN" --wait
    xcrun stapler staple "$DMG"
fi
hdiutil verify -quiet "$DMG"
# appcast.xml is left out: the live feed is rewritten when a beta is published, so its checksum would go stale.
(cd dist && shasum -a 256 Sable-Markdown-Writer.zip Sable-Markdown-Writer.dmg > SHA256SUMS)
