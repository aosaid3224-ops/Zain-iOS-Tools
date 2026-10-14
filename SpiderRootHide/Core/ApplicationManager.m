#import "ApplicationManager.h"
#import <objc/runtime.h>
#import <dlfcn.h>

#import "Logger.h"

@implementation AppInfo
@end

@interface ApplicationManager ()
@property (nonatomic, strong) NSCache *iconCache;
@property (nonatomic, strong) NSArray<NSString *> *protectedApps;
@end

@implementation ApplicationManager

+ (instancetype)sharedManager {
    static ApplicationManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _iconCache = [[NSCache alloc] init];
        _iconCache.countLimit = 200;
        _protectedApps = @[
            @"com.apple.springboard", @"com.apple.Preferences",
            @"com.apple.mobilesafari", @"com.apple.MobileSMS",
            @"com.apple.mobilephone", @"com.apple.camera",
            @"com.apple.mobilemail", @"com.apple.Maps",
            @"com.apple.mobilecal", @"com.apple.mobileslideshow",
            @"com.apple.AppStore", @"com.apple.Health",
            @"com.apple.mobiletimer", @"com.apple.weather",
            @"com.apple.news", @"com.apple.podcasts",
            @"com.apple.music", @"com.apple.mobilewallet",
            @"com.apple.stocks", @"com.apple.Home",
            @"com.apple.findmy", @"com.apple.shortcuts",
            @"com.apple.translate", @"com.apple.compass",
            @"com.apple.calculator", @"com.apple.mobilenotes",
            @"com.apple.reminders", @"com.apple.facetime",
            @"com.apple.mobileipod"
        ];
    }
    return self;
}

- (NSArray<AppInfo *> *)allInstalledApplications {
    NSMutableArray<AppInfo *> *apps = [NSMutableArray array];

    Class LSApplicationWorkspace_class = objc_getClass("LSApplicationWorkspace");
    if (!LSApplicationWorkspace_class) return apps;

    id workspace = [LSApplicationWorkspace_class performSelector:@selector(defaultWorkspace)];
    if (!workspace) return apps;

    NSArray *allApps = nil;
    @try {
        allApps = [workspace performSelector:@selector(allInstalledApplications)];
    } @catch (NSException *e) { return apps; }

    if (!allApps) return apps;

    for (id app in allApps) {
        @try {
            AppInfo *info = [[AppInfo alloc] init];
            info.bundleID = [app performSelector:@selector(bundleIdentifier)] ?: @"";
            info.name = [app performSelector:@selector(localizedName)] ?: info.bundleID;
            info.version = [app performSelector:@selector(shortVersionString)] ?: @"";

            if ([app respondsToSelector:@selector(applicationType)]) {
                info.appType = [app performSelector:@selector(applicationType)] ?: @"User";
            } else {
                info.appType = @"User";
            }

            info.isSystemApp = [self isSystemApp:info.bundleID];
            info.isProtected = [self isProtectedApp:info.bundleID];

            if ([app respondsToSelector:@selector(bundleURL)]) {
                info.bundlePath = [[app performSelector:@selector(bundleURL)] path];
            } else if ([app respondsToSelector:@selector(containerURL)]) {
                info.bundlePath = [[app performSelector:@selector(containerURL)] path];
            }

            info.icon = [self iconForBundleID:info.bundleID bundlePath:info.bundlePath];

            [apps addObject:info];
        } @catch (NSException *e) { continue; }
    }

    return [apps sortedArrayUsingComparator:^NSComparisonResult(AppInfo *a, AppInfo *b) {
        return [a.name compare:b.name options:NSCaseInsensitiveSearch];
    }];
}

- (NSArray<AppInfo *> *)userApplications {
    return [[self allInstalledApplications] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isSystemApp == NO"]];
}

- (NSArray<AppInfo *> *)systemApplications {
    return [[self allInstalledApplications] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isSystemApp == YES"]];
}

- (AppInfo *)appInfoForBundleID:(NSString *)bundleID {
    for (AppInfo *app in [self allInstalledApplications]) {
        if ([app.bundleID isEqualToString:bundleID]) return app;
    }
    return nil;
}

- (UIImage *)iconForBundleID:(NSString *)bundleID bundlePath:(NSString *)bundlePath {
    if (!bundleID) return nil;
    UIImage *cached = [self.iconCache objectForKey:bundleID];
    if (cached) return cached;

    UIImage *icon = nil;

    @try {
        Class LSApplicationProxy_class = objc_getClass("LSApplicationProxy");
        if (LSApplicationProxy_class && [LSApplicationProxy_class respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
            id proxy = [LSApplicationProxy_class performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleID];
            if (proxy) {
                NSArray *variants = @[@(0), @(1), @(2), @(10)];
                for (NSNumber *variant in variants) {
                    if ([proxy respondsToSelector:@selector(iconDataForVariant:)]) {
                        NSData *iconData = [proxy performSelector:@selector(iconDataForVariant:) withObject:variant];
                        if (iconData) {
                            icon = [UIImage imageWithData:iconData];
                            if (icon) break;
                        }
                    }
                }
            }
        }
    } @catch (NSException *e) {}

    if (!icon && bundlePath.length > 0) {
        NSString *infoPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        if (plist) {
            NSArray *iconFiles = nil;
            NSDictionary *iconsDict = plist[@"CFBundleIcons"];
            NSDictionary *primaryIcon = iconsDict[@"CFBundlePrimaryIcon"];
            iconFiles = primaryIcon[@"CFBundleIconFiles"];
            if (!iconFiles) iconFiles = plist[@"CFBundleIconFiles"];
            if (!iconFiles || iconFiles.count == 0) iconFiles = @[@"AppIcon60x60"];

            for (NSString *iconName in [iconFiles reverseObjectEnumerator]) {
                for (NSString *scale in @[@"@3x", @"@2x", @""]) {
                    for (NSString *ext in @[@".png", @".jpg", @".jpeg"]) {
                        NSString *path = [bundlePath stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"%@%@%@", iconName, scale, ext]];
                        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                            icon = [UIImage imageWithContentsOfFile:path];
                            if (icon) break;
                        }
                    }
                    if (icon) break;
                }
                if (icon) break;
            }
        }
    }

    if (icon) [self.iconCache setObject:icon forKey:bundleID];
    return icon;
}

- (UIImage *)iconForBundleID:(NSString *)bundleID {
    if (!bundleID) return nil;

    NSString *bundlePath = nil;
    @try {
        Class LSApplicationProxy_class = objc_getClass("LSApplicationProxy");
        if (LSApplicationProxy_class && [LSApplicationProxy_class respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
            id proxy = [LSApplicationProxy_class performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleID];
            if (proxy && [proxy respondsToSelector:@selector(bundleURL)]) {
                bundlePath = [[proxy performSelector:@selector(bundleURL)] path];
            }
        }
    } @catch (NSException *e) {}

    return [self iconForBundleID:bundleID bundlePath:bundlePath];
}

- (NSString *)versionForBundleID:(NSString *)bundleID {
    if (!bundleID) return @"\u063a\u064a\u0631 \u0645\u0639\u0631\u0648\u0641";
    Class LSApplicationProxy_class = objc_getClass("LSApplicationProxy");
    if (LSApplicationProxy_class && [LSApplicationProxy_class respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
        id proxy = [LSApplicationProxy_class performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleID];
        if (proxy && [proxy respondsToSelector:@selector(shortVersionString)]) {
            return [proxy performSelector:@selector(shortVersionString)] ?: @"\u063a\u064a\u0631 \u0645\u0639\u0631\u0648\u0641";
        }
    }
    return @"\u063a\u064a\u0631 \u0645\u0639\u0631\u0648\u0641";
}

- (BOOL)isSystemApp:(NSString *)bundleID {
    if (!bundleID) return NO;
    return [self.protectedApps containsObject:bundleID] || [bundleID hasPrefix:@"com.apple."];
}

- (BOOL)isProtectedApp:(NSString *)bundleID {
    if (!bundleID) return NO;
    return [self.protectedApps containsObject:bundleID];
}

- (void)killApp:(NSString *)bundleID {
    if (!bundleID) return;
    @try {
        void *fbHandle = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
        if (fbHandle) {
            Class FBSSystemService_class = NSClassFromString(@"FBSSystemService");
            if (FBSSystemService_class && [FBSSystemService_class respondsToSelector:@selector(sharedService)]) {
                id service = [FBSSystemService_class performSelector:@selector(sharedService)];
                SEL killSel = @selector(terminateApplication:forReason:andReport:completion:);
                if (service && [service respondsToSelector:killSel]) {
                    NSMethodSignature *sig = [service methodSignatureForSelector:killSel];
                    if (sig) {
                        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                        [inv setSelector:killSel];
                        [inv setTarget:service];
                        NSString *bid = bundleID;
                        NSNumber *reason = @(1);
                        NSNumber *report = @(NO);
                        [inv setArgument:&bid atIndex:2];
                        [inv setArgument:&reason atIndex:3];
                        [inv setArgument:&report atIndex:4];
                        [inv invoke];
                    }
                }
            }
        }
    } @catch (NSException *e) {}
}

@end
