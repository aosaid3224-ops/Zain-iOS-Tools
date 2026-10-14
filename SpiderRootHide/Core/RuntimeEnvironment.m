#import "RuntimeEnvironment.h"
#import "Logger.h"
#import "../rootless.h"
#include <stdlib.h>
#include <errno.h>

#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <unistd.h>

@interface RuntimeEnvironment ()
@property (nonatomic, copy, readwrite) NSString *bootstrapPath;
@property (nonatomic, assign, readwrite) BOOL isRootless;
@property (nonatomic, assign, readwrite) BOOL isRootHide;
@property (nonatomic, assign, readwrite) SpiderJailbreakType jailbreakType;
@property (nonatomic, copy, readwrite) NSString *jailbreakTypeName;
@property (nonatomic, copy, readwrite) NSString *iosVersion;
@property (nonatomic, copy, readwrite) NSString *architecture;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *binSearchPaths;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *librarySearchPaths;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *environmentVariables;
@property (nonatomic, assign, readwrite) BOOL isCharacterized;
@end

@implementation RuntimeEnvironment

+ (instancetype)sharedEnvironment {
    static RuntimeEnvironment *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self characterizeEnvironment];
    }
    return self;
}

- (void)characterizeEnvironment {
    NSDate *start = [NSDate date];

    _iosVersion = [self detectIOSVersion];
    _architecture = [self detectArchitecture];

    _bootstrapPath = [self detectBootstrapPath];
    _isRootless = (_bootstrapPath != nil);
    _isRootHide = SPIsRootHide();

    _jailbreakType = [self detectJailbreakType];
    _jailbreakTypeName = [self nameForJailbreakType:_jailbreakType];
    if (_isRootHide) {
        _jailbreakTypeName = (_jailbreakType == SpiderJailbreakTypeDopamine) ? @"Dopamine RootHide" : @"RootHide";
    }

    _binSearchPaths = [self buildBinSearchPaths];
    _librarySearchPaths = [self buildLibrarySearchPaths];

    _environmentVariables = [self buildEnvironmentVariables];

    _isCharacterized = YES;

    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];
    [[Logger sharedLogger] info:[NSString stringWithFormat:@"RuntimeEnvironment: characterized in %.3fs | rootless=%@ | roothide=%@ | bootstrap=%@ | type=%@ | iOS=%@ | arch=%@",
                                 duration,
                                 _isRootless ? @"YES" : @"NO",
                                 _isRootHide ? @"YES" : @"NO",
                                 _bootstrapPath ?: @"none",
                                 _jailbreakTypeName,
                                 _iosVersion,
                                 _architecture]];
}

- (NSString *)detectRootHideJBRoot {
    return SPIsRootHide() ? SPJBRootPath() : nil;
}

- (NSString *)detectBootstrapPath {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *rootHidePath = [self detectRootHideJBRoot];
    if (rootHidePath.length > 0) return rootHidePath;

    const char *procursusRoot = getenv("PROCURSUS_ROOT");
    if (procursusRoot) {
        NSString *path = [NSString stringWithUTF8String:procursusRoot];
        if ([fm fileExistsAtPath:path]) return path;
    }

    const char *rootPath = getenv("ROOT_PATH");
    if (rootPath) {
        NSString *path = [NSString stringWithUTF8String:rootPath];
        if ([fm fileExistsAtPath:path]) return path;
    }

    NSArray<NSString *> *palera1nSignatures = @[
        @"/var/LIY/.installed_palera1n",
        @"/var/LIY/usr/share/palera1n",
    ];
    for (NSString *sig in palera1nSignatures) {
        if ([fm fileExistsAtPath:sig]) {
            return @"/var/LIY";
        }
    }

    NSArray<NSString *> *signaturePaths = @[
        @"/var/jb/.installed_dopamine",
        @"/var/jb/.procursus_strapped",
        @"/var/jb/.bootstrapped",
    ];
    for (NSString *sig in signaturePaths) {
        if ([fm fileExistsAtPath:sig]) {
            NSString *parent = [sig stringByDeletingLastPathComponent];
            if ([parent isEqualToString:@"/var/jb"]) {
                return parent;
            }
        }
    }

    NSString *liDpkg = @"/var/LIY/usr/bin/dpkg";
    NSString *jbDpkg = @"/var/jb/usr/bin/dpkg";
    NSString *optDpkg = @"/opt/procursus/bin/dpkg";
    NSString *usrDpkg = @"/usr/bin/dpkg";

    if (access(liDpkg.fileSystemRepresentation, X_OK) == 0) {
        return @"/var/LIY";
    }
    if (access(jbDpkg.fileSystemRepresentation, X_OK) == 0) {
        return @"/var/jb";
    }
    if (access(optDpkg.fileSystemRepresentation, X_OK) == 0) {
        return @"/opt/procursus";
    }

    if ([fm fileExistsAtPath:@"/var/LIY"]) {
        if ([fm fileExistsAtPath:@"/var/LIY/usr/bin"] || [fm fileExistsAtPath:@"/var/LIY/bin"]) {
            return @"/var/LIY";
        }
    }
    if ([fm fileExistsAtPath:@"/var/jb"]) {
        if ([fm fileExistsAtPath:@"/var/jb/usr/bin"] || [fm fileExistsAtPath:@"/var/jb/bin"]) {
            return @"/var/jb";
        }
    }
    if ([fm fileExistsAtPath:@"/opt/procursus"]) {
        return @"/opt/procursus";
    }

    if (access(usrDpkg.fileSystemRepresentation, X_OK) == 0) {
        return nil;
    }

    return nil;
}

- (SpiderJailbreakType)detectJailbreakType {
    NSFileManager *fm = [NSFileManager defaultManager];

    if (SPIsRootHide()) {
        if ([fm fileExistsAtPath:SPJBPath(@"/.installed_dopamine")] ||
            [fm fileExistsAtPath:SPJBPath(@"/basebin")] ||
            [fm fileExistsAtPath:SPJBPath(@"/usr/share/dopamine")]) {
            return SpiderJailbreakTypeDopamine;
        }
        return SpiderJailbreakTypeRelaxin;
    }

    if ([fm fileExistsAtPath:@"/var/jb/.installed_dopamine"] ||
        [fm fileExistsAtPath:@"/var/jb/usr/share/dopamine"] ||
        [fm fileExistsAtPath:@"/usr/share/dopamine"]) {
        return SpiderJailbreakTypeDopamine;
    }

    if ([fm fileExistsAtPath:@"/var/LIY/.installed_palera1n"] ||
        [fm fileExistsAtPath:@"/var/LIY/usr/share/palera1n"]) {
        return SpiderJailbreakTypePalera1n;
    }

    if ([fm fileExistsAtPath:@"/usr/lib/libhooker.dylib"] ||
        [fm fileExistsAtPath:@"/usr/lib/libsubstitute.dylib"] ||
        [fm fileExistsAtPath:@"/var/checkra1n"]) {
        return SpiderJailbreakTypeCheckra1n;
    }

    if ([fm fileExistsAtPath:@"/usr/share/unc0ver"] ||
        [fm fileExistsAtPath:@"/var/unc0ver"]) {
        return SpiderJailbreakTypeUnc0ver;
    }

    if ([fm fileExistsAtPath:@"/usr/share/libhooker"] ||
        [fm fileExistsAtPath:@"/var/libexec/libhooker"]) {
        if ([fm fileExistsAtPath:@"/usr/share/taurine"]) {
            return SpiderJailbreakTypeTaurine;
        }
        if ([fm fileExistsAtPath:@"/usr/share/odyssey"]) {
            return SpiderJailbreakTypeOdyssey;
        }
        return SpiderJailbreakTypeTaurine;
    }

    if ([fm fileExistsAtPath:@"/var/xina"] ||
        [fm fileExistsAtPath:@"/usr/share/xina"]) {
        return SpiderJailbreakTypeXinaA15;
    }

    if ([self.bootstrapPath containsString:@".jbroot-"]) {
        return SpiderJailbreakTypeRelaxin;
    }

    if (self.isRootless) {
        return SpiderJailbreakTypeOther;
    }

    if (access("/usr/bin/dpkg", X_OK) == 0) {
        return SpiderJailbreakTypeOther;
    }

    return SpiderJailbreakTypeUnknown;
}

- (NSString *)nameForJailbreakType:(SpiderJailbreakType)type {
    switch (type) {
        case SpiderJailbreakTypeCheckra1n: return @"Checkra1n";
        case SpiderJailbreakTypeUnc0ver: return @"Unc0ver";
        case SpiderJailbreakTypeDopamine: return @"Dopamine";
        case SpiderJailbreakTypePalera1n: return @"Palera1n";
        case SpiderJailbreakTypeTaurine: return @"Taurine";
        case SpiderJailbreakTypeOdyssey: return @"Odyssey";
        case SpiderJailbreakTypeXinaA15: return @"XinaA15";
        case SpiderJailbreakTypeRelaxin: return @"RootHide";
        case SpiderJailbreakTypeOther: return @"Other";
        case SpiderJailbreakTypeUnknown: return @"Unknown";
    }
}

- (NSString *)detectIOSVersion {
    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    return [NSString stringWithFormat:@"%ld.%ld.%ld", (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion];
}

- (NSString *)detectArchitecture {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *machine = [NSString stringWithUTF8String:systemInfo.machine];

    if ([machine hasPrefix:@"iPhone"] || [machine hasPrefix:@"iPad"] || [machine hasPrefix:@"iPod"]) {
        size_t size;
        cpu_type_t cpuType;
        size = sizeof(cpuType);
        if (sysctlbyname("hw.cputype", &cpuType, &size, NULL, 0) == 0) {
            if (cpuType == CPU_TYPE_ARM64) {
                cpu_subtype_t cpuSubtype;
                size = sizeof(cpuSubtype);
                if (sysctlbyname("hw.cpusubtype", &cpuSubtype, &size, NULL, 0) == 0) {
                    if (cpuSubtype == CPU_SUBTYPE_ARM64E) {
                        return @"arm64e";
                    }
                }
                return @"arm64";
            }
        }
    }

    return machine;
}

- (NSArray<NSString *> *)buildBinSearchPaths {
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];

    if (self.isRootHide) {
        for (NSString *dir in @[@"/usr/local/bin", @"/usr/bin", @"/bin", @"/usr/sbin", @"/sbin"]) {
            [paths addObject:SPJBPath(dir)];
        }
    }

    const char *pathEnv = getenv("PATH");
    if (pathEnv) {
        NSString *pathStr = [NSString stringWithUTF8String:pathEnv];
        for (NSString *p in [pathStr componentsSeparatedByString:@":"]) {
            if (p.length > 0) [paths addObject:p];
        }
    }

    if (self.bootstrapPath) {
        [paths addObject:[self.bootstrapPath stringByAppendingPathComponent:@"usr/bin"]];
        [paths addObject:[self.bootstrapPath stringByAppendingPathComponent:@"bin"]];
        [paths addObject:[self.bootstrapPath stringByAppendingPathComponent:@"usr/local/bin"]];
    }

    [paths addObject:@"/usr/bin"];
    [paths addObject:@"/bin"];
    [paths addObject:@"/usr/local/bin"];
    [paths addObject:@"/opt/procursus/bin"];

    if (!self.isRootHide) {
        [paths addObject:@"/var/jb/usr/bin"];
        [paths addObject:@"/var/jb/bin"];
        [paths addObject:@"/var/LIY/usr/bin"];
        [paths addObject:@"/var/LIY/bin"];
    }

    return paths.array;
}

- (NSArray<NSString *> *)buildLibrarySearchPaths {
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];

    const char *ldPath = getenv("DYLD_LIBRARY_PATH");
    if (ldPath) {
        NSString *pathStr = [NSString stringWithUTF8String:ldPath];
        for (NSString *p in [pathStr componentsSeparatedByString:@":"]) {
            if (p.length > 0) [paths addObject:p];
        }
    }

    if (self.bootstrapPath) {
        [paths addObject:[self.bootstrapPath stringByAppendingPathComponent:@"usr/lib"]];
        [paths addObject:[self.bootstrapPath stringByAppendingPathComponent:@"lib"]];
    }

    [paths addObject:@"/usr/lib"];
    [paths addObject:@"/usr/local/lib"];
    [paths addObject:@"/opt/procursus/lib"];
    [paths addObject:@"/var/jb/usr/lib"];
    [paths addObject:@"/var/LIY/usr/lib"];

    return paths.array;
}

- (NSDictionary<NSString *, NSString *> *)buildEnvironmentVariables {
    NSMutableDictionary<NSString *, NSString *> *env = [NSMutableDictionary dictionary];

    extern char **environ;
    for (char **ep = environ; *ep != NULL; ep++) {
        NSString *pair = [NSString stringWithUTF8String:*ep];
        NSRange eq = [pair rangeOfString:@"="];
        if (eq.location != NSNotFound) {
            NSString *key = [pair substringToIndex:eq.location];
            NSString *val = [pair substringFromIndex:eq.location + 1];
            env[key] = val;
        }
    }

    if (self.isRootHide) return env;

    NSMutableOrderedSet<NSString *> *pathSet = [NSMutableOrderedSet orderedSet];
    NSString *existingPath = env[@"PATH"];
    if (existingPath) {
        for (NSString *p in [existingPath componentsSeparatedByString:@":"]) {
            if (p.length > 0) [pathSet addObject:p];
        }
    }
    for (NSString *p in self.binSearchPaths) {
        [pathSet addObject:p];
    }
    env[@"PATH"] = [pathSet.array componentsJoinedByString:@":"];

    NSMutableOrderedSet<NSString *> *ldSet = [NSMutableOrderedSet orderedSet];
    NSString *existingLD = env[@"DYLD_LIBRARY_PATH"];
    if (existingLD) {
        for (NSString *p in [existingLD componentsSeparatedByString:@":"]) {
            if (p.length > 0) [ldSet addObject:p];
        }
    }
    for (NSString *p in self.librarySearchPaths) {
        [ldSet addObject:p];
    }
    if (ldSet.count > 0) {
        env[@"DYLD_LIBRARY_PATH"] = [ldSet.array componentsJoinedByString:@":"];
    }

    return env;
}

- (NSString *)resolvePath:(NSString *)logicalPath {
    return SPJBPath(logicalPath);
}

- (NSDictionary *)diagnosticSnapshot {
    return @{
        @"isRootless": @(self.isRootless),
        @"isRootHide": @(self.isRootHide),
        @"bootstrapPath": self.bootstrapPath ?: @"none",
        @"jailbreakType": self.jailbreakTypeName,
        @"iosVersion": self.iosVersion,
        @"architecture": self.architecture,
        @"binSearchPathsCount": @(self.binSearchPaths.count),
        @"librarySearchPathsCount": @(self.librarySearchPaths.count),
        @"isCharacterized": @(self.isCharacterized)
    };
}

@end
