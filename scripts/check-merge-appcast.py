#!/usr/bin/env python3
import os, pathlib, runpy, subprocess, sys, tempfile, xml.etree.ElementTree as ET

ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
repo = 'test/Sable'
def item(build, chan=None, url=None):
    tag = f'<sparkle:channel>{chan}</sparkle:channel>' if chan else ''
    url = url or f'https://github.com/{repo}/releases/download/v{build}/Sable-Markdown-Writer.zip'
    return (f'<item><title>{build}</title>{tag}<sparkle:version>{build}</sparkle:version>'
            f'<enclosure url="{url}" length="1" type="application/octet-stream" sparkle:edSignature="sig{build}"/></item>')
def feed(*items):
    return ('<?xml version="1.0" encoding="utf-8"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            '<channel><title>Sable</title>' + ''.join(items) + '</channel></rss>')
def merge(base, new, require=None):
    with tempfile.TemporaryDirectory() as d:
        paths = [pathlib.Path(d) / name for name in ('base.xml', 'new.xml', 'out.xml')]
        if base is not None: paths[0].write_text(base)
        paths[1].write_text(new)
        result = subprocess.run([sys.executable, 'scripts/merge-appcast.py', *map(str, paths), *([require] if require else [])], env=dict(os.environ, GITHUB_REPOSITORY=repo), capture_output=True, text=True)
        if result.returncode: return result.stderr
        return [(int(i.findtext(ns + 'version')), i.findtext(ns + 'channel')) for i in ET.parse(paths[2]).findall('.//item')]

# First release: no base feed yet.
assert merge(None, feed(item(1))) == [(1, None)]
# A beta lands on top of the live stable feed, and the stable item stays.
assert merge(feed(item(5)), feed(item(6, 'beta'))) == [(6, 'beta'), (5, None)]
# The same build replaces itself instead of duplicating.
assert merge(feed(item(5), item(6, 'beta')), feed(item(6, 'beta'))) == [(6, 'beta'), (5, None)]
# A newer stable supersedes every older beta.
assert merge(feed(item(5), item(6, 'beta'), item(7, 'beta')), feed(item(8))) == [(8, None), (5, None)]
# A beta at or below the newest stable is dropped, never resurfaced.
assert merge(feed(item(8)), feed(item(7, 'beta'))) == [(8, None)]
# At most three of each channel are kept, newest first.
old = [item(b) for b in (1, 2, 3, 4)] + [item(b, 'beta') for b in (11, 12, 13)]
assert merge(feed(*old), feed(item(14, 'beta'))) == [(14, 'beta'), (13, 'beta'), (12, 'beta'), (4, None), (3, None), (2, None)]
# Foreign download URLs, unknown channels and missing builds are refused.
assert 'releases' in merge(feed(item(5)), feed(item(6, url='https://example.com/x.zip')))
assert 'channel' in merge(feed(item(5)), feed(item(6, 'nightly')))
# The publish-time step only ever accepts beta items, so a stable item in a prerelease can't reach the live feed.
assert merge(feed(item(5)), feed(item(6, 'beta')), 'beta') == [(6, 'beta'), (5, None)]
assert 'beta channel' in merge(feed(item(5)), feed(item(6)), 'beta')
print('Passed: appcast merge keeps stable and beta items apart, prunes superseded betas, and refuses foreign URLs.')
