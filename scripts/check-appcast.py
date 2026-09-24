#!/usr/bin/env python3
import base64, os, pathlib, plistlib, subprocess, sys, xml.etree.ElementTree as ET, zipfile
feed, archive = map(pathlib.Path, sys.argv[1:3])
channel = sys.argv[3] if len(sys.argv) > 3 else 'stable'
assert channel in ('stable', 'beta'), 'Channel must be stable or beta.'
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(feed).findall('.//item')
assert len(items) == 1, 'Expected exactly one release in this feed.'
enclosure = items[0].find('enclosure')
assert enclosure is not None
# Stable updates carry no channel tag, so every user sees them; betas are tagged and only opted-in users see them.
assert items[0].findtext(ns + 'channel') == ('beta' if channel == 'beta' else None), 'The item’s channel tag must match the release channel.'
assert int(enclosure.get('length')) == archive.stat().st_size
assert len(base64.b64decode(enclosure.get(ns + 'edSignature'), validate=True)) == 64
with zipfile.ZipFile(archive) as z:
    info = plistlib.loads(z.read('Sable Markdown Writer.app/Contents/Info.plist'))
assert (items[0].findtext(ns + 'version') or enclosure.get(ns + 'version')) == info['CFBundleVersion']
assert (items[0].findtext(ns + 'shortVersionString') or enclosure.get(ns + 'shortVersionString')) == info['CFBundleShortVersionString']
expected = f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/releases/download/v{info['CFBundleShortVersionString']}/{archive.name}"
assert enclosure.get('url') == expected, 'Archive URL must point to this immutable version, not latest.'
print('Appcast version, archive length, signature shape and release URL match.')

root = pathlib.Path(__file__).resolve().parent.parent
subprocess.run(['swift', '-module-cache-path', str(root / '.build/module-cache'), str(root / 'scripts/verify-update.swift'), str(archive), info['SUPublicEDKey'], enclosure.get(ns + 'edSignature')], check=True)
