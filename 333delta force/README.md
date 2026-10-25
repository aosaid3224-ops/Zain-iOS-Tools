# Garena Delta Force — IPA extraction

This directory contains the extracted contents of `GarenaDeltaForce.ipa` (654 archive entries; 487 regular files; 1,298,700,736 expanded bytes).

The IPA container has been fully extracted, preserving its `Payload/DeltaForceClient.app` tree and bundled resources. Two files exceed GitHub's 100 MB ordinary-Git per-file limit, so they are stored as verified parts under `_git_parts/` rather than as single blobs. After cloning the repository, restore them from the repository root with:

```bash
python3 "333delta force/restore_garena_deltaforce_parts.py"
```

The script verifies each reconstructed file's byte length and SHA-256 and preserves its executable mode. It leaves the parts in place. The Mach-O executable and Unreal `.pak` data are retained in their original packaged formats; this extraction does not decompile the executable or unpack encrypted/game-specific asset containers.
