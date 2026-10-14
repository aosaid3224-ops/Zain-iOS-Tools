#import "IPAValidator.h"
#import "ProcessRunner.h"
#import "CommandResult.h"
#import "Logger.h"
#import "RootlessManager.h"

#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>

extern char **environ;

@interface IPAValidator ()
@property (nonatomic, strong) NSCache<NSString *, NSString *> *plistPathCache;
@end

@implementation IPAValidationResult
@end

@implementation IPAValidator

+ (instancetype)sharedValidator {
    static IPAValidator *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _plistPathCache = [[NSCache alloc] init];
        _plistPathCache.countLimit = 20;
    }
    return self;
}

- (IPAValidationResult *)validateIPAAtPath:(NSString *)ipaPath {
    IPAValidationResult *result = [[IPAValidationResult alloc] init];
    NSError *error = nil;
    BOOL valid = [self validateIPAAtPath:ipaPath error:&error];
    result.isReadyForInstall = valid;
    result.status = valid ? IPAValidationStatusValid : IPAValidationStatusUnknown;
    result.statusMessage = valid ? @"IPA جاهز للتثبيت" : (error.localizedDescription ?: @"فشل التحقق من IPA");
    result.issues = error ? @[error.localizedDescription ?: @"خطأ غير معروف"] : @[];
    result.missingLibraries = @[];
    return result;
}

- (IPAValidationResult *)validateExtractedAppAtPath:(NSString *)appPath {
    IPAValidationResult *result = [[IPAValidationResult alloc] init];
    NSMutableArray<NSString *> *issues = [NSMutableArray array];
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info) [issues addObject:@"Info.plist مفقود أو غير صالح"];
    NSString *executable = [info[@"CFBundleExecutable"] isKindOfClass:NSString.class] ? info[@"CFBundleExecutable"] : nil;
    if (executable.length == 0) [issues addObject:@"الملف التنفيذي غير محدد"];
    else if (![[NSFileManager defaultManager] fileExistsAtPath:[appPath stringByAppendingPathComponent:executable]]) [issues addObject:@"الملف التنفيذي مفقود"];
    result.isReadyForInstall = issues.count == 0;
    result.status = result.isReadyForInstall ? IPAValidationStatusValid : IPAValidationStatusMissingExecutable;
    result.statusMessage = result.isReadyForInstall ? @"التطبيق المستخرج جاهز" : [issues componentsJoinedByString:@"، "];
    result.issues = issues;
    result.missingLibraries = @[];
    return result;
}

- (NSArray<NSString *> *)checkDependenciesAtAppPath:(NSString *)appPath {
    return @[];
}

- (BOOL)validateIPAAtPath:(NSString *)path error:(NSError **)error {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (error) *error = [NSError errorWithDomain:@"IPAValidator" code:1 userInfo:@{NSLocalizedDescriptionKey: @"IPA file not found"}];
        return NO;
    }
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    unsigned long long fileSize = [attrs[NSFileSize] unsignedLongLongValue];
    if (fileSize == 0) {
        if (error) *error = [NSError errorWithDomain:@"IPAValidator" code:2 userInfo:@{NSLocalizedDescriptionKey: @"IPA file is empty"}];
        return NO;
    }
    if (![self isValidZipFile:path]) {
        if (error) *error = [NSError errorWithDomain:@"IPAValidator" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Invalid IPA file format"}];
        return NO;
    }

    NSString *infoPlistPath = [self extractInfoPlistFromIPA:path];
    if (!infoPlistPath || infoPlistPath.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"IPAValidator" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Could not extract Info.plist"}];
        return NO;
    }

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
    if (!info) {
        if (error) *error = [NSError errorWithDomain:@"IPAValidator" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Invalid Info.plist content (binary plist may be corrupted)"}];
        return NO;
    }

    if (!info[@"CFBundleIdentifier"]) {
        if (error) *error = [NSError errorWithDomain:@"IPAValidator" code:6 userInfo:@{NSLocalizedDescriptionKey: @"Missing CFBundleIdentifier"}];
        return NO;
    }

    NSString *execName = info[@"CFBundleExecutable"];
    if (!execName || ![execName isKindOfClass:[NSString class]] || execName.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"IPAValidator" code:7 userInfo:@{NSLocalizedDescriptionKey: @"Missing CFBundleExecutable"}];
        return NO;
    }

    NSString *execPath = [self executablePathForIPA:path usingInfoPlistPath:infoPlistPath];
    if (execPath) {
        if (![self validateExecutableArchitecture:execPath]) {
            if (error) *error = [NSError errorWithDomain:@"IPAValidator" code:8 userInfo:@{NSLocalizedDescriptionKey: @"Invalid executable architecture"}];
            return NO;
        }
    }

    return YES;
}

- (NSDictionary *)detailedValidationForIPA:(NSString *)path {
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    results[@"exists"] = @([[NSFileManager defaultManager] fileExistsAtPath:path]);
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    results[@"size"] = attrs[NSFileSize] ?: @0;
    results[@"validZip"] = @([self isValidZipFile:path]);

    NSString *infoPlistPath = [self extractInfoPlistFromIPA:path];
    results[@"hasInfoPlist"] = @(infoPlistPath != nil && infoPlistPath.length > 0);

    if (infoPlistPath) {
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
        results[@"bundleID"] = info[@"CFBundleIdentifier"] ?: @"";
        results[@"bundleName"] = info[@"CFBundleName"] ?: @"";
        results[@"version"] = info[@"CFBundleShortVersionString"] ?: @"";
        results[@"executable"] = info[@"CFBundleExecutable"] ?: @"";
        results[@"minimumOS"] = info[@"MinimumOSVersion"] ?: @"";
    }

    NSString *execPath = [self executablePathForIPA:path usingInfoPlistPath:infoPlistPath];
    if (execPath) {
        results[@"signatureValid"] = @([self validateCodeSignature:execPath]);
        results[@"architectureValid"] = @([self validateExecutableArchitecture:execPath]);
    }

    return results;
}

- (BOOL)isValidZipFile:(NSString *)path {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return NO;
    NSData *header = [handle readDataOfLength:4];
    [handle closeFile];
    if (header.length < 4) return NO;
    const uint8_t *bytes = header.bytes;
    return (bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04);
}

- (NSString *)extractInfoPlistFromIPA:(NSString *)path {
    NSString *cached = [self.plistPathCache objectForKey:path];
    if (cached && [[NSFileManager defaultManager] fileExistsAtPath:cached]) return cached;

    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSError *dirErr = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:&dirErr]) {
        [[Logger sharedLogger] error:[NSString stringWithFormat:@"IPAValidator: failed to create temp dir: %@", dirErr.localizedDescription]];
        return nil;
    }

    NSString *cmd = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/unzip"];
    CommandResult *listResult = [[ProcessRunner sharedRunner] runCommand:cmd arguments:@[@"-l", path] timeout:30.0];
    NSString *exactInfoPlistEntry = nil;
    if (listResult.success) {
        NSString *listing = listResult.stdoutText;
        NSArray<NSString *> *lines = [listing componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSString *bestEntry = nil;
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
            if (!bestEntry || entry.length < bestEntry.length) {
                bestEntry = entry;
            }
        }
        if (bestEntry) exactInfoPlistEntry = bestEntry;
    }

    if (!exactInfoPlistEntry) {
        exactInfoPlistEntry = @"Payload/*/Info.plist";
        [[Logger sharedLogger] warning:@"IPAValidator: could not determine exact Info.plist path, falling back to wildcard"];
    }

    CommandResult *result = [[ProcessRunner sharedRunner] runCommand:cmd
                                                           arguments:@[@"-p", path, exactInfoPlistEntry]
                                                             timeout:60.0];

    if (!result.success || !result.stdoutData || result.stdoutData.length == 0) {
        NSString *fallbackTempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:fallbackTempDir withIntermediateDirectories:YES attributes:nil error:nil];

        CommandResult *extractResult = [[ProcessRunner sharedRunner] runCommand:cmd
                                                                       arguments:@[@"-q", path, @"-d", fallbackTempDir]
                                                                         timeout:60.0];
        if (extractResult.success) {
            NSString *payloadPath = [fallbackTempDir stringByAppendingPathComponent:@"Payload"];
            NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadPath error:nil];
            for (NSString *item in contents) {
                if ([item hasSuffix:@".app"]) {
                    NSString *appPath = [payloadPath stringByAppendingPathComponent:item];
                    NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
                    if ([[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
                        NSString *tempPlist = [tempDir stringByAppendingPathComponent:@"Info.plist"];
                        NSError *copyErr = nil;
                        [[NSFileManager defaultManager] copyItemAtPath:plistPath toPath:tempPlist error:&copyErr];
                        if (!copyErr) {
                            [[NSFileManager defaultManager] removeItemAtPath:fallbackTempDir error:nil];
                            [self.plistPathCache setObject:tempPlist forKey:path];
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                                [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
                                [self.plistPathCache removeObjectForKey:path];
                            });
                            return tempPlist;
                        }
                    }
                }
            }
        }
        [[NSFileManager defaultManager] removeItemAtPath:fallbackTempDir error:nil];
    }

    if (!result.success) {
        [[Logger sharedLogger] error:[NSString stringWithFormat:@"IPAValidator: unzip failed | category=%@ | exit=%d | stderr=%@",
                                      result.failureCategory, result.exitCode, result.stderrText]];
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        return nil;
    }

    NSData *plistData = result.stdoutData;
    NSString *tempPlist = [tempDir stringByAppendingPathComponent:@"Info.plist"];
    BOOL parsedOK = NO;

    if (plistData && plistData.length > 0) {
        if ([plistData writeToFile:tempPlist atomically:YES]) {
            NSDictionary *testParse = [NSDictionary dictionaryWithContentsOfFile:tempPlist];
            if (testParse) {
                parsedOK = YES;
            } else {
                [[Logger sharedLogger] warning:@"IPAValidator: pipe-extracted plist is corrupted, will attempt disk fallback"];
            }
        }
    }

    if (!parsedOK) {
        NSString *fallbackTempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:fallbackTempDir withIntermediateDirectories:YES attributes:nil error:nil];

        CommandResult *extractResult = [[ProcessRunner sharedRunner] runCommand:cmd
                                                                       arguments:@[@"-q", path, @"-d", fallbackTempDir]
                                                                         timeout:60.0];
        if (extractResult.success) {
            NSString *payloadPath = [fallbackTempDir stringByAppendingPathComponent:@"Payload"];
            NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadPath error:nil];
            for (NSString *item in contents) {
                if ([item hasSuffix:@".app"]) {
                    NSString *appPath = [payloadPath stringByAppendingPathComponent:item];
                    NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
                    if ([[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
                        NSDictionary *fallbackParse = [NSDictionary dictionaryWithContentsOfFile:plistPath];
                        if (fallbackParse) {
                            NSError *copyErr = nil;
                            [[NSFileManager defaultManager] removeItemAtPath:tempPlist error:nil];
                            [[NSFileManager defaultManager] copyItemAtPath:plistPath toPath:tempPlist error:&copyErr];
                            if (!copyErr) {
                                parsedOK = YES;
                            }
                        }
                    }
                }
            }
        }
        [[NSFileManager defaultManager] removeItemAtPath:fallbackTempDir error:nil];
    }

    if (!parsedOK) {
        [[Logger sharedLogger] error:@"IPAValidator: failed to extract valid Info.plist via pipe and disk fallback"];
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        return nil;
    }

    [self.plistPathCache setObject:tempPlist forKey:path];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        [self.plistPathCache removeObjectForKey:path];
    });

    return tempPlist;
}

- (NSString *)executablePathForIPA:(NSString *)path usingInfoPlistPath:(NSString *)infoPlistPath {
    if (!infoPlistPath) return nil;
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
    NSString *execName = info[@"CFBundleExecutable"];
    if (!execName) return nil;

    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSError *dirErr = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:&dirErr]) return nil;

    NSString *unzipPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/unzip"];
    CommandResult *result = [[ProcessRunner sharedRunner] runCommand:unzipPath
                                                           arguments:@[@"-q", path, @"-d", tempDir]
                                                             timeout:60.0];
    if (!result.success) {
        [[Logger sharedLogger] error:[NSString stringWithFormat:@"IPAValidator: unzip bundle failed | category=%@ | exit=%d",
                                      result.failureCategory, result.exitCode]];
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        return nil;
    }

    NSString *payloadPath = [tempDir stringByAppendingPathComponent:@"Payload"];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadPath error:nil];
    for (NSString *item in contents) {
        if ([item hasSuffix:@".app"]) {
            NSString *appPath = [payloadPath stringByAppendingPathComponent:item];
            NSString *execPath = [appPath stringByAppendingPathComponent:execName];
            if ([[NSFileManager defaultManager] fileExistsAtPath:execPath]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
                });
                return execPath;
            }
        }
    }

    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    return nil;
}

- (NSString *)executablePathForIPA:(NSString *)path {
    NSString *infoPlistPath = [self extractInfoPlistFromIPA:path];
    return [self executablePathForIPA:path usingInfoPlistPath:infoPlistPath];
}

- (BOOL)validateCodeSignature:(NSString *)path {
    NSString *codesignPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/codesign"];
    CommandResult *result = [[ProcessRunner sharedRunner] runCommand:codesignPath
                                                           arguments:@[@"-v", path]
                                                             timeout:30.0];
    return result.success;
}

- (BOOL)validateExecutableArchitecture:(NSString *)path {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) {
        return YES;
    }
    NSData *header = [handle readDataOfLength:8];
    [handle closeFile];
    if (header.length < 4) {
        return YES;
    }

    const uint8_t *bytes = header.bytes;
    uint32_t magic = *(uint32_t *)bytes;

    if (magic == 0xfeedfacf || magic == 0xfeedface) {
        if (header.length >= 8) {
            uint32_t cputype = *(uint32_t *)(bytes + 4);
            if (cputype == 0x0100000c || cputype == 0x0000000c) return YES;
        }
        return YES;
    }
    if (magic == 0xcafebabe || magic == 0xbebafeca || magic == 0xcafebabf) {
        return YES;
    }
    return YES;
}

@end
