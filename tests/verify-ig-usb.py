#!/usr/bin/env python3
"""Validate the complete USB -> NEMESIS package -> signed HMG-API mod chain."""
import base64
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import uuid
import zipfile


def need(ok, message):
    if not ok:
        raise AssertionError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


with zipfile.ZipFile(sys.argv[1]) as usb:
    need(usb.testzip() is None, 'USB ZIP CRC')
    instruction = usb.read('NEMESIS.data').decode()
    need('type=install' in instruction and 'path=packages/korea.projection.zip' in instruction, 'USB install instruction')
    need('Korea Projection' in usb.read('README.txt').decode(), 'USB installation guide')
    need('IG-WIFI-GUIDE.md' in usb.namelist(), 'Vehicle test guide included')
    with zipfile.ZipFile(io.BytesIO(usb.read('packages/korea.projection.zip'))) as package:
        need(package.testzip() is None, 'NEMESIS package CRC')
        for f in ['scripts/post.sh', 'scripts/preun.sh', 'svc/hotspot.sh', 'bin/status.sh', 'bin/carreport.sh', 'app/KoreaProjection.apk', 'bin/busybox', 'bin/busybox-LICENSE.txt', 'svc/ig-wifi-recovery.sh']:
            need(f in package.namelist(), 'Missing package component: ' + f)
        metadata = package.read('NEMESIS.data').decode()
        need('id=korea.projection\n' in metadata and 'package-version=1.7.2.2\n' in metadata, 'NEMESIS identity/version')
        need(sha(package.read('app/KoreaProjection.apk')) == '661ffcf49889f45e7f84dc8c667b45e7af9858634d4b33232c651e77528989cd', 'Original signed app retained')
        busybox_sha = '3d31efecd4d09625a5d04597ad857f3475d35e6d63a3365912a7edd4c60770a5'
        need(sha(package.read('bin/busybox')) == busybox_sha, 'K3 ARM BusyBox retained')
        need(package.getinfo('bin/busybox').external_attr >> 16 & 0o111 != 0, 'BusyBox execution permission')
        need(busybox_sha in package.read('bin/busybox-LICENSE.txt').decode(), 'BusyBox license/source notice')
        need(usb.read('BUSYBOX-LICENSE.txt') == package.read('bin/busybox-LICENSE.txt'), 'USB license notice')
        data = package.read('hmgapi/wireless-carplay-aa.zip')
        service = package.read('svc/hotspot.sh').decode()
        need(re.search(r'^MOD_MD5=(\w+)$', service, re.M)[1] == hashlib.md5(data).hexdigest(), 'Auto-install checksum matches bundled mod')
        with zipfile.ZipFile(io.BytesIO(data)) as mod:
            need(mod.testzip() is None, 'Mod ZIP CRC')
            config = json.loads(mod.read('mod.json'))
            need(config['version'] == '2.4.0', 'Original release mod version retained')
            need(re.search(r'^MOD_VER=(.+)$', service, re.M)[1] == config['version'], 'Auto-install version matches bundled mod')
            manifest_bytes = mod.read('META-HMGAPI/manifest.json')
            manifest = json.loads(manifest_bytes)
            need(manifest['id'] == config['id'] == 'wireless-carplay-aa', 'Signed mod identity')
            need(manifest['version'] == config['version'], 'Signed version')
            need(manifest['uuid'] == '2cc2e759-39f0-8c87-9bbf-8db2d7a811b9', 'Original release signing identity retained')
            key = base64.b64decode(manifest['key'])
            b = bytearray(hashlib.sha256(key).digest()[:16]); b[6] = b[6] & 15 | 128; b[8] = b[8] & 63 | 128
            need(str(uuid.UUID(bytes=bytes(b))) == manifest['uuid'], 'Author identity derived from public key')
            for name, digest in manifest['files'].items():
                need(sha(mod.read(name)) == digest, 'Signed file checksum: ' + name)
            files = {n for n in mod.namelist() if not n.endswith('/') and not n.startswith('META-HMGAPI/')}
            need(files == set(manifest['files']), 'No unsigned payload files')
            with tempfile.TemporaryDirectory() as tmp:
                tmp = Path(tmp)
                (tmp / 'key.der').write_bytes(key)
                (tmp / 'signature.der').write_bytes(base64.b64decode(mod.read('META-HMGAPI/signature')))
                (tmp / 'manifest.json').write_bytes(manifest_bytes)
                subprocess.run(['openssl', 'pkey', '-pubin', '-inform', 'DER', '-in', str(tmp / 'key.der'), '-out', str(tmp / 'key.pem')], check=True, capture_output=True)
                subprocess.run(['openssl', 'dgst', '-sha256', '-verify', str(tmp / 'key.pem'), '-signature', str(tmp / 'signature.der'), str(tmp / 'manifest.json')], check=True, capture_output=True)
print('PASS: IG complete USB, recovery helper, original signed APK/BusyBox/mod, installer version/checksum and ECDSA signature')
