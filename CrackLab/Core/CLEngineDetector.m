//
//  CLEngineDetector.m
//

#import "CLEngineDetector.h"
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <libkern/OSByteOrder.h>

@implementation CLEngineDetector

+ (NSString *)localizedNameForEngine:(CLGameEngine)engine {
    switch (engine) {
        case CLGameEngineUnity:       return @"Unity";
        case CLGameEngineUnreal:      return @"Unreal Engine";
        case CLGameEngineGodot:       return @"Godot";
        case CLGameEngineCocos2D:     return @"Cocos2D";
        case CLGameEngineNativeMetal: return @"Metal (Native)";
        case CLGameEngineSpriteKit:   return @"SpriteKit";
        case CLGameEngineSceneKit:    return @"SceneKit";
        default:                      return @"غير معروف";
    }
}

// Lightweight Mach-O dylib-name collector. Handles thin + fat, 32/64.
+ (NSSet<NSString *> *)dylibNamesForExecutable:(NSString *)path {
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    FILE *f = fopen(path.fileSystemRepresentation, "rb");
    if (!f) return names;

    uint32_t magic = 0;
    if (fread(&magic, sizeof(magic), 1, f) != 1) { fclose(f); return names; }

    NSMutableArray<NSValue *> *slices = [NSMutableArray array]; // NSValue(NSRange) offsets
    if (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64) {
        int is64 = (magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64);
        int swapped = (magic == FAT_CIGAM || magic == FAT_CIGAM_64);
        uint32_t nfat = 0;
        if (is64) {
            struct fat_header_64 fh; rewind(f);
            if (fread(&fh, sizeof(fh), 1, f) == 1) {
                nfat = swapped ? OSSwapInt32(fh.nfat_arch) : fh.nfat_arch;
            }
        } else {
            struct fat_header fh; rewind(f);
            if (fread(&fh, sizeof(fh), 1, f) == 1) {
                nfat = swapped ? OSSwapInt32(fh.nfat_arch) : fh.nfat_arch;
            }
        }
        for (uint32_t i = 0; i < nfat && i < 8; i++) {
            uint32_t offset = 0;
            if (is64) {
                struct fat_arch_64 a; 
                if (fread(&a, sizeof(a), 1, f) == 1) offset = swapped ? (uint32_t)OSSwapInt64(a.offset) : (uint32_t)a.offset;
            } else {
                struct fat_arch a;
                if (fread(&a, sizeof(a), 1, f) == 1) offset = swapped ? OSSwapInt32(a.offset) : a.offset;
            }
            if (offset) [slices addObject:[NSValue valueWithRange:NSMakeRange(offset, 0)]];
        }
    } else {
        [slices addObject:[NSValue valueWithRange:NSMakeRange(0, 0)]];
    }

    char nameBuf[1024];
    for (NSValue *rv in slices) {
        uint32_t off = (uint32_t)rv.rangeValue.location;
        fseek(f, off, SEEK_SET);
        uint32_t mhMagic = 0;
        if (fread(&mhMagic, sizeof(mhMagic), 1, f) != 1) continue;
        uint32_t ncmds = 0; uint32_t sizeofcmds = 0; long lcOffset = 0;
        if (mhMagic == MH_MAGIC_64 || mhMagic == MH_CIGAM_64) {
            struct mach_header_64 mh;
            fseek(f, off, SEEK_SET);
            if (fread(&mh, sizeof(mh), 1, f) != 1) continue;
            int swapped = (mhMagic == MH_CIGAM_64);
            ncmds = swapped ? OSSwapInt32(mh.ncmds) : mh.ncmds;
            sizeofcmds = swapped ? OSSwapInt32(mh.sizeofcmds) : mh.sizeofcmds;
            lcOffset = off + sizeof(struct mach_header_64);
        } else if (mhMagic == MH_MAGIC || mhMagic == MH_CIGAM) {
            struct mach_header mh;
            fseek(f, off, SEEK_SET);
            if (fread(&mh, sizeof(mh), 1, f) != 1) continue;
            int swapped = (mhMagic == MH_CIGAM);
            ncmds = swapped ? OSSwapInt32(mh.ncmds) : mh.ncmds;
            sizeofcmds = swapped ? OSSwapInt32(mh.sizeofcmds) : mh.sizeofcmds;
            lcOffset = off + sizeof(struct mach_header);
        } else continue;

        fseek(f, lcOffset, SEEK_SET);
        long pos = lcOffset;
        for (uint32_t i = 0; i < ncmds && i < 256; i++) {
            struct load_command lc;
            if (fread(&lc, sizeof(lc), 1, f) != 1) break;
            uint32_t cmd = lc.cmd; uint32_t cmdsize = lc.cmdsize;
            if (mhMagic == MH_CIGAM_64 || mhMagic == MH_CIGAM) {
                cmd = OSSwapInt32(lc.cmd); cmdsize = OSSwapInt32(lc.cmdsize);
            }
            if (cmd == LC_LOAD_DYLIB || cmd == LC_LOAD_WEAK_DYLIB) {
                struct dylib_command dc;
                fseek(f, pos, SEEK_SET);
                if (fread(&dc, sizeof(dc), 1, f) == 1) {
                    uint32_t noff = (mhMagic == MH_CIGAM_64 || mhMagic == MH_CIGAM) ? OSSwapInt32(dc.dylib.name.offset) : dc.dylib.name.offset;
                    fseek(f, pos + noff, SEEK_SET);
                    size_t r = fread(nameBuf, 1, sizeof(nameBuf) - 1, f);
                    nameBuf[r] = 0;
                    NSString *nm = [NSString stringWithUTF8String:nameBuf];
                    if (nm.length) [names addObject:nm];
                }
            }
            pos += cmdsize;
            fseek(f, pos, SEEK_SET);
            if (cmdsize < sizeof(struct load_command)) break;
        }
        (void)sizeofcmds;
    }
    fclose(f);
    return names;
}

+ (CLGameEngine)detectEngineForBundle:(NSString *)bundlePath
                       linkedFrameworks:(NSArray<NSString *> **)outFrameworks {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Read executable name from Info.plist
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *exeName = info[@"CFBundleExecutable"];
    NSString *exePath = exeName.length ? [bundlePath stringByAppendingPathComponent:exeName] : nil;

    NSSet<NSString *> *dylibs = exePath && [fm fileExistsAtPath:exePath]
        ? [self dylibNamesForExecutable:exePath] : [NSSet set];

    if (outFrameworks) {
        NSArray *all = [[dylibs allObjects] sortedArrayUsingSelector:@selector(compare:)];
        if (all.count > 24) all = [all subarrayWithRange:NSMakeRange(0, 24)];
        *outFrameworks = all;
    }

    // Layer 1 — bundle markers
    if ([fm fileExistsAtPath:[bundlePath stringByAppendingPathComponent:@"UnityFramework.framework"]])
        return CLGameEngineUnity;

    // Unreal: cooked .uasset bundles usually sit under the app or CookedData dirs
    NSArray *unrealHints = @[@"ue4", @"ue5", @"unrealengine", @".uasset", @"cookeddata"];
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:bundlePath];
    NSInteger unrealScore = 0, godotScore = 0, cocosScore = 0;
    NSString *rel;
    NSInteger scanned = 0;
    while ((rel = [en nextObject]) && scanned < 4000) {
        scanned++;
        NSString *low = rel.lowercaseString;
        for (NSString *h in unrealHints) {
            if ([low containsString:h]) { unrealScore++; break; }
        }
        if ([low containsString:@"godot"] || [low hasSuffix:@".gdc"]) godotScore++;
        if ([low containsString:@"cocos2d"] || [low containsString:@"libcocos"]) cocosScore++;
        if (unrealScore > 8 || godotScore > 3 || cocosScore > 3) break;
    }
    if (godotScore > 3) return CLGameEngineGodot;
    if (cocosScore > 3) return CLGameEngineCocos2D;
    if (unrealScore > 8) return CLGameEngineUnreal;

    // Layer 2 — linked frameworks
    BOOL hasMetal = NO, hasSpriteKit = NO, hasSceneKit = NO, hasUnityFW = NO;
    for (NSString *d in dylibs) {
        NSString *low = d.lowercaseString;
        if ([low containsString:@"unityframework"]) hasUnityFW = YES;
        else if ([low containsString:@"metalkit"] || [low hasSuffix:@"/metal.framework"]) hasMetal = YES;
        else if ([low containsString:@"spritekit"]) hasSpriteKit = YES;
        else if ([low containsString:@"scenekit"]) hasSceneKit = YES;
    }
    if (hasUnityFW) return CLGameEngineUnity;
    if (hasSpriteKit) return CLGameEngineSpriteKit;
    if (hasSceneKit) return CLGameEngineSceneKit;
    if (hasMetal) return CLGameEngineNativeMetal;

    return CLGameEngineUnknown;
}

@end
