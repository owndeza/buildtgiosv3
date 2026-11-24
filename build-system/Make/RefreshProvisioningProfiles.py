#!/usr/bin/env python3
"""Refresh the fake provisioning profiles so device builds do not reject them as expired.

rules_apple's plisttool compares the profile's ExpirationDate with the current
date and fails the build when it is in the past. The fake profiles checked into
build-system/fake-codesigning/profiles are intentionally self-signed and expire;
this script re-signs each of them with the repository's SelfSigned certificate
after moving ExpirationDate to the far future. Run it before Make.py in CI; it
does not change the checked-in files.
"""

import argparse
import datetime
import os
import plistlib
import re
import subprocess
import sys
import tempfile

DEFAULT_EXPIRATION = datetime.datetime(2099, 12, 31, 23, 59, 59, tzinfo=datetime.timezone.utc)
KEYCHAIN_NAME = 'refresh-profiles-temp.keychain'
KEYCHAIN_PASSWORD = 'temp123'


def run(*arguments, input_data=None, check=True):
    process = subprocess.run(
        list(arguments),
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and process.returncode != 0:
        raise RuntimeError(
            '{} failed ({}): {}'.format(
                ' '.join(arguments), process.returncode,
                process.stderr.decode('utf-8', errors='replace').strip()
            )
        )
    return process.stdout.decode('utf-8', errors='replace')


def setup_keychain(p12_path, password=''):
    run('security', 'delete-keychain', KEYCHAIN_NAME, check=False)
    run('security', 'create-keychain', '-p', KEYCHAIN_PASSWORD, KEYCHAIN_NAME)
    existing = run('security', 'list-keychains', '-d', 'user')
    existing_paths = [line.strip().strip('"') for line in existing.splitlines() if line.strip()]
    run('security', 'list-keychains', '-d', 'user', '-s', KEYCHAIN_NAME, *existing_paths)
    run('security', 'set-keychain-settings', KEYCHAIN_NAME)
    run('security', 'unlock-keychain', '-p', KEYCHAIN_PASSWORD, KEYCHAIN_NAME)
    run('security', 'import', p12_path, '-k', KEYCHAIN_NAME, '-P', password,
        '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
    run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:',
        '-k', KEYCHAIN_PASSWORD, KEYCHAIN_NAME)

    # Do not filter with '-p codesigning' or '-v': the fake identity is
    # self-signed and is intentionally not trusted, but `security cms -S`
    # can still use it.
    identities = run('security', 'find-identity', KEYCHAIN_NAME)
    match = re.search(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})(?:\s+"([^"]+)")?', identities, re.MULTILINE)
    if not match:
        raise RuntimeError(
            'No signing identity found in {}. security find-identity output:\n{}'.format(
                p12_path, identities.strip()
            )
        )
    return match.group(2) or match.group(1)


def refresh_profile(path, identity, expiration):
    decoded = subprocess.run(
        ['security', 'cms', '-D', '-i', path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if decoded.returncode != 0:
        raise RuntimeError(
            'Could not decode {}: {}'.format(
                path, decoded.stderr.decode('utf-8', errors='replace').strip()
            )
        )

    profile = plistlib.loads(decoded.stdout)
    previous = profile.get('ExpirationDate')
    profile['ExpirationDate'] = expiration
    # A stale embedded signature copy would describe the old plist.
    profile.pop('DER-Encoded-Profile', None)

    handle, plist_path = tempfile.mkstemp(suffix='.plist')
    os.close(handle)
    output_path = tempfile.mktemp(suffix='.mobileprovision')
    try:
        with open(plist_path, 'wb') as file:
            file.write(plistlib.dumps(profile, fmt=plistlib.FMT_XML))
        run('security', 'cms', '-S', '-k', KEYCHAIN_NAME, '-N', identity,
            '-i', plist_path, '-o', output_path)
        # Verify the written file before replacing the original.
        check = subprocess.run(
            ['security', 'cms', '-D', '-i', output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if check.returncode != 0 or plistlib.loads(check.stdout).get('ExpirationDate') != expiration:
            raise RuntimeError('Verification failed for {}'.format(path))
        os.replace(output_path, path)
    finally:
        for temporary_path in (plist_path, output_path):
            if os.path.exists(temporary_path):
                os.unlink(temporary_path)

    print('{}: ExpirationDate {} -> {}'.format(
        os.path.basename(path),
        previous.isoformat() if previous else 'missing',
        expiration.isoformat(),
    ))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profilesPath', default='build-system/fake-codesigning/profiles')
    parser.add_argument('--certsPath', default='build-system/fake-codesigning/certs')
    parser.add_argument('--password', default='', help='Password of SelfSigned.p12')
    args = parser.parse_args()

    p12_path = os.path.join(args.certsPath, 'SelfSigned.p12')
    if not os.path.exists(p12_path):
        print('{} does not exist'.format(p12_path))
        return 1
    if not os.path.isdir(args.profilesPath):
        print('{} does not exist'.format(args.profilesPath))
        return 1

    identity = setup_keychain(p12_path, args.password)
    try:
        profiles = sorted(
            os.path.join(args.profilesPath, name)
            for name in os.listdir(args.profilesPath)
            if name.endswith('.mobileprovision')
        )
        if not profiles:
            print('No provisioning profiles found in {}'.format(args.profilesPath))
            return 1
        for profile_path in profiles:
            refresh_profile(profile_path, identity, DEFAULT_EXPIRATION)
    finally:
        run('security', 'delete-keychain', KEYCHAIN_NAME, check=False)

    print('Refreshed {} provisioning profiles.'.format(len(profiles)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
