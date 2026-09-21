//
//  CLGameDiscovery.m
//
//  Classification: LSApplicationProxy genre + bundle marker heuristics.
//  Games-only output; user/system games both included.
//

#import "CLGameDiscovery.h"
#import "CLEngineDetector.h"

@implementation CLGameDiscovery

+ (long long)bundleSizeAtPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    if (!attrs) return 0;
    if ([attrs.fileType isEqualToString:NSFileTypeDirectory]) {
        // Sum top-level to keep it cheap; recursion cap below.
        long long total = 0;
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:path];
        NSString *rel; NSInteger n = 0;
        while ((rel = [en nextObject]) && n < 200000) {
            n++;
            NSDictionary *a = [en fileAttributes];
            if (a && [a.fileType isEqualToString:NSFileTypeRegular]) total += [a fileSize];
        }
        return total;
    }
    return [attrs fileSize];
}

- (void)discoverGamesWithCompletion:(void (^)(NSArray<CLGame *> *, NSString *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<id> *rawProxies = [NSMutableArray array];
        NSString *mechanism = nil;
        NSString *errorMsg = nil;

        // ── Mechanism chain: first that returns real proxies wins ──
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        id workspace = ([wsClass respondsToSelector:@selector(defaultWorkspace)])
            ? [wsClass performSelector:@selector(defaultWorkspace)] : nil;

        if (workspace) {
            // (1) Block enumeration — the stable modern SPI across iOS 13–18.
            SEL enumSel = NSSelectorFromString(@"enumerateApplicationsOfType:legacySPI:block:");
            if (![workspace respondsToSelector:enumSel])
                enumSel = NSSelectorFromString(@"enumerateApplicationsOfType:legacySPI:usingBlock:");
            if ([workspace respondsToSelector:enumSel]) {
                void (^proxyBlock)(id) = ^(id proxy) {
                    if (proxy) [rawProxies addObject:proxy];
                };
                @try {
                    NSMethodSignature *sig = [workspace methodSignatureForSelector:enumSel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:workspace];
                    [inv setSelector:enumSel];
                    unsigned long long type = 0;   // 0 = all applications
                    BOOL legacy = NO;
                    [inv setArgument:&type atIndex:2];
                    [inv setArgument:&legacy atIndex:3];
                    [inv setArgument:&proxyBlock atIndex:4];
                    [inv invoke];
                    if (rawProxies.count > 0) mechanism = @"LSApplicationWorkspace enumerateApplicationsOfType";
                } @catch (NSException *e) {
                    errorMsg = [NSString stringWithFormat:@"فشل التعداد بالـ block: %@", e.reason ?: @"خطأ غير معروف"];
                    [rawProxies removeAllObjects];
                }
            }

            // (2) Instance allInstalledApplications on the WORKSPACE
            //     (the previous bug called this on LSApplicationProxy, which
            //     does not implement it — unrecognized selector).
            if (!mechanism && [workspace respondsToSelector:@selector(allInstalledApplications)]) {
                @try {
                    id apps = [workspace performSelector:@selector(allInstalledApplications)];
                    if ([apps isKindOfClass:[NSArray class]] && [apps count] > 0) {
                        [rawProxies addObjectsFromArray:apps];
                        mechanism = @"LSApplicationWorkspace allInstalledApplications";
                    }
                } @catch (NSException *e) {
                    errorMsg = [NSString stringWithFormat:@"فشل allInstalledApplications: %@", e.reason ?: @"خطأ غير معروف"];
                }
            }
        }

        if (!mechanism || rawProxies.count == 0) {
            NSString *final = [NSString stringWithFormat:
                @"تعذّر جلب التطبيقات من كل الآليات المتاحة. %@", errorMsg ?: @"لا توجد آلية LaunchServices متاحة."];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], final); });
            return;
        }

        // ── Classification: games only, robust per-proxy handling ──
        NSMutableArray<CLGame *> *games = [NSMutableArray array];
        for (id proxy in rawProxies) {
            @autoreleasepool {
                @try {
                    NSString *bundleID = [proxy valueForKey:@"bundleIdentifier"];
                    NSString *name = [proxy valueForKey:@"localizedName"];
                    NSURL *bundleURL = [proxy valueForKey:@"bundleURL"];
                    NSString *bundlePath = bundleURL.path;
                    if (!bundleID.length || !bundlePath.length) continue;
                    if (![bundlePath hasSuffix:@".app"]) continue;

                    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                        [bundlePath stringByAppendingPathComponent:@"Info.plist"]];
                    if (!info) continue;

                    BOOL isGame = NO;
                    @try {
                        NSArray *genreIDs = [proxy valueForKey:@"genreIDs"];
                        for (id gid in genreIDs) {
                            if ([gid respondsToSelector:@selector(integerValue)] && [gid integerValue] == 6014) { isGame = YES; break; }
                        }
                        if (!isGame) {
                            NSString *genre = [proxy valueForKey:@"genre"];
                            if ([genre.lowercaseString containsString:@"game"]) isGame = YES;
                        }
                        if (!isGame) {
                            NSArray *genres = [proxy valueForKey:@"genres"];
                            for (NSString *g in genres) {
                                if ([g.lowercaseString containsString:@"game"]) { isGame = YES; break; }
                            }
                        }
                    } @catch (__unused NSException *e) {}

                    if (!isGame) {
                        NSArray *fw = nil;
                        CLGameEngine eng = [CLEngineDetector detectEngineForBundle:bundlePath linkedFrameworks:&fw];
                        if (eng == CLGameEngineUnity || eng == CLGameEngineUnreal || eng == CLGameEngineGodot)
                            isGame = YES;
                    }
                    if (!isGame) continue;

                    CLGame *game = [CLGame new];
                    game.bundleID = bundleID;
                    game.name = name.length ? name : bundleID;
                    game.bundlePath = bundlePath;
                    game.version = info[@"CFBundleShortVersionString"] ?: info[@"CFBundleVersion"] ?: @"؟";
                    game.executablePath = info[@"CFBundleExecutable"].length
                        ? [bundlePath stringByAppendingPathComponent:info[@"CFBundleExecutable"]] : nil;
                    game.lastModified = [[NSFileManager defaultManager]
                        attributesOfItemAtPath:bundlePath error:nil].fileModificationDate;
                    game.icon = [self iconForBundle:bundlePath info:info];

                    NSArray *fw = nil;
                    game.engine = [CLEngineDetector detectEngineForBundle:bundlePath linkedFrameworks:&fw];
                    game.engineName = [CLEngineDetector localizedNameForEngine:game.engine];
                    game.frameworks = fw;
                    game.bundleSize = [CLGameDiscovery bundleSizeAtPath:bundlePath];

                    [games addObject:game];
                } @catch (__unused NSException *e) { continue; }
            }
        }

        [games sortUsingComparator:^NSComparisonResult(CLGame *a, CLGame *b) {
            return [a.name localizedCaseInsensitiveCompare:b.name];
        }];

        // Successful discovery is only claimed when a real list came back.
        NSString *summary = [NSString stringWithFormat:
            @"%ld تطبيق ممسوح · %ld لعبة · الآلية: %@",
            (long)rawProxies.count, (long)games.count, mechanism];
        [[CLOperationLog sharedLog] addEntryWithKind:CLOperationKindDiscovery
            status:CLOperationStatusSuccess title:@"اكتشاف الألعاب" detail:summary];

        dispatch_async(dispatch_get_main_queue(), ^{ completion([games copy], nil); });
    }];
}

- (UIImage *)iconForBundle:(NSString *)path info:(NSDictionary *)info {
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
        [path stringByAppendingPathComponent:[name stringByAppendingString:@"@3x.png"]],
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
