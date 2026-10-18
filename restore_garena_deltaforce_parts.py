#!/usr/bin/env python3
"""Rebuild oversized files split for ordinary Git hosting limits."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath

REPO = Path(__file__).resolve().parent
ROOT = REPO / 'GarenaDeltaForce_unpacked'
MANIFEST = ROOT / '_git_parts' / 'manifest.json'


def safe_rel(value: str) -> Path:
    rel = PurePosixPath(value)
    if rel.is_absolute() or '..' in rel.parts or '\\' in value:
        raise ValueError(f'Unsafe manifest path: {value!r}')
    return Path(*rel.parts)


def main() -> None:
    manifest = json.loads(MANIFEST.read_text())
    for entry in manifest['files']:
        target = ROOT / safe_rel(entry['target'])
        expected_size = int(entry['size'])
        expected_sha = entry['sha256']
        if target.exists():
            h = hashlib.sha256()
            with target.open('rb') as f:
                for block in iter(lambda: f.read(8 * 1024 * 1024), b''):
                    h.update(block)
            if target.stat().st_size == expected_size and h.hexdigest() == expected_sha:
                print(f'Already restored: {entry["target"]}')
                continue
            raise SystemExit(f'Refusing to overwrite non-matching file: {target}')

        target.parent.mkdir(parents=True, exist_ok=True)
        temp = target.with_name(target.name + '.assembling')
        h = hashlib.sha256()
        size = 0
        try:
            with temp.open('wb') as out:
                for part_name in entry['parts']:
                    part = ROOT / safe_rel(part_name)
                    with part.open('rb') as src:
                        for block in iter(lambda: src.read(8 * 1024 * 1024), b''):
                            out.write(block)
                            h.update(block)
                            size += len(block)
            if size != expected_size or h.hexdigest() != expected_sha:
                raise SystemExit(f'Integrity check failed while rebuilding {entry["target"]}')
            os.chmod(temp, int(entry.get('mode', 0o644)))
            os.replace(temp, target)
            print(f'Restored {entry["target"]}: {size:,} bytes; SHA256 verified')
        finally:
            if temp.exists():
                temp.unlink()

    print('All oversized files are reconstructed. Git parts were retained.')


if __name__ == '__main__':
    main()
