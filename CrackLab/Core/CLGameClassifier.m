//
//  CLGameClassifier.m
//

#import "CLGameClassifier.h"
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <libkern/OSByteOrder.h>

// Evidence weights — single source of truth, every weight is named.
static NSInteger const kWeightGameKit          = 40;  // Game Center APIs — games only
static NSInteger const kWeightGameController   = 30;
static NSInteger const kWeightReplayKit        = 25;
static NSInteger const kWeightSpriteKit        = 15;
static NSInteger const kWeightSceneKit         = 15;
static NSInteger const kWeightAppStoreOrigin   = 10;  // DTAppStoreToolsBuild (provenance, not game proof)

static NSString * const kEntitlementPatternNew = @"com.apple.developer.game-center";
static NSString * const kEntitlementPatternOld = @"<key>game-center</key>";

@implementation CLClassificationResult
@end

@implementation CLGameClassifier

#pragma mark - Public

+ (CLClassificationResult *)classifyProxy:(id)proxy
                                     info:(NSDictionary *)info
                                    probe:(CLMetadataProbeResult *)probe
                           executablePath:(NSString *)executablePath {
    CLClassificationResult *res = [CLClassificationResult new];
    res.signals = [NSMutableArray array];
    res.score = 0;

    // ── (A) Official metadata — when present it is decisive ──
    if ([probe.metadataState isEqualToString:@"ok"]) {
        if ([probe.genreId respondsToSelector:@selector(integerValue)] &&
            [probe.genreId integerValue] == 6014) {
            [self setConfident:res signal:[NSString stringWithFormat:@"iTunesMetadata genreId=%@", probe.genreId]];
            return res;
        }
        if ([probe.genre.lowercaseString containsString:@"game"]) {
            [self setConfident:res signal:[NSString stringWithFormat:@"iTunesMetadata genre=%@", probe.genre]];
            return res;
        }
        [res.signals addObject:@"iTunesMetadata بدون genre"];
    } else {
        [res.signals addObject:[NSString stringWithFormat:@"iTunesMetadata: %@", probe.metadataState]];
    }

    NSString *category = info[@"LSApplicationCategoryType"] ?: @"";
    if ([category.lowercaseString containsString:@"game"]) {
        [self setConfident:res signal:@"LSApplicationCategoryType=Games"];
        return res;
    }
    if (category.length) [res.signals addObject:[NSString stringWithFormat:@"category=%@ (ليس Games)", category]];

    @try {
        for (id gid in ([proxy valueForKey:@"genreIDs"] ?: @[])) {
            if ([gid respondsToSelector:@selector(integerValue)] && [gid integerValue] == 6014) {
                [self setConfident:res signal:@"LS genreID=6014"];
                return res;
            }
        }
        NSString *g = [proxy valueForKey:@"genre"];
        if ([g.lowercaseString containsString:@"game"]) {
            [self setConfident:res signal:@"LS genre=Games"];
            return res;
        }
    } @catch (__unused NSException *e) {}

    // ── (B) Developer-declared evidence inside the binary ──
    if (executablePath.length) {
        BOOL hasEntitlement =
            [self file:executablePath containsPattern:kEntitlementPatternNew] ||
            [self file:executablePath containsPattern:kEntitlementPatternOld];
        if (hasEntitlement) {
            [self setConfident:res signal:@"Game Center entitlement (معلن من المطور)"];
            return res;
        }
    }

    // ── (C) Framework evidence (weighted, never decisive alone) ──
    // GameKit linkage implies Game Center usage → strong.
    NSSet<NSString *> *dylibs = executablePath.length ? [self dylibNamesForExecutable:executablePath] : [NSSet set];
    NSString *dylibDesc = dylibs.count
        ? [[[dylibs allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]
        : @"—";

    BOOL hasGameKit = [self dylibs:dylibs containAny:@[@"gamekit"]];
    BOOL hasGameController = [self dylibs:dylibs containAny:@[@"gamecontroller"]];
    BOOL hasReplayKit = [self dylibs:dylibs containAny:@[@"replaykit"]];
    BOOL hasSpriteKit = [self dylibs:dylibs containAny:@[@"spritekit"]];
    BOOL hasSceneKit = [self dylibs:dylibs containAny:@[@"scenekit"]];

    if (hasGameKit)    { res.score += kWeightGameKit;        [res.signals addObject:@"GameKit مربوط"]; }
    if (hasGameController) { res.score += kWeightGameController; [res.signals addObject:@"GameController مربوط"]; }
    if (hasReplayKit)  { res.score += kWeightReplayKit;      [res.signals addObject:@"ReplayKit مربوط"]; }
    if (hasSpriteKit)  { res.score += kWeightSpriteKit;      [res.signals addObject:@"SpriteKit مربوط"]; }
    if (hasSceneKit)   { res.score += kWeightSceneKit;       [res.signals addObject:@"SceneKit مربوط"]; }

    // App Store provenance (DTAppStoreToolsBuild) — context only.
    if (info[@"DTAppStoreToolsBuild"]) {
        res.score += kWeightAppStoreOrigin;
        [res.signals addObject:@"DTAppStoreToolsBuild (App Store)"];
    }

    [res.signals addObject:[NSString stringWithFormat:@"dylibs: %@", dylibDesc]];

    // ── Decision ──
    if (res.score >= 70)      res.confidence = CLGameConfidenceConfident;
    else if (res.score >= 40) res.confidence = CLGameConfidencePossible;
    else                      res.confidence = CLGameConfidenceUnlikely;
    res.isGame = (res.confidence != CLGameConfidenceUnlikely);
    res.confidenceName = [self arabicNameForConfidence:res.confidence];
    if (!res.isGame) [res.signals addObject:[NSString stringWithFormat:@"ثقة %ld < عتبة اللعبة", (long)res.score]];
    return res;
}

#pragma mark - Helpers

+ (void)setConfident:(CLClassificationResult *)res signal:(NSString *)signal {
    res.confidence = CLGameConfidenceConfident;
    res.isGame = YES;
    res.score = 100;
    res.confidenceName = [self arabicNameForConfidence:CLGameConfidenceConfident];
    [res.signals addObject:signal];
}

+ (NSString *)arabicNameForConfidence:(CLGameConfidence)c {
    switch (c) {
        case CLGameConfidenceConfident: return @"واثق";
        case CLGameConfidencePossible:  return @"محتمل";
        default:                        return @"ضئيل";
    }
}

+ (BOOL)dylibs:(NSSet<NSString *> *)dylibs containAny:(NSArray<NSString *> *)needles {
    for (NSString *d in dylibs) {
        NSString *low = d.lowercaseString;
        for (NSString *n in needles) if ([low containsString:n]) return YES;
    }
    return NO;
}

// Chunked substring scan — bounded memory on large game binaries.
+ (BOOL)file:(NSString *)path containsPattern:(NSString *)pattern {
    NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!h) return NO;
    NSData *needle = [pattern dataUsingEncoding:NSUTF8StringEncoding];
    if (!needle.length) { [h closeFile]; return NO; }
    const NSUInteger chunkSize = 4 * 1024 * 1024;
    NSMutableData *carry = [NSMutableData data];
    BOOL found = NO;
    while (!found) {
        NSData *chunk = [h readDataOfLength:chunkSize];
        if (!chunk.length) break;
        [carry appendData:chunk];
        if ([carry rangeOfData:needle options:0 range:NSMakeRange(0, carry.length)].location != NSNotFound) {
            found = YES; break;
        }
        NSUInteger keep = needle.length > 1 ? needle.length - 1 : 1;
        if (carry.length > keep) {
            [carry replaceBytesInRange:NSMakeRange(0, carry.length - keep) withBytes:NULL length:0];
        }
    }
    [h closeFile];
    return found;
}

// Minimal LC_LOAD_DYLIB scanner (thin + fat, 32/64) — framework evidence only.
+ (NSSet<NSString *> *)dylibNamesForExecutable:(NSString *)path {
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    FILE *f = fopen(path.fileSystemRepresentation, "rb");
    if (!f) return names;
    uint32_t magic = 0;
    if (fread(&magic, sizeof(magic), 1, f) != 1) { fclose(f); return names; }

    NSMutableArray<NSValue *> *offsets = [NSMutableArray array];
    if (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64) {
        int is64 = (magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64);
        int swapped = (magic == FAT_CIGAM || magic == FAT_CIGAM_64);
        uint32_t nfat = 0;
        rewind(f);
        // The fat header has the same nfat_arch layout for 32/64 containers;
        // only fat_arch versus fat_arch_64 differs below.
        struct fat_header fh;
        if (fread(&fh, sizeof(fh), 1, f) == 1) nfat = swapped ? OSSwapInt32(fh.nfat_arch) : fh.nfat_arch;
        for (uint32_t i = 0; i < nfat && i < 8; i++) {
            uint32_t off = 0;
            if (is64) { struct fat_arch_64 a; if (fread(&a, sizeof(a), 1, f) == 1) off = swapped ? (uint32_t)OSSwapInt64(a.offset) : (uint32_t)a.offset; }
            else      { struct fat_arch   a; if (fread(&a, sizeof(a), 1, f) == 1) off = swapped ? OSSwapInt32(a.offset) : a.offset; }
            if (off) [offsets addObject:[NSValue valueWithRange:NSMakeRange(off, 0)]];
        }
    } else {
        [offsets addObject:[NSValue valueWithRange:NSMakeRange(0, 0)]];
    }

    char buf[1024];
    for (NSValue *rv in offsets) {
        uint32_t off = (uint32_t)rv.rangeValue.location;
        fseek(f, off, SEEK_SET);
        uint32_t mhMagic = 0;
        if (fread(&mhMagic, sizeof(mhMagic), 1, f) != 1) continue;
        uint32_t ncmds = 0; long lcOff = 0; int swapped = 0;
        if (mhMagic == MH_MAGIC_64 || mhMagic == MH_CIGAM_64) {
            struct mach_header_64 mh; fseek(f, off, SEEK_SET);
            if (fread(&mh, sizeof(mh), 1, f) != 1) continue;
            swapped = (mhMagic == MH_CIGAM_64);
            ncmds = swapped ? OSSwapInt32(mh.ncmds) : mh.ncmds;
            lcOff = off + sizeof(struct mach_header_64);
        } else if (mhMagic == MH_MAGIC || mhMagic == MH_CIGAM) {
            struct mach_header mh; fseek(f, off, SEEK_SET);
            if (fread(&mh, sizeof(mh), 1, f) != 1) continue;
            swapped = (mhMagic == MH_CIGAM);
            ncmds = swapped ? OSSwapInt32(mh.ncmds) : mh.ncmds;
            lcOff = off + sizeof(struct mach_header);
        } else continue;

        fseek(f, lcOff, SEEK_SET);
        long pos = lcOff;
        for (uint32_t i = 0; i < ncmds && i < 512; i++) {
            struct load_command lc;
            if (fread(&lc, sizeof(lc), 1, f) != 1) break;
            uint32_t cmd = lc.cmd, cmdsize = lc.cmdsize;
            if (swapped) { cmd = OSSwapInt32(lc.cmd); cmdsize = OSSwapInt32(lc.cmdsize); }
            if (cmd == LC_LOAD_DYLIB || cmd == LC_LOAD_WEAK_DYLIB) {
                struct dylib_command dc;
                fseek(f, pos, SEEK_SET);
                if (fread(&dc, sizeof(dc), 1, f) == 1) {
                    uint32_t noff = swapped ? OSSwapInt32(dc.dylib.name.offset) : dc.dylib.name.offset;
                    fseek(f, pos + noff, SEEK_SET);
                    size_t rd = fread(buf, 1, sizeof(buf) - 1, f);
                    buf[rd] = 0;
                    NSString *nm = [NSString stringWithUTF8String:buf];
                    if (nm.length) [names addObject:nm];
                }
            }
            if (cmdsize < sizeof(struct load_command)) break;
            pos += cmdsize;
            fseek(f, pos, SEEK_SET);
        }
    }
    fclose(f);
    return names;
}

@end
