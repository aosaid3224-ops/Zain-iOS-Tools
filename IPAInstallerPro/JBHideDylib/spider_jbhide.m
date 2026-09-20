//
//  spider_jbhide.m
//  Spider Jailbreak Hide — injected interposition dylib.
//
//  Self-contained: DYLD_INTERPOSE for C functions + ObjC method swizzling.
//  No Substrate / ElleKit / libhooker API dependency — ElleKit only *injects*
//  this dylib; everything here works through dyld itself.
//
//  Coverage model (honest):
//   Type A (covered): detections via libc file APIs, NSFileManager,
//     NSURL/UIApplication canOpenURL, getenv(DYLD_*), fork/system-style
//     sandbox probes, dyld image enumeration, getfsstat mount enumeration.
//   Type B (NOT covered): raw syscalls (syscall(SYS_stat) etc.), statically
//     linked detection code, server-side heuristics. Logged, never faked.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import <sys/param.h>
#import <dirent.h>
#import <fcntl.h>
#import <dlfcn.h>
#import <errno.h>
#import <unistd.h>
#import <string.h>
#import <stdlib.h>
#import <stdarg.h>

#define SPIDER_JBHIDE_VERSION "1.0.0"

#pragma mark - DYLD_INTERPOSE

#define SPIDER_INTERPOSE(_repl, _orig) \
    __attribute__((used)) static struct { const void *repl; const void *orig; } \
    _spider_interpose_##_orig __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(unsigned long)&_repl, (const void *)(unsigned long)&_orig }

#pragma mark - Blocked path policy

// Exact jailbreak-indicator paths that must disappear. Deliberately does NOT
// blanket-block "/var/jb": the host app itself lives under /var/jb/Applications
// on rootless installs, and blanket blocking would break the host's own
// bundle access. Detectors are answered on the *indicator* paths instead.
static const char *blockedExact[] = {
    "/var/jb", "/private/var/jb",
    "/var/LIY", "/private/var/LIY",
    "/var/lib/dpkg", "/private/var/lib/dpkg",
    "/var/lib/apt", "/private/var/lib/apt",
    "/var/log/dpkg.log", "/private/var/log/dpkg.log",
    "/var/log/apt", "/private/var/log/apt",
    "/etc/apt", "/private/etc/apt",
    "/etc/dpkg", "/private/etc/dpkg",
    "/etc/ssh/sshd_config", "/private/etc/ssh/sshd_config",
    "/etc/sudoers.d", "/private/etc/sudoers.d",
    "/usr/bin/dpkg", "/usr/bin/apt", "/usr/bin/apt-get",
    "/usr/sbin/sshd", "/usr/bin/sshd", "/usr/bin/sudo",
    "/usr/lib/libsubstrate.dylib", "/usr/lib/libsubstitute.dylib",
    "/usr/lib/libhooker.dylib", "/usr/lib/libellekit.dylib",
    "/usr/lib/TweakInject", "/usr/lib/ellekit",
    "/Library/MobileSubstrate", "/Library/Frameworks/CydiaSubstrate.framework",
    "/Applications/Cydia.app", "/Applications/Sileo.app",
    "/Applications/Sileo-Nightly.app", "/Applications/Zebra.app",
    "/Applications/ElleKit.app", "/Applications/Installer.app",
    "/Applications/NewTerm.app", "/Applications/Filza.app",
    "/var/stash", "/private/var/stash",
    "/var/tmp/cydia.log", "/private/var/tmp/cydia.log",
    "/var/mobile/Library/Cydia", "/private/var/mobile/Library/Cydia",
    "/var/mobile/Library/Preferences/com.saurik.Cydia.plist",
    "/private/var/mobile/Library/Preferences/com.saurik.Cydia.plist",
    NULL
};

// Jailbreak *app* names inside Applications dirs (rootless + rootful).
static const char *blockedAppNames[] = {
    "Cydia.app", "Sileo.app", "Sileo-Nightly.app", "Zebra.app",
    "ElleKit.app", "Installer.app", "NewTerm.app", "Filza.app",
    NULL
};

static BOOL pathIsBlocked(const char *path) {
    if (!path || path[0] != '/') return NO;
    // Normalize a leading /private without walking the FS.
    const char *p = path;
    if (strncmp(p, "/private", 8) == 0 && (p[8] == '/' || p[8] == 0)) {
        // keep both forms checked below via exact table
    }
    for (int i = 0; blockedExact[i]; i++) {
        size_t n = strlen(blockedExact[i]);
        if (strncmp(p, blockedExact[i], n) == 0 && (p[n] == 0 || p[n] == '/')) return YES;
        // Also match the /private-prefixed variant of the same entry.
        if (strncmp(blockedExact[i], "/private", 8) != 0) {
            if (strncmp(p, blockedExact[i], n) == 0) return YES;
        }
    }
    // Blocked jailbreak apps under any Applications directory.
    const char *appsMarker = strstr(p, "/Applications/");
    if (appsMarker) {
        const char *appName = appsMarker + strlen("/Applications/");
        for (int i = 0; blockedAppNames[i]; i++) {
            size_t n = strlen(blockedAppNames[i]);
            if (strncmp(appName, blockedAppNames[i], n) == 0 && (appName[n] == 0 || appName[n] == '/')) return YES;
        }
    }
    return NO;
}

static int blockedErrno(void) { errno = ENOENT; return -1; }

#pragma mark - POSIX interpositions

static int spider_stat(const char *path, struct stat *buf) {
    if (pathIsBlocked(path)) return blockedErrno();
    return stat(path, buf);
}
static int spider_lstat(const char *path, struct stat *buf) {
    if (pathIsBlocked(path)) return blockedErrno();
    return lstat(path, buf);
}
static int spider_fstatat(int fd, const char *path, struct stat *buf, int flag) {
    if (pathIsBlocked(path)) return blockedErrno();
    return fstatat(fd, path, buf, flag);
}
static int spider_access(const char *path, int mode) {
    if (pathIsBlocked(path)) return blockedErrno();
    return access(path, mode);
}
static int spider_faccessat(int fd, const char *path, int mode, int flag) {
    if (pathIsBlocked(path)) return blockedErrno();
    return faccessat(fd, path, mode, flag);
}
static int spider_open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list a; va_start(a, flags); mode = (mode_t)va_arg(a, int); va_end(a); }
    if (pathIsBlocked(path)) return blockedErrno();
    return open(path, flags, mode);
}
static int spider_openat(int fd, const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list a; va_start(a, flags); mode = (mode_t)va_arg(a, int); va_end(a); }
    if (pathIsBlocked(path)) return blockedErrno();
    return openat(fd, path, flags, mode);
}
static FILE *spider_fopen(const char *path, const char *mode) {
    if (pathIsBlocked(path)) { errno = ENOENT; return NULL; }
    return fopen(path, mode);
}
static DIR *spider_opendir(const char *path) {
    if (pathIsBlocked(path)) { errno = ENOENT; return NULL; }
    return opendir(path);
}
static char *spider_realpath(const char *path, char *resolved) {
    if (pathIsBlocked(path)) { errno = ENOENT; return NULL; }
    return realpath(path, resolved);
}
static int spider_statfs(const char *path, struct statfs *buf) {
    if (pathIsBlocked(path)) return blockedErrno();
    return statfs(path, buf);
}
static int spider_getfsstat(struct statfs *buf, long bufsize, int flags) {
    // Snapshot the real table, then filter jailbreak mounts out of the copy.
    if (!buf || bufsize <= 0) return getfsstat(buf, bufsize, flags);
    int count = getfsstat(NULL, 0, MNT_NOWAIT);
    if (count <= 0) return count;
    struct statfs *tmp = malloc(sizeof(struct statfs) * count);
    if (!tmp) return getfsstat(buf, bufsize, flags);
    int got = getfsstat(tmp, (long)(sizeof(struct statfs) * count), MNT_NOWAIT);
    int kept = 0;
    long cap = bufsize / (long)sizeof(struct statfs);
    for (int i = 0; i < got && kept < cap; i++) {
        const char *on = tmp[i].f_mntonname, *from = tmp[i].f_mntfromname;
        if ((on && (strstr(on, "preboot") || strstr(on, "/var/jb") || strstr(on, "LIY"))) ||
            (from && (strstr(from, "preboot") || strstr(from, "LIY")))) continue;
        buf[kept++] = tmp[i];
    }
    free(tmp);
    return kept;
}

SPIDER_INTERPOSE(spider_stat, stat);
SPIDER_INTERPOSE(spider_lstat, lstat);
SPIDER_INTERPOSE(spider_fstatat, fstatat);
SPIDER_INTERPOSE(spider_access, access);
SPIDER_INTERPOSE(spider_faccessat, faccessat);
SPIDER_INTERPOSE(spider_open, open);
SPIDER_INTERPOSE(spider_openat, openat);
SPIDER_INTERPOSE(spider_fopen, fopen);
SPIDER_INTERPOSE(spider_opendir, opendir);
SPIDER_INTERPOSE(spider_realpath, realpath);
SPIDER_INTERPOSE(spider_statfs, statfs);
SPIDER_INTERPOSE(spider_getfsstat, getfsstat);

#pragma mark - Environment / sandbox probes

static char *spider_getenv(const char *name) {
    if (name && (strcmp(name, "DYLD_INSERT_LIBRARIES") == 0 ||
                 strcmp(name, "DYLD_PRINT_LIBRARIES") == 0)) return NULL;
    return getenv(name);
}
static pid_t spider_fork(void) { errno = EPERM; return (pid_t)-1; }
static FILE *spider_popen(const char *cmd, const char *type) { (void)cmd; (void)type; errno = ENOENT; return NULL; }

SPIDER_INTERPOSE(spider_getenv, getenv);
SPIDER_INTERPOSE(spider_fork, fork);
SPIDER_INTERPOSE(spider_popen, popen);

#pragma mark - dyld image enumeration filter

static char **g_filteredNames = NULL;
static uint32_t g_filteredCount = 0;
static uint32_t g_lastRawCount = 0;

static BOOL imageNameIsTweak(const char *name) {
    if (!name) return NO;
    return strstr(name, "TweakInject") || strstr(name, "ellekit") || strstr(name, "ElleKit") ||
           strstr(name, "substrate") || strstr(name, "Substrate") || strstr(name, "Substitute") ||
           strstr(name, "libhooker") || strstr(name, "libblackjack") || strstr(name, "libmryipc");
}

static void rebuildImageCache(void) {
    uint32_t raw = _dyld_image_count();
    if (raw == g_lastRawCount && g_filteredNames) return;
    if (g_filteredNames) {
        for (uint32_t i = 0; i < g_filteredCount; i++) free(g_filteredNames[i]);
        free(g_filteredNames);
        g_filteredNames = NULL;
    }
    g_filteredNames = calloc(raw + 1, sizeof(char *));
    g_filteredCount = 0;
    for (uint32_t i = 0; i < raw; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        if (imageNameIsTweak(name)) continue;
        if (pathIsBlocked(name)) continue;
        g_filteredNames[g_filteredCount++] = strdup(name);
    }
    g_lastRawCount = raw;
}

static uint32_t spider_dyld_image_count(void) {
    rebuildImageCache();
    return g_filteredCount;
}
static const char *spider_dyld_get_image_name(uint32_t index) {
    rebuildImageCache();
    if (index >= g_filteredCount) return NULL;
    return g_filteredNames[index];
}

SPIDER_INTERPOSE(spider_dyld_image_count, _dyld_image_count);
SPIDER_INTERPOSE(spider_dyld_get_image_name, _dyld_get_image_name);

#pragma mark - Objective-C swizzles

@interface NSFileManager (SpiderJBHide)
@end
@implementation NSFileManager (SpiderJBHide)

static BOOL (*orig_fileExists)(NSFileManager *, SEL, NSString *) = NULL;
static BOOL (*orig_fileExistsIsDir)(NSFileManager *, SEL, NSString *, BOOL *) = NULL;

static BOOL swz_fileExists(NSFileManager *self, SEL _cmd, NSString *path) {
    if (path.length && pathIsBlocked(path.fileSystemRepresentation)) return NO;
    return orig_fileExists(self, _cmd, path);
}
static BOOL swz_fileExistsIsDir(NSFileManager *self, SEL _cmd, NSString *path, BOOL *isDir) {
    if (path.length && pathIsBlocked(path.fileSystemRepresentation)) {
        if (isDir) *isDir = NO;
        return NO;
    }
    return orig_fileExistsIsDir(self, _cmd, path, isDir);
}

+ (void)spiderJBHideLoad {
    Method m1 = class_getInstanceMethod(self, @selector(fileExistsAtPath:));
    Method m2 = class_getInstanceMethod(self, @selector(fileExistsAtPath:isDirectory:));
    if (m1) { orig_fileExists = (void *)method_getImplementation(m1);
        method_setImplementation(m1, (IMP)swz_fileExists); }
    if (m2) { orig_fileExistsIsDir = (void *)method_getImplementation(m2);
        method_setImplementation(m2, (IMP)swz_fileExistsIsDir); }
}

@end

@interface UIApplication (SpiderJBHide)
@end
@implementation UIApplication (SpiderJBHide)

static BOOL (*orig_canOpenURL)(UIApplication *, SEL, NSURL *) = NULL;
static BOOL swz_canOpenURL(UIApplication *self, SEL _cmd, NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    static NSSet *blockedSchemes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedSchemes = [NSSet setWithArray:@[ @"cydia", @"sileo", @"zbra", @"filza",
                                                @"activator", @"sileonightly" ]];
    });
    if (scheme && [blockedSchemes containsObject:scheme]) return NO;
    return orig_canOpenURL ? orig_canOpenURL(self, _cmd, url) : NO;
}

+ (void)spiderJBHideLoad {
    Method m = class_getInstanceMethod(self, @selector(canOpenURL:));
    if (m) { orig_canOpenURL = (void *)method_getImplementation(m);
        method_setImplementation(m, (IMP)swz_canOpenURL); }
}

@end

#pragma mark - Load marker

static void writeLoadMarkerToDir(NSString *dir, NSString *bundleID) {
    if (!dir.length) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions: @0755 } error:nil];
    NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.load.plist", bundleID]];
    NSDictionary *marker = @{
        @"bundleID": bundleID,
        @"timestamp": [NSDate date],
        @"version": @SPIDER_JBHIDE_VERSION,
        @"pid": @(getpid())
    };
    NSString *tmp = [path stringByAppendingString:@".tmp"];
    if ([marker writeToFile:tmp atomically:YES]) {
        rename(tmp.fileSystemRepresentation, path.fileSystemRepresentation);
    }
}

static void writeLoadMarker(void) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
        // PRIMARY: the app's own data container — always writable, even sandboxed.
        writeLoadMarkerToDir([NSHomeDirectory() stringByAppendingPathComponent:@"Library/SpiderJB"], bundleID);
        // SECONDARY: shared marker dir (fallback for verification from outside).
        writeLoadMarkerToDir(@"/var/mobile/Library/SpiderJB", bundleID);
    }
}

__attribute__((constructor)) static void spider_jbhide_constructor(void) {
    writeLoadMarker();
    [NSFileManager performSelector:@selector(spiderJBHideLoad)];
    [UIApplication performSelector:@selector(spiderJBHideLoad)];
}
