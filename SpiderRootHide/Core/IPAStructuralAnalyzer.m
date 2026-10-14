#import "IPAStructuralAnalyzer.h"
#import "IPAStructuralResult.h"
#import "ProcessRunner.h"
#import "CommandResult.h"
#import "Logger.h"
#import "MachOAnalyzer.h"
#import "MachOAnalyzer.h"

#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>

extern char **environ;

@interface IPAStructuralAnalyzer ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *cachedAnalyses;
@property (nonatomic, strong) dispatch_queue_t analysisQueue;
@end

@implementation IPAStructuralAnalyzer

+ (instancetype)sharedAnalyzer {
    static IPAStructuralAnalyzer *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cachedAnalyses = [NSMutableDictionary dictionary];
        _analysisQueue = dispatch_queue_create("com.spider.structuralanalyzer", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (IPAStructuralResult *)analyzeIPAAtPath:(NSString *)path {
    __block IPAStructuralResult *cachedResult = nil;
    dispatch_sync(self.analysisQueue, ^{
        NSNumber *cached = self.cachedAnalyses[path];
        if (cached && cached.boolValue) {
            cachedResult = [self cachedResultForPath:path];
        }
    });

    if (cachedResult) return cachedResult;

    IPAStructuralResult *result = [[IPAStructuralResult alloc] init];
    result.ipaPath = path;

    [self extractAndAnalyzeIPA:path result:result];

    dispatch_async(self.analysisQueue, ^{
        self.cachedAnalyses[path] = @YES;
        [self cacheResult:result forPath:path];
    });

    return result;
}

- (IPAStructuralResult *)analyzeIPAAtPath:(NSString *)path keepExtracted:(BOOL)keep {
    IPAStructuralResult *result = [self analyzeIPAAtPath:path];
    (void)keep;
    return result;
}

- (IPAStructuralResult *)analyzeExtractedPayloadAtPath:(NSString *)payloadPath sourceIPAPath:(NSString *)ipaPath {
    IPAStructuralResult *result = [[IPAStructuralResult alloc] init];
    result.ipaPath = ipaPath;
    result.extractPath = [payloadPath stringByDeletingLastPathComponent];
    NSArray<NSString *> *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadPath error:nil];
    for (NSString *item in items) {
        if ([item hasSuffix:@".app"]) {
            [self analyzeAppBundle:[payloadPath stringByAppendingPathComponent:item] result:result];
            result.success = YES;
            break;
        }
    }
    if (!result.success) {
        result.errors = [NSMutableArray arrayWithObject:@"Payload لا يحتوي على App bundle صالح"];
    }
    return result;
}

- (NSArray<NSString *> *)listContentsOfIPA:(NSString *)path {
    CommandResult *result = [[ProcessRunner sharedRunner] runCommand:@"/usr/bin/unzip"
                                                           arguments:@[@"-Z1", path]
                                                             timeout:30.0];
    if (!result.success) {
        [[Logger sharedLogger] error:[NSString stringWithFormat:@"IPAStructuralAnalyzer: unzip -Z1 failed | category=%@ | exit=%d | stderr=%@",
                                      result.failureCategory, result.exitCode, result.stderrText]];
        return @[];
    }

    NSString *output = result.stdoutText;
    if (!output || output.length == 0) return @[];

    return [output componentsSeparatedByString:@"\n"];
}

- (NSDictionary *)extractInfoPlistFromIPA:(NSString *)path {
    CommandResult *result = [[ProcessRunner sharedRunner] runCommand:@"/usr/bin/unzip"
                                                           arguments:@[@"-p", path, @"Payload/*/Info.plist"]
                                                             timeout:30.0];
    if (!result.success) {
        [[Logger sharedLogger] error:[NSString stringWithFormat:@"IPAStructuralAnalyzer: unzip Info.plist failed | category=%@ | exit=%d",
                                      result.failureCategory, result.exitCode]];
        return nil;
    }

    NSString *plistContent = result.stdoutText;
    if (!plistContent || plistContent.length == 0) return nil;

    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [plistContent writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:tempPath];

    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

    return info;
}

- (NSArray<NSString *> *)findExecutablesInIPA:(NSString *)path {
    NSArray *contents = [self listContentsOfIPA:path];
    NSMutableArray<NSString *> *executables = [NSMutableArray array];

    for (NSString *item in contents) {
        if ([item hasSuffix:@""] && ![item containsString:@"Frameworks/"] && ![item containsString:@"PlugIns/"]) {
            [executables addObject:item];
        }
    }

    return executables;
}

- (NSArray<NSString *> *)findFrameworksInIPA:(NSString *)path {
    NSArray *contents = [self listContentsOfIPA:path];
    NSMutableArray<NSString *> *frameworks = [NSMutableArray array];

    for (NSString *item in contents) {
        if ([item containsString:@"Frameworks/"] && [item hasSuffix:@".framework/"]) {
            [frameworks addObject:item];
        }
    }

    return frameworks;
}

- (NSArray<NSString *> *)findPlugInsInIPA:(NSString *)path {
    NSArray *contents = [self listContentsOfIPA:path];
    NSMutableArray<NSString *> *plugins = [NSMutableArray array];

    for (NSString *item in contents) {
        if ([item containsString:@"PlugIns/"] && [item hasSuffix:@".appex/"]) {
            [plugins addObject:item];
        }
    }

    return plugins;
}

- (NSArray<NSString *> *)findDylibsInIPA:(NSString *)path {
    NSArray *contents = [self listContentsOfIPA:path];
    NSMutableArray<NSString *> *dylibs = [NSMutableArray array];

    for (NSString *item in contents) {
        if ([item hasSuffix:@".dylib"]) {
            [dylibs addObject:item];
        }
    }

    return dylibs;
}

- (BOOL)hasWatchExtension:(NSString *)path {
    NSArray *plugins = [self findPlugInsInIPA:path];
    for (NSString *plugin in plugins) {
        if ([plugin containsString:@"watchkit"]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)hasAppClips:(NSString *)path {
    NSDictionary *info = [self extractInfoPlistFromIPA:path];
    if (!info) return NO;

    return info[@"NSAppClip"] != nil;
}

- (void)extractAndAnalyzeIPA:(NSString *)path result:(IPAStructuralResult *)result {
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    CommandResult *extractResult = [[ProcessRunner sharedRunner] runCommand:@"/usr/bin/unzip"
                                                                   arguments:@[@"-q", path, @"-d", tempDir]
                                                                     timeout:60.0];
    if (!extractResult.success) {
        [[Logger sharedLogger] error:[NSString stringWithFormat:@"IPAStructuralAnalyzer: unzip extraction failed | category=%@ | exit=%d | stderr=%@",
                                      extractResult.failureCategory, extractResult.exitCode, extractResult.stderrText]];
        result.error = [NSString stringWithFormat:@"Extraction failed: %@", extractResult.failureCategory];
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        return;
    }

    NSString *payloadPath = [tempDir stringByAppendingPathComponent:@"Payload"];
    NSArray *payloadContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadPath error:nil];

    for (NSString *item in payloadContents) {
        if ([item hasSuffix:@".app"]) {
            NSString *appPath = [payloadPath stringByAppendingPathComponent:item];
            [self analyzeAppBundle:appPath result:result];
            break;
        }
    }

    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
}

- (void)analyzeAppBundle:(NSString *)appPath result:(IPAStructuralResult *)result {
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    NSString *bundleID = nil;
    NSString *execName = nil;

    if (info) {
        bundleID = info[@"CFBundleIdentifier"];
        result.bundleID = bundleID;
        result.bundleName = info[@"CFBundleName"];
        result.version = info[@"CFBundleShortVersionString"];
        execName = info[@"CFBundleExecutable"];
        result.executableName = execName;
    }

    IPAStructuralBundle *mainBundle = [[IPAStructuralBundle alloc] init];
    mainBundle.path = appPath;
    mainBundle.bundleType = @".app";
    mainBundle.bundleIdentifier = bundleID;
    mainBundle.executableName = execName;
    if (execName.length > 0) {
        mainBundle.executablePath = [appPath stringByAppendingPathComponent:execName];
        mainBundle.executableExists = [[NSFileManager defaultManager] fileExistsAtPath:mainBundle.executablePath];
    } else {
        mainBundle.executableExists = NO;
    }
    mainBundle.nestingLevel = 0;

    NSMutableArray *bundles = [result.bundles mutableCopy] ?: [NSMutableArray array];
    [bundles insertObject:mainBundle atIndex:0];
    result.bundles = [bundles copy];
    result.bundleCount = result.bundles.count;

    [self findMachOBinariesInDirectory:appPath result:result];

    NSString *frameworksPath = [appPath stringByAppendingPathComponent:@"Frameworks"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:frameworksPath]) {
        NSArray *frameworks = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:frameworksPath error:nil];
        for (NSString *framework in frameworks) {
            if ([framework hasSuffix:@".framework"]) {
                NSString *frameworkPath = [frameworksPath stringByAppendingPathComponent:framework];
                [self analyzeFramework:frameworkPath result:result];
            }
        }
    }

    NSString *pluginsPath = [appPath stringByAppendingPathComponent:@"PlugIns"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:pluginsPath]) {
        NSArray *plugins = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:pluginsPath error:nil];
        for (NSString *plugin in plugins) {
            if ([plugin hasSuffix:@".appex"]) {
                NSString *pluginPath = [pluginsPath stringByAppendingPathComponent:plugin];
                [self analyzePlugIn:pluginPath result:result];
            }
        }
    }
}

- (void)findMachOBinariesInDirectory:(NSString *)directory result:(IPAStructuralResult *)result {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:directory error:nil];

    for (NSString *item in contents) {
        NSString *itemPath = [directory stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        [fm fileExistsAtPath:itemPath isDirectory:&isDir];

        if (isDir && [item hasSuffix:@".framework"]) {
            NSString *frameworkName = [item stringByDeletingPathExtension];
            NSString *binaryPath = [itemPath stringByAppendingPathComponent:frameworkName];
            if ([fm fileExistsAtPath:binaryPath]) {
                [self addAnalyzedBinary:binaryPath result:result];
            }
        } else if (isDir && [item hasSuffix:@".appex"]) {
            NSString *infoPath = [itemPath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
            NSString *execName = info[@"CFBundleExecutable"];
            if (execName.length > 0) {
                NSString *binaryPath = [itemPath stringByAppendingPathComponent:execName];
                if ([fm fileExistsAtPath:binaryPath]) {
                    [self addAnalyzedBinary:binaryPath result:result];
                }
            }
        } else if (!isDir) {
            if ([self isMachOBinary:itemPath]) {
                [self addAnalyzedBinary:itemPath result:result];
            }
        }
    }
}

- (BOOL)isMachOBinary:(NSString *)path {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return NO;

    NSData *header = [handle readDataOfLength:4];
    [handle closeFile];

    if (header.length < 4) return NO;

    const uint32_t *magic = header.bytes;
    return (*magic == 0xfeedfacf || *magic == 0xfeedface ||
            *magic == 0xcafebabe || *magic == 0xcafebabf);
}

- (void)analyzeFramework:(NSString *)frameworkPath result:(IPAStructuralResult *)result {
    NSString *frameworkName = [frameworkPath lastPathComponent];
    NSString *binaryName = [frameworkName stringByDeletingPathExtension];
    NSString *binaryPath = [frameworkPath stringByAppendingPathComponent:binaryName];

    if ([[NSFileManager defaultManager] fileExistsAtPath:binaryPath]) {
        [result addFramework:frameworkPath withBinary:binaryPath];
    }
}

- (void)analyzePlugIn:(NSString *)pluginPath result:(IPAStructuralResult *)result {
    NSString *infoPath = [pluginPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    NSString *execName = info[@"CFBundleExecutable"];

    if (execName) {
        NSString *binaryPath = [pluginPath stringByAppendingPathComponent:execName];
        if ([[NSFileManager defaultManager] fileExistsAtPath:binaryPath]) {
            [result addPlugIn:pluginPath withBinary:binaryPath];
        }
    }
}

- (IPAStructuralResult *)cachedResultForPath:(NSString *)path {
    return nil;
}

- (void)cacheResult:(IPAStructuralResult *)result forPath:(NSString *)path {
}

- (void)addAnalyzedBinary:(NSString *)path result:(IPAStructuralResult *)result {
    [result addMachOBinary:path];

    MachOAnalysisResult *analysis = [[MachOAnalyzer sharedAnalyzer] analyzeFileAtPath:path];
    if (!analysis) return;

    NSMutableArray *executables = [result.executables mutableCopy] ?: [NSMutableArray array];
    for (NSUInteger i = 0; i < executables.count; i++) {
        IPAStructuralExecutable *executable = executables[i];
        if ([executable.path isEqualToString:path]) {
            executable.parseStatus = (analysis.parseStatus == MachOParseSuccess) ? IPAStructuralParseSuccess :
                                     (analysis.parseStatus == MachOParsePartial) ? IPAStructuralParsePartial :
                                     (analysis.parseStatus == MachOParseFailed) ? IPAStructuralParseFailed : IPAStructuralParseNotAttempted;
            executable.parseError = analysis.parseError;
            executable.machOType = analysis.machOType;
            executable.machOTypeName = analysis.machOTypeName;
            executable.uuid = analysis.uuid;
            executable.minOSVersion = analysis.minOSVersion;
            executable.sdkVersion = analysis.sdkVersion;
            executable.platform = analysis.platform;
            executable.platformName = analysis.platformName;
            executable.hasCodeSignature = analysis.hasCodeSignature;
            executable.hasEncryptedSlice = analysis.hasEncryptedSlice;
            executable.encryptedSliceCount = analysis.encryptedSliceCount;
            executable.hasEncryptedArm64Slice = analysis.hasEncryptedArm64Slice;
            executable.encryptedArm64SliceCount = analysis.encryptedArm64SliceCount;

            NSMutableArray *slices = [NSMutableArray array];
            for (MachOSlice *machSlice in analysis.slices) {
                IPAStructuralExecutableSlice *slice = [[IPAStructuralExecutableSlice alloc] init];
                slice.cputype = machSlice.cputype;
                slice.cpusubtype = machSlice.cpusubtype;
                slice.offset = machSlice.offset;
                slice.size = machSlice.size;
                slice.uuid = machSlice.uuid;
                slice.architectureName = machSlice.architectureName;
                [slices addObject:slice];
            }
            executable.slices = [slices copy];

            executable.machOValid = (analysis.parseStatus == MachOParseSuccess || analysis.parseStatus == MachOParsePartial || analysis.hasEncryptedSlice);

            BOOL hasArm64 = NO;
            for (MachOSlice *slice in analysis.slices) {
                if (slice.cputype == 0x0100000c) { hasArm64 = YES; break; }
            }
            executable.arm64Compatible = hasArm64;

            NSMutableArray *deps = [NSMutableArray array];
            for (MachODependency *machDep in analysis.dependencies) {
                IPAStructuralDependency *dep = [[IPAStructuralDependency alloc] init];
                dep.rawInstallName = machDep.rawInstallName;
                dep.isWeak = machDep.isWeak;
                dep.sourceExecutablePath = machDep.sourceExecutablePath;
                [deps addObject:dep];
            }
            executable.dependencies = [deps copy];

            NSMutableArray *rpaths = [NSMutableArray array];
            for (MachORPath *machRPath in analysis.rpaths) {
                IPAStructuralRPath *rp = [[IPAStructuralRPath alloc] init];
                rp.rawPath = machRPath.rawPath;
                rp.sourceExecutablePath = machRPath.sourceExecutablePath;
                [rpaths addObject:rp];
            }
            executable.rpaths = [rpaths copy];

            NSMutableArray *lcs = [NSMutableArray array];
            for (MachOLoadCommand *machLc in analysis.loadCommands) {
                IPAStructuralLoadCommand *lc = [[IPAStructuralLoadCommand alloc] init];
                lc.cmd = machLc.cmd;
                lc.cmdsize = machLc.cmdsize;
                lc.cmdDescription = machLc.cmdDescription;
                [lcs addObject:lc];
            }
            executable.loadCommands = [lcs copy];

            executables[i] = executable;
            break;
        }
    }
    result.executables = [executables copy];
    result.executableCount = result.executables.count;

    NSUInteger totalSlices = 0;
    for (IPAStructuralExecutable *e in result.executables) totalSlices += e.slices.count;
    result.sliceCount = totalSlices;
}

@end
