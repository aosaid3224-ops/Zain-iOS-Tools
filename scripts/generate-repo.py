#!/usr/bin/env python3
"""Generate flat and standard APT indexes for a Sileo repository."""

import argparse
import bz2
import gzip
import hashlib
import lzma
import os
import subprocess
import time
from email.utils import formatdate

parser = argparse.ArgumentParser(description="Generate APT repository Packages/Release files")
parser.add_argument("repo_dir", nargs="?", default=".", help="Repository root directory")
parser.add_argument("--dev", action="store_true", help="Generate for dev repo (repo-dev)")
parser.add_argument("--prod", action="store_true", help="Generate for production repo (repo)")
args = parser.parse_args()

REPO_DIR = os.path.abspath(args.repo_dir)
POOL_ROOT = os.path.join(REPO_DIR, "pool", "main")
POOL_ARCHES = ("iphoneos-arm64", "iphoneos-arm64e")


def file_hash(data, algorithm):
    return hashlib.new(algorithm, data).hexdigest()


def package_info(path):
    return subprocess.check_output(["dpkg-deb", "-f", path], text=True).strip()


def compressions(text):
    data = text.encode("utf-8")
    return {
        "Packages": data,
        "Packages.gz": gzip.compress(data, mtime=0),
        "Packages.bz2": bz2.compress(data),
        "Packages.xz": lzma.compress(data),
    }


def write_indexes(directory, text):
    os.makedirs(directory, exist_ok=True)
    payloads = compressions(text)
    for name, data in payloads.items():
        with open(os.path.join(directory, name), "wb") as f:
            f.write(data)
    return payloads


def release_text(payloads, paths, origin, label, suite, codename, description, date_value):
    lines = [
        f"Origin: {origin}",
        f"Label: {label}",
        f"Suite: {suite}",
        "Version: 1.0",
        f"Codename: {codename}",
        f"Date: {date_value}",
        "Architectures: iphoneos-arm64 iphoneos-arm64e",
        "Components: main",
        f"Description: {description}",
        "",
    ]
    for label_name, algorithm in (("MD5Sum", "md5"), ("SHA1", "sha1"), ("SHA256", "sha256")):
        lines.append(f"{label_name}:")
        for name, data in payloads.items():
            lines.append(f" {file_hash(data, algorithm)} {len(data)} {paths[name]}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def parse_stanzas(text):
    return [block.strip() for block in text.strip().split("\n\n") if block.strip()]


def stanza_architecture(stanza):
    for line in stanza.splitlines():
        if line.startswith("Architecture:"):
            return line.split(":", 1)[1].strip()
    return ""


def main():
    package_stanzas = []
    for architecture in POOL_ARCHES:
        pool_dir = os.path.join(POOL_ROOT, architecture)
        if not os.path.isdir(pool_dir):
            continue
        for filename in sorted(os.listdir(pool_dir)):
            if not filename.endswith(".deb"):
                continue
            path = os.path.join(pool_dir, filename)
            entry = package_info(path)
            entry += f"\nFilename: pool/main/{architecture}/{filename}"
            entry += f"\nSize: {os.path.getsize(path)}"
            entry += f"\nMD5sum: {file_hash(open(path, 'rb').read(), 'md5')}"
            entry += f"\nSHA1: {file_hash(open(path, 'rb').read(), 'sha1')}"
            entry += f"\nSHA256: {file_hash(open(path, 'rb').read(), 'sha256')}"
            package_stanzas.append(entry)

    if not package_stanzas:
        raise SystemExit(f"No .deb packages found under {POOL_ROOT}")

    combined = "\n\n".join(package_stanzas) + "\n"
    origin, label = (("A-ZAIN Dev Repo", "A-ZAIN Development") if args.dev else ("A-ZAIN Repo", "A-ZAIN"))
    codename = "ios-dev" if args.dev else "ios"
    description = "A-ZAIN Development Repo - Private testing channel" if args.dev else "A-ZAIN Repo - Jailbreak tools and utilities"
    date_value = formatdate(time.time(), usegmt=True)

    # Keep the existing flat layout for sources configured with the ./ suite.
    root_payloads = write_indexes(REPO_DIR, combined)
    root_paths = {name: name for name in root_payloads}
    root_release = release_text(root_payloads, root_paths, origin, label, "stable", codename, description, date_value)
    with open(os.path.join(REPO_DIR, "Release"), "w", encoding="utf-8") as f:
        f.write(root_release)

    # Also publish the conventional Debian layout expected by APT/Sileo suites.
    stanzas_by_arch = {
        arch: [s for s in package_stanzas if stanza_architecture(s) == arch]
        for arch in (*POOL_ARCHES, "all")
    }
    dist_names = tuple(dict.fromkeys(("stable", codename)))
    for dist_name in dist_names:
        dist_dir = os.path.join(REPO_DIR, "dists", dist_name)
        payloads = {}
        paths = {}
        for arch, stanzas in stanzas_by_arch.items():
            text = "\n\n".join(stanzas) + ("\n" if stanzas else "")
            index_dir = os.path.join(dist_dir, "main", f"binary-{arch}")
            arch_payloads = write_indexes(index_dir, text)
            for name, data in arch_payloads.items():
                relative_path = f"main/binary-{arch}/{name}"
                payloads[relative_path] = data
                paths[relative_path] = relative_path
        dist_release = release_text(payloads, paths, origin, label, "stable", codename, description, date_value)
        with open(os.path.join(dist_dir, "Release"), "w", encoding="utf-8") as f:
            f.write(dist_release)

    print(f"Generated flat and dists indexes for {len(package_stanzas)} packages ({'dev' if args.dev else 'production'})")


if __name__ == "__main__":
    main()
