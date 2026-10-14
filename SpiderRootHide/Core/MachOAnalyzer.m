#import "MachOAnalyzer.h"
#import <sys/stat.h>
#include <string.h>

#define MH_MAGIC        0xfeedface
#define MH_MAGIC_64     0xfeedfacf
#define MH_CIGAM        0xcefaedfe
#define MH_CIGAM_64     0xcffaedfe
#define FAT_MAGIC       0xcafebabe
#define FAT_CIGAM       0xbebafeca
#define FAT_MAGIC_64    0xcafebabf
#define FAT_CIGAM_64    0xbfbafeca

#define LC_REQ_DYLD             0x80000000U
#define LC_LOAD_DYLIB           0x0c
#define LC_LOAD_WEAK_DYLIB      0x18
#define LC_RPATH                0x1c
#define LC_ID_DYLIB             0x0d
#define LC_UUID                 0x1b
#define LC_CODE_SIGNATURE       0x1d
#define LC_BUILD_VERSION        0x32
#define LC_ENCRYPTION_INFO      0x21
#define LC_ENCRYPTION_INFO_64   0x2c

#define MH_EXECUTE      2
#define MH_DYLIB        6
#define MH_DYLINKER     7
#define MH_BUNDLE       8

#ifndef CPU_TYPE_ARM
#define CPU_TYPE_ARM        0x0000000c
#endif
#ifndef CPU_TYPE_X86
#define CPU_TYPE_X86        0x00000007
#endif
#ifndef CPU_TYPE_ARM64
#define CPU_TYPE_ARM64      0x0100000c
#endif
#ifndef CPU_TYPE_ARM64_32
#define CPU_TYPE_ARM64_32   0x0200000c
#endif
#ifndef CPU_TYPE_X86_64
#define CPU_TYPE_X86_64     0x01000007
#endif

#define PLATFORM_MACOS      1
#define PLATFORM_IOS        2
#define PLATFORM_TVOS       3
#define PLATFORM_WATCHOS    4

struct mach_header {
    uint32_t magic;
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t filetype;
    uint32_t ncmds;
    uint32_t sizeofcmds;
    uint32_t flags;
};

struct mach_header_64 {
    uint32_t magic;
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t filetype;
    uint32_t ncmds;
    uint32_t sizeofcmds;
    uint32_t flags;
    uint32_t reserved;
};

struct fat_header {
    uint32_t magic;
    uint32_t nfat_arch;
};

struct fat_arch {
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t offset;
    uint32_t size;
    uint32_t align;
};

struct fat_arch_64 {
    uint32_t cputype;
    uint32_t cpusubtype;
    uint64_t offset;
    uint64_t size;
    uint32_t align;
    uint32_t reserved;
};

struct load_command {
    uint32_t cmd;
    uint32_t cmdsize;
};

struct dylib_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t dylib_name_offset;
    uint32_t dylib_timestamp;
    uint32_t dylib_current_version;
    uint32_t dylib_compatibility_version;
};

struct rpath_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t path_offset;
};

struct uuid_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint8_t uuid[16];
};

struct build_version_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t platform;
    uint32_t minos;
    uint32_t sdk;
    uint32_t ntools;
};

static inline uint32_t swap32(uint32_t v) {
    return ((v & 0xFF000000) >> 24) |
           ((v & 0x00FF0000) >> 8)  |
           ((v & 0x0000FF00) << 8)  |
           ((v & 0x000000FF) << 24);
}

static inline uint64_t swap64(uint64_t v) {
    return ((v & 0xFF00000000000000ULL) >> 56) |
           ((v & 0x00FF000000000000ULL) >> 40) |
           ((v & 0x0000FF0000000000ULL) >> 24) |
           ((v & 0x000000FF00000000ULL) >> 8)  |
           ((v & 0x00000000FF000000ULL) << 8)  |
           ((v & 0x0000000000FF0000ULL) << 24) |
           ((v & 0x000000000000FF00ULL) << 40) |
           ((v & 0x00000000000000FFULL) << 56);
}

@implementation MachOSlice
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"cputype"] = @(self.cputype);
    d[@"cpusubtype"] = @(self.cpusubtype);
    d[@"offset"] = @(self.offset);
    d[@"size"] = @(self.size);
    if (self.uuid) d[@"uuid"] = self.uuid;
    if (self.architectureName) d[@"architectureName"] = self.architectureName;
    d[@"encrypted"] = @(self.encrypted);
    d[@"encryptionID"] = @(self.encryptionID);
    return d;
}
@end

@implementation MachODependency
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.rawInstallName) d[@"rawInstallName"] = self.rawInstallName;
    d[@"isWeak"] = @(self.isWeak);
    if (self.sourceExecutablePath) d[@"sourceExecutablePath"] = self.sourceExecutablePath;
    return d;
}
@end

@implementation MachORPath
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.rawPath) d[@"rawPath"] = self.rawPath;
    if (self.sourceExecutablePath) d[@"sourceExecutablePath"] = self.sourceExecutablePath;
    return d;
}
@end

@implementation MachOLoadCommand
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"cmd"] = @(self.cmd);
    d[@"cmdsize"] = @(self.cmdsize);
    if (self.cmdDescription) d[@"description"] = self.cmdDescription;
    return d;
}
@end

@implementation MachOAnalysisResult
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.filePath) d[@"filePath"] = self.filePath;
    d[@"fileSize"] = @(self.fileSize);
    d[@"magic"] = @(self.magic);
    if (self.magicName) d[@"magicName"] = self.magicName;
    d[@"machOType"] = @(self.machOType);
    if (self.machOTypeName) d[@"machOTypeName"] = self.machOTypeName;
    if (self.uuid) d[@"uuid"] = self.uuid;
    if (self.minOSVersion) d[@"minOSVersion"] = self.minOSVersion;
    if (self.sdkVersion) d[@"sdkVersion"] = self.sdkVersion;
    d[@"platform"] = @(self.platform);
    if (self.platformName) d[@"platformName"] = self.platformName;
    d[@"hasCodeSignature"] = @(self.hasCodeSignature);
    d[@"hasEncryptedSlice"] = @(self.hasEncryptedSlice);
    d[@"encryptedSliceCount"] = @(self.encryptedSliceCount);
    d[@"hasEncryptedArm64Slice"] = @(self.hasEncryptedArm64Slice);
    d[@"encryptedArm64SliceCount"] = @(self.encryptedArm64SliceCount);
    d[@"codeSignatureOffset"] = @(self.codeSignatureOffset);
    d[@"codeSignatureSize"] = @(self.codeSignatureSize);
    d[@"parseStatus"] = @(self.parseStatus);
    if (self.parseError) d[@"parseError"] = self.parseError;
    if (self.source) d[@"source"] = self.source;

    NSMutableArray *slicesArr = [NSMutableArray array];
    for (MachOSlice *s in self.slices) { [slicesArr addObject:[s dictionaryRepresentation]]; }
    d[@"slices"] = slicesArr;

    NSMutableArray *depsArr = [NSMutableArray array];
    for (MachODependency *dep in self.dependencies) { [depsArr addObject:[dep dictionaryRepresentation]]; }
    d[@"dependencies"] = depsArr;

    NSMutableArray *rpathsArr = [NSMutableArray array];
    for (MachORPath *rp in self.rpaths) { [rpathsArr addObject:[rp dictionaryRepresentation]]; }
    d[@"rpaths"] = rpathsArr;

    NSMutableArray *lcArr = [NSMutableArray array];
    for (MachOLoadCommand *lc in self.loadCommands) { [lcArr addObject:[lc dictionaryRepresentation]]; }
    d[@"loadCommands"] = lcArr;

    return d;
}
@end

@interface MachOAnalyzer ()
- (NSString *)architectureNameForCputype:(uint32_t)cputype subtype:(uint32_t)subtype;
- (NSString *)machOTypeName:(uint32_t)filetype;
- (NSString *)platformName:(uint32_t)platform;
- (NSString *)versionStringFromUint32:(uint32_t)version;
- (void)parseMachOHeader:(const void *)data
                  length:(size_t)length
                  offset:(uint64_t)offset
                  result:(MachOAnalysisResult *)result
                 isSwap:(BOOL)isSwap;
@end

@implementation MachOAnalyzer

+ (instancetype)sharedAnalyzer {
    static MachOAnalyzer *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (NSString *)architectureNameForCputype:(uint32_t)cputype subtype:(uint32_t)subtype {
    switch (cputype) {
        case CPU_TYPE_ARM64:
            if ((subtype & 0x80000000) || (subtype & 0x00000002)) return @"arm64e";
            return @"arm64";
        case CPU_TYPE_ARM64_32: return @"arm64_32";
        case CPU_TYPE_ARM:
            if (subtype == 9) return @"armv7s";
            if (subtype == 11) return @"armv7k";
            return @"armv7";
        case CPU_TYPE_X86_64: return @"x86_64";
        case CPU_TYPE_X86: return @"i386";
        default: return [NSString stringWithFormat:@"unknown(0x%x)", cputype];
    }
}

- (NSString *)machOTypeName:(uint32_t)filetype {
    switch (filetype) {
        case MH_EXECUTE: return @"MH_EXECUTE";
        case MH_DYLIB: return @"MH_DYLIB";
        case MH_DYLINKER: return @"MH_DYLINKER";
        case MH_BUNDLE: return @"MH_BUNDLE";
        default: return [NSString stringWithFormat:@"unknown(%u)", filetype];
    }
}

- (NSString *)platformName:(uint32_t)platform {
    switch (platform) {
        case PLATFORM_MACOS: return @"macOS";
        case PLATFORM_IOS: return @"iOS";
        case PLATFORM_TVOS: return @"tvOS";
        case PLATFORM_WATCHOS: return @"watchOS";
        default: return [NSString stringWithFormat:@"unknown(%u)", platform];
    }
}

- (NSString *)versionStringFromUint32:(uint32_t)version {
    uint32_t major = (version >> 16) & 0xFFFF;
    uint32_t minor = (version >> 8) & 0xFF;
    uint32_t patch = version & 0xFF;
    if (patch == 0) return [NSString stringWithFormat:@"%u.%u", major, minor];
    return [NSString stringWithFormat:@"%u.%u.%u", major, minor, patch];
}

- (MachOAnalysisResult *)analyzeFileAtPath:(NSString *)path {
    MachOAnalysisResult *result = [[MachOAnalysisResult alloc] init];
    result.filePath = path;
    result.parseStatus = MachOParseNotAttempted;
    result.source = @"internal";
    result.slices = @[];
    result.dependencies = @[];
    result.rpaths = @[];
    result.loadCommands = @[];

    struct stat st;
    if (stat(path.UTF8String, &st) != 0) {
        result.parseStatus = MachOParseFailed;
        result.parseError = @"Failed to stat file";
        return result;
    }
    result.fileSize = st.st_size;

    if (result.fileSize < 4) {
        result.parseStatus = MachOParseFailed;
        result.parseError = @"File too small to be Mach-O";
        return result;
    }

    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) {
        result.parseStatus = MachOParseFailed;
        result.parseError = @"Failed to open file";
        return result;
    }

    NSData *magicData = [fh readDataOfLength:4];
    [fh closeFile];

    if (magicData.length < 4) {
        result.parseStatus = MachOParseFailed;
        result.parseError = @"Failed to read magic";
        return result;
    }

    uint32_t magic = 0;
    [magicData getBytes:&magic length:4];
    result.magic = magic;

    switch (magic) {
        case MH_MAGIC:      result.magicName = @"MH_MAGIC"; break;
        case MH_MAGIC_64:   result.magicName = @"MH_MAGIC_64"; break;
        case MH_CIGAM:      result.magicName = @"MH_CIGAM"; break;
        case MH_CIGAM_64:   result.magicName = @"MH_CIGAM_64"; break;
        case FAT_MAGIC:     result.magicName = @"FAT_MAGIC"; break;
        case FAT_CIGAM:     result.magicName = @"FAT_CIGAM"; break;
        case FAT_MAGIC_64:  result.magicName = @"FAT_MAGIC_64"; break;
        case FAT_CIGAM_64:  result.magicName = @"FAT_CIGAM_64"; break;
        default:
            result.parseStatus = MachOParseFailed;
            result.parseError = [NSString stringWithFormat:@"Unknown magic: 0x%08x", magic];
            return result;
    }

    NSData *fileData = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!fileData || fileData.length == 0) {
        result.parseStatus = MachOParseFailed;
        result.parseError = @"Failed to read file data";
        return result;
    }

    const void *data = fileData.bytes;
    size_t length = fileData.length;

    BOOL isSwap = (magic == MH_CIGAM || magic == MH_CIGAM_64 ||
                   magic == FAT_CIGAM || magic == FAT_CIGAM_64);

    if (magic == MH_MAGIC || magic == MH_MAGIC_64 ||
        magic == MH_CIGAM || magic == MH_CIGAM_64) {
        [self parseMachOHeader:data length:length offset:0 result:result isSwap:isSwap];
    }
    else if (magic == FAT_MAGIC || magic == FAT_CIGAM ||
             magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64) {
        [self parseFatBinary:data length:length result:result isSwap:isSwap];
    }

    return result;
}

- (void)parseMachOHeader:(const void *)data
                  length:(size_t)length
                  offset:(uint64_t)offset
                  result:(MachOAnalysisResult *)result
                  isSwap:(BOOL)isSwap {
    if (length < offset + sizeof(struct mach_header)) {
        result.parseStatus = MachOParsePartial;
        if (!result.parseError) result.parseError = @"Data too short for mach_header";
        return;
    }

    const struct mach_header *mh = (const struct mach_header *)((const uint8_t *)data + offset);
    uint32_t magic = mh->magic;
    BOOL is64 = (magic == MH_MAGIC_64 || magic == MH_CIGAM_64);

    uint32_t cputype = isSwap ? swap32(mh->cputype) : mh->cputype;
    uint32_t cpusubtype = isSwap ? swap32(mh->cpusubtype) : mh->cpusubtype;
    uint32_t filetype = isSwap ? swap32(mh->filetype) : mh->filetype;
    uint32_t ncmds = isSwap ? swap32(mh->ncmds) : mh->ncmds;

    result.machOType = filetype;
    result.machOTypeName = [self machOTypeName:filetype];

    MachOSlice *slice = [[MachOSlice alloc] init];
    slice.cputype = cputype;
    slice.cpusubtype = cpusubtype;
    slice.offset = offset;
    slice.size = length;
    slice.architectureName = [self architectureNameForCputype:cputype subtype:cpusubtype];
    slice.encrypted = NO;
    slice.encryptionID = 0;

    NSMutableArray *slices = [NSMutableArray arrayWithArray:result.slices];
    [slices addObject:slice];
    result.slices = slices;

    uint64_t lcOffset = offset + (is64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header));
    NSMutableArray *deps = [NSMutableArray array];
    NSMutableArray *rpaths = [NSMutableArray array];
    NSMutableArray *lcs = [NSMutableArray array];

    for (uint32_t i = 0; i < ncmds; i++) {
        if (lcOffset + sizeof(struct load_command) > length) break;

        const struct load_command *lc = (const struct load_command *)((const uint8_t *)data + lcOffset);
        uint32_t cmd = isSwap ? swap32(lc->cmd) : lc->cmd;
        uint32_t baseCmd = cmd & ~LC_REQ_DYLD;
        uint32_t cmdsize = isSwap ? swap32(lc->cmdsize) : lc->cmdsize;

        if (cmdsize == 0 || lcOffset + cmdsize > length) break;

        MachOLoadCommand *lcObj = [[MachOLoadCommand alloc] init];
        lcObj.cmd = cmd;
        lcObj.cmdsize = cmdsize;

        switch (baseCmd) {
            case LC_LOAD_DYLIB:
            case LC_LOAD_WEAK_DYLIB:
            case LC_ID_DYLIB: {
                const struct dylib_command *dlc = (const struct dylib_command *)lc;
                uint32_t nameOffset = isSwap ? swap32(dlc->dylib_name_offset) : dlc->dylib_name_offset;
                if (nameOffset < cmdsize && lcOffset + nameOffset < length) {
                    const char *namePtr = (const char *)lc + nameOffset;
                    uint32_t maxLen = cmdsize - nameOffset;
                    uint32_t actualLen = 0;
                    for (uint32_t j = 0; j < maxLen; j++) {
                        if (namePtr[j] == '\0') { actualLen = j; break; }
                    }
                    if (actualLen > 0) {
                        NSString *name = [[NSString alloc] initWithBytes:namePtr length:actualLen encoding:NSUTF8StringEncoding];
                        if (cmd == LC_ID_DYLIB) {
                            lcObj.cmdDescription = [NSString stringWithFormat:@"LC_ID_DYLIB: %@", name];
                        } else {
                            MachODependency *dep = [[MachODependency alloc] init];
                            dep.rawInstallName = name;
                            dep.isWeak = (baseCmd == LC_LOAD_WEAK_DYLIB);
                            dep.sourceExecutablePath = result.filePath;
                            [deps addObject:dep];
                            lcObj.cmdDescription = [NSString stringWithFormat:@"%@: %@",
                                (baseCmd == LC_LOAD_WEAK_DYLIB ? @"LC_LOAD_WEAK_DYLIB" : @"LC_LOAD_DYLIB"), name];
                        }
                    }
                }
                break;
            }
            case LC_RPATH: {
                const struct rpath_command *rpc = (const struct rpath_command *)lc;
                uint32_t pathOffset = isSwap ? swap32(rpc->path_offset) : rpc->path_offset;
                if (pathOffset < cmdsize && lcOffset + pathOffset < length) {
                    const char *pathPtr = (const char *)lc + pathOffset;
                    uint32_t maxLen = cmdsize - pathOffset;
                    uint32_t actualLen = 0;
                    for (uint32_t j = 0; j < maxLen; j++) {
                        if (pathPtr[j] == '\0') { actualLen = j; break; }
                    }
                    if (actualLen > 0) {
                        NSString *path = [[NSString alloc] initWithBytes:pathPtr length:actualLen encoding:NSUTF8StringEncoding];
                        MachORPath *rp = [[MachORPath alloc] init];
                        rp.rawPath = path;
                        rp.sourceExecutablePath = result.filePath;
                        [rpaths addObject:rp];
                        lcObj.cmdDescription = [NSString stringWithFormat:@"LC_RPATH: %@", path];
                    }
                }
                break;
            }
            case LC_UUID: {
                if (cmdsize >= sizeof(struct uuid_command)) {
                    const struct uuid_command *uc = (const struct uuid_command *)lc;
                    NSString *uuidStr = [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                        uc->uuid[0], uc->uuid[1], uc->uuid[2], uc->uuid[3],
                        uc->uuid[4], uc->uuid[5], uc->uuid[6], uc->uuid[7],
                        uc->uuid[8], uc->uuid[9], uc->uuid[10], uc->uuid[11],
                        uc->uuid[12], uc->uuid[13], uc->uuid[14], uc->uuid[15]];
                    result.uuid = uuidStr;
                    slice.uuid = uuidStr;
                    lcObj.cmdDescription = [NSString stringWithFormat:@"LC_UUID: %@", uuidStr];
                }
                break;
            }
            case LC_ENCRYPTION_INFO:
            case LC_ENCRYPTION_INFO_64: {
                if (cmdsize >= 20) {
                    const uint8_t *cryptidBytes = (const uint8_t *)lc + 16;
                    uint32_t cryptid = 0;
                    memcpy(&cryptid, cryptidBytes, sizeof(cryptid));
                    if (isSwap) cryptid = swap32(cryptid);
                    slice.encryptionID = cryptid;
                    slice.encrypted = (cryptid != 0);
                    if (slice.encrypted) {
                        result.hasEncryptedSlice = YES;
                        result.encryptedSliceCount += 1;
                        if (cputype == CPU_TYPE_ARM64) {
                            result.hasEncryptedArm64Slice = YES;
                            result.encryptedArm64SliceCount += 1;
                        }
                    }
                    lcObj.cmdDescription = [NSString stringWithFormat:@"%@ cryptid=%u", baseCmd == LC_ENCRYPTION_INFO_64 ? @"LC_ENCRYPTION_INFO_64" : @"LC_ENCRYPTION_INFO", cryptid];
                }
                break;
            }
            case LC_CODE_SIGNATURE: {
                if (cmdsize >= sizeof(struct load_command) + 8) {
                    const uint8_t *sigData = (const uint8_t *)lc + sizeof(struct load_command);
                    uint32_t dataoff = isSwap ? swap32(*(uint32_t *)sigData) : *(uint32_t *)sigData;
                    uint32_t datasize = isSwap ? swap32(*(uint32_t *)(sigData + 4)) : *(uint32_t *)(sigData + 4);
                    result.hasCodeSignature = YES;
                    result.codeSignatureOffset = dataoff;
                    result.codeSignatureSize = datasize;
                    lcObj.cmdDescription = [NSString stringWithFormat:@"LC_CODE_SIGNATURE: offset=%u size=%u", dataoff, datasize];
                }
                break;
            }
            case LC_BUILD_VERSION: {
                if (cmdsize >= sizeof(struct build_version_command)) {
                    const struct build_version_command *bvc = (const struct build_version_command *)lc;
                    uint32_t platform = isSwap ? swap32(bvc->platform) : bvc->platform;
                    uint32_t minos = isSwap ? swap32(bvc->minos) : bvc->minos;
                    uint32_t sdk = isSwap ? swap32(bvc->sdk) : bvc->sdk;
                    result.platform = platform;
                    result.platformName = [self platformName:platform];
                    result.minOSVersion = [self versionStringFromUint32:minos];
                    result.sdkVersion = [self versionStringFromUint32:sdk];
                    lcObj.cmdDescription = [NSString stringWithFormat:@"LC_BUILD_VERSION: platform=%u minos=%@ sdk=%@",
                        platform, result.minOSVersion, result.sdkVersion];
                }
                break;
            }
            default:
                lcObj.cmdDescription = [NSString stringWithFormat:@"LC(0x%x) size=%u", cmd, cmdsize];
                break;
        }

        [lcs addObject:lcObj];
        lcOffset += cmdsize;
    }

    result.dependencies = deps;
    result.rpaths = rpaths;
    result.loadCommands = lcs;

    if (slice.encrypted) {
        result.parseStatus = MachOParseSuccess;
        result.parseError = nil;
    } else if (!result.parseError) {
        result.parseStatus = MachOParseSuccess;
    } else if (result.parseStatus == MachOParseNotAttempted) {
        result.parseStatus = MachOParseSuccess;
    }
}

- (void)parseFatBinary:(const void *)data
                length:(size_t)length
                result:(MachOAnalysisResult *)result
                isSwap:(BOOL)isSwap {
    if (length < sizeof(struct fat_header)) {
        result.parseStatus = MachOParseFailed;
        result.parseError = @"Data too short for fat_header";
        return;
    }

    const struct fat_header *fh = (const struct fat_header *)data;
    uint32_t nfat_arch = isSwap ? swap32(fh->nfat_arch) : fh->nfat_arch;

    uint64_t archOffset = sizeof(struct fat_header);
    BOOL isFat64 = (result.magic == FAT_MAGIC_64 || result.magic == FAT_CIGAM_64);
    size_t archStructSize = isFat64 ? sizeof(struct fat_arch_64) : sizeof(struct fat_arch);

    NSMutableArray *slices = [NSMutableArray array];
    NSMutableArray *allDeps = [NSMutableArray array];
    NSMutableArray *allRpaths = [NSMutableArray array];
    NSMutableArray *allLcs = [NSMutableArray array];

    BOOL anySuccess = NO;
    NSString *firstError = nil;

    for (uint32_t i = 0; i < nfat_arch; i++) {
        if (archOffset + archStructSize > length) {
            if (!firstError) firstError = @"FAT arch entry exceeds file length";
            break;
        }

        uint32_t cputype, cpusubtype;
        uint64_t offset, size;

        if (isFat64) {
            const struct fat_arch_64 *fa = (const struct fat_arch_64 *)((const uint8_t *)data + archOffset);
            cputype = isSwap ? swap32(fa->cputype) : fa->cputype;
            cpusubtype = isSwap ? swap32(fa->cpusubtype) : fa->cpusubtype;
            offset = isSwap ? swap64(fa->offset) : fa->offset;
            size = isSwap ? swap64(fa->size) : fa->size;
        } else {
            const struct fat_arch *fa = (const struct fat_arch *)((const uint8_t *)data + archOffset);
            cputype = isSwap ? swap32(fa->cputype) : fa->cputype;
            cpusubtype = isSwap ? swap32(fa->cpusubtype) : fa->cpusubtype;
            offset = isSwap ? swap32(fa->offset) : fa->offset;
            size = isSwap ? swap32(fa->size) : fa->size;
        }

        archOffset += archStructSize;

        if (offset + size > length) {
            if (!firstError) firstError = [NSString stringWithFormat:@"FAT slice %u exceeds file bounds", i];
            continue;
        }

        const uint8_t *sliceData = (const uint8_t *)data + offset;
        uint32_t sliceMagic = *(uint32_t *)sliceData;
        BOOL sliceIsSwap = (sliceMagic == MH_CIGAM || sliceMagic == MH_CIGAM_64);

        MachOAnalysisResult *sliceResult = [[MachOAnalysisResult alloc] init];
        sliceResult.filePath = result.filePath;
        [self parseMachOHeader:data length:length offset:offset result:sliceResult isSwap:sliceIsSwap];

        if (sliceResult.parseStatus == MachOParseSuccess || sliceResult.parseStatus == MachOParsePartial) {
            anySuccess = YES;

            MachOSlice *slice = [[MachOSlice alloc] init];
            slice.cputype = cputype;
            slice.cpusubtype = cpusubtype;
            slice.offset = offset;
            slice.size = size;
            slice.uuid = sliceResult.uuid;
            slice.architectureName = [self architectureNameForCputype:cputype subtype:cpusubtype];
            MachOSlice *parsedSlice = sliceResult.slices.firstObject;
            slice.encrypted = parsedSlice.encrypted;
            slice.encryptionID = parsedSlice.encryptionID;
            [slices addObject:slice];

            [allDeps addObjectsFromArray:sliceResult.dependencies];
            [allRpaths addObjectsFromArray:sliceResult.rpaths];
            [allLcs addObjectsFromArray:sliceResult.loadCommands];
            if (sliceResult.hasEncryptedSlice) result.hasEncryptedSlice = YES;
            result.encryptedSliceCount += sliceResult.encryptedSliceCount;
            if (sliceResult.hasEncryptedArm64Slice) result.hasEncryptedArm64Slice = YES;
            result.encryptedArm64SliceCount += sliceResult.encryptedArm64SliceCount;

            if (!result.machOTypeName) {
                result.machOType = sliceResult.machOType;
                result.machOTypeName = sliceResult.machOTypeName;
                result.platform = sliceResult.platform;
                result.platformName = sliceResult.platformName;
                result.minOSVersion = sliceResult.minOSVersion;
                result.sdkVersion = sliceResult.sdkVersion;
                result.hasCodeSignature = sliceResult.hasCodeSignature;
                result.codeSignatureOffset = sliceResult.codeSignatureOffset;
                result.codeSignatureSize = sliceResult.codeSignatureSize;
            }
        } else {
            if (!firstError) firstError = sliceResult.parseError;
        }
    }

    result.slices = slices;
    result.dependencies = allDeps;
    result.rpaths = allRpaths;
    result.loadCommands = allLcs;

    if (anySuccess) {
        result.parseStatus = firstError ? MachOParsePartial : MachOParseSuccess;
        if (firstError) result.parseError = firstError;
    } else if (slices.count > 0) {
        result.parseStatus = MachOParseSuccess;
        result.parseError = nil;
    } else {
        result.parseStatus = MachOParseFailed;
        result.parseError = firstError ?: @"Failed to parse any FAT slice";
    }
}

@end
