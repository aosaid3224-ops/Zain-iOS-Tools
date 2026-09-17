# CarTV 1.0.8 — Static Analysis Package

This directory contains a **static, non-invasive analysis** of the supplied `CarTV.ipa`. It is intended for review and interoperability research. It does not include the original application binary, a decrypted payload, extracted credentials, or a reconstructed source tree.

## Scope

The analysis covers the application metadata, supported devices and OS, URL-scheme queries, privacy declarations, scene and extension registration, embedded framework inventory, binary hashes, file inventory, printable strings, and a domain-only network indicator list.

## Identified components

| Component | Identifier | Version | Notes |
|---|---|---:|---|
| Main app | `com.lyntra.player` | `1.0.8 (21)` | arm64; minimum iOS 18; portrait iPhone UI; CarPlay and external-display scenes |
| ScreenRelay | `com.lyntra.player.ScreenRelay` | `1.0.8 (21)` | ReplayKit broadcast upload extension |
| CastWidget | `com.lyntra.player.CastWidget` | `1.0.8 (21)` | WidgetKit extension |
| MobileVLCKit | embedded framework | — | arm64 dynamic framework; media playback dependency |

## Declared capabilities

The metadata declares local-network access, camera access for QR scanning, photo-library access for importing videos, background audio, Bonjour service `_lyntracast._tcp`, and arbitrary App Transport Security loads. The app queries many third-party URL schemes, including media, social, messaging, and streaming applications; scheme queries do not prove that those services are contacted.

## Important limitation

An IPA normally contains compiled Mach-O code, not Objective-C/Swift source. A complete source-level reconstruction cannot be guaranteed without the developer's source, symbols, or explicit authorization and appropriate tooling. This package therefore records observable artifacts rather than claiming a nonexistent “full decompilation.” DRM, FairPlay encryption, code-signature bypass, credential extraction, and protected-data recovery were intentionally not attempted.

## Files

- `Info.plist.json` and extension plist JSON files: normalized metadata.
- `PrivacyInfo.xcprivacy.json`: privacy manifest.
- `file-inventory.tsv`: all app files and sizes.
- `binary-summary.json`: binary sizes and SHA-256 hashes.
- `strings/`: printable strings extracted from embedded binaries.
- `network-domains.txt`: domains observed in printable strings, without URL paths or query values.
- `SHA256SUMS`: integrity hashes for this analysis package.

Generated from the supplied IPA on 2026-09-18.
