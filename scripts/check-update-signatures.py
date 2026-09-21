#!/usr/bin/env python3
"""Exercise Sparkle's signature checks using an ephemeral test key, never a release key."""
import base64, os, pathlib, plistlib, subprocess, tempfile, zipfile, xml.etree.ElementTree as ET
root = pathlib.Path(__file__).resolve().parent.parent
signer = root / '.build/artifacts/sparkle/Sparkle/bin/sign_update'
with tempfile.TemporaryDirectory(prefix='quill-update-check-') as folder:
    folder = pathlib.Path(folder)
    private = folder / 'test-key'
    generator = folder / 'key.swift'
    generator.write_text("""import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
try key.publicKey.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
""")
    public = folder / 'public-key'
    subprocess.run(['swift', '-module-cache-path', str(root / '.build/module-cache'), str(generator), str(private), str(public)], check=True)
    private.chmod(0o600)
    archive = folder / 'update.zip'
    with zipfile.ZipFile(archive, 'w') as z:
        z.writestr('Sable Markdown Writer.app/Contents/Info.plist', plistlib.dumps(dict(CFBundleVersion='5', CFBundleShortVersionString='0.5.0', SUPublicEDKey=public.read_text())))
    signature = subprocess.check_output([str(signer), '--ed-key-file', str(private), '-p', str(archive)], text=True).strip()
    subprocess.run([str(signer), '--ed-key-file', str(private), '--verify', str(archive), signature], check=True, stdout=subprocess.DEVNULL)
    feed = folder / 'appcast.xml'
    ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    rss = ET.Element('rss'); channel = ET.SubElement(rss, 'channel'); item = ET.SubElement(channel, 'item')
    ET.SubElement(item, ns + 'version').text = '5'
    ET.SubElement(item, ns + 'shortVersionString').text = '0.5.0'
    enclosure = ET.SubElement(item, 'enclosure', {'url': 'https://github.com/test/new-quill/releases/download/v0.5.0/update.zip', 'length': str(archive.stat().st_size), ns + 'edSignature': signature})
    ET.ElementTree(rss).write(feed)
    environment = dict(os.environ, GITHUB_REPOSITORY='test/new-quill')
    command = ['python3', str(root / 'scripts/check-appcast.py'), str(feed), str(archive)]
    subprocess.run(command, env=environment, check=True)
    ET.SubElement(item, ns + 'unused')
    item.find(ns + 'version').text = '4'
    ET.ElementTree(rss).write(feed)
    assert subprocess.run(command, env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0, 'Mismatched appcast version must be rejected.'
    archive.write_bytes(archive.read_bytes() + b' tampered')
    result = subprocess.run([str(signer), '--ed-key-file', str(private), '--verify', str(archive), signature], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert result.returncode != 0, 'Modified update must be rejected.'
print('Passed: signed appcast/archive verified against embedded key; mismatched version and tampered archive rejected; test key removed.')
