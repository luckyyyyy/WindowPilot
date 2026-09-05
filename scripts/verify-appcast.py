#!/usr/bin/env python3
"""Fail publication if feed metadata does not match the final release payload."""
import base64
from pathlib import Path
import plistlib
import sys
import xml.etree.ElementTree as ET

feed, archive = map(Path, sys.argv[1:])
info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
item = ET.parse(feed).find('./channel/item')
assert item is not None, 'Missing release item'
assert item.findtext('sparkle:version', namespaces=ns) == info['CFBundleVersion']
assert item.findtext('sparkle:shortVersionString', namespaces=ns) == info['CFBundleShortVersionString']
assert item.findtext('sparkle:minimumSystemVersion', namespaces=ns) == info['LSMinimumSystemVersion']
enclosure = item.find('enclosure')
assert enclosure is not None
expected = f"https://github.com/luckyyyyy/WindowPilot/releases/download/v{info['CFBundleShortVersionString']}/{archive.name}"
assert enclosure.attrib['url'] == expected
assert int(enclosure.attrib['length']) == archive.stat().st_size
assert len(base64.b64decode(enclosure.attrib['{' + ns['sparkle'] + '}edSignature'], validate=True)) == 64
assert b'<!-- sparkle-signatures:' in feed.read_bytes(), 'Missing signed-feed header'
print(f'Feed metadata verified: {info["CFBundleShortVersionString"]} ({info["CFBundleVersion"]}), {archive.stat().st_size} bytes')
