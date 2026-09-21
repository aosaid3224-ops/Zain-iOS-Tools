//
//  CLGameDiscovery.m
//

#import "CLGameDiscovery.h"
#import "CLEngineDetector.h"
#import "CLOperationLog.h"

@implementation CLGameDiscovery {
    NSArray<CLDiscoveryRecord *> *_lastDiagnostics;
}

#pragma mark - Public

- (NSArray<CLDiscoveryRecord *> *)lastDiagnostics { return _lastDiagnostics ?: @[]; }

+ (long long)bundleSizeAtPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    if (!attrs) return 0;
    if ([attrs.fileType isEqualToString:NSFileTypeDirectory]) {
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
        // ── Layer 1: Application Discovery (mechanism chain) ──
        NSMutableArray<id> *rawProxies = [NSMutableArray array];
        NSString *mechanism = nil;
        NSString *errorMsg = nil;

        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        id workspace = ([wsClass respondsToSelector:@selector(defaultWorkspace)])
            ? [wsClass performSelector:@selector(defaultWorkspace)] : nil;

        if (workspace) {
            SEL enumSel = NSSelectorFromString(@"enumerateApplicationsOfType:legacySPI:block:");
            if (![workspace respondsToSelector:enumSel])
                enumSel = NSSelectorFromString(@"enumerateApplicationsOfType:legacySPI:usingBlock:");
            if ([workspace respondsToSelector:enumSel]) {
                void (^proxyBlock)(id) = ^(id proxy) { if (proxy) [rawProxies addObject:proxy]; };
                @try {
                    NSMethodSignature *sig = [workspace methodSignatureForSelector:enumSel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:workspace]; [inv setSelector:enumSel];
                    unsigned long long type = 0; BOOL legacy = NO;
                    [inv setArgument:&type atIndex:2];
                    [inv setArgument:&legacy atIndex:3];
                    [inv setArgument:&proxyBlock atIndex:4];
                    [inv invoke];
                    if (rawProxies.count > 0) mechanism = @"enumerateApplicationsOfType";
                } @catch (NSException *e) {
                    errorMsg = e.reason; [rawProxies removeAllObjects];
                }
            }
            if (!mechanism && [workspace respondsToSelector:@selector(allInstalledApplications)]) {
                @try {
                    id apps = [workspace performSelector:@selector(allInstalledApplications)];
                    if ([apps isKindOfClass:[NSArray class]] && [apps count] > 0) {
                        [rawProxies addObjectsFromArray:apps];
                        mechanism = @"allInstalledApplications";
                    }
                } @catch (NSException *e) { errorMsg = e.reason; }
            }
        }

        if (!mechanism || rawProxies.count == 0) {
            NSString *final = [NSString stringWithFormat:@"تعذّر جلب التطبيقات من كل الآليات. %@", errorMsg ?: @""];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], final); });
            return;
        }

        // ── Layer 2+3: metadata + multi-signal classification, with diagnostics ──
        NSMutableArray<CLGame *> *games = [NSMutableArray array];
        NSMutableArray<CLDiscoveryRecord *> *diagnostics = [NSMutableArray array];

        [self classifyProxies:rawProxies intoGames:games diagnostics:diagnostics];

        // Fallback: if the strict pass produced zero games, rescan proxies with
        // richer metadata (legacySPI:YES often restores genre fields on modern iOS).
        BOOL usedLegacyPass = NO;
        if (games.count == 0) {
            NSMutableArray<id> *richProxies = [NSMutableArray array];
            SEL enumSel = NSSelectorFromString(@"enumerateApplicationsOfType:legacySPI:block:");
            if (![workspace respondsToSelector:enumSel])
                enumSel = NSSelectorFromString(@"enumerateApplicationsOfType:legacySPI:usingBlock:");
            if ([workspace respondsToSelector:enumSel]) {
                void (^proxyBlock)(id) = ^(id proxy) { if (proxy) [richProxies addObject:proxy]; };
                @try {
                    NSMethodSignature *sig = [workspace methodSignatureForSelector:enumSel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:workspace]; [inv setSelector:enumSel];
                    unsigned long long type = 0; BOOL legacy = YES;
                    [inv setArgument:&type atIndex:2];
                    [inv setArgument:&legacy atIndex:3];
                    [inv setArgument:&proxyBlock atIndex:4];
                    [inv invoke];
                    if (richProxies.count > 0) {
                        [games removeAllObjects]; [diagnostics removeAllObjects];
                        [self classifyProxies:richProxies intoGames:games diagnostics:diagnostics];
                        usedLegacyPass = YES;
                    }
                } @catch (__unused NSException *e) {}
            }
        }

        [games sortUsingComparator:^NSComparisonResult(CLGame *a, CLGame *b) {
            return [a.name localizedCaseInsensitiveCompare:b.name];
        }];

        _lastDiagnostics = [diagnostics copy];
        // Persist diagnostics for developer inspection.
        NSMutableArray *raw = [NSMutableArray array];
        for (CLDiscoveryRecord *d in diagnostics) [raw addObject:[d dictionaryRepresentation]];
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [raw writeToFile:[docs stringByAppendingPathComponent:@"CLDiscoveryDiagnostics.plist"] atomically:YES];

        // ── Log: summary + per-game reason ──
        NSString *summary = [NSString stringWithFormat:@"%ld تطبيق · %ld لعبة · %@%@",
            (long)rawProxies.count, (long)games.count, mechanism,
            usedLegacyPass ? @" (legacy pass)" : @""];
        [[CLOperationLog sharedLog] addEntryWithKind:CLOperationKindDiscovery
            status:CLOperationStatusSuccess title:@"اكتشاف الألعاب" detail:summary];
        for (CLGame *g in games) {
            CLDiscoveryRecord *rec = nil;
            for (CLDiscoveryRecord *d in diagnostics) {
                if ([d.bundleID isEqualToString:g.bundleID]) { rec = d; break; }
            }
            NSString *why = rec.signals.count ? [rec.signals componentsJoinedByString:@" + "] : @"—";
            [[CLOperationLog sharedLog] addEntryWithKind:CLOperationKindDiscovery
                status:CLOperationStatusSuccess
                title:[NSString stringWithFormat:@"لعبة: %@", g.name]
                detail:[NSString stringWithFormat:@"%@ · v%@ · %@", g.bundleID, g.version, why]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{ completion([games copy], nil); });
    });
}

#pragma mark - Layer 2/3: metadata + scoring classification

- (void)classifyProxies:(NSArray<id> *)proxies
             intoGames:(NSMutableArray<CLGame *> *)games
           diagnostics:(NSMutableArray<CLDiscoveryRecord *> *)diagnostics {
    NSFileManager *fm = [NSFileManager defaultManager];

    for (id proxy in proxies) {
        @autoreleasepool {
            CLDiscoveryRecord *rec = [CLDiscoveryRecord new];
            rec.signals = [NSMutableArray array];
            rec.score = 0;
            @try {
                rec.bundleID = [proxy valueForKey:@"bundleIdentifier"] ?: @"";
                rec.name = [proxy valueForKey:@"localizedName"] ?: rec.bundleID;
                NSURL *bundleURL = [proxy valueForKey:@"bundleURL"];
                rec.bundlePath = bundleURL.path ?: @"";
            } @catch (__unused NSException *e) { continue; }

            if (!rec.bundleID.length || ![rec.bundlePath hasSuffix:@".app"]) continue;

            // App type: user vs system by install location (reliable).
            if ([rec.bundlePath hasPrefix:@"/private/var/containers/Bundle/Application/"]) rec.appType = @"مستخدم";
            else if ([rec.bundlePath hasPrefix:@"/Applications"]) rec.appType = @"نظام";
            else rec.appType = @"أخرى";

            NSString *infoPath = [rec.bundlePath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
            rec.hasInfoPlist = (info != nil);
            if (!info) {
                rec.isGame = NO;
                [rec.signals addObject:@"لا يوجد Info.plist"];
                [diagnostics addObject:rec];
                continue;
            }

            // ── Metadata signals ──
            // (a) LSApplicationCategoryType — the App Store category the developer
            //     declared in their own Info.plist. Works for sideloaded apps too.
            rec.categoryType = info[@"LSApplicationCategoryType"] ?: @"";
            if ([rec.categoryType.lowercaseString containsString:@"game"]) {
                rec.score += 3;
                [rec.signals addObject:[NSString stringWithFormat:@"التصنيف=%@", rec.categoryType]];
            }

            // (b) LaunchServices genre fields (may be nil on modern iOS — non-fatal).
            @try {
                rec.genreIDs = [proxy valueForKey:@"genreIDs"];
                for (id gid in rec.genreIDs) {
                    if ([gid respondsToSelector:@selector(integerValue)] && [gid integerValue] == 6014) {
                        rec.score += 3; [rec.signals addObject:@"genreID=6014"]; break;
                    }
                }
                NSString *genre = [proxy valueForKey:@"genre"];
                if ([genre.lowercaseString containsString:@"game"]) { rec.score += 2; [rec.signals addObject:@"genre=Games"]; }
                NSMutableArray *gs = [NSMutableArray array];
                for (NSString *g in ([proxy valueForKey:@"genres"] ?: @[])) { if (g.length) [gs addObject:g]; }
                rec.genres = gs;
                for (NSString *g in gs) {
                    if ([g.lowercaseString containsString:@"game"]) { rec.score += 2; [rec.signals addObject:@"genres∋Games"]; break; }
                }
            } @catch (__unused NSException *e) {}

            // (c) Linked game frameworks via Mach-O scan.
            NSArray *fw = nil;
            CLGameEngine eng = [CLEngineDetector detectEngineForBundle:rec.bundlePath linkedFrameworks:&fw];
            rec.engineName = [CLEngineDetector localizedNameForEngine:eng];
            if (eng == CLGameEngineUnity || eng == CLGameEngineUnreal || eng == CLGameEngineGodot) {
                rec.score += 2; [rec.signals addObject:[NSString stringWithFormat:@"محرك=%@", rec.engineName]];
            }
            for (NSString *d in fw) {
                NSString *low = d.lowercaseString;
                if ([low containsString:@"gamecontroller"] || [low containsString:@"gamekit"]) {
                    rec.score += 2; [rec.signals addObject:@"GameController/GameKit"]; break;
                }
            }
            for (NSString *d in fw) {
                NSString *low = d.lowercaseString;
                if ([low containsString:@"spritekit"] || [low containsString:@"scenekit"]) {
                    rec.score += 1; [rec.signals addObject:@"SpriteKit/SceneKit"]; break;
                }
            }

            // ── Decision: >= 2 is a game (engine/framework signals are specific) ──
            rec.isGame = (rec.score >= 2);
            if (!rec.isGame) [rec.signals addObject:@"لا إشارة لعبة موثوقة"];
            [diagnostics addObject:rec];
            if (!rec.isGame) continue;

            // Build the CLGame (Layer 4 engine info reused for display).
            CLGame *game = [CLGame new];
            game.bundleID = rec.bundleID;
            game.name = rec.name.length ? rec.name : rec.bundleID;
            game.bundlePath = rec.bundlePath;
            game.version = info[@"CFBundleShortVersionString"] ?: info[@"CFBundleVersion"] ?: @"؟";
            game.executablePath = info[@"CFBundleExecutable"].length
                ? [rec.bundlePath stringByAppendingPathComponent:info[@"CFBundleExecutable"]] : nil;
            game.lastModified = [fm attributesOfItemAtPath:rec.bundlePath error:nil].fileModificationDate;
            game.icon = [self iconForBundle:rec.bundlePath info:info];
            game.engine = eng;
            game.engineName = rec.engineName;
            game.frameworks = fw;
            game.bundleSize = [CLGameDiscovery bundleSizeAtPath:rec.bundlePath];
            [games addObject:game];
        }
    }
}

#pragma mark - Icon

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
