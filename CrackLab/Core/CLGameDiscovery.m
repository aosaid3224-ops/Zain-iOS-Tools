//
//  CLGameDiscovery.m
//
//  Clean three-layer architecture:
//    Layer 1  App Discovery      — mechanism chain (LSApplicationWorkspace)
//    Layer 2  Metadata Probe     — CLMetadataProbe (evidence, 3-state honest)
//    Layer 3  Game Classification— CLGameClassifier (confidence, evidence-only)
//    Layer 4  Engine Detection   — CLEngineDetector (display only, never decides)
//

#import "CLGameDiscovery.h"
#import "CLEngineDetector.h"
#import "CLMetadataProbe.h"
#import "CLGameClassifier.h"
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

#pragma mark - Layer 1: App Discovery

- (BOOL)enumerateWithWorkspace:(id)workspace
                        legacy:(BOOL)legacy
                       proxies:(NSMutableArray<id> *)outProxies
                        mechanism:(NSString **)outMechanism {
    SEL enumSel = NSSelectorFromString(@"enumerateApplicationsOfType:legacySPI:block:");
    if (![workspace respondsToSelector:enumSel])
        enumSel = NSSelectorFromString(@"enumerateApplicationsOfType:legacySPI:usingBlock:");
    if (![workspace respondsToSelector:enumSel]) return NO;
    void (^proxyBlock)(id) = ^(id proxy) { if (proxy) [outProxies addObject:proxy]; };
    @try {
        NSMethodSignature *sig = [workspace methodSignatureForSelector:enumSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:workspace]; [inv setSelector:enumSel];
        unsigned long long type = 0;
        [inv setArgument:&type atIndex:2];
        [inv setArgument:&legacy atIndex:3];
        [inv setArgument:&proxyBlock atIndex:4];
        [inv invoke];
        if (outProxies.count > 0) {
            *outMechanism = legacy ? @"enumerate(legacySPI)" : @"enumerate";
            return YES;
        }
    } @catch (__unused NSException *e) { [outProxies removeAllObjects]; }
    return NO;
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
            if (![self enumerateWithWorkspace:workspace legacy:NO proxies:rawProxies mechanism:&mechanism]) {
                if ([workspace respondsToSelector:@selector(allInstalledApplications)]) {
                    @try {
                        id apps = [workspace performSelector:@selector(allInstalledApplications)];
                        if ([apps isKindOfClass:[NSArray class]] && [apps count] > 0) {
                            [rawProxies addObjectsFromArray:apps];
                            mechanism = @"allInstalledApplications";
                        }
                    } @catch (NSException *e) { errorMsg = e.reason; }
                }
            }
        }

        if (!mechanism || rawProxies.count == 0) {
            NSString *final = [NSString stringWithFormat:@"تعذّر جلب التطبيقات من كل الآليات. %@", errorMsg ?: @""];
            [[CLOperationLog sharedLog] addEntryWithKind:CLOperationKindDiscovery
                status:CLOperationStatusFailed title:@"اكتشاف الألعاب" detail:final];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], final); });
            return;
        }

        // ── Layers 2/3/4 per app ──
        NSMutableArray<CLGame *> *games = [NSMutableArray array];
        NSMutableArray<CLDiscoveryRecord *> *diagnostics = [NSMutableArray array];
        [self processProxies:rawProxies intoGames:games diagnostics:diagnostics];

        // Second enumeration pass (legacySPI) only when nothing classified —
        // richer proxies on modern iOS can restore metadata fields.
        BOOL usedLegacyPass = NO;
        if (games.count == 0 && workspace) {
            NSMutableArray<id> *richProxies = [NSMutableArray array];
            NSString *m2 = nil;
            if ([self enumerateWithWorkspace:workspace legacy:YES proxies:richProxies mechanism:&m2]) {
                [games removeAllObjects]; [diagnostics removeAllObjects];
                [self processProxies:richProxies intoGames:games diagnostics:diagnostics];
                usedLegacyPass = YES;
                mechanism = [mechanism stringByAppendingString:@" + legacy"];
            }
        }

        [games sortUsingComparator:^NSComparisonResult(CLGame *a, CLGame *b) {
            return [a.name localizedCaseInsensitiveCompare:b.name];
        }];

        _lastDiagnostics = [diagnostics copy];
        NSMutableArray *raw = [NSMutableArray array];
        for (CLDiscoveryRecord *drec in diagnostics) [raw addObject:[drec dictionaryRepresentation]];
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [raw writeToFile:[docs stringByAppendingPathComponent:@"CLDiscoveryDiagnostics.plist"] atomically:YES];

        [[CLOperationLog sharedLog] addEntryWithKind:CLOperationKindDiscovery
            status:CLOperationStatusSuccess title:@"اكتشاف الألعاب"
            detail:[NSString stringWithFormat:@"%ld تطبيق · %ld لعبة · %@", (long)rawProxies.count, (long)games.count, mechanism]];

        for (CLDiscoveryRecord *rec in diagnostics) {
            if ([rec.appType isEqualToString:@"مستخدم"]) {
                NSString *infoKeys = rec.infoPlistStoreKeys.count
                    ? [rec.infoPlistStoreKeys.description stringByReplacingOccurrencesOfString:@"\n" withString:@" "] : @"—";
                NSString *detail = [NSString stringWithFormat:
                    @"bundle: %@\n"
                    "container: %@\n"
                    "metadata: %@ (%@)%@\n"
                    "genreId: %@ · genre: %@\n"
                    "receipt: %@\n"
                    "infoPlist-store: %@\n"
                    "cat: %@ · محرك: %@ · ثقة: %@ (%ld)\n"
                    "قرار: %@ — %@",
                    rec.bundleID,
                    rec.dataContainerPath.length ? rec.dataContainerPath : @"—",
                    rec.metadataPath.length ? rec.metadataPath : @"غير موجود",
                    rec.metadataState,
                    rec.metadataSize > 0 ? [NSString stringWithFormat:@" · %lldB", rec.metadataSize] : @"",
                    rec.iTunesGenreId ?: @"—",
                    rec.iTunesGenre ?: @"—",
                    rec.receiptPresent ? @"YES" : @"NO",
                    infoKeys,
                    rec.categoryType.length ? rec.categoryType : @"—",
                    rec.engineName.length ? rec.engineName : @"—",
                    rec.confidence ?: @"—", (long)rec.score,
                    rec.isGame ? @"لعبة" : @"غير لعبة",
                    rec.signals.count ? [rec.signals componentsJoinedByString:@" + "] : @"—"];
                [[CLOperationLog sharedLog] addEntryWithKind:CLOperationKindDiscovery
                    status:(rec.isGame ? CLOperationStatusSuccess : CLOperationStatusSkipped)
                    title:[NSString stringWithFormat:@"فحص: %@", rec.name]
                    detail:detail];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{ completion([games copy], nil); });
    });
}

#pragma mark - Layers 2/3/4: probe → classify → engine

- (void)processProxies:(NSArray<id> *)proxies
            intoGames:(NSMutableArray<CLGame *> *)games
          diagnostics:(NSMutableArray<CLDiscoveryRecord *> *)diagnostics {
    NSFileManager *fm = [NSFileManager defaultManager];

    for (id proxy in proxies) {
        @autoreleasepool {
            CLDiscoveryRecord *rec = [CLDiscoveryRecord new];
            rec.signals = [NSMutableArray array];

            @try {
                rec.bundleID = [proxy valueForKey:@"bundleIdentifier"] ?: @"";
                rec.name = [proxy valueForKey:@"localizedName"] ?: rec.bundleID;
                NSURL *bundleURL = [proxy valueForKey:@"bundleURL"];
                rec.bundlePath = bundleURL.path ?: @"";
            } @catch (NSException *e) {
                rec.name = @"proxy غير مقروء"; rec.bundleID = @"";
                [rec.signals addObject:[NSString stringWithFormat:@"استثناء: %@", e.reason ?: @""]];
                [diagnostics addObject:rec];
                continue;
            }
            if (!rec.bundleID.length) { [rec.signals addObject:@"لا bundleID"]; [diagnostics addObject:rec]; continue; }
            if (!rec.bundlePath.length) {
                rec.appType = @"غير معروف"; [rec.signals addObject:@"لا مسار"]; [diagnostics addObject:rec]; continue;
            }
            if (![rec.bundlePath hasSuffix:@".app"]) {
                rec.appType = @"أخرى"; [rec.signals addObject:@"ليس .app"]; [diagnostics addObject:rec]; continue;
            }

            if ([rec.bundlePath hasPrefix:@"/private/var/containers/Bundle/Application/"]) rec.appType = @"مستخدم";
            else if ([rec.bundlePath hasPrefix:@"/Applications"]) rec.appType = @"نظام";
            else rec.appType = @"أخرى";

            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                [rec.bundlePath stringByAppendingPathComponent:@"Info.plist"]];
            rec.hasInfoPlist = (info != nil);
            if (!info) {
                rec.isGame = NO; rec.confidence = @"ضئيل";
                [rec.signals addObject:@"لا Info.plist"];
                [diagnostics addObject:rec];
                continue;
            }
            rec.categoryType = info[@"LSApplicationCategoryType"] ?: @"";

            // Layer 2 — probe
            CLMetadataProbeResult *probe = [CLMetadataProbe probeProxy:proxy bundlePath:rec.bundlePath];
            rec.dataContainerPath = probe.dataContainerPath;
            rec.metadataState = probe.metadataState;
            rec.metadataPath = probe.metadataPath;
            rec.metadataSize = probe.metadataSize;
            rec.metadataReadable = probe.metadataReadable;
            rec.metadataParseable = probe.metadataParseable;
            rec.metadataKeys = probe.metadataKeys;
            rec.iTunesGenreId = probe.genreId;
            rec.iTunesGenre = probe.genre;
            rec.receiptPresent = probe.receiptPresent;
            rec.infoPlistStoreKeys = probe.infoPlistStoreKeys;

            NSString *exePath = info[@"CFBundleExecutable"].length
                ? [rec.bundlePath stringByAppendingPathComponent:info[@"CFBundleExecutable"]] : nil;

            // Layer 3 — classify (confidence engine)
            CLClassificationResult *result = [CLGameClassifier classifyProxy:proxy info:info probe:probe executablePath:exePath];
            rec.isGame = result.isGame;
            rec.score = result.score;
            rec.confidence = result.confidenceName;
            rec.signals = result.signals;

            // Layer 4 — engine (display only)
            NSArray *fw = nil;
            CLGameEngine eng = [CLEngineDetector detectEngineForBundle:rec.bundlePath linkedFrameworks:&fw];
            rec.engineName = [CLEngineDetector localizedNameForEngine:eng];

            [diagnostics addObject:rec];
            if (!rec.isGame) continue;

            CLGame *game = [CLGame new];
            game.bundleID = rec.bundleID;
            game.name = rec.name.length ? rec.name : rec.bundleID;
            game.bundlePath = rec.bundlePath;
            game.version = info[@"CFBundleShortVersionString"] ?: info[@"CFBundleVersion"] ?: @"؟";
            game.executablePath = exePath;
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
