#!/usr/bin/env python3
"""Package the SwiftPM executable with Sparkle, preserving framework symlinks."""
import base64, json, os, pathlib, plistlib, re, shutil, subprocess, sys
root = pathlib.Path(__file__).resolve().parent.parent
scratch = pathlib.Path(sys.argv[1]).resolve()
preview = '--preview' in sys.argv
app = root / 'build' / ('Sable Markdown Writer Preview.app' if preview else 'Sable Markdown Writer.app')
contents = app / 'Contents'
for name in ['MacOS', 'Resources', 'Frameworks']:
    (contents / name).mkdir(parents=True, exist_ok=True)
binary_dir = pathlib.Path(os.environ.get('QUILL_BINARY_DIR', str(scratch / 'release')))
shutil.copy2(binary_dir / 'Quill', contents / 'MacOS/Quill')
shutil.copy2(root / 'docs/Sable Guide.md', contents / 'Resources/Sable Guide.md')
shutil.copy2(root / 'LICENSE', contents / 'Resources/LICENSE.txt')
shutil.copy2(root / 'Assets/Sable.icns', contents / 'Resources/Sable.icns')
shutil.copy2(scratch / 'artifacts/sparkle/Sparkle/LICENSE', contents / 'Resources/Sparkle-LICENSE.txt')
frameworks = list((scratch / 'artifacts').glob('**/macos-arm64_x86_64/Sparkle.framework'))
if len(frameworks) != 1:
    raise SystemExit('Expected exactly one universal Sparkle framework in SwiftPM artifacts.')
destination = contents / 'Frameworks/Sparkle.framework'
if destination.exists(): shutil.rmtree(destination)
shutil.copytree(frameworks[0], destination, symlinks=True)
info = plistlib.load(open(root / 'Info.plist', 'rb'))
config_path = root / 'UpdateConfig.json'
config = json.loads(config_path.read_text()) if config_path.exists() else {}
feed = os.environ.get('UPDATE_FEED_URL', config.get('feedURL', ''))
key = os.environ.get('SPARKLE_PUBLIC_KEY', config.get('publicKey', ''))
if feed or key:
    from urllib.parse import urlsplit
    parsed = urlsplit(feed)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise SystemExit('Update feed must be an HTTPS URL without credentials.')
    if len(base64.b64decode(key, validate=True)) != 32:
        raise SystemExit('Sparkle public key must decode to 32 bytes.')
    info.update(SUFeedURL=feed, SUPublicEDKey=key)
version, build = os.environ.get('RELEASE_VERSION'), os.environ.get('RELEASE_BUILD')
if version:
    if not re.fullmatch(r'\d+\.\d+\.\d+(-beta\.[1-9]\d*)?', version): raise SystemExit('Use a numeric major.minor.patch version, with -beta.N for a beta.')
    info['CFBundleShortVersionString'] = version
if build:
    if not re.fullmatch(r'[1-9]\d*', build): raise SystemExit('Build must be a positive integer.')
    info['CFBundleVersion'] = build
if preview:
    info.update(CFBundleIdentifier='local.quill.preview.v5', CFBundleName='Sable Markdown Writer Preview', CFBundleDisplayName='Sable Markdown Writer Preview')
    info.pop('SUFeedURL', None); info.pop('SUPublicEDKey', None)
    shutil.copytree(root / 'Examples', contents / 'Resources/Examples', dirs_exist_ok=True)
plistlib.dump(info, open(contents / 'Info.plist', 'wb'))
identity = os.environ.get('SIGNING_IDENTITY', '-')
flags = ['--force', '--sign', identity, '--preserve-metadata=entitlements,identifier']
if identity != '-': flags += ['--options', 'runtime', '--timestamp']
def sign(path): subprocess.run(['codesign', *flags, str(path)], check=True)
# Sign nested code inside out; never use --deep to sign a distribution.
version_dir = destination / 'Versions/B'
sign(version_dir / 'Autoupdate')
for path in sorted(version_dir.glob('**/*.xpc'), key=lambda p: len(p.parts), reverse=True): sign(path)
for path in sorted(version_dir.glob('**/*.app'), key=lambda p: len(p.parts), reverse=True): sign(path)
sign(destination)
sign(app)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(app)
