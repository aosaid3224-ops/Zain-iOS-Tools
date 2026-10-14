#import "SPRootHide.h"
#include "SPRootHideCore.h"

#include <limits.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE) && __has_include(<roothide.h>)
#include <roothide.h>
#define SP_HAS_ROOTHIDE_API 1
#endif

NSString *const SPRootHelperName = @"ipainstallerpro_helper";

static NSString *SPTrimTrailingSlash(NSString *path) {
    while (path.length > 1 && [path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    return path;
}

static NSString *SPComputeJBRoot(void) {
#ifdef SP_HAS_ROOTHIDE_API
    const char *root = jbroot("/");
    if (root && root[0]) {
        NSString *path = SPTrimTrailingSlash(@(root));
        if ([path containsString:@"/.jbroot-"]) return path;
    }
#endif
    NSString *bundle = NSBundle.mainBundle.bundlePath ?: @"";
    NSRange marker = [bundle rangeOfString:@"/.jbroot-"];
    if (marker.location != NSNotFound) {
        NSUInteger from = NSMaxRange(marker);
        NSRange slash = [bundle rangeOfString:@"/" options:0 range:NSMakeRange(from, bundle.length - from)];
        return slash.location == NSNotFound ? bundle : [bundle substringToIndex:slash.location];
    }
    struct stat st;
    if (stat("/var/jb", &st) == 0 && S_ISDIR(st.st_mode)) return @"/var/jb";
    return @"";
}

NSString *SPJBRootPath(void) {
    static NSString *root;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ root = [SPComputeJBRoot() copy]; });
    return root;
}

BOOL SPIsRootHide(void) {
    return [SPJBRootPath() containsString:@"/.jbroot-"];
}

static NSArray<NSString *> *SPJBRootAliases(void) {
    static NSArray<NSString *> *aliases;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
        NSString *root = SPJBRootPath();
        void (^add)(NSString *) = ^(NSString *p) {
            if (p.length <= 1) return;
            p = SPTrimTrailingSlash(p);
            [set addObject:p];
            if ([p hasPrefix:@"/private/var/"]) [set addObject:[p substringFromIndex:@"/private".length]];
            else if ([p hasPrefix:@"/var/"]) [set addObject:[@"/private" stringByAppendingString:p]];
        };
        add(root);
        char resolved[PATH_MAX];
        if (root.length > 1 && realpath(root.fileSystemRepresentation, resolved)) add(@(resolved));
        aliases = set.array;
    });
    return aliases;
}

static NSString *SPRelativeToAliases(NSString *path) {
    for (NSString *alias in SPJBRootAliases()) {
        if ([path isEqualToString:alias]) return @"/";
        NSString *prefix = [alias stringByAppendingString:@"/"];
        if ([path hasPrefix:prefix]) return [path substringFromIndex:alias.length];
    }
    return nil;
}

static NSString *SPResolvedPath(NSString *path) {
    NSString *existing = path;
    NSMutableArray<NSString *> *tail = [NSMutableArray array];
    char resolved[PATH_MAX];
    while (existing.length > 1) {
        if (realpath(existing.fileSystemRepresentation, resolved)) {
            NSString *result = @(resolved);
            for (NSString *component in tail.reverseObjectEnumerator) result = [result stringByAppendingPathComponent:component];
            return result;
        }
        [tail addObject:existing.lastPathComponent];
        existing = existing.stringByDeletingLastPathComponent;
    }
    return nil;
}

NSString *SPJBRelativePath(NSString *realPath) {
    if (!SPIsRootHide() || ![realPath hasPrefix:@"/"]) return nil;
    NSString *relative = SPRelativeToAliases(realPath);
    if (relative) return relative;
    NSString *resolved = SPResolvedPath(realPath);
    return resolved ? SPRelativeToAliases(resolved) : nil;
}

BOOL SPIsInsideJBRoot(NSString *realPath) {
    if (!SPIsRootHide()) {
        NSString *root = SPJBRootPath();
        return root.length > 0 && ([realPath isEqualToString:root] || [realPath hasPrefix:[root stringByAppendingString:@"/"]]);
    }
    return SPJBRelativePath(realPath) != nil;
}

NSString *SPJBPath(NSString *jailbreakPath) {
    if (jailbreakPath.length == 0 || ![jailbreakPath hasPrefix:@"/"]) return jailbreakPath;
    NSString *root = SPJBRootPath();
    if (root.length == 0) return jailbreakPath;
    if (SPIsRootHide()) {
        if ([jailbreakPath isEqualToString:@"/rootfs"]) return @"/";
        if ([jailbreakPath hasPrefix:@"/rootfs/"]) return [jailbreakPath substringFromIndex:@"/rootfs".length];
        if (SPIsInsideJBRoot(jailbreakPath)) return jailbreakPath;
    } else if ([jailbreakPath isEqualToString:root] || [jailbreakPath hasPrefix:[root stringByAppendingString:@"/"]]) {
        return jailbreakPath;
    }
    if ([jailbreakPath isEqualToString:@"/"]) return root;
    return [root stringByAppendingString:jailbreakPath];
}

BOOL SPToolUsesJBRootPaths(NSString *executable) {
    if (!SPIsRootHide() || executable.length == 0) return NO;
    if (!SPIsInsideJBRoot(executable)) return NO;

    static NSMutableDictionary<NSString *, NSNumber *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    @synchronized (cache) {
        NSNumber *known = cache[executable];
        if (known) return known.boolValue;
    }
    int scan = sp_macho_uses_roothide(executable.fileSystemRepresentation);
    BOOL usesJBRoot = (scan != 0);
    @synchronized (cache) { cache[executable] = @(usesJBRoot); }
    return usesJBRoot;
}

static NSString *SPToolFormPath(NSString *realPath) {
    if (![realPath hasPrefix:@"/"]) return realPath;
    if ([realPath isEqualToString:@"/rootfs"] || [realPath hasPrefix:@"/rootfs/"]) return realPath;
    NSString *relative = SPJBRelativePath(realPath);
    if (relative) return relative;
    struct stat st;
    if (lstat(realPath.fileSystemRepresentation, &st) != 0 &&
        lstat(SPJBPath(realPath).fileSystemRepresentation, &st) == 0) return realPath;
#ifdef SP_HAS_ROOTHIDE_API
    const char *converted = rootfs(realPath.fileSystemRepresentation);
    if (converted && converted[0] == '/') return @(converted);
#endif
    return [@"/rootfs" stringByAppendingString:realPath];
}

NSString *SPToolPathForTool(NSString *executable, NSString *realPath) {
    if (realPath.length == 0 || !SPToolUsesJBRootPaths(executable)) return realPath;
    return SPToolFormPath(realPath);
}

static NSString *SPToolFormArgument(NSString *argument) {
    const char *bytes = argument.UTF8String;
    long offset = sp_arg_path_offset(bytes);
    if (offset < 0) return argument;
    for (long i = 0; i < offset; i++) {
        if ((unsigned char)bytes[i] >= 0x80) return argument;
    }
    NSString *prefix = [argument substringToIndex:(NSUInteger)offset];
    NSString *path = [argument substringFromIndex:(NSUInteger)offset];
    return [prefix stringByAppendingString:SPToolFormPath(path)];
}

NSArray<NSString *> *SPToolArguments(NSString *executable, NSArray<NSString *> *arguments) {
    if (!arguments) return @[];
    if (!SPIsRootHide() || arguments.count == 0) return arguments;

    if ([executable.lastPathComponent isEqualToString:SPRootHelperName]) {
        if ([arguments.firstObject isEqualToString:@"--copy-tree"]) return arguments;
        NSString *target = arguments.firstObject;
        NSArray<NSString *> *rest = [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)];
        return [@[target] arrayByAddingObjectsFromArray:SPToolArguments(target, rest)];
    }

    if (!SPToolUsesJBRootPaths(executable)) return arguments;
    NSMutableArray<NSString *> *converted = [NSMutableArray arrayWithCapacity:arguments.count];
    for (NSString *argument in arguments) [converted addObject:SPToolFormArgument(argument)];
    return converted;
}

NSString *SPPathFromTool(NSString *toolPath) {
    if (!SPIsRootHide() || ![toolPath hasPrefix:@"/"]) return toolPath;
    return SPJBPath(toolPath);
}
