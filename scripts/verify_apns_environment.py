#!/usr/bin/env python3
"""Check source signing settings and, optionally, a signed distribution app.

Usage: python3 scripts/verify_apns_environment.py [--app /path/to/jifen.app]
Pass the exported distribution app to check its actual signed entitlements;
an archive may still carry a development signature before export re-signs it.
"""
import argparse
import plistlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def verify_sources():
    project = (ROOT / 'jifen.xcodeproj/project.pbxproj').read_text()
    for identifier, name, expected in [('0FA5BADD2F18F3EC00182375', 'Debug', 'development'),
                                       ('0FA5BADE2F18F3EC00182375', 'Release', 'production')]:
        block = project.split(identifier + ' /* ' + name + ' */ = {', 1)[1].split('name = ' + name, 1)[0]
        path = re.search(r'CODE_SIGN_ENTITLEMENTS = ([^;]+);', block).group(1).strip('"')
        actual = plistlib.loads((ROOT / path).read_bytes()).get('aps-environment')
        if actual != expected:
            raise ValueError(f'{name}: expected {expected}, got {actual}')
        print(f'PASS {name}: {expected}')


def verify_app(app, expected):
    app = Path(app)
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)],
                            capture_output=True, check=True)
    entitlements = plistlib.loads(result.stdout)
    actual = entitlements.get('aps-environment')
    if actual != expected:
        raise ValueError(f'Signed app: expected {expected}, got {actual}')
    profile_path = app / 'embedded.mobileprovision'
    if profile_path.exists():
        result = subprocess.run(['security', 'cms', '-D', '-i', str(profile_path)],
                                capture_output=True, check=True)
        profile = plistlib.loads(result.stdout)
        if profile.get('Entitlements', {}).get('aps-environment') != actual:
            raise ValueError('Signed app and provisioning profile disagree on APNs environment')
    print(f'PASS signed app: {actual}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app')
    parser.add_argument('--expected', choices=['development', 'production'], default='production')
    args = parser.parse_args()
    verify_sources()
    if args.app:
        verify_app(args.app, args.expected)
