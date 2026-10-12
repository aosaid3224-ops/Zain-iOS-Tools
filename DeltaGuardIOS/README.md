# DeltaGuardIOS 0.1.0

Native iOS recreation of the visible UI from the supplied Android APK `游戏保镖 V4.4`.

## Implemented

- Home dashboard and status display
- Permission-mode selection UI
- Server selection UI for Mainland, International, and Taiwan packages
- Settings screen with dark mode, cache/data reset, tutorial, and version
- In-app floating-tool panel with explicit honest status messages
- No Android DEX, Android runtime, injection claim, or fake success state

## Not implemented

The Android APK's injection engine, Android permissions (Shizuku/root/SAF), external process control, and game modification behavior are not portable to iOS and are intentionally not represented as working features.

## Build

```sh
make package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
```
