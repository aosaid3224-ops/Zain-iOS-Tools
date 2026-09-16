//
//  SpiderManagedAppsRegistry.m
//
//  Source of truth: the persisted OperationLog. Only bundle IDs that went
//  through a SUCCESSFUL installation pipeline appear here. Names/icons are
//  resolved from the live bundle on disk; apps uninstalled since are dropped.
//

#import "SpiderManagedAppsRegistry.h"
#import "RootlessManager.h"

@implementation SpiderManagedApp
@end

@implementation SpiderManagedAppsRegistry {
    NSArray<SpiderManagedApp *> *_cached;
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
    NSMutableSet<NSString *> *bundleIDs = [NSMutableSet set];
    [self collectBundleIDsFromOperationLogInto:bundleIDs];

    NSMutableArray<SpiderManagedApp *> *apps = [NSMutableArray array];
    for (NSString *bid in bundleIDs) {
        SpiderManagedApp *app = [self resolveAppForBundleID:bid];
        if (app) [apps addObject:app];
    }
    [apps sortUsingComparator:^NSComparisonResult(SpiderManagedApp *a, SpiderManagedApp *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    _cached = [apps copy];
}

#pragma mark - OperationLog scan

- (void)collectBundleIDsFromOperationLogInto:(NSMutableSet<NSString *> *)outSet {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *logPath = [docs stringByAppendingPathComponent:@"IPAInstallerPro_OperationLog.plist"];
    id root = [NSDictionary dictionaryWithContentsOfFile:logPath] ?: [NSArray arrayWithContentsOfFile:logPath];
    if (!root) return;
    [self walk:root into:outSet];
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
            NSString *bid = [self bundleIDFromContext:d[@"context"]];
            if (!bid) bid = [self bundleIDFromTarget:d[@"target"]];
            if ([self isValidBundleID:bid]) [outSet addObject:bid];
        }
        [d enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *s) { [self walk:v into:outSet]; }];
    } else if ([node isKindOfClass:[NSArray class]]) {
        for (id v in node) [self walk:v into:outSet];
    }
}

- (NSString *)bundleIDFromContext:(id)context {
    if (![context isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *c = context;
    for (NSString *key in c) {
        if ([key.lowercaseString containsString:@"bundleid"] || [key.lowercaseString isEqualToString:@"bundle"]) {
            id v = c[key];
            if ([v isKindOfClass:[NSString class]] && [self isValidBundleID:v]) return v;
        }
    }
    return nil;
}

- (NSString *)bundleIDFromTarget:(id)target {
    if (![target isKindOfClass:[NSString class]]) return nil;
    NSString *path = (NSString *)target;
    if (![path hasSuffix:@".app"] && ![path containsString:@".app/"]) return nil;
    NSString *appDir = path;
    if ([path containsString:@".app/"]) {
        NSRange r = [path rangeOfString:@".app/"];
        appDir = [path substringToIndex:r.location + 4];
    }
    NSString *infoPath = [appDir stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    NSString *bid = info[@"CFBundleIdentifier"];
    return [self isValidBundleID:bid] ? bid : nil;
}

- (BOOL)isValidBundleID:(NSString *)bid {
    if (!bid.length || bid.length > 200) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9\\-\\.]+$"
                                                                         options:0 error:nil];
    return [re rangeOfFirstMatchInString:bid options:0 range:NSMakeRange(0, bid.length)].location == 0;
}

#pragma mark - App resolution

- (SpiderManagedApp *)resolveAppForBundleID:(NSString *)bid {
    // LaunchServices lookup (private API, mirrors ForensicRegistrationProbe).
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if (!proxyClass) return nil;
    id proxy = [proxyClass applicationProxyForIdentifier:bid];
    if (!proxy) return nil;
    NSURL *bundleURL = [proxy valueForKey:@"bundleURL"];
    if (!bundleURL) return nil;
    NSString *path = bundleURL.path;
    if (!path.length || ![path hasSuffix:@".app"]) return nil;

    SpiderManagedApp *app = [SpiderManagedApp new];
    app.bundleID = bid;
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
    if (!iconFiles.count) iconFiles = info[@"CFBundleIconFiles"];
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
