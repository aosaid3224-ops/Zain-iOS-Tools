//
//  SpiderInstalledAppsStore.h
//  IPAInstallerPro — authoritative registry of Spider-installed apps.
//
//  Written ONLY at the install-success point of the installation pipeline.
//  This is the single source of truth for "which apps did Spider install";
//  UI lists read from here, never from transient state or ad-hoc scans.
//

#import <Foundation/Foundation.h>

@interface SpiderInstalledAppsStore : NSObject
+ (instancetype)sharedStore;

/// Called by the installation pipeline after a successful install. Updates
/// lastInstalledAt/installCount if the bundleID already exists.
- (void)noteInstalledAppWithBundleID:(NSString *)bundleID path:(NSString *)appPath;

/// All registered entries: bundleID -> {bundleID, path, firstInstalledAt,
/// lastInstalledAt, installCount}. Entries persist across reboots/reinstalls.
- (NSDictionary<NSString *, NSDictionary *> *)allApps;
@end
