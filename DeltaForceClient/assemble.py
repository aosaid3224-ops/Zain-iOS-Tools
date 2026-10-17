#!/usr/bin/env python3
from pathlib import Path
import hashlib
import sys

ROOT = Path(__file__).resolve().parent
PARTS = [ROOT / f"DeltaForceClient.part{i:03d}" for i in range(1, 6)]
OUTPUT = ROOT / "DeltaForceClient"
EXPECTED_SIZE = 416_167_600
EXPECTED_SHA256 = "175b75f14edcdd409d3267f19ec3997b6fda415d71a0b3c7650d66b040bdc599"

if any(not p.is_file() for p in PARTS):
    missing = [str(p.name) for p in PARTS if not p.is_file()]
    sys.exit("Missing parts: " + ", ".join(missing))

sha = hashlib.sha256()
size = 0
with OUTPUT.open("wb") as out:
    for part in PARTS:
        with part.open("rb") as src:
            while block := src.read(8 * 1024 * 1024):
                out.write(block)
                sha.update(block)
                size += len(block)
if size != EXPECTED_SIZE or sha.hexdigest() != EXPECTED_SHA256:
    OUTPUT.unlink(missing_ok=True)
    sys.exit(f"Verification failed: size={size}, sha256={sha.hexdigest()}")
print(f"Reassembled and verified: {OUTPUT} ({size} bytes)")
print(f"SHA-256: {sha.hexdigest()}")
