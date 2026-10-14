#import "ExecutableValidator.h"
#import "ExecutableCapability.h"
#import "ProcessRunner.h"
#import "CommandResult.h"
#import "RuntimeEnvironment.h"
#import "Logger.h"

#include <unistd.h>
#include <errno.h>

@interface ExecutableValidator ()
@property (nonatomic, strong) dispatch_queue_t validationQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ExecutableCapability *> *cache;
@property (nonatomic, strong) NSDate *lastCacheReset;
@end

@implementation ExecutableValidator

+ (instancetype)sharedValidator {
    static ExecutableValidator *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _validationQueue = dispatch_queue_create("com.spider.executablevalidator", DISPATCH_QUEUE_SERIAL);
        _cache = [NSMutableDictionary dictionary];
        _lastCacheReset = [NSDate date];
    }
    return self;
}

- (ExecutableCapability *)validateExecutableNamed:(NSString *)name {
    if (name.length == 0) {
        ExecutableCapability *cap = [[ExecutableCapability alloc] initWithExecutableName:@"" searchedPaths:@[]];
        [cap markStatus:ExecutableCapabilityStatusUnknownError errorMessage:@"اسم الأداة فارغ"];
        return cap;
    }

    __block ExecutableCapability *cached = nil;
    dispatch_sync(self.validationQueue, ^{
        cached = self.cache[name];
        if (cached && [[NSDate date] timeIntervalSinceDate:cached.testTimestamp] < 60.0) {
            [[Logger sharedLogger] info:[NSString stringWithFormat:@"ExecutableValidator: using cached result for %@", name]];
        } else {
            cached = nil;
        }
    });

    if (cached) return cached;

    NSArray<NSString *> *searchPaths = [self buildSearchPathsForName:name];
    ExecutableCapability *cap = [[ExecutableCapability alloc] initWithExecutableName:name searchedPaths:searchPaths];

    NSString *foundPath = nil;
    BOOL foundExists = NO;
    BOOL foundExecutable = NO;

    for (NSString *dir in searchPaths) {
        NSString *candidate = [dir stringByAppendingPathComponent:name];
        int acc = access(candidate.fileSystemRepresentation, F_OK);
        if (acc == 0) {
            foundPath = candidate;
            foundExists = YES;
            int xok = access(candidate.fileSystemRepresentation, X_OK);
            foundExecutable = (xok == 0);
            [cap markFoundAtPath:candidate exists:foundExists executable:foundExecutable];

            if (foundExecutable) {
                break;
            }
        }
    }

    if (!foundPath) {
        [cap markStatus:ExecutableCapabilityStatusNotFound
           errorMessage:[NSString stringWithFormat:@"لم يُعثر على %@ في أي من المسارات المُفحصة (%lu مسار)", name, (unsigned long)searchPaths.count]];
        [self cacheResult:cap forName:name];
        [[Logger sharedLogger] error:[NSString stringWithFormat:@"ExecutableValidator: %@ NOT_FOUND in %lu paths", name, (unsigned long)searchPaths.count]];
        return cap;
    }

    if (!foundExecutable) {
        [cap markStatus:ExecutableCapabilityStatusNotExecutable
           errorMessage:[NSString stringWithFormat:@"%@ موجود في %@ لكنه غير قابل للتنفيذ", name, foundPath]];
        [self cacheResult:cap forName:name];
        [[Logger sharedLogger] error:[NSString stringWithFormat:@"ExecutableValidator: %@ NOT_EXECUTABLE at %@", name, foundPath]];
        return cap;
    }

    ExecutableCapability *testedCap = [self runInvocationTestForExecutable:name
                                                                      atPath:foundPath
                                                            startingCapability:cap];
    [self cacheResult:testedCap forName:name];
    return testedCap;
}

- (ExecutableCapability *)validateLDID {
    ExecutableCapability *cap = [self validateExecutableNamed:@"ldid"];

    if (cap.status == ExecutableCapabilityStatusReady) {
        CommandResult *vResult = [[ProcessRunner sharedRunner] runCommand:cap.resolvedPath
                                                                arguments:@[@"-v"]
                                                                  timeout:5.0];
        NSString *versionOutput = [NSString stringWithFormat:@"%@ %@", vResult.stdoutText, vResult.stderrText];
        BOOL looksLikeLDID = vResult.success ||
                             [versionOutput containsString:@"ldid"] ||
                             [versionOutput containsString:@"Usage"] ||
                             [versionOutput containsString:@"usage"];

        BOOL supportsCoreTrust = NO;
        if (looksLikeLDID) {
            supportsCoreTrust = [versionOutput containsString:@"procursus"] ||
                                [versionOutput containsString:@"2.1.5"] ||
                                [versionOutput containsString:@"2.1.6"] ||
                                [versionOutput containsString:@"2.1.7"] ||
                                [versionOutput containsString:@"2.2"] ||
                                [versionOutput containsString:@"2.3"];
            if (!supportsCoreTrust) {
                NSString *tmpFile = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"ldid_test_%@", [[NSUUID UUID] UUIDString]]];
                [@"#!/bin/sh\nexit 0\n" writeToFile:tmpFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
                CommandResult *signTest = [[ProcessRunner sharedRunner] runCommand:cap.resolvedPath
                                                                         arguments:@[@"-S", tmpFile]
                                                                           timeout:5.0];
                supportsCoreTrust = signTest.success;
                [[NSFileManager defaultManager] removeItemAtPath:tmpFile error:nil];
            }
        }

        if (looksLikeLDID && supportsCoreTrust) {
            [[Logger sharedLogger] info:[NSString stringWithFormat:@"ExecutableValidator: ldid CoreTrust-ready at %@", cap.resolvedPath]];
            return cap;
        }

        if (looksLikeLDID && !supportsCoreTrust) {
            [cap markStatus:ExecutableCapabilityStatusInvalidOutput
               errorMessage:@"ldid موجود لكن إصدارته قديمة ولا تدعم CoreTrust المطلوب في iOS 16+"];
            [[Logger sharedLogger] warning:[NSString stringWithFormat:@"ExecutableValidator: ldid TOO_OLD for iOS16+ at %@", cap.resolvedPath]];
            return cap;
        }

        CommandResult *bareResult = [[ProcessRunner sharedRunner] runCommand:cap.resolvedPath
                                                                   arguments:@[]
                                                                     timeout:5.0];
        NSString *combined = [NSString stringWithFormat:@"%@ %@", bareResult.stdoutText, bareResult.stderrText];
        if ([combined containsString:@"ldid"] || [combined containsString:@"Usage"] || [combined containsString:@"usage"]) {
            [[Logger sharedLogger] info:[NSString stringWithFormat:@"ExecutableValidator: ldid bare test passed at %@", cap.resolvedPath]];
            return cap;
        }

        [cap markStatus:ExecutableCapabilityStatusInvalidOutput
           errorMessage:@"الأداة تعمل لكنها لا تُنتج خرجًا متوقعًا (قد تكون نسخة غير متوافقة)"];
        [[Logger sharedLogger] warning:[NSString stringWithFormat:@"ExecutableValidator: ldid INVALID_OUTPUT at %@ | stdout=%@ | stderr=%@",
                                        cap.resolvedPath, bareResult.stdoutText, bareResult.stderrText]];
    }

    return cap;
}
- (ExecutableCapability *)validateUnzip {
    return [self validateExecutableNamed:@"unzip"];
}

- (ExecutableCapability *)validateUICache {
    return [self validateExecutableNamed:@"uicache"];
}

- (NSString *)findExecutableNamed:(NSString *)name {
    NSArray<NSString *> *paths = [self buildSearchPathsForName:name];
    NSLog(@"[Spider-ToolSearch] === Searching for '%@' ===", name);
    NSLog(@"[Spider-ToolSearch] Search paths count: %lu", (unsigned long)paths.count);
    for (NSUInteger i = 0; i < paths.count; i++) {
        NSString *dir = paths[i];
        NSString *candidate = [dir stringByAppendingPathComponent:name];
        int result = access(candidate.fileSystemRepresentation, F_OK);
        if (result == 0) {
            NSLog(@"[Spider-ToolSearch] [%lu] FOUND: %@", (unsigned long)i, candidate);
            return candidate;
        } else {
            NSLog(@"[Spider-ToolSearch] [%lu] NOT FOUND: %@ (errno=%d: %s)", 
                  (unsigned long)i, candidate, errno, strerror(errno));
        }
    }
    NSLog(@"[Spider-ToolSearch] === '%@' NOT FOUND in any path ===", name);
    return nil;
}

- (NSArray<NSString *> *)currentSearchPaths {
    return [self buildSearchPathsForName:@""];
}

- (NSArray<NSString *> *)buildSearchPathsForName:(NSString *)name {
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];

    RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];
    for (NSString *p in rt.binSearchPaths) {
        if (p.length > 0) [paths addObject:p];
    }

    [paths addObject:@"/usr/bin"];
    [paths addObject:@"/bin"];
    [paths addObject:@"/usr/local/bin"];

    if (rt.bootstrapPath) {
        [paths addObject:[rt.bootstrapPath stringByAppendingPathComponent:@"usr/bin"]];
        [paths addObject:[rt.bootstrapPath stringByAppendingPathComponent:@"bin"]];
    } else {
        [paths addObject:@"/var/jb/usr/bin"];
        [paths addObject:@"/var/jb/bin"];
    }
    [paths addObject:@"/var/LIY/usr/bin"];
    [paths addObject:@"/var/LIY/bin"];
    [paths addObject:@"/opt/procursus/bin"];
    [paths addObject:@"/opt/procursus/usr/bin"];

    return paths.array;
}

- (ExecutableCapability *)runInvocationTestForExecutable:(NSString *)name
                                                    atPath:(NSString *)path
                                          startingCapability:(ExecutableCapability *)cap {
    NSDate *start = [NSDate date];

    CommandResult *result = [[ProcessRunner sharedRunner] runCommand:path
                                                           arguments:@[@"-v"]
                                                             timeout:5.0];
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];

    [cap markInvocationResultWithSpawnError:result.spawnError
                                   exitCode:result.exitCode
                               signalNumber:result.signalNumber
                                     output:[NSString stringWithFormat:@"%@ %@", result.stdoutText, result.stderrText]
                                   duration:duration];

    if (result.spawnError != 0) {
        return cap;
    }

    if (result.timedOut) {
        [cap markStatus:ExecutableCapabilityStatusTimeout
           errorMessage:@"انتهت مهلة اختبار تشغيل الأداة"];
        return cap;
    }

    NSString *combined = [NSString stringWithFormat:@"%@ %@", result.stdoutText, result.stderrText];
    BOOL outputLooksValid = (combined.length > 0) || (result.exitCode == 0);

    if (!outputLooksValid && result.exitCode != 0) {
        NSDate *bareStart = [NSDate date];
        CommandResult *bareResult = [[ProcessRunner sharedRunner] runCommand:path
                                                                   arguments:@[]
                                                                     timeout:5.0];
        NSTimeInterval bareDuration = [[NSDate date] timeIntervalSinceDate:bareStart];
        duration += bareDuration;

        combined = [NSString stringWithFormat:@"%@ %@", bareResult.stdoutText, bareResult.stderrText];
        outputLooksValid = (combined.length > 0);

        [cap markInvocationResultWithSpawnError:bareResult.spawnError
                                       exitCode:bareResult.exitCode
                                   signalNumber:bareResult.signalNumber
                                         output:combined
                                       duration:duration];

        if (bareResult.spawnError != 0) {
            return cap;
        }
        if (bareResult.timedOut) {
            [cap markStatus:ExecutableCapabilityStatusTimeout
               errorMessage:@"انتهت مهلة الاختبار الثاني"];
            return cap;
        }
    }

    if (!outputLooksValid) {
        [cap markStatus:ExecutableCapabilityStatusInvalidOutput
           errorMessage:@"الأداة تعمل لكنها لا تُنتج أي خرج متوقع"];
        [[Logger sharedLogger] warning:[NSString stringWithFormat:@"ExecutableValidator: %@ INVALID_OUTPUT at %@", name, path]];
        return cap;
    }

    [cap markReadyWithPath:path output:combined duration:duration];
    [[Logger sharedLogger] info:[NSString stringWithFormat:@"ExecutableValidator: %@ READY at %@ (%.3fs)", name, path, duration]];
    return cap;
}

- (void)cacheResult:(ExecutableCapability *)cap forName:(NSString *)name {
    dispatch_async(self.validationQueue, ^{
        self.cache[name] = cap;
    });
}

- (void)invalidateCache {
    dispatch_async(self.validationQueue, ^{
        [self.cache removeAllObjects];
        self.lastCacheReset = [NSDate date];
    });
}

@end
