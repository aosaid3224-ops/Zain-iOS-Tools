//
//  RootlessManager.m
//  IPAInstallerPro — Commit 3: Runtime Environment Discovery
//
//  CHANGES:
//  - Replaced hardcoded /var/jb fallback with RuntimeEnvironment delegation.
//  - resolvePath now uses bootstrapPath dynamically discovered.
//  - isRootlessActive delegates to RuntimeEnvironment.
//  - No public API changes.
//

#import "RootlessManager.h"
#import "RuntimeEnvironment.h"
#import "Logger.h"
#import "../rootless.h"

@implementation RootlessManager

+ (instancetype)sharedManager {
    static RootlessManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // RuntimeEnvironment is the single source of truth for rootless state.
    }
    return self;
}

#pragma mark - Public API (unchanged signatures)

- (NSString *)resolvePath:(NSString *)path {
    if (!path || path.length == 0) return path;

    NSFileManager *fm = [NSFileManager defaultManager];
    RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];

    if (rt.bootstrapPath && [path hasPrefix:rt.bootstrapPath]) return path;
    if ([fm fileExistsAtPath:path]) return path;

    // RootHide/Relaxin exposes an outer randomized .jbroot directory. Its
    // logical root is usually <outer-jbroot>/var/jb, not <outer-jbroot>.
    // Prefer libroot's authoritative mapping, then probe both layouts.
    NSString *librootMapped = SPJBRRootPath(path);
    if (librootMapped.length && [fm fileExistsAtPath:librootMapped]) return librootMapped;

    if (rt.bootstrapPath.length > 0 && [rt.bootstrapPath containsString:@".jbroot-"]) {
        NSString *innerRoot = [rt.bootstrapPath stringByAppendingPathComponent:@"var/jb"];
        NSString *innerCandidate = [innerRoot stringByAppendingPathComponent:[path hasPrefix:@"/"] ? [path substringFromIndex:1] : path];
        if ([fm fileExistsAtPath:innerCandidate]) return innerCandidate;

        NSString *outerCandidate = [rt.bootstrapPath stringByAppendingPathComponent:[path hasPrefix:@"/"] ? [path substringFromIndex:1] : path];
        if ([fm fileExistsAtPath:outerCandidate]) return outerCandidate;

        // Destinations must remain deterministic even before creation.
        return innerCandidate;
    }

    if (rt.isRootless && rt.bootstrapPath.length > 0) {
        NSString *relativePath = [path hasPrefix:@"/"] ? [path substringFromIndex:1] : path;
        return [rt.bootstrapPath stringByAppendingPathComponent:relativePath];
    }

    return path;
}

- (NSString *)rootlessPathForPath:(NSString *)path {
    return [self resolvePath:path];
}

- (NSString *)standardPathForPath:(NSString *)path {
    // Reverse: if path starts with bootstrap path, strip it
    RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];
    if (rt.bootstrapPath && [path hasPrefix:rt.bootstrapPath]) {
        NSString *relative = [path substringFromIndex:rt.bootstrapPath.length];
        if ([relative hasPrefix:@"/"]) {
            return relative;
        }
        return [@"/" stringByAppendingString:relative];
    }
    return path;
}

- (BOOL)fileExistsAtLogicalPath:(NSString *)path {
    NSString *resolved = [self resolvePath:path];
    return [[NSFileManager defaultManager] fileExistsAtPath:resolved];
}

- (BOOL)createDirectoryAtLogicalPath:(NSString *)path error:(NSError **)error {
    NSString *resolved = [self resolvePath:path];
    return [[NSFileManager defaultManager] createDirectoryAtPath:resolved withIntermediateDirectories:YES attributes:nil error:error];
}

- (BOOL)fileExistsAtRootlessPath:(NSString *)path {
    return [self fileExistsAtLogicalPath:path];
}

- (BOOL)isFileAtPathExecutable:(NSString *)path {
    NSString *resolved = [self resolvePath:path];
    return [[NSFileManager defaultManager] isExecutableFileAtPath:resolved];
}

@end
