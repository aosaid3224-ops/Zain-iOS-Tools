# MaxDock iOS 16 rootless migration

## Phase 1: dock magnification preview (current)

The package is filtered to `com.apple.springboard`, verifies iOS 16 and checks
the runtime classes before initializing its hook group. Based on the iOS 16.3
SpringBoardHome headers it prefers `SBDockIconListView`, with `SBDockView` as a
fallback, and requires `SBIconView`. It adds a simultaneous, non-cancelling pan
recognizer to the dock list and discovers
visible icon views through the live view hierarchy. Nearby icons are scaled and
lifted using transforms, then restored when the gesture ends or is cancelled.

Native icon touch handling is not replaced, so tapping and launching remain
owned by SpringBoard. Missing runtime classes disable Harbor instead of causing
SpringBoard to abort.

The remaining original iOS 10 implementation is retained in `SBIconView.xm` and
in git history. It is not part of `Harbor_FILES` in this phase.

## Obsolete API inventory

| Legacy dependency | Why it is unsafe on iOS 16 | Migration direction |
| --- | --- | --- |
| `SBDockIconListView` initializers/layout methods | Signatures and layout ownership changed | Discover the live dock list/view classes and hook only selectors verified with `respondsToSelector:` |
| `SBIconController sharedInstance`, `dockListView`, `iconTapped:` | Old singleton and launch path | Obtain icon views from the active root-folder hierarchy; launch through the current icon-view delegate/action path |
| `SBIconViewMap mappedIconViewForIcon:` | Mapping internals changed | Enumerate visible dock icon views from the dock list view instead of relying on the old map |
| `model.icons` / `numberOfIcons` | Model structure and accessors changed | Read arranged/visible icon views from the current list layout |
| `defaultVisibleIconImageSize`, `defaultIconSize` | Class sizing APIs changed | Derive geometry from each visible icon view/image container bounds |
| `UIApplication.statusBarOrientation` | Deprecated and scene-inaccurate | Use the active `UIWindowScene.interfaceOrientation` and dock geometry |
| `SBUIController` bounce windows | Removed/changed global UI ownership | Defer bounce overlay; use a scene-attached passthrough window only after lifecycle testing |
| `SBUIAppIconForceTouchController` | 3D Touch implementation replaced | Defer menus and use current context-menu interaction/delegate behavior |
| `SBIconFadeAnimator`, `SBScaleIconZoomAnimator` ivars | Private animator internals are version-specific | Do not hook or mutate animator ivars; initially let SpringBoard own launch animations |
| `MSHookIvar` on `_dockIconToViewMap`, `_iconListView`, `_backgroundView`, `_labelView` | Hard crash risk when ivars move/disappear | Replace with public view traversal/properties or runtime-checked access; never assume an ivar exists |
| `BBServer` bulletin hooks | BulletinBoard internals and process boundaries changed | Defer notification bounce until the dock core is stable; use a dedicated modern notification source |

## Planned feature groups

1. `HarborDockCore`: runtime-gated discovery of the iOS 16 dock and visible icon views.
2. `HarborMagnification`: touch/pan tracking and transforms, with SpringBoard layout restored on cancellation.
3. `HarborActivation`: launch the focused icon via the current delegate path.
4. `HarborIndicators`: app-name and running-state indicators.
5. `HarborBounce`: notification/launch bounce behavior.
6. Preferences: a separate rootless PreferenceLoader bundle after core stability.

Each group should be initialized only when all required classes and selectors are
present. A missing API must disable that group rather than abort SpringBoard.
