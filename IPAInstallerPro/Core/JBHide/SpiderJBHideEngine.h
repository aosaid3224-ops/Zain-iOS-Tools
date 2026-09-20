//
//  SpiderJBHideEngine.h
//  Jailbreak Hiding — per-app mechanism orchestration.
//
//  Mechanism: per-app ElleKit tweak injection. A self-contained interposition
//  dylib (no substrate/libhooker dependency) is dropped into the jailbreak
//  TweakInject directory with a bundle-filter plist. ON = files installed +
//  launch-proven. OFF = files removed. No Mach-O surgery, no re-signing of the
//  target app, works on already-installed apps.
//

#import <Foundation/Foundation.h>
#import "SpiderJBHideTypes.h"

@interface SpiderJBHideEngine : NSObject
+ (instancetype)sharedEngine;

/// Applies mechanism + runs launch probe. Completion on main queue.
- (void)applyHidingForBundleID:(NSString *)bundleID completion:(void (^)(SpiderJBHideResult *result))completion;
/// Removes mechanism. Completion on main queue.
- (void)removeHidingForBundleID:(NSString *)bundleID completion:(void (^)(SpiderJBHideResult *result))completion;
/// Static state only (files presence). No side effects.
- (SpiderJBHideResult *)staticStatusForBundleID:(NSString *)bundleID;

/// World-readable marker directory written by the injected dylib on load.
+ (NSString *)markerDirectoryPath;
/// Whether any TweakInject directory is present on this jailbreak.
- (BOOL)isMechanismAvailableWithReason:(NSString **)reason;
@end
