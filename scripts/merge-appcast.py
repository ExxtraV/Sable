#!/usr/bin/env python3
"""Merge the items of one appcast into another: merge-appcast.py BASE NEW OUT [beta].

BASE is the live feed (may not exist yet on the first release), NEW holds the freshly signed item(s).
Items are keyed by build number; a build in NEW replaces the same build in BASE. Stable items are
untagged, beta items carry <sparkle:channel>beta</sparkle:channel>. A beta at or below the newest
stable build is superseded and dropped. A fourth argument (beta) refuses NEW items of any other channel. The newest KEEP items of each channel stay. Signatures are
copied untouched, so no signing key is needed here.
"""
import os, sys, xml.etree.ElementTree as ET

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ns = '{' + SPARKLE + '}'
KEEP = 3
ET.register_namespace('sparkle', SPARKLE)
ET.register_namespace('dc', 'http://purl.org/dc/elements/1.1/')

def build(item):
    enclosure = item.find('enclosure')
    value = item.findtext(ns + 'version') or (enclosure.get(ns + 'version') if enclosure is not None else None)
    if not value or not value.isdigit(): raise SystemExit('Appcast item has no numeric build number.')
    return int(value)

def channel(item): return (item.findtext(ns + 'channel') or '').strip() or None

def check_urls(items, repo):
    prefix = f'https://github.com/{repo}/releases/download/'
    for item in items:
        enclosure = item.find('enclosure')
        if enclosure is None or not (enclosure.get('url') or '').startswith(prefix):
            raise SystemExit('Appcast item does not download from this repository’s releases.')
        if channel(item) not in (None, 'beta'): raise SystemExit('Unknown appcast channel.')

def merge(base_items, new_items):
    by_build = {build(item): item for item in base_items}
    by_build.update({build(item): item for item in new_items})
    ordered = sorted(by_build.values(), key=build, reverse=True)
    stable = [item for item in ordered if channel(item) is None][:KEEP]
    newest_stable = build(stable[0]) if stable else 0
    beta = [item for item in ordered if channel(item) == 'beta' and build(item) > newest_stable][:KEEP]
    return sorted(stable + beta, key=build, reverse=True)

def load(path):
    root = ET.parse(path).getroot()
    feed = root.find('channel')
    if feed is None: raise SystemExit('Feed has no channel element.')
    return root, feed

if __name__ == '__main__':
    base_path, new_path, out_path = sys.argv[1:4]
    required = sys.argv[4] if len(sys.argv) > 4 else None
    repo = os.environ['GITHUB_REPOSITORY']
    new_root, new_feed = load(new_path)
    new_items = new_feed.findall('item')
    if required and any(channel(item) != required for item in new_items):
        raise SystemExit(f'Every new appcast item must be on the {required} channel.')
    base_items = []
    if os.path.exists(base_path) and os.path.getsize(base_path) > 0:
        base_items = load(base_path)[1].findall('item')
    check_urls(base_items + new_items, repo)
    merged = merge(base_items, new_items)
    for item in new_feed.findall('item'): new_feed.remove(item)
    for item in merged: new_feed.append(item)
    ET.indent(new_root)
    ET.ElementTree(new_root).write(out_path, encoding='utf-8', xml_declaration=True)
    print(f'Merged appcast: {len(merged)} item(s), newest build {build(merged[0])}.')
