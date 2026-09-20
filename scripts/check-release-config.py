#!/usr/bin/env python3
import base64, json, os, re, subprocess, urllib.request, xml.etree.ElementTree as ET
mode = os.environ.get('DISTRIBUTION_MODE', 'community')
if mode not in ('community', 'notarized'): raise SystemExit('Unknown distribution mode.')
required = ['RELEASE_VERSION', 'RELEASE_BUILD', 'SPARKLE_PUBLIC_KEY', 'SPARKLE_PRIVATE_KEY', 'GITHUB_REPOSITORY']
if mode == 'notarized':
    required += ['SIGNING_IDENTITY', 'CERTIFICATE', 'CERTIFICATE_PASSWORD', 'APPLE_ID', 'APPLE_TEAM_ID', 'APPLE_APP_PASSWORD']
missing = [key for key in required if not os.environ.get(key)]
if missing: raise SystemExit('Missing release settings: ' + ', '.join(missing))
version, build = os.environ['RELEASE_VERSION'], os.environ['RELEASE_BUILD']
if not re.fullmatch(r'\d+\.\d+\.\d+', version): raise SystemExit('Version must be major.minor.patch.')
if not re.fullmatch(r'[1-9]\d*', build): raise SystemExit('Build must be a positive integer.')
if mode == 'notarized' and not os.environ['SIGNING_IDENTITY'].startswith('Developer ID Application:'): raise SystemExit('A Developer ID Application signing identity is required.')
if len(base64.b64decode(os.environ['SPARKLE_PUBLIC_KEY'], validate=True)) != 32: raise SystemExit('Invalid public key.')
repo = os.environ['GITHUB_REPOSITORY']
metadata = json.loads(subprocess.check_output(['gh', 'api', f'repos/{repo}']))
if metadata['private']: raise SystemExit('This release feed requires public downloads; private repositories need a separate public distribution channel.')
pages = json.loads(subprocess.check_output(['gh', 'api', '--paginate', '--slurp', f'repos/{repo}/releases?per_page=100']))
releases = [release for page in pages for release in page]
if any(r['tag_name'] == 'v' + version for r in releases): raise SystemExit('This release version already exists; choose a new version.')
# Check the largest published build, including prereleases, to prevent downgrades.
for release in releases:
    if release['draft']: continue
    for asset in release['assets']:
        if asset['name'] != 'appcast.xml': continue
        with urllib.request.urlopen(asset['browser_download_url'], timeout=30) as response:
            feed = ET.fromstring(response.read())
        for item in feed.findall('.//item'):
            ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
            enclosure = item.find('enclosure')
            previous = item.findtext(ns + 'version') or (enclosure.get(ns + 'version') if enclosure is not None else None)
            if not previous: raise SystemExit('Published feed has no build number; inspect it before releasing.')
            if previous and (not previous.isdigit() or int(build) <= int(previous)):
                raise SystemExit('Build must exceed every published update build.')
print('Release configuration is complete; build number increases.')
