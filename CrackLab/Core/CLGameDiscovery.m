//
//  CLGameDiscovery.m
//
//  Classification principle (anti false-positive):
//    BASE   = category-type signals only:
//               (1) iTunesMetadata.plist genreId/genre  ← App Store store-metadata,
//                   embedded in the bundle at install time; works on iOS 18
//                   regardless of LaunchServices private API availability.
//               (2) LSApplicationCategoryType (developer-declared, Info.plist)
//               (3) LaunchServices genre/genreIDs (when available)
//    SUPPORT = engine / game-framework signals (cap 2, never sufficient alone)
//    Game    = base score >= 3  (support can push a borderline base over)
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
        NSMutableArray<id> *rawProxies = [NSMutableArray array];
        NSString *mechanism = nil;
        NSString *errorMsg = nil;
        id workspace = nil;

        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        workspace = ([wsClass respondsToSelector:@selector(defaultWorkspace)])
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
                } @catch (NSException *e) { errorMsg = e.reason; [rawProxies removeAllObjects]; }
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
            [[CLOperationLog sharedLog] addEntryWithKind:CLOperationKindDiscovery
                status:CLOperationStatusFailed title:@"اكتشاف الألعاب" detail:final];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], final); });
            return;
        }

        // ── Classification passes ──
        NSMutableArray<CLGame *> *games = [NSMutableArray array];
        NSMutableArray<CLDiscoveryRecord *> *diagnostics = [NSMutableArray array];
        [self classifyProxies:rawProxies intoGames:games diagnostics:diagnostics];

        BOOL usedLegacyPass = NO;
        if (games.count == 0 && workspace) {
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
        NSMutableArray *raw = [NSMutableArray array];
        for (CLDiscoveryRecord *d in diagnostics) [raw addObject:[d dictionaryRepresentation]];
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [raw writeToFile:[docs stringByAppendingPathComponent:@"CLDiscoveryDiagnostics.plist"] atomically:YES];

        // ── Log: EVERY scanned app, with its decision and reason ──
        [[CLOperationLog sharedLog] addEntryWithKind:CLOperationKindDiscovery
            status:CLOperationStatusSuccess
            title:@"اكتشاف الألعاب"
            detail:[NSString stringWithFormat:@"%ld تطبيق · %ld لعبة · %@%@",
                    (long)rawProxies.count, (long)games.count, mechanism,
                    usedLegacyPass ? @" (legacy pass)" : @""]];
        for (CLDiscoveryRecord *rec in diagnostics) {
            NSString *genreShow = rec.iTunesGenre.length ? rec.iTunesGenre
                                : (rec.genres.count ? rec.genres.firstObject : @"—");
            NSString *detail = [NSString stringWithFormat:
                @"%@ · %@ · cat:%@ · genreId:%@ · genre:%@ · محرك:%@ · نقاط:%ld%@",
                rec.bundleID, rec.appType,
                rec.categoryType.length ? rec.categoryType : @"—",
                rec.iTunesGenreId ?: @"—",
                genreShow,
                rec.engineName.length ? rec.engineName : @"—",
                (long)rec.score,
                rec.signals.count ? [@" · " stringByAppendingString:[rec.signals componentsJoinedByString:@"+"]] : @""];
            [[CLOperationLog sharedLog] addEntryWithKind:CLOperationKindDiscovery
                status:(rec.isGame ? CLOperationStatusSuccess : CLOperationStatusSkipped)
                title:[NSString stringWithFormat:@"%@: %@", (rec.isGame ? @"لعبة" : @"مستبعد"), rec.name]
                detail:detail];
        }

        dispatch_async(dispatch_get_main_queue(), ^{ completion([games copy], nil); });
    });
}

#pragma mark - Classification (base = category, support = engine/framework, capped)

- (void)classifyProxies:(NSArray<id> *)proxies
             intoGames:(NSMutableArray<CLGame *> *)games
           diagnostics:(NSMutableArray<CLDiscoveryRecord *> *)diagnostics {
    NSFileManager *fm = [NSFileManager defaultManager];

    for (id proxy in proxies) {
        @autoreleasepool {
            CLDiscoveryRecord *rec = [CLDiscoveryRecord new];
            rec.signals = [NSMutableArray array];
            rec.score = 0;

            // Proxy read — record even a broken proxy so nothing is invisible.
            @try {
                rec.bundleID = [proxy valueForKey:@"bundleIdentifier"] ?: @"";
                rec.name = [proxy valueForKey:@"localizedName"] ?: rec.bundleID;
                NSURL *bundleURL = [proxy valueForKey:@"bundleURL"];
                rec.bundlePath = bundleURL.path ?: @"";
            } @catch (NSException *e) {
                rec.name = @"proxy غير مقروء"; rec.bundleID = @"";
                [rec.signals addObject:[NSString stringWithFormat:@"استثناء قراءة proxy: %@", e.reason ?: @""]];
                [diagnostics addObject:rec];
                continue;
            }

            if (!rec.bundleID.length) {
                [rec.signals addObject:@"لا يوجد bundleID"];
                [diagnostics addObject:rec];
                continue;
            }
            if (!rec.bundlePath.length) {
                rec.appType = @"غير معروف";
                [rec.signals addObject:@"لا يوجد مسار حزمة"];
                [diagnostics addObject:rec];
                continue;
            }
            if (![rec.bundlePath hasSuffix:@".app"]) {
                rec.appType = @"أخرى";
                [rec.signals addObject:@"المسار ليس .app"];
                [diagnostics addObject:rec];
                continue;
            }

            if ([rec.bundlePath hasPrefix:@"/private/var/containers/Bundle/Application/"]) rec.appType = @"مستخدم";
            else if ([rec.bundlePath hasPrefix:@"/Applications"]) rec.appType = @"نظام";
            else rec.appType = @"أخرى";

            NSString *infoPath = [rec.bundlePath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
            rec.hasInfoPlist = (info != nil);
            if (!info) {
                rec.isGame = NO;
                [rec.signals addObject:@"لا يوجد Info.plist مقروء"];
                [diagnostics addObject:rec];
                continue;
            }

            // ── BASE SIGNALS ──

            // (1) iTunesMetadata.plist — App Store store-metadata embedded at
            //     install time (genreId 6014 = Games). Disk-based; unaffected by
            //     LaunchServices private API changes on iOS 17/18.
            NSDictionary *itunesMeta = [NSDictionary dictionaryWithContentsOfFile:
                [rec.bundlePath stringByAppendingPathComponent:@"iTunesMetadata.plist"]];
            if (itunesMeta) {
                rec.iTunesGenreId = itunesMeta[@"genreId"];
                rec.iTunesGenre = itunesMeta[@"genre"];
                BOOL itGame = NO;
                if ([rec.iTunesGenreId respondsToSelector:@selector(integerValue)] &&
                    [rec.iTunesGenreId integerValue] == 6014) itGame = YES;
                if (!itGame && [rec.iTunesGenre.lowercaseString containsString:@"game"]) itGame = YES;
                if (itGame) {
                    rec.score += 4;
                    [rec.signals addObject:[NSString stringWithFormat:@"iTunes genreId=%@",
                        rec.iTunesGenreId ?: rec.iTunesGenre]];
                }
            }

            // (2) LSApplicationCategoryType — developer-declared in Info.plist.
            rec.categoryType = info[@"LSApplicationCategoryType"] ?: @"";
            if ([rec.categoryType.lowercaseString containsString:@"game"]) {
                rec.score += 3;
                [rec.signals addObject:@"LSApplicationCategoryType=Games"];
            }

            // (3) LaunchServices genre fields (best-effort; may be nil on iOS 18).
            @try {
                rec.genreIDs = [proxy valueForKey:@"genreIDs"];
                for (id gid in rec.genreIDs) {
                    if ([gid respondsToSelector:@selector(integerValue)] && [gid integerValue] == 6014) {
                        rec.score += 3; [rec.signals addObject:@"LS genreID=6014"]; break;
                    }
                }
                NSString *genre = [proxy valueForKey:@"genre"];
                if ([genre.lowercaseString containsString:@"game"]) { rec.score += 2; [rec.signals addObject:@"LS genre=Games"]; }
                NSMutableArray *gs = [NSMutableArray array];
                for (NSString *g in ([proxy valueForKey:@"genres"] ?: @[])) { if (g.length) [gs addObject:g]; }
                rec.genres = gs;
                for (NSString *g in gs) {
                    if ([g.lowercaseString containsString:@"game"]) { rec.score += 2; [rec.signals addObject:@"LS genres∋Games"]; break; }
                }
            } @catch (__unused NSException *e) {}

            // ── SUPPORT SIGNALS (cap 2 — never sufficient alone) ──
            NSInteger support = 0;
            NSArray *fw = nil;
            CLGameEngine eng = [CLEngineDetector detectEngineForBundle:rec.bundlePath linkedFrameworks:&fw];
            rec.engineName = [CLEngineDetector localizedNameForEngine:eng];
            if (eng == CLGameEngineUnity || eng == CLGameEngineUnreal || eng == CLGameEngineGodot) {
                support += 1; [rec.signals addObject:[NSString stringWithFormat:@"محرك %@", rec.engineName]];
            }
            BOOL hasGameKit = NO, hasSK = NO;
            for (NSString *d in fw) {
                NSString *low = d.lowercaseString;
                if ([low containsString:@"gamecontroller"] || [low containsString:@"gamekit"]) hasGameKit = YES;
                if ([low containsString:@"spritekit"] || [low containsString:@"scenekit"]) hasSK = YES;
            }
            if (hasGameKit) { support += 1; [rec.signals addObject:@"GameKit/GameController"]; }
            if (hasSK && support < 2) { support += 1; [rec.signals addObject:@"SpriteKit/SceneKit"]; }
            if (support > 2) support = 2;
            rec.score += support;

            // ── Decision ──
            // Game needs a real category-class base (score >= 3 always includes
            // at least one category signal: iTunes 4, CategoryType 3, LSgenreID 3,
            // or genre 2 + one support). Pure-framework apps cap at 2 → excluded.
            rec.isGame = (rec.score >= 3);
            if (!rec.isGame) [rec.signals addObject:[NSString stringWithFormat:@"نقاط %ld < 3", (long)rec.score]];
            [diagnostics addObject:rec];
            if (!rec.isGame) continue;

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
