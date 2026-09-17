//
//  SpiderManagedAppsRegistry.m
//

#import "SpiderManagedAppsRegistry.h"
#import "SpiderInstalledAppsStore.h"

@implementation SpiderManagedApp
@end

@implementation SpiderManagedAppsRegistry {
    NSArray<SpiderManagedApp *> *_cached;
    BOOL _legacyMigrated;
}

+ (instancetype)sharedRegistry {
    static SpiderManagedAppsRegistry *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (instancetype)init { self = [super init]; [self refresh]; return self; }

- (NSArray<SpiderManagedApp *> *)managedApps { return _cached ?: @[]; }

- (void)refresh {
    [self migrateLegacyOnce];

    NSMutableArray<SpiderManagedApp *> *apps = [NSMutableArray array];
    NSDictionary *stored = [SpiderInstalledAppsStore sharedStore].allApps;
    for (NSString *bid in stored) {
        SpiderManagedApp *app = [self resolveAppForBundleID:bid storedEntry:stored[bid]];
        if (app) [apps addObject:app];
    }
    [apps sortUsingComparator:^NSComparisonResult(SpiderManagedApp *a, SpiderManagedApp *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    _cached = [apps copy];
}

#pragma mark - One-time legacy migration from OperationLog

- (void)migrateLegacyOnce {
    if (_legacyMigrated) return;
    _legacyMigrated = YES;

    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *logPath = [docs stringByAppendingPathComponent:@"IPAInstallerPro_OperationLog.plist"];
    id root = [NSDictionary dictionaryWithContentsOfFile:logPath] ?: [NSArray arrayWithContentsOfFile:logPath];
    if (!root) return;

    NSMutableSet<NSString *> *found = [NSMutableSet set];
    [self walk:root into:found];
    for (NSString *bid in found) {
        // Only add if the pipeline never recorded it in the authoritative store.
        if (![SpiderInstalledAppsStore sharedStore].allApps[bid]) {
            [[SpiderInstalledAppsStore sharedStore] noteInstalledAppWithBundleID:bid path:nil];
        }
    }
}

- (void)walk:(id)node into:(NSMutableSet<NSString *> *)outSet {
    if ([node isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = node;
        NSString *phaseName = d[@"phaseName"];
        NSString *resultName = d[@"resultName"];
        BOOL installPhase = [phaseName isEqualToString:@"UICACHE"] ||
                            [phaseName isEqualToString:@"VERIFY"] ||
                            [phaseName isEqualToString:@"COMPLETE"];
        if (installPhase && [resultName isEqualToString:@"SUCCESS"]) {
            NSString *bid = [self bundleIDFromContext:d[@"context"]] ?: [self bundleIDFromTarget:d[@"target"]];
            if ([self isValidBundleID:bid]) [outSet addObject:bid];
        }
        [d enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *s) { [self walk:v into:outSet]; }];
    } else if ([node isKindOfClass:[NSArray class]]) {
        for (id v in node) [self walk:v into:outSet];
    }
}

- (NSString *)bundleIDFromContext:(id)context {
    if (![context isKindOfClass:[NSDictionary class]]) return nil;
    for (NSString *key in (NSDictionary *)context) {
        if ([key.lowercaseString containsString:@"bundleid"] || [key.lowercaseString isEqualToString:@"bundle"]) {
            id v = context[key];
            if ([v isKindOfClass:[NSString class]] && [self isValidBundleID:v]) return v;
        }
    }
    return nil;
}

- (NSString *)bundleIDFromTarget:(id)target {
    if (![target isKindOfClass:[NSString class]]) return nil;
    NSString *path = target;
    if (![path containsString:@".app"]) return nil;
    NSString *appDir = path;
    NSRange r = [path rangeOfString:@".app"];
    if (r.location != NSNotFound) appDir = [path substringToIndex:r.location + 4];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appDir stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bid = info[@"CFBundleIdentifier"];
    return [self isValidBundleID:bid] ? bid : nil;
}

- (BOOL)isValidBundleID:(NSString *)bid {
    if (!bid.length || bid.length > 200) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9\\-\\.]+$"
                                                                         options:0 error:nil];
    return [re rangeOfFirstMatchInString:bid options:0 range:NSMakeRange(0, bid.length)].location == 0;
}

#pragma mark - Resolution (keeps recorded-but-missing apps)

- (SpiderManagedApp *)resolveAppForBundleID:(NSString *)bid storedEntry:(NSDictionary *)entry {
    SpiderManagedApp *app = [SpiderManagedApp new];
    app.bundleID = bid;
    app.currentlyInstalled = YES;

    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    id proxy = proxyClass ? [proxyClass applicationProxyForIdentifier:bid] : nil;
    NSURL *bundleURL = proxy ? [proxy valueForKey:@"bundleURL"] : nil;

    NSString *path = bundleURL.path ?: entry[@"path"];
    if (!path.length || ![path hasSuffix:@".app"]) {
        // Recorded but not currently on device: KEEP the row, flag it.
        app.currentlyInstalled = NO;
        app.name = bid;
        app.bundlePath = entry[@"path"] ?: @"";
        return app;
    }

    app.bundlePath = path;
    NSString *localizedName = [proxy valueForKey:@"localizedName"];
    if (!localizedName.length) {
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
        localizedName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: bid;
    }
    app.name = localizedName;
    app.icon = [self iconForBundleAtPath:path];
    return app;
}

- (UIImage *)iconForBundleAtPath:(NSString *)path {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
    NSArray *iconFiles = nil;
    NSDictionary *icons = info[@"CFBundleIcons"];
    NSDictionary *primary = icons[@"CFBundlePrimaryIcon"];
    if ([primary isKindOfClass:[NSDictionary class]]) iconFiles = primary[@"CFBundleIconFiles"];
    if (![iconFiles isKindOfClass:[NSArray class]] || !iconFiles.count) iconFiles = info[@"CFBundleIconFiles"];
    if (![iconFiles isKindOfClass:[NSArray class]] || !iconFiles.count) return nil;

    NSString *name = iconFiles.lastObject;
    NSArray *candidates = @[
        [path stringByAppendingPathComponent:name],
        [path stringByAppendingPathComponent:[name stringByAppendingString:@".png"]],
        [path stringByAppendingPathComponent:[name stringByAppendingString:@"@2x.png"]],
        [path stringByAppendingPathComponent:[name stringByAppendingString:@"@3x.png"]]
    ];
    for (NSString *p in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
            UIImage *img = [UIImage imageWithContentsOfFile:p];
            if (img) return img;
        }
    }
    return nil;
}

@end
