#!/usr/bin/env python3
"""
Validate APT/Sileo repository structure and content.
Verifies that Packages/Release hashes match the actual .deb file.
Exits with code 1 if any check fails.
"""

import os
import sys
import re
import hashlib


def fail(msg):
    print(f"  ❌ {msg}", file=sys.stderr)
    return False


def ok(msg):
    print(f"  ✅ {msg}")
    return True


def file_hash(filepath, algorithm):
    h = hashlib.new(algorithm)
    with open(filepath, 'rb') as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def file_size(filepath):
    return os.path.getsize(filepath)


def validate_repo(repo_root):
    errors = 0

    print("[validate-repo] Starting validation...")
    print()

    # 1. Check required files exist and are non-empty
    print("[validate-repo] Checking required files...")
    required_files = ['Packages', 'Packages.bz2', 'Packages.xz', 'Release']
    for fname in required_files:
        path = os.path.join(repo_root, fname)
        if not os.path.exists(path):
            errors += 1
            fail(f"Missing file: {fname}")
        elif os.path.getsize(path) == 0:
            errors += 1
            fail(f"Empty file: {fname}")
        else:
            ok(f"{fname} exists ({os.path.getsize(path)} bytes)")

    # 2. Check .deb exists in pool
    print()
    print("[validate-repo] Checking .deb package...")
    deb_dirs = [
        os.path.join(repo_root, 'pool', 'main', 'iphoneos-arm64'),
        os.path.join(repo_root, 'pool', 'main', 'iphoneos-arm64e'),
    ]
    debs = []
    for deb_dir in deb_dirs:
        if os.path.isdir(deb_dir):
            debs.extend((deb_dir, f) for f in os.listdir(deb_dir) if f.endswith('.deb'))

    if not debs:
        errors += 1
        fail(f"No .deb found in {', '.join(deb_dirs)}")
        return 1

    deb_path = os.path.join(debs[0][0], debs[0][1])
    ok(f"Found .deb: {debs[0][1]} ({file_size(deb_path)} bytes)")

    # Calculate actual hashes of the .deb
    actual_size = file_size(deb_path)
    actual_md5 = file_hash(deb_path, 'md5')
    actual_sha256 = file_hash(deb_path, 'sha256')

    print()
    print(f"[validate-repo] Actual .deb hashes:")
    print(f"  Size:   {actual_size}")
    print(f"  MD5:    {actual_md5}")
    print(f"  SHA256: {actual_sha256}")

    # 3. Validate Packages content and compare with actual .deb
    print()
    print("[validate-repo] Validating Packages against actual .deb...")
    packages_path = os.path.join(repo_root, 'Packages')
    if os.path.exists(packages_path):
        with open(packages_path) as f:
            content = f.read()

        # Check required fields
        checks = [
            ('Package field', r'^Package:\s+\S+'),
            ('Version field', r'^Version:\s+\S+'),
            ('Architecture field', r'^Architecture:\s+iphoneos-arm64e?'),
            ('Maintainer field', r'^Maintainer:\s+\S+'),
            ('Filename field', r'^Filename:\s+pool/main/iphoneos-arm64/'),
            ('Size field', r'^Size:\s+[1-9]\d*'),
            ('MD5sum field', r'^MD5sum:\s+[a-f0-9]{32}'),
            ('SHA256 field', r'^SHA256:\s+[a-f0-9]{64}'),
        ]

        for name, pattern in checks:
            if re.search(pattern, content, re.MULTILINE):
                ok(f"{name} valid")
            else:
                errors += 1
                fail(f"{name} missing or invalid")

        # Compare every Packages stanza with its corresponding .deb file.
        # A repository may contain several packages and historical versions;
        # validating only os.listdir()[0] makes the result filesystem-order
        # dependent and can hide a stale or corrupted package entry.
        entries = []
        for block in re.split(r'\n\s*\n', content.strip()):
            fields = {}
            for line in block.splitlines():
                if ':' not in line or line.startswith(' '):
                    continue
                key, value = line.split(':', 1)
                fields[key.strip()] = value.strip()
            if fields.get('Filename'):
                entries.append(fields)

        if not entries:
            errors += 1
            fail('No package stanzas found in Packages')
        else:
            for entry in entries:
                filename = entry.get('Filename', '')
                valid_prefixes = (
                    'pool/main/iphoneos-arm64/',
                    'pool/main/iphoneos-arm64e/',
                )
                if not filename.startswith(valid_prefixes):
                    errors += 1
                    fail(f"Unsafe or invalid Filename field: {filename}")
                    continue

                repo_root_abs = os.path.abspath(repo_root)
                package_path = os.path.abspath(os.path.join(repo_root, filename))
                if not package_path.startswith(repo_root_abs + os.sep) or not os.path.isfile(package_path):
                    errors += 1
                    fail(f"Missing package for Packages entry: {filename}")
                    continue

                actual_entry_size = file_size(package_path)
                actual_entry_md5 = file_hash(package_path, 'md5')
                actual_entry_sha256 = file_hash(package_path, 'sha256')
                entry_name = os.path.basename(package_path)

                if entry.get('Size') == str(actual_entry_size):
                    ok(f"Size matches for {entry_name}")
                else:
                    errors += 1
                    fail(f"Size mismatch for {entry_name}: Packages says {entry.get('Size')}, actual is {actual_entry_size}")

                if entry.get('MD5sum') == actual_entry_md5:
                    ok(f"MD5 matches for {entry_name}")
                else:
                    errors += 1
                    fail(f"MD5 mismatch for {entry_name}")

                if entry.get('SHA256') == actual_entry_sha256:
                    ok(f"SHA256 matches for {entry_name}")
                else:
                    errors += 1
                    fail(f"SHA256 mismatch for {entry_name}")

        # Check for placeholders
        if 'Size: 0' in content or 'Size: 0000' in content:
            errors += 1
            fail("Placeholder Size detected")
        if 'MD5sum: 00000000000000000000000000000000' in content:
            errors += 1
            fail("Placeholder MD5 detected")
        if 'SHA256: 0000000000000000000000000000000000000000000000000000000000000000' in content:
            errors += 1
            fail("Placeholder SHA256 detected")

    # 4. Validate Release file hashes against actual files
    print()
    print("[validate-repo] Validating Release against actual files...")
    release_path = os.path.join(repo_root, 'Release')
    if os.path.exists(release_path):
        with open(release_path) as f:
            rel_content = f.read()

        rel_checks = [
            ('Origin', 'Origin:'),
            ('Label', 'Label:'),
            ('Suite', 'Suite:'),
            ('Architectures', 'Architectures: iphoneos-arm64'),
            ('Components', 'Components: main'),
            ('MD5Sum section', 'MD5Sum:'),
            ('SHA256 section', 'SHA256:'),
        ]

        for name, text in rel_checks:
            if text in rel_content:
                ok(f"{name} present")
            else:
                errors += 1
                fail(f"{name} missing")

        # Verify Release hashes match actual Packages file
        packages_path = os.path.join(repo_root, 'Packages')
        if os.path.exists(packages_path):
            actual_pkg_size = file_size(packages_path)
            actual_pkg_md5 = file_hash(packages_path, 'md5')
            actual_pkg_sha256 = file_hash(packages_path, 'sha256')

            # Extract MD5 for Packages from Release
            md5_match = re.search(r'^ ([a-f0-9]{32})\s+\d+\s+Packages$', rel_content, re.MULTILINE)
            if md5_match:
                expected_md5 = md5_match.group(1)
                if expected_md5 == actual_pkg_md5:
                    ok(f"Release MD5 for Packages matches ({actual_pkg_md5})")
                else:
                    errors += 1
                    fail(f"Release MD5 mismatch: expected {expected_md5}, got {actual_pkg_md5}")

            # Extract SHA256 for Packages from Release
            sha256_match = re.search(r'^ ([a-f0-9]{64})\s+\d+\s+Packages$', rel_content, re.MULTILINE)
            if sha256_match:
                expected_sha = sha256_match.group(1)
                if expected_sha == actual_pkg_sha256:
                    ok(f"Release SHA256 for Packages matches ({actual_pkg_sha256})")
                else:
                    errors += 1
                    fail(f"Release SHA256 mismatch: expected {expected_sha}, got {actual_pkg_sha256}")

            # Extract Size for Packages from Release
            size_match = re.search(r'^ [a-f0-9]+\s+(\d+)\s+Packages$', rel_content, re.MULTILINE)
            if size_match:
                expected_size = int(size_match.group(1))
                if expected_size == actual_pkg_size:
                    ok(f"Release Size for Packages matches ({actual_pkg_size})")
                else:
                    errors += 1
                    fail(f"Release Size mismatch: expected {expected_size}, got {actual_pkg_size}")

    # Summary
    print()
    print("=" * 50)
    if errors == 0:
        print("✅ VALIDATION PASSED — Repository is Sileo-ready!")
        print(f"   Package: {debs[0]}")
        print(f"   Size: {actual_size} bytes")
        print(f"   MD5: {actual_md5}")
        print(f"   SHA256: {actual_sha256}")
        return 0
    else:
        print(f"❌ VALIDATION FAILED — {errors} error(s) found")
        return 1


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <repo-root>", file=sys.stderr)
        sys.exit(1)

    sys.exit(validate_repo(sys.argv[1]))
