# DragonGA.dylib — split archive

The original dylib is split into four ordered parts. Verify each part and reconstruct the original with:

```sh
cat "dylib DARGON"/DragonGA.dylib.part01 "dylib DARGON"/DragonGA.dylib.part02 "dylib DARGON"/DragonGA.dylib.part03 "dylib DARGON"/DragonGA.dylib.part04 > DragonGA.dylib
sha256sum DragonGA.dylib
```

Compare the resulting SHA-256 with `original_sha256` in `manifest.json`.
