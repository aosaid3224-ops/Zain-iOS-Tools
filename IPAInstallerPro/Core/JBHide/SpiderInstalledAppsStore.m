//
//  SpiderInstalledAppsStore.m
//

#import "SpiderInstalledAppsStore.h"

@implementation SpiderInstalledAppsStore {
    NSMutableDictionary *_apps;
    NSString *_plistPath;
}

+ (instancetype)sharedStore {
    static SpiderInstalledAppsStore *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    _plistPath = [docs stringByAppendingPathComponent:@"SpiderInstalledApps.plist"];
    NSDictionary *raw = [NSDictionary dictionaryWithContentsOfFile:_plistPath] ?: @{};
    _apps = [raw mutableCopy];
    return self;
}

- (void)noteInstalledAppWithBundleID:(NSString *)bundleID path:(NSString *)appPath {
    if (!bundleID.length) return;
    NSMutableDictionary *entry = [_apps[bundleID] mutableCopy] ?: [NSMutableDictionary dictionary];
    entry[@"bundleID"] = bundleID;
    if (appPath.length) entry[@"path"] = appPath;
    if (!entry[@"firstInstalledAt"]) entry[@"firstInstalledAt"] = [NSDate date];
    entry[@"lastInstalledAt"] = [NSDate date];
    entry[@"installCount"] = @([entry[@"installCount"] integerValue] + 1);
    _apps[bundleID] = entry;
    [self persist];
}

- (NSDictionary<NSString *, NSDictionary *> *)allApps { return [_apps copy]; }

- (void)persist {
    [_apps writeToFile:_plistPath atomically:YES];
}

@end
