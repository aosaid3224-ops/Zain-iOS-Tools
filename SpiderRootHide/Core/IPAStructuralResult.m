#import "IPAStructuralResult.h"

@implementation IPAStructuralBundle
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.path) d[@"path"] = self.path;
    if (self.bundleType) d[@"bundleType"] = self.bundleType;
    if (self.bundleIdentifier) d[@"bundleIdentifier"] = self.bundleIdentifier;
    if (self.executableName) d[@"executableName"] = self.executableName;
    if (self.executablePath) d[@"executablePath"] = self.executablePath;
    d[@"executableExists"] = @(self.executableExists);
    if (self.parentBundlePath) d[@"parentBundlePath"] = self.parentBundlePath;
    d[@"nestingLevel"] = @(self.nestingLevel);
    return d;
}
@end

@implementation IPAStructuralExecutableSlice
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"cputype"] = @(self.cputype);
    d[@"cpusubtype"] = @(self.cpusubtype);
    d[@"offset"] = @(self.offset);
    d[@"size"] = @(self.size);
    if (self.uuid) d[@"uuid"] = self.uuid;
    if (self.architectureName) d[@"architectureName"] = self.architectureName;
    return d;
}
@end

@implementation IPAStructuralDependency
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.rawInstallName) d[@"rawInstallName"] = self.rawInstallName;
    d[@"isWeak"] = @(self.isWeak);
    if (self.sourceExecutablePath) d[@"sourceExecutablePath"] = self.sourceExecutablePath;
    return d;
}
@end

@implementation IPAStructuralRPath
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.rawPath) d[@"rawPath"] = self.rawPath;
    if (self.sourceExecutablePath) d[@"sourceExecutablePath"] = self.sourceExecutablePath;
    return d;
}
@end

@implementation IPAStructuralLoadCommand
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"cmd"] = @(self.cmd);
    d[@"cmdsize"] = @(self.cmdsize);
    if (self.cmdDescription) d[@"description"] = self.cmdDescription;
    return d;
}
@end

@implementation IPAStructuralExecutable
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.path) d[@"path"] = self.path;
    if (self.name) d[@"name"] = self.name;
    d[@"fileSize"] = @(self.fileSize);
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
    d[@"parseStatus"] = @(self.parseStatus);
    if (self.parseError) d[@"parseError"] = self.parseError;

    NSMutableArray *slicesArr = [NSMutableArray array];
    for (IPAStructuralExecutableSlice *s in self.slices) { [slicesArr addObject:[s dictionaryRepresentation]]; }
    d[@"slices"] = slicesArr;

    NSMutableArray *depsArr = [NSMutableArray array];
    for (IPAStructuralDependency *dep in self.dependencies) { [depsArr addObject:[dep dictionaryRepresentation]]; }
    d[@"dependencies"] = depsArr;

    NSMutableArray *rpathsArr = [NSMutableArray array];
    for (IPAStructuralRPath *rp in self.rpaths) { [rpathsArr addObject:[rp dictionaryRepresentation]]; }
    d[@"rpaths"] = rpathsArr;

    NSMutableArray *lcArr = [NSMutableArray array];
    for (IPAStructuralLoadCommand *lc in self.loadCommands) { [lcArr addObject:[lc dictionaryRepresentation]]; }
    d[@"loadCommands"] = lcArr;

    return d;
}
@end

@implementation IPAStructuralResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _errors = [NSMutableArray array];
        _warnings = [NSMutableArray array];
        _bundles = @[];
        _executables = @[];
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.ipaPath) d[@"ipaPath"] = self.ipaPath;
    if (self.extractPath) d[@"extractPath"] = self.extractPath;
    d[@"ipaSize"] = @(self.ipaSize);
    d[@"success"] = @(self.success);
    d[@"analysisDurationMs"] = @(self.analysisDurationMs);
    if (self.analysisStartTime) d[@"analysisStartTime"] = [self isoStringFromDate:self.analysisStartTime];
    if (self.analysisEndTime) d[@"analysisEndTime"] = [self isoStringFromDate:self.analysisEndTime];

    d[@"bundleCount"] = @(self.bundleCount);
    d[@"executableCount"] = @(self.executableCount);
    d[@"frameworkCount"] = @(self.frameworkCount);
    d[@"dylibCount"] = @(self.dylibCount);
    d[@"appexCount"] = @(self.appexCount);
    d[@"xpcCount"] = @(self.xpcCount);
    d[@"dependencyCount"] = @(self.dependencyCount);
    d[@"rpathCount"] = @(self.rpathCount);
    d[@"sliceCount"] = @(self.sliceCount);

    NSMutableArray *bundlesArr = [NSMutableArray array];
    for (IPAStructuralBundle *b in self.bundles) { [bundlesArr addObject:[b dictionaryRepresentation]]; }
    d[@"bundles"] = bundlesArr;

    NSMutableArray *execsArr = [NSMutableArray array];
    for (IPAStructuralExecutable *e in self.executables) { [execsArr addObject:[e dictionaryRepresentation]]; }
    d[@"executables"] = execsArr;

    d[@"errors"] = [self.errors copy];
    d[@"warnings"] = [self.warnings copy];

    return d;
}

- (NSString *)jsonRepresentation {
    NSDictionary *dict = [self dictionaryRepresentation];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];
    if (data) {
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return [NSString stringWithFormat:@"{\"error\":\"%@\"}", error.localizedDescription ?: @"unknown"];
}

- (NSString *)summaryReport {
    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"=== IPA Structural Analysis ===\n"];
    [report appendFormat:@"IPA Path: %@\n", self.ipaPath];
    [report appendFormat:@"IPA Size: %llu bytes\n", self.ipaSize];
    [report appendFormat:@"Duration: %.2f ms\n", self.analysisDurationMs];
    [report appendFormat:@"Success: %@\n", self.success ? @"YES" : @"NO"];
    [report appendFormat:@"\n--- Counters ---\n"];
    [report appendFormat:@"Bundles: %ld\n", (long)self.bundleCount];
    [report appendFormat:@"Executables: %ld\n", (long)self.executableCount];
    [report appendFormat:@"Frameworks: %ld\n", (long)self.frameworkCount];
    [report appendFormat:@"Dylibs: %ld\n", (long)self.dylibCount];
    [report appendFormat:@"App Extensions: %ld\n", (long)self.appexCount];
    [report appendFormat:@"XPC Services: %ld\n", (long)self.xpcCount];
    [report appendFormat:@"Dependencies: %ld\n", (long)self.dependencyCount];
    [report appendFormat:@"RPATHs: %ld\n", (long)self.rpathCount];
    [report appendFormat:@"Slices: %ld\n", (long)self.sliceCount];

    [report appendFormat:@"\n--- Bundles ---\n"];
    for (IPAStructuralBundle *b in self.bundles) {
        [report appendFormat:@"[%@] %@ | ID=%@ | Exe=%@ | Exists=%@ | Level=%ld\n",
            b.bundleType, b.path, b.bundleIdentifier ?: @"N/A",
            b.executableName ?: @"N/A", b.executableExists ? @"YES" : @"NO", (long)b.nestingLevel];
    }

    [report appendFormat:@"\n--- Executables ---\n"];
    for (IPAStructuralExecutable *e in self.executables) {
        [report appendFormat:@"%@ | Type=%@ | Size=%llu | Slices=%lu | Deps=%lu | RPaths=%lu | Sig=%@\n",
            e.path, e.machOTypeName ?: @"N/A", e.fileSize,
            (unsigned long)e.slices.count, (unsigned long)e.dependencies.count,
            (unsigned long)e.rpaths.count, e.hasCodeSignature ? @"YES" : @"NO"];
        if (e.hasEncryptedSlice) {
            [report appendFormat:@"  Encryption: FAIRPLAY/cryptid-present slices=%u, arm64=%u — signing cannot decrypt this binary\n", e.encryptedSliceCount, e.encryptedArm64SliceCount];
        }
        for (IPAStructuralExecutableSlice *s in e.slices) {
            [report appendFormat:@"  Slice: %@ | UUID=%@ | Offset=%llu | Size=%llu\n",
                s.architectureName ?: @"?", s.uuid ?: @"N/A", s.offset, s.size];
        }
    }

    if (self.warnings.count > 0) {
        [report appendFormat:@"\n--- Warnings (%lu) ---\n", (unsigned long)self.warnings.count];
        for (NSString *w in self.warnings) { [report appendFormat:@"⚠️ %@\n", w]; }
    }

    if (self.errors.count > 0) {
        [report appendFormat:@"\n--- Errors (%lu) ---\n", (unsigned long)self.errors.count];
        for (NSString *e in self.errors) { [report appendFormat:@"❌ %@\n", e]; }
    }

    return report;
}

- (void)addMachOBinary:(NSString *)path {
    if (path.length == 0) return;
    IPAStructuralExecutable *executable = [[IPAStructuralExecutable alloc] init];
    executable.path = path;
    executable.name = [path lastPathComponent];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    executable.fileSize = [attrs[NSFileSize] unsignedLongLongValue];
    NSMutableArray *items = [self.executables mutableCopy] ?: [NSMutableArray array];
    [items addObject:executable];
    self.executables = [items copy];
    self.executableCount = self.executables.count;
}

- (void)addFramework:(NSString *)frameworkPath withBinary:(NSString *)binaryPath {
    IPAStructuralBundle *bundle = [[IPAStructuralBundle alloc] init];
    bundle.path = frameworkPath;
    bundle.bundleType = @".framework";
    bundle.executablePath = binaryPath;
    bundle.executableName = [binaryPath lastPathComponent];
    bundle.executableExists = [[NSFileManager defaultManager] fileExistsAtPath:binaryPath];
    NSMutableArray *items = [self.bundles mutableCopy] ?: [NSMutableArray array];
    [items addObject:bundle];
    self.bundles = [items copy];
    self.frameworkCount += 1;
    self.bundleCount = self.bundles.count;
}

- (void)addPlugIn:(NSString *)pluginPath withBinary:(NSString *)binaryPath {
    IPAStructuralBundle *bundle = [[IPAStructuralBundle alloc] init];
    bundle.path = pluginPath;
    bundle.bundleType = @".appex";
    bundle.executablePath = binaryPath;
    bundle.executableName = [binaryPath lastPathComponent];
    bundle.executableExists = [[NSFileManager defaultManager] fileExistsAtPath:binaryPath];
    NSMutableArray *items = [self.bundles mutableCopy] ?: [NSMutableArray array];
    [items addObject:bundle];
    self.bundles = [items copy];
    self.appexCount += 1;
    self.bundleCount = self.bundles.count;
}

- (NSString *)isoStringFromDate:(NSDate *)date {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    return [formatter stringFromDate:date];
}

@end
