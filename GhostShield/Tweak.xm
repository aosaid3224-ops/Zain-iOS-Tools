// ═══════════════════════════════════════════════════════
//  GhostShield v1.0 — درع الحماية | ZAIN iOS Tools
//  يعمل داخل اللعبة فقط: يخفي نفسه وإخوته + يخفي الجلبريك + يزوّر الهوية
//  صامت تمامًا — لا ملفات، لا لوق، لا شبكة
// ═══════════════════════════════════════════════════════
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <dirent.h>
#import <errno.h>
#import <dlfcn.h>

static BOOL gs_hidden(const char *path) {
    if (!path) return NO;
    return (strstr(path, "TweakInject")  != NULL ||
            strstr(path, "ellekit")       != NULL ||
            strstr(path, "Substitute")    != NULL ||
            strstr(path, "MobileSubstrate")!= NULL ||
            strstr(path, "CydiaSubstrate")!= NULL ||
            strstr(path, "libhooker")     != NULL ||
            strstr(path, ".jbroot")       != NULL ||
            strstr(path, "procursus")     != NULL ||
            strstr(path, "systemhook")    != NULL ||
            strstr(path, "GhostShield")   != NULL ||
            strstr(path, "dopamine-")     != NULL);
}

static BOOL gs_jbpath(const char *path) {
    if (!path) return NO;
    return (strncmp(path, "/var/jb", 7) == 0          ||
            strstr(path, "/.jbroot")      != NULL     ||
            strstr(path, "/procursus/")   != NULL     ||
            strstr(path, "TweakInject")   != NULL     ||
            strstr(path, "/Sileo.app")    != NULL     ||
            strstr(path, "/Filza.app")    != NULL     ||
            strstr(path, "Cydia.app")     != NULL     ||
            strstr(path, "Dopamine.app")  != NULL);
}

// ─── 1) إخفاء الصور الأجنبية من dyld ───
%hookf(const char *, _dyld_get_image_name, uint32_t image_index) {
    const char *n = %orig;
    if (gs_hidden(n)) return "/usr/lib/libobjc.A.dylib";
    return n;
}

%hookf(int, dladdr, const void *addr, Dl_info *info) {
    int r = %orig;
    if (r && info && info->dli_fname && gs_hidden(info->dli_fname)) {
        info->dli_fname = "/usr/lib/libobjc.A.dylib";
        info->dli_fbase = NULL;
        info->dli_sname = NULL;
        info->dli_saddr = NULL;
    }
    return r;
}

// ─── 2) إخفاء ملفات الجلبريك ───
%hookf(int, access, const char *path, int mode) {
    if (gs_jbpath(path)) { errno = ENOENT; return -1; }
    return %orig;
}

%hookf(int, stat, const char *path, struct stat *buf) {
    if (gs_jbpath(path)) { errno = ENOENT; return -1; }
    return %orig;
}

%hookf(int, lstat, const char *path, struct stat *buf) {
    if (gs_jbpath(path)) { errno = ENOENT; return -1; }
    return %orig;
}

%hookf(int, fstatat, int fd, const char *path, struct stat *buf, int flag) {
    if (gs_jbpath(path)) { errno = ENOENT; return -1; }
    return %orig;
}

%hookf(DIR *, opendir, const char *path) {
    if (gs_jbpath(path)) { errno = ENOENT; return NULL; }
    return %orig;
}

// ─── 3) تزوير هوية الجهاز ───
%hookf(CFTypeRef, MGCopyAnswer, CFStringRef key) {
    if (key) {
        NSString *k = (__bridge NSString *)key;
        if ([k isEqualToString:@"SerialNumber"])    return CFSTR("Z2A1IN0GHO5T");
        if ([k isEqualToString:@"UniqueDeviceID"])  return CFSTR("00008020-001A2B3C4D5E6F80");
    }
    return %orig;
}

%hook UIDevice
- (NSUUID *)identifierForVendor {
    static NSUUID *fake = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fake = [[NSUUID alloc] initWithUUIDString:@"7A1B2C3D-4E5F-6A7B-8C9D-0E1F2A3B4C5D"];
    });
    return fake;
}
%end

%ctor {
    // صامت — لا شيء
}
