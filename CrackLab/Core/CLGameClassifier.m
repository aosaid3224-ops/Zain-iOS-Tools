//
//  CLGameClassifier.m
//

#import "CLGameClassifier.h"
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <libkern/OSByteOrder.h>

// Evidence weights — single source of truth, every weight is named.
// Evidence model — anti false-positive by construction:
//   DECISIVE : official metadata OR Game Center entitlement (parsed from the
//              code signature blob) → Confident immediately.
//   STRONG   : GameKit linkage (40) — Game Center APIs are game-only; reaches
//              the game threshold alone.
//   SUPPORT  : GameController/ReplayKit/SpriteKit/SceneKit/engine/provenance.
//              SUPPORT TOTAL IS CAPPED AT 30 — strictly below the game
//              threshold (40), so no combination of generic frameworks can
//              ever classify a non-game app as a game.
static NSInteger const kWeightGameKit          = 40;  // Game Center APIs — games only
static NSInteger const kWeightGameController   = 30;  // support
static NSInteger const kWeightReplayKit        = 25;  // support
static NSInteger const kWeightSpriteKit        = 15;  // support
static NSInteger const kWeightSceneKit         = 15;  // support
static NSInteger const kWeightEngine           = 10;  // support (Unity/UE/Godot)
static NSInteger const kWeightAppStoreOrigin   = 5;   // support (DTAppStoreToolsBuild)
static NSInteger const kSupportCap             = 30;  // hard ceiling for all support signals
static NSInteger const kGameThreshold          = 40;  // support alone can NEVER reach this

static NSString * const kEntitlementPatternNew = @"com.apple.developer.game-center";

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

    // ── (B) Developer-declared evidence: Game Center entitlement ──
    // Parsed from the CODE SIGNATURE entitlement blob (CSSLOT_ENTITLEMENTS /
    // CSSLOT_ENTITLEMENTS_DER) — the same bytes iOS enforces at launch. Never a
    // whole-file substring scan: string tables and SDK resources must not count.
    if (executablePath.length) {
        CL entitlementResult = 0; (void)entitlementResult;
        BOOL hasEntitlement = [self hasGameCenterEntitlement:executablePath];
        NSString *entState = hasEntitlement ? @"YES" : @"NO";
        if (hasEntitlement) {
            [self setConfident:res signal:[NSString stringWithFormat:@"Game Center entitlement (%@)", entState]];
            return res;
        }
        [res.signals addObject:[NSString stringWithFormat:@"GameCenter entitlement: %@", entState]];
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

    // STRONG: GameKit — reaches the threshold alone (non-support).
    if (hasGameKit) { res.score += kWeightGameKit; [res.signals addObject:@"GameKit مربوط"]; }

    // SUPPORT: capped collectively at kSupportCap (30 < threshold 40).
    NSInteger support = 0;
    if (hasGameController) { support += kWeightGameController; [res.signals addObject:@"GameController مربوط"]; }
    if (hasReplayKit)      { support += kWeightReplayKit;      [res.signals addObject:@"ReplayKit مربوط"]; }
    if (hasSpriteKit)      { support += kWeightSpriteKit;      [res.signals addObject:@"SpriteKit مربوط"]; }
    if (hasSceneKit)       { support += kWeightSceneKit;       [res.signals addObject:@"SceneKit مربوط"]; }
    if (info[@"DTAppStoreToolsBuild"]) {
        support += kWeightAppStoreOrigin;
        [res.signals addObject:@"DTAppStoreToolsBuild"];
    }
    if (support > kSupportCap) support = kSupportCap;
    res.score += support;
    if (support == kSupportCap) [res.signals addObject:[NSString stringWithFormat:@"دعم مكبّر عند %ld", (long)kSupportCap]];

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

#pragma mark - Code-signature entitlement parsing

// CS magic constants (big-endian on disk)
static uint32_t const kCSMagicEmbeddedSignature = 0xfade0cc0;
static uint32_t const kCSMagicEntitlements      = 0xfade7171;
static uint32_t const kCSMagicEntitlementsDER   = 0xfade7181;
static uint32_t const kCSSlotEntitlements       = 5;
static uint32_t const kCSSlotEntitlementsDER    = 7;

static uint32_t CLReadBE32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

/// Extracts the embedded entitlement blob (XML or DER) from the Mach-O code
/// signature and answers whether the Game Center entitlement is present.
/// Returns NO also when the signature cannot be parsed (honest negative —
/// we never fall back to whole-file scanning).
+ (BOOL)hasGameCenterEntitlement:(NSString *)path {
    FILE *f = fopen(path.fileSystemRepresentation, "rb");
    if (!f) return NO;
    BOOL found = NO;

    // Locate LC_CODE_SIGNATURE linkedit_data_command in every Mach-O slice.
    uint32_t magic = 0;
    if (fread(&magic, sizeof(magic), 1, f) != 1) { fclose(f); return NO; }

    NSMutableArray<NSValue *> *offsets = [NSMutableArray array];
    if (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64) {
        int is64 = (magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64);
        int swapped = (magic == FAT_CIGAM || magic == FAT_CIGAM_64);
        uint32_t nfat = 0;
        rewind(f);
        if (is64) { struct fat_header_64 fh; if (fread(&fh, sizeof(fh), 1, f) == 1) nfat = swapped ? OSSwapInt32(fh.nfat_arch) : fh.nfat_arch; }
        else      { struct fat_header   fh; if (fread(&fh, sizeof(fh), 1, f) == 1) nfat = swapped ? OSSwapInt32(fh.nfat_arch) : fh.nfat_arch; }
        for (uint32_t i = 0; i < nfat && i < 8; i++) {
            uint32_t off = 0;
            if (is64) { struct fat_arch_64 a; if (fread(&a, sizeof(a), 1, f) == 1) off = swapped ? (uint32_t)OSSwapInt64(a.offset) : (uint32_t)a.offset; }
            else      { struct fat_arch   a; if (fread(&a, sizeof(a), 1, f) == 1) off = swapped ? OSSwapInt32(a.offset) : a.offset; }
            if (off) [offsets addObject:[NSValue valueWithRange:NSMakeRange(off, 0)]];
        }
    } else {
        [offsets addObject:[NSValue valueWithRange:NSMakeRange(0, 0)]];
    }

    for (NSValue *rv in offsets) {
        if (found) break;
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

        // Find LC_CODE_SIGNATURE (0x1d) → linkedit_data_command {cmd,cmdsize,dataoff,datasize}
        fseek(f, lcOff, SEEK_SET);
        long pos = lcOff;
        uint32_t csDataOff = 0, csDataSize = 0;
        for (uint32_t i = 0; i < ncmds && i < 1024; i++) {
            struct load_command lc;
            if (fread(&lc, sizeof(lc), 1, f) != 1) break;
            uint32_t cmd = lc.cmd, cmdsize = lc.cmdsize;
            if (swapped) { cmd = OSSwapInt32(lc.cmd); cmdsize = OSSwapInt32(lc.cmdsize); }
            if (cmd == LC_CODE_SIGNATURE) {
                struct linkedit_data_command ldc;
                fseek(f, pos, SEEK_SET);
                if (fread(&ldc, sizeof(ldc), 1, f) == 1) {
                    csDataOff = swapped ? OSSwapInt32(ldc.dataoff) : ldc.dataoff;
                    csDataSize = swapped ? OSSwapInt32(ldc.datasize) : ldc.datasize;
                }
                break;
            }
            if (cmdsize < sizeof(struct load_command)) break;
            pos += cmdsize;
            fseek(f, pos, SEEK_SET);
        }
        if (!csDataOff || !csDataSize || csDataSize > 64 * 1024 * 1024) continue;

        // Read the superblob; iterate blob indices for entitlement slots.
        uint8_t *blob = malloc(csDataSize);
        if (!blob) continue;
        fseek(f, csDataOff, SEEK_SET);
        if (fread(blob, 1, csDataSize, f) != csDataSize) { free(blob); continue; }

        uint32_t sbMagic = CLReadBE32(blob);
        if (sbMagic == kCSMagicEmbeddedSignature) {
            uint32_t count = CLReadBE32(blob + 8);
            if (count > 64) count = 64;
            for (uint32_t i = 0; i < count && !found; i++) {
                size_t idx = 12 + (size_t)i * 8;
                if (idx + 8 > csDataSize) break;
                uint32_t type = CLReadBE32(blob + idx);
                uint32_t boff = CLReadBE32(blob + idx + 4);
                if (boff + 8 > csDataSize) continue;
                if (type == kCSSlotEntitlements || type == kCSSlotEntitlementsDER) {
                    uint32_t bmagic = CLReadBE32(blob + boff);
                    if (bmagic == kCSMagicEntitlements || bmagic == kCSMagicEntitlementsDER) {
                        uint32_t blen = CLReadBE32(blob + boff + 4);
                        if (blen < 8 || boff + blen > csDataSize) continue;
                        NSData *payload = [NSData dataWithBytesNoCopy:blob + boff + 8
                                                                 length:blen - 8
                                                           freeWhenDone:NO];
                        // XML: parse; DER: byte-scan the blob only (bounded, exact).
                        if (bmagic == kCSMagicEntitlements) {
                            NSError *pe = nil;
                            id obj = [NSPropertyListSerialization propertyListWithData:payload
                                                                               options:NSPropertyListImmutable
                                                                                format:nil
                                                                                 error:&pe];
                            if ([obj isKindOfClass:[NSDictionary class]]) {
                                id gc = obj[@"com.apple.developer.game-center"];
                                if ([gc isKindOfClass:[NSNumber class]] && [gc boolValue]) found = YES;
                            }
                        } else {
                            NSData *needle = [kEntitlementPatternNew dataUsingEncoding:NSUTF8StringEncoding];
                            if (needle.length && [payload rangeOfData:needle
                                                              options:0
                                                                range:NSMakeRange(0, payload.length)].location != NSNotFound) found = YES;
                        }
                    }
                }
            }
        }
        free(blob);
    }
    fclose(f);
    return found;
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
        if (is64) { struct fat_header_64 fh; if (fread(&fh, sizeof(fh), 1, f) == 1) nfat = swapped ? OSSwapInt32(fh.nfat_arch) : fh.nfat_arch; }
        else      { struct fat_header   fh; if (fread(&fh, sizeof(fh), 1, f) == 1) nfat = swapped ? OSSwapInt32(fh.nfat_arch) : fh.nfat_arch; }
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
