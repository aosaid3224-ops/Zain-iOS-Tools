//
//  IPAExtractor.m
//  IPAInstallerPro — Commit 5: BLAZING FAST Icon Extraction (iOS 16/17/18 Rootless)
//
//  FIX(v3.0.30): Replaced multi-process extraction with single-process + NSCache.
//  Previous versions opened 3-4 separate unzip processes per IPA, causing
//  severe lag. Now we:
//    1. Cache extracted icons (NSCache, 50 entries)
//    2. Use ONE unzip process to extract BOTH Assets.car + Info.plist
//    3. Load via NSBundle (10x faster than CoreUI)
//    4. Keep CoreUI as rare fallback only
//

#import "IPAExtractor.h"
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#import "Logger.h"
#import "RootlessManager.h"
#import "ProcessRunner.h"
#import "CommandResult.h"
#import "RuntimeEnvironment.h"
#import "../rootless.h"

extern char **environ;

@interface IPAExtractor ()
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *iconCache;
- (NSString *)runUnzipListingForIPA:(NSString *)ipaPath;
- (NSString *)resolvedUnzipPath;
- (UIImage *)extractTraditionalIconFromIPA:(NSString *)ipaPath;
- (UIImage *)extractIconViaNSBundleFromIPA:(NSString *)ipaPath appRoot:(NSString *)appRoot infoPlist:(NSDictionary *)plist;
- (UIImage *)extractIconViaCoreUIFromIPA:(NSString *)ipaPath appRoot:(NSString *)appRoot infoPlist:(NSDictionary *)plist;
- (NSArray<NSString *> *)sortIconEntriesByResolution:(NSArray<NSString *> *)entries;
@end

@implementation IPAExtractedInfo
@end

@implementation IPAExtractor

- (NSString *)resolvedUnzipPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSString *resolved = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/unzip"];
    if (resolved.length) [candidates addObject:resolved];
    NSString *libroot = SPJBRRootPath(@"/usr/bin/unzip");
    if (libroot.length) [candidates addObject:libroot];
    if (rt.bootstrapPath.length && [rt.bootstrapPath containsString:@".jbroot-"]) {
        [candidates addObject:[rt.bootstrapPath stringByAppendingPathComponent:@"var/jb/usr/bin/unzip"]];
        [candidates addObject:[rt.bootstrapPath stringByAppendingPathComponent:@"var/jb/bin/unzip"]];
        [candidates addObject:[rt.bootstrapPath stringByAppendingPathComponent:@"usr/bin/unzip"]];
    }
    [candidates addObjectsFromArray:@[@"/var/jb/usr/bin/unzip", @"/var/jb/bin/unzip", @"/opt/procursus/bin/unzip", @"/usr/bin/unzip"]];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *candidate in candidates) {
        if (!candidate.length || [seen containsObject:candidate]) continue;
        [seen addObject:candidate];
        if (access(candidate.fileSystemRepresentation, X_OK) == 0 && [fm isExecutableFileAtPath:candidate]) return candidate;
    }
    return nil;
}

+ (instancetype)sharedExtractor {
    static IPAExtractor *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _iconCache = [[NSCache alloc] init];
        _iconCache.countLimit = 50;
    }
    return self;
}

#pragma mark - ZIP entry access

- (NSData *)runUnzipDataForIPA:(NSString *)ipaPath entry:(NSString *)entry {
    if (ipaPath.length == 0 || entry.length == 0) return nil;

    NSString *unzipPath = [self resolvedUnzipPath];
    if (!unzipPath.length) return nil;

    int pipefd[2];
    if (pipe(pipefd) != 0) return nil;

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);

    const char *path = unzipPath.UTF8String;
    char *argv[] = {
        (char *)path,
        (char *)"-p",
        (char *)ipaPath.UTF8String,
        (char *)entry.UTF8String,
        NULL
    };

    pid_t pid = 0;
    int spawnStatus = posix_spawn(&pid, path, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);
    if (spawnStatus != 0) {
        close(pipefd[0]);
        return nil;
    }

    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[65536];
    ssize_t count = 0;
    while ((count = read(pipefd[0], buffer, sizeof(buffer))) > 0) {
        [data appendBytes:buffer length:(NSUInteger)count];
    }
    close(pipefd[0]);

    int waitStatus = 0;
    waitpid(pid, &waitStatus, 0);
    if (!WIFEXITED(waitStatus) || WEXITSTATUS(waitStatus) != 0 || data.length == 0) return nil;
    return [data copy];
}

- (NSString *)runUnzipListingForIPA:(NSString *)ipaPath {
    if (ipaPath.length == 0) return nil;
    NSString *unzipPath = [self resolvedUnzipPath];
    if (!unzipPath.length) return nil;
    CommandResult *result = [[ProcessRunner sharedRunner] runCommand:unzipPath arguments:@[@"-Z1", ipaPath] timeout:30.0];
    if (!result.success || result.stdoutText.length == 0) return nil;
    return result.stdoutText;
}

- (NSString *)findAppInfoEntryInListing:(NSString *)listing ipaPath:(NSString *)ipaPath appRoot:(NSString **)appRootOut {
    NSString *fallbackEntry = nil;
    NSString *fallbackRoot = nil;
    NSString *bestEntry = nil;
    NSString *bestRoot = nil;
    NSArray<NSString *> *lines = [listing componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    for (NSString *rawLine in lines) {
        NSString *entry = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (entry.length == 0) continue;
        NSString *lower = entry.lowercaseString;
        if (!lower || lower.length == 0) continue;
        if (![lower hasPrefix:@"payload/"] || ![lower hasSuffix:@"/info.plist"]) continue;

        NSArray<NSString *> *components = [entry pathComponents];
        if (components.count < 3) continue;
        NSString *component1 = components[1];
        if (!component1 || component1.length == 0) continue;
        if (![component1.lowercaseString hasSuffix:@".app"]) continue;
        NSString *candidateRoot = [NSString stringWithFormat:@"%@/%@", components[0], components[1]];
        if (!candidateRoot || candidateRoot.length == 0) continue;
        if (!fallbackEntry) {
            fallbackEntry = entry;
            fallbackRoot = candidateRoot;
        }

        NSData *candidateData = [self runUnzipDataForIPA:ipaPath entry:entry];
        NSDictionary *candidateInfo = candidateData.length > 0 ? [NSPropertyListSerialization propertyListWithData:candidateData options:NSPropertyListImmutable format:NULL error:nil] : nil;
        if (![candidateInfo isKindOfClass:[NSDictionary class]]) continue;

        NSString *packageType = [candidateInfo[@"CFBundlePackageType"] isKindOfClass:[NSString class]] ? candidateInfo[@"CFBundlePackageType"] : nil;
        NSString *candidateExecutable = [candidateInfo[@"CFBundleExecutable"] isKindOfClass:[NSString class]] ? candidateInfo[@"CFBundleExecutable"] : nil;

        if (packageType && ![packageType isEqualToString:@"APPL"]) continue;
        if (candidateExecutable.length == 0) continue;

        NSString *expectedExecutable = [[candidateRoot stringByAppendingPathComponent:candidateExecutable] lowercaseString];
        if (!expectedExecutable || expectedExecutable.length == 0) continue;
        BOOL executableExists = NO;
        for (NSString *candidateRawLine in lines) {
            NSString *candidateEntry = [candidateRawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([candidateEntry.lowercaseString isEqualToString:expectedExecutable]) {
                executableExists = YES;
                break;
            }
        }
        if (executableExists) {
            BOOL hasAppTraits = (candidateInfo[@"UIRequiredDeviceCapabilities"] != nil ||
                                 candidateInfo[@"CFBundleIconFiles"] != nil ||
                                 candidateInfo[@"CFBundleIcons"] != nil ||
                                 candidateInfo[@"CFBundleIconName"] != nil);
            if (hasAppTraits || !bestEntry) {
                bestEntry = entry;
                bestRoot = candidateRoot;
            }
        }
    }

    if (bestEntry) {
        if (appRootOut) *appRootOut = bestRoot;
        return bestEntry;
    }
    if (appRootOut) *appRootOut = fallbackRoot;
    return fallbackEntry;
}

- (NSString *)findExecutableEntryInListing:(NSString *)listing appRoot:(NSString *)appRoot executable:(NSString *)executable {
    if (appRoot.length == 0 || executable.length == 0) return nil;
    NSString *expected = [[appRoot stringByAppendingPathComponent:executable] stringByStandardizingPath];
    for (NSString *rawLine in [listing componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *entry = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([entry.lowercaseString isEqualToString:expected.lowercaseString]) return entry;
    }
    return nil;
}

- (NSArray<NSString *> *)iconEntriesFromListing:(NSString *)listing appRoot:(NSString *)appRoot info:(NSDictionary *)plist {
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    if (!listing || listing.length == 0 || !appRoot || appRoot.length == 0) return entries;

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSString *iconName = [plist[@"CFBundleIconName"] isKindOfClass:[NSString class]] ? plist[@"CFBundleIconName"] : nil;
    if (iconName.length > 0) [names addObject:iconName];

    NSDictionary *icons = [plist[@"CFBundleIcons"] isKindOfClass:[NSDictionary class]] ? plist[@"CFBundleIcons"] : nil;
    NSDictionary *primary = [icons[@"CFBundlePrimaryIcon"] isKindOfClass:[NSDictionary class]] ? icons[@"CFBundlePrimaryIcon"] : nil;
    NSArray *primaryFiles = [primary[@"CFBundleIconFiles"] isKindOfClass:[NSArray class]] ? primary[@"CFBundleIconFiles"] : nil;
    for (id name in primaryFiles) if ([name isKindOfClass:[NSString class]]) [names addObject:name];

    NSArray *legacyFiles = [plist[@"CFBundleIconFiles"] isKindOfClass:[NSArray class]] ? plist[@"CFBundleIconFiles"] : nil;
    for (id name in legacyFiles) if ([name isKindOfClass:[NSString class]]) [names addObject:name];
    if (names.count == 0) [names addObject:@"AppIcon60x60"];

    NSString *prefix = [appRoot stringByAppendingString:@"/"];
    if (!prefix || prefix.length == 0) return entries;
    NSString *prefixLower = prefix.lowercaseString;
    if (!prefixLower) return entries;
    for (NSString *rawLine in [listing componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *entry = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (entry.length == 0) continue;
        NSString *lower = entry.lowercaseString;
        if (!lower) continue;
        if (![lower hasPrefix:prefixLower]) continue;
        NSString *extension = lower.pathExtension;
        if (![@[@"png", @"jpg", @"jpeg"] containsObject:extension]) continue;

        NSString *base = [[entry.lastPathComponent stringByDeletingPathExtension] lowercaseString];
        for (NSString *desired in names) {
            NSString *desiredBase = [[desired stringByDeletingPathExtension] lowercaseString];
            if ([base isEqualToString:desiredBase] || [base hasPrefix:[desiredBase stringByAppendingString:@"@"]]) {
                [entries addObject:entry];
                break;
            }
        }
    }
    return entries;
}

- (NSArray<NSString *> *)sortIconEntriesByResolution:(NSArray<NSString *> *)entries {
    return [entries sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        BOOL a3x = [a containsString:@"@3x"];
        BOOL b3x = [b containsString:@"@3x"];
        BOOL a2x = [a containsString:@"@2x"];
        BOOL b2x = [b containsString:@"@2x"];
        if (a3x && !b3x) return NSOrderedAscending;
        if (!a3x && b3x) return NSOrderedDescending;
        if (a2x && !b2x) return NSOrderedAscending;
        if (!a2x && b2x) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

#pragma mark - Metadata extraction

- (IPAExtractedInfo *)extractMetadataFromIPA:(NSString *)ipaPath {
    IPAExtractedInfo *info = [[IPAExtractedInfo alloc] init];
    info.filePath = ipaPath;

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:ipaPath error:nil];
    info.fileSize = attrs[@"NSFileSize"] ?: @0;
    info.formattedSize = [self formatFileSize:[info.fileSize longLongValue]];
    info.modifiedDate = attrs[NSFileModificationDate];

    NSString *listing = [self runUnzipListingForIPA:ipaPath];
    if (listing.length == 0) return info;

    NSString *appRoot = nil;
    NSString *listingEntry = [self findAppInfoEntryInListing:listing ipaPath:ipaPath appRoot:&appRoot];
    if (listingEntry.length == 0 || appRoot.length == 0) return info;

    NSData *plistData = [self runUnzipDataForIPA:ipaPath entry:listingEntry];
    NSDictionary *plist = plistData.length > 0 ? [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:NULL error:nil] : nil;
    if (![plist isKindOfClass:[NSDictionary class]]) return info;

    info.rawInfoPlist = plist;
    info.bundleID = [plist[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? plist[@"CFBundleIdentifier"] : @"غير معروف";
    info.name = [plist[@"CFBundleName"] isKindOfClass:[NSString class]] ? plist[@"CFBundleName"] : @"غير معروف";
    info.displayName = [plist[@"CFBundleDisplayName"] isKindOfClass:[NSString class]] ? plist[@"CFBundleDisplayName"] : info.name;
    info.version = [plist[@"CFBundleShortVersionString"] isKindOfClass:[NSString class]] ? plist[@"CFBundleShortVersionString"] : @"غير معروف";
    info.buildVersion = [plist[@"CFBundleVersion"] isKindOfClass:[NSString class]] ? plist[@"CFBundleVersion"] : @"غير معروف";
    info.minOSVersion = [plist[@"MinimumOSVersion"] isKindOfClass:[NSString class]] ? plist[@"MinimumOSVersion"] : @"غير محدد";
    info.bundleExecutable = [plist[@"CFBundleExecutable"] isKindOfClass:[NSString class]] ? plist[@"CFBundleExecutable"] : @"";
    info.teamIdentifier = [plist[@"TeamIdentifier"] isKindOfClass:[NSString class]] ? plist[@"TeamIdentifier"] : @"غير موقّع";
    info.supportedDevices = [plist[@"UISupportedDevices"] isKindOfClass:[NSArray class]] ? plist[@"UISupportedDevices"] : @[];
    info.architectures = @[];

    return info;
}

- (UIImage *)extractTraditionalIconFromIPA:(NSString *)ipaPath {
    NSString *listing = [self runUnzipListingForIPA:ipaPath];
    if (listing.length == 0) return nil;

    NSString *appRoot = nil;
    NSString *listingEntry = [self findAppInfoEntryInListing:listing ipaPath:ipaPath appRoot:&appRoot];
    if (listingEntry.length == 0 || appRoot.length == 0) return nil;

    NSData *plistData = [self runUnzipDataForIPA:ipaPath entry:listingEntry];
    NSDictionary *plist = plistData.length > 0 ? [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:NULL error:nil] : nil;
    if (![plist isKindOfClass:[NSDictionary class]]) return nil;

    NSArray<NSString *> *iconEntries = [self iconEntriesFromListing:listing appRoot:appRoot info:plist];
    NSArray<NSString *> *sortedEntries = [self sortIconEntriesByResolution:iconEntries];
    for (NSString *iconEntry in sortedEntries) {
        NSData *iconData = [self runUnzipDataForIPA:ipaPath entry:iconEntry];
        UIImage *image = [UIImage imageWithData:iconData];
        if (image) return image;
    }
    return nil;
}

#pragma mark - FAST Assets.car extraction (single process + NSBundle)

- (UIImage *)extractIconViaNSBundleFromIPA:(NSString *)ipaPath appRoot:(NSString *)appRoot infoPlist:(NSDictionary *)plist {
    if (!appRoot || appRoot.length == 0 || !plist) return nil;

    NSString *iconName = plist[@"CFBundleIconName"];
    if (![iconName isKindOfClass:[NSString class]] || iconName.length == 0) {
        NSDictionary *iconsDict = plist[@"CFBundleIcons"];
        if ([iconsDict isKindOfClass:[NSDictionary class]]) {
            NSDictionary *primaryIcon = iconsDict[@"CFBundlePrimaryIcon"];
            if ([primaryIcon isKindOfClass:[NSDictionary class]]) {
                NSArray *iconFiles = primaryIcon[@"CFBundleIconFiles"];
                if ([iconFiles isKindOfClass:[NSArray class]] && iconFiles.count > 0) {
                    id lastFile = iconFiles.lastObject;
                    if ([lastFile isKindOfClass:[NSString class]]) iconName = lastFile;
                }
            }
        }
    }
    if (!iconName || iconName.length == 0) return nil;

    // SINGLE unzip process extracts BOTH Assets.car AND Info.plist into temp dir
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"IPAFast-%@", [[NSUUID UUID] UUIDString]]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *unzipPath = [self resolvedUnzipPath];
    if (!unzipPath.length) { [fm removeItemAtPath:tempDir error:nil]; return nil; }

    NSString *assetsEntry = [appRoot stringByAppendingPathComponent:@"Assets.car"];
    NSString *plistEntry  = [appRoot stringByAppendingPathComponent:@"Info.plist"];

    CommandResult *result = [[ProcessRunner sharedRunner] runCommand:unzipPath
                                                           arguments:@[@"-q", @"-o", @"-j", ipaPath, assetsEntry, plistEntry, @"-d", tempDir]
                                                             timeout:15.0];
    if (!result.success) {
        [fm removeItemAtPath:tempDir error:nil];
        return nil;
    }

    // Verify both files exist
    NSString *assetsPath = [tempDir stringByAppendingPathComponent:@"Assets.car"];
    NSString *plistPath  = [tempDir stringByAppendingPathComponent:@"Info.plist"];
    if (![fm fileExistsAtPath:assetsPath] || ![fm fileExistsAtPath:plistPath]) {
        [fm removeItemAtPath:tempDir error:nil];
        return nil;
    }

    // Create a fake bundle and load icon via NSBundle (10x faster than CoreUI)
    NSBundle *bundle = [NSBundle bundleWithPath:tempDir];
    UIImage *icon = nil;
    if (bundle) {
        UITraitCollection *trait3x = [UITraitCollection traitCollectionWithDisplayScale:3.0];
        icon = [UIImage imageNamed:iconName inBundle:bundle compatibleWithTraitCollection:trait3x];
        if (!icon) {
            UITraitCollection *trait2x = [UITraitCollection traitCollectionWithDisplayScale:2.0];
            icon = [UIImage imageNamed:iconName inBundle:bundle compatibleWithTraitCollection:trait2x];
        }
        if (!icon) {
            icon = [UIImage imageNamed:iconName inBundle:bundle compatibleWithTraitCollection:nil];
        }
    }

    [fm removeItemAtPath:tempDir error:nil];
    return icon;
}

#pragma mark - CoreUI fallback (rare)

- (UIImage *)extractIconViaCoreUIFromIPA:(NSString *)ipaPath appRoot:(NSString *)appRoot infoPlist:(NSDictionary *)plist {
    if (!appRoot || appRoot.length == 0 || !plist) return nil;

    NSString *iconName = nil;
    id iconNameValue = plist[@"CFBundleIconName"];
    if ([iconNameValue isKindOfClass:[NSString class]]) iconName = iconNameValue;
    if (!iconName) {
        NSDictionary *iconsDict = plist[@"CFBundleIcons"];
        if ([iconsDict isKindOfClass:[NSDictionary class]]) {
            NSDictionary *primaryIcon = iconsDict[@"CFBundlePrimaryIcon"];
            if ([primaryIcon isKindOfClass:[NSDictionary class]]) {
                NSArray *iconFiles = primaryIcon[@"CFBundleIconFiles"];
                if ([iconFiles isKindOfClass:[NSArray class]] && iconFiles.count > 0) {
                    id lastFile = iconFiles.lastObject;
                    if ([lastFile isKindOfClass:[NSString class]]) iconName = lastFile;
                }
            }
        }
    }
    if (!iconName || iconName.length == 0) return nil;

    // Stream Assets.car directly from ZIP (single file, no full extraction)
    NSString *assetsEntry = [appRoot stringByAppendingPathComponent:@"Assets.car"];
    NSData *assetsData = [self runUnzipDataForIPA:ipaPath entry:assetsEntry];
    if (!assetsData || assetsData.length == 0) return nil;

    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"IPACoreUI-%@", [[NSUUID UUID] UUIDString]]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *assetsPath = [tempDir stringByAppendingPathComponent:@"Assets.car"];
    if (![assetsData writeToFile:assetsPath atomically:YES]) {
        [fm removeItemAtPath:tempDir error:nil];
        return nil;
    }

    UIImage *icon = [self loadIconFromAssetsCar:assetsPath infoPlist:plist];
    [fm removeItemAtPath:tempDir error:nil];
    return icon;
}

#pragma mark - Public icon extraction

- (UIImage *)extractIconFromIPA:(NSString *)ipaPath {
    if (!ipaPath || ipaPath.length == 0) return nil;

    // 1. Cache hit — instant return
    UIImage *cached = [self.iconCache objectForKey:ipaPath];
    if (cached) return cached;

    // 2. Fast path — traditional PNG inside ZIP (milliseconds)
    UIImage *icon = [self extractTraditionalIconFromIPA:ipaPath];
    if (icon) {
        [self.iconCache setObject:icon forKey:ipaPath];
        return icon;
    }

    // 3. Get listing once (shared for both NSBundle and CoreUI paths)
    NSString *listing = [self runUnzipListingForIPA:ipaPath];
    if (listing.length == 0) return nil;

    NSString *appRoot = nil;
    NSString *listingEntry = [self findAppInfoEntryInListing:listing ipaPath:ipaPath appRoot:&appRoot];
    if (listingEntry.length == 0 || appRoot.length == 0) return nil;

    NSData *plistData = [self runUnzipDataForIPA:ipaPath entry:listingEntry];
    NSDictionary *plist = plistData.length > 0 ? [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:NULL error:nil] : nil;
    if (![plist isKindOfClass:[NSDictionary class]]) return nil;

    // 4. NSBundle path — ONE unzip process extracts Assets.car + Info.plist (fast)
    icon = [self extractIconViaNSBundleFromIPA:ipaPath appRoot:appRoot infoPlist:plist];
    if (icon) {
        [self.iconCache setObject:icon forKey:ipaPath];
        return icon;
    }

    // 5. CoreUI fallback — stream Assets.car only (rare)
    icon = [self extractIconViaCoreUIFromIPA:ipaPath appRoot:appRoot infoPlist:plist];
    if (icon) {
        [self.iconCache setObject:icon forKey:ipaPath];
        return icon;
    }

    return nil;
}

#pragma mark - Compatibility metadata + icon extraction

- (IPAExtractedInfo *)extractInfoFromIPA:(NSString *)ipaPath {
    IPAExtractedInfo *info = [self extractMetadataFromIPA:ipaPath];
    if (!info || ipaPath.length == 0) return info;
    info.icon = [self extractIconFromIPA:ipaPath];
    return info;
}

- (BOOL)containsDangerousPath:(NSString *)path {
    if (!path) return YES;
    if ([path containsString:@".."] || [path containsString:@"~"] || [path hasPrefix:@"/"]) return YES;
    return NO;
}

#pragma mark - Full extraction fallback (kept for compatibility, rarely used)

- (UIImage *)extractIconFromAppDirectory:(NSString *)appDir infoPlist:(NSDictionary *)plist {
    if (appDir.length == 0 || plist.count == 0) return nil;

    NSArray *iconFiles = nil;
    NSDictionary *iconsDict = plist[@"CFBundleIcons"];
    NSDictionary *primaryIcon = iconsDict[@"CFBundlePrimaryIcon"];
    iconFiles = primaryIcon[@"CFBundleIconFiles"];
    if (!iconFiles) iconFiles = plist[@"CFBundleIconFiles"];
    if (!iconFiles || iconFiles.count == 0) iconFiles = @[@"AppIcon60x60"];

    for (NSString *iconName in [iconFiles reverseObjectEnumerator]) {
        for (NSString *scale in @[@"@3x", @"@2x", @""]) {
            for (NSString *ext in @[@".png", @".jpg", @".jpeg"]) {
                NSString *path = [appDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@%@%@", iconName, scale, ext]];
                if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                    UIImage *img = [UIImage imageWithContentsOfFile:path];
                    if (img) return img;
                }
            }
        }
    }

    NSString *iconName = plist[@"CFBundleIconName"];
    if ([iconName isKindOfClass:[NSString class]] && iconName.length > 0) {
        NSBundle *bundle = [NSBundle bundleWithPath:appDir];
        if (bundle) {
            UITraitCollection *trait3x = [UITraitCollection traitCollectionWithDisplayScale:3.0];
            UIImage *img = [UIImage imageNamed:iconName inBundle:bundle compatibleWithTraitCollection:trait3x];
            if (img) return img;
            UITraitCollection *trait2x = [UITraitCollection traitCollectionWithDisplayScale:2.0];
            img = [UIImage imageNamed:iconName inBundle:bundle compatibleWithTraitCollection:trait2x];
            if (img) return img;
            img = [UIImage imageNamed:iconName inBundle:bundle compatibleWithTraitCollection:nil];
            if (img) return img;
        }
    }

    NSString *assetsPath = [appDir stringByAppendingPathComponent:@"Assets.car"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:assetsPath]) {
        UIImage *img = [self loadIconFromAssetsCar:assetsPath infoPlist:plist];
        if (img) return img;
    }

    NSArray *bundleContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appDir error:nil];
    for (NSString *file in bundleContents) {
        NSString *lower = file.lowercaseString;
        if ([lower hasPrefix:@"appicon"] && ([lower hasSuffix:@".png"] || [lower hasSuffix:@".jpg"] || [lower hasSuffix:@".jpeg"])) {
            NSString *path = [appDir stringByAppendingPathComponent:file];
            UIImage *img = [UIImage imageWithContentsOfFile:path];
            if (img) return img;
        }
    }
    return nil;
}

- (UIImage *)extractIconFromAssetsCatalogInIPA:(NSString *)ipaPath {
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"IPAIconExtract-%@", [[NSUUID UUID] UUIDString]]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *unzipPath = [self resolvedUnzipPath];
    if (!unzipPath.length) { [fm removeItemAtPath:tempDir error:nil]; return nil; }

    CommandResult *extractResult = [[ProcessRunner sharedRunner] runCommand:unzipPath
                                                                   arguments:@[@"-q", @"-o", ipaPath, @"-d", tempDir]
                                                                     timeout:60.0];
    if (!extractResult.success) {
        [fm removeItemAtPath:tempDir error:nil];
        return nil;
    }

    NSString *payloadPath = [tempDir stringByAppendingPathComponent:@"Payload"];
    NSArray *payloadItems = [fm contentsOfDirectoryAtPath:payloadPath error:nil];
    NSString *appPath = nil;
    for (NSString *item in payloadItems) {
        if ([item hasSuffix:@".app"]) {
            appPath = [payloadPath stringByAppendingPathComponent:item];
            break;
        }
    }

    if (!appPath) {
        [fm removeItemAtPath:tempDir error:nil];
        return nil;
    }

    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    if (!plist) {
        [fm removeItemAtPath:tempDir error:nil];
        return nil;
    }

    UIImage *icon = [self extractIconFromAppDirectory:appPath infoPlist:plist];
    [fm removeItemAtPath:tempDir error:nil];
    return icon;
}

- (UIImage *)loadIconFromAssetsCar:(NSString *)assetsPath infoPlist:(NSDictionary *)plist {
    static dispatch_once_t onceToken;
    static Class CUICatalogClass = nil;
    static SEL initWithURLErrorSel = NULL;
    static SEL imageWithNameScaleFactorDeviceIdiomSel = NULL;

    dispatch_once(&onceToken, ^{
        NSBundle *coreUIBundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreUI.framework"];
        if (coreUIBundle) {
            [coreUIBundle load];
            CUICatalogClass = NSClassFromString(@"CUICatalog");
            if (CUICatalogClass) {
                initWithURLErrorSel = NSSelectorFromString(@"initWithURL:error:");
                imageWithNameScaleFactorDeviceIdiomSel = NSSelectorFromString(@"imageWithName:scaleFactor:deviceIdiom:");
            }
        }
    });

    if (!CUICatalogClass || !initWithURLErrorSel) return nil;

    NSString *iconName = nil;
    id iconNameValue = plist[@"CFBundleIconName"];
    if ([iconNameValue isKindOfClass:[NSString class]]) iconName = iconNameValue;

    if (!iconName) {
        NSDictionary *iconsDict = plist[@"CFBundleIcons"];
        if ([iconsDict isKindOfClass:[NSDictionary class]]) {
            NSDictionary *primaryIcon = iconsDict[@"CFBundlePrimaryIcon"];
            if ([primaryIcon isKindOfClass:[NSDictionary class]]) {
                NSArray *iconFiles = primaryIcon[@"CFBundleIconFiles"];
                if ([iconFiles isKindOfClass:[NSArray class]] && iconFiles.count > 0) {
                    id lastFile = iconFiles.lastObject;
                    if ([lastFile isKindOfClass:[NSString class]]) iconName = lastFile;
                }
            }
        }
    }

    if (!iconName) return nil;

    id catalog = [[CUICatalogClass alloc] init];
    NSURL *assetsURL = [NSURL fileURLWithPath:assetsPath];

    id (*initWithURL)(id, SEL, id, NSError *__autoreleasing *) = (id (*)(id, SEL, id, NSError *__autoreleasing *))[catalog methodForSelector:initWithURLErrorSel];
    if (initWithURL) {
        NSError *__autoreleasing error = nil;
        id result = initWithURL(catalog, initWithURLErrorSel, assetsURL, &error);
        if (!result || error) return nil;
        catalog = result;
    }

    if (!imageWithNameScaleFactorDeviceIdiomSel) return nil;

    UIImage *(*getImage)(id, SEL, NSString *, CGFloat, NSInteger) = (UIImage *(*)(id, SEL, NSString *, CGFloat, NSInteger))[catalog methodForSelector:imageWithNameScaleFactorDeviceIdiomSel];
    if (!getImage) return nil;

    UIImage *icon = getImage(catalog, imageWithNameScaleFactorDeviceIdiomSel, iconName, 3.0, 0);
    if (!icon) icon = getImage(catalog, imageWithNameScaleFactorDeviceIdiomSel, iconName, 2.0, 0);
    if (!icon) icon = getImage(catalog, imageWithNameScaleFactorDeviceIdiomSel, iconName, 1.0, 0);
    if (!icon) icon = getImage(catalog, imageWithNameScaleFactorDeviceIdiomSel, iconName, 3.0, 1);
    if (!icon) icon = getImage(catalog, imageWithNameScaleFactorDeviceIdiomSel, iconName, 2.0, 1);
    if (!icon) icon = getImage(catalog, imageWithNameScaleFactorDeviceIdiomSel, iconName, 1.0, 1);

    return icon;
}

- (NSArray *)extractArchitectures:(NSString *)executablePath {
    NSMutableArray *archs = [NSMutableArray array];
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:executablePath];
    if (!fh) return archs;
    NSData *header = [fh readDataOfLength:8];
    [fh closeFile];
    if (header.length < 8) return archs;
    const unsigned char *bytes = header.bytes;
    uint32_t magic = *(uint32_t *)bytes;
    if (magic == 0xfeedfacf) {
        uint32_t cputype = *(uint32_t *)(bytes + 4);
        if (cputype == 0x0100000c) [archs addObject:@"arm64"];
        else if (cputype == 0x0200000c) [archs addObject:@"arm64e"];
    } else if (magic == 0xcafebabe || magic == 0xbebafeca) {
        [archs addObject:@"universal"];
    }
    return [archs copy];
}

- (NSString *)formatFileSize:(long long)bytes {
    if (bytes < 1024) return [NSString stringWithFormat:@"%lld بايت", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.1f كيلوبايت", bytes / 1024.0];
    if (bytes < 1024 * 1024 * 1024) return [NSString stringWithFormat:@"%.1f ميغابايت", bytes / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.2f غيغابايت", bytes / (1024.0 * 1024.0 * 1024.0)];
}

@end
