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
        NSMutableArray<CLGame *> *games = [NSMutableArray array];
        NSString *errorMsg = nil;

        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        if (!proxyClass) {
            errorMsg = @"تعذّر الوصول إلى LaunchServices (LSApplicationProxy غير متاح).";
            dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], errorMsg); });
            return;
        }

        NSArray *proxies = nil;
        @try {
            proxies = [proxyClass performSelector:@selector(allInstalledApplications)];
        } @catch (NSException *e) {
            errorMsg = [NSString stringWithFormat:@"فشل استعلام التطبيقات: %@", e.reason ?: @"خطأ غير معروف"];
        }
        if (![proxies isKindOfClass:[NSArray class]]) proxies = @[];

        for (id proxy in proxies) {
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

                    // ── Game classification ──
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

                    // Heuristic fallback: game-only frameworks in the main executable
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
                    id rawExecutableName = info[@"CFBundleExecutable"];
                    NSString *executableName = [rawExecutableName isKindOfClass:[NSString class]]
                        ? (NSString *)rawExecutableName : nil;
                    game.executablePath = executableName.length
                        ? [bundlePath stringByAppendingPathComponent:executableName] : nil;
                    game.lastModified = [[NSFileManager defaultManager]
                        attributesOfItemAtPath:bundlePath error:nil].fileModificationDate;

                    // Icon: primary icon file in bundle
                    game.icon = [self iconForBundle:bundlePath info:info];

                    // Engine + frameworks
                    NSArray *fw = nil;
                    game.engine = [CLEngineDetector detectEngineForBundle:bundlePath linkedFrameworks:&fw];
                    game.engineName = [CLEngineDetector localizedNameForEngine:game.engine];
                    game.frameworks = fw;

                    // Size
                    game.bundleSize = [CLGameDiscovery bundleSizeAtPath:bundlePath];

                    [games addObject:game];
                } @catch (__unused NSException *e) { continue; }
            }
        }

        [games sortUsingComparator:^NSComparisonResult(CLGame *a, CLGame *b) {
            return [a.name localizedCaseInsensitiveCompare:b.name];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{ completion([games copy], errorMsg); });
    });
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
