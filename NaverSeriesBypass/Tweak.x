/*
 * NaverSeriesBypass v3.3.10 - updated developer attribution
 * Fixed: %hookf replaced with MSHookFunction, delayed keychain cleanup,
 *        removed UIKit from filter, fixed buffer overflows
 */

#import <substrate.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <AdSupport/AdSupport.h>
#import <Security/Security.h>
#include <dlfcn.h>
#include <notify.h>

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - sysctl Constants
// ═══════════════════════════════════════════════════════════════════════════════

#ifndef CTL_HW
#define CTL_HW 6
#endif
#ifndef HW_MACHINE
#define HW_MACHINE 1
#endif
#ifndef HW_MODEL
#define HW_MODEL 2
#endif
#ifndef HW_MACHINE_ARCH
#define HW_MACHINE_ARCH 12
#endif

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Preference Constants
// ═══════════════════════════════════════════════════════════════════════════════

static NSString *const kPrefsDomain = @"com.aosaid.naverseriesbypass";
static NSString *const kKeyEnabled = @"Enabled";
static NSString *const kKeySpoofDevice = @"SpoofDevice";
static NSString *const kKeySpoofIDFV = @"SpoofIDFV";
static NSString *const kKeySpoofIDFA = @"SpoofIDFA";
static NSString *const kKeySpoofHeaders = @"SpoofHeaders";
static NSString *const kKeySpoofNetwork = @"SpoofNetwork";
static NSString *const kKeyBlockKeychain = @"BlockKeychain";
static NSString *const kKeyJBBypass = @"JBBypass";

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Configuration
// ═══════════════════════════════════════════════════════════════════════════════

static BOOL isEnabled = YES;
static BOOL spoofIDFV = YES;
static BOOL spoofIDFA = YES;
static BOOL spoofHeaders = YES;
static BOOL spoofDevice = YES;
static BOOL spoofNetwork = YES;
static BOOL blockKeychain = YES;
static BOOL jbBypass = YES;

static NSString *const kSpoofModel = @"iPhone16,1";
static NSString *const kSpoofLocalizedModel = @"iPhone";
static NSString *const kSpoofSystemVersion = @"18.3.1";
static NSString *const kSpoofSystemName = @"iOS";
static NSString *const kSpoofDeviceName = @"iPhone";

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Safe File Paths
// ═══════════════════════════════════════════════════════════════════════════════

static NSString *heartbeatPath() {
    return [@"/var/mobile/Library/Preferences" stringByAppendingPathComponent:@"com.aosaid.naverseriesbypass.heartbeat.plist"];
}

static NSString *statsPath() {
    return [@"/var/mobile/Library/Preferences" stringByAppendingPathComponent:@"com.aosaid.naverseriesbypass.stats.plist"];
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Statistics (Thread-Safe)
// ═══════════════════════════════════════════════════════════════════════════════

static NSMutableDictionary *stats = nil;
static dispatch_queue_t nbStatsQueue = nil;

// ===== نظام سجل الأحداث — حلقي عبر notify_set_state (يعبر الـ sandbox) =====
// كل حدث = uint64: [timestamp:32 | code:16 | detail:16] في 32 خانة دوّارة.
#define NB_LOG_SLOTS 32

static void NBLogEvent(uint16_t code, uint16_t detail) {
    static int countTok = 0;
    if (!countTok) notify_register_check("com.aosaid.nsb.log.count", &countTok);
    uint64_t count = 0;
    notify_get_state(countTok, &count);
    count++;
    notify_set_state(countTok, count);

    char name[64];
    snprintf(name, sizeof(name), "com.aosaid.nsb.log.%llu", (unsigned long long)(count % NB_LOG_SLOTS));
    int slotTok = 0;
    notify_register_check(name, &slotTok);
    uint32_t tsec = (uint32_t)[[NSDate date] timeIntervalSince1970];
    uint64_t packed = ((uint64_t)tsec << 32) | ((uint64_t)code << 16) | (uint64_t)detail;
    notify_set_state(slotTok, packed);
}

// ربط تلقائي: كل مفتاح NBIncrementStat له كود حدث — مكان واحد يغطي كل الـ ~30 hook
static uint16_t NBEventCodeForKey(NSString *key) {
    NSDictionary *map = @{
        @"uname":@1, @"sysctl":@2, @"idfa":@3, @"tracking":@4, @"idfv":@5,
        @"model":@6, @"systemVersion":@7, @"deviceName":@8, @"localizedModel":@9,
        @"systemName":@10, @"idiom":@11, @"osVersionString":@12, @"osVersion":@13,
        @"processorCount":@14, @"activeProcessorCount":@15, @"physicalMemory":@16,
        @"screenBounds":@17, @"screenScale":@18, @"nativeScale":@19, @"nativeBounds":@20,
        @"header_device":@21, @"header_adid":@22, @"header_ua":@23,
        @"header_model":@24, @"header_os":@25, @"dataTask":@26,
        @"keychain_add_blocked":@27, @"keychain_update_blocked":@28, @"keychain_copy_blocked":@29
    };
    return (uint16_t)[map[key] unsignedShortValue];
}

// ناقل قيم الهوية المموّهة إلى الـ Dashboard — 8 بايت/خانة، خانتان = 16 حرف.
// بلا تكرار مصدر: القيمة تأتي من ثوابت التويك نفسها.
static void NBMirrorString(const char *slot, NSString *value) {
    const char *u = value.UTF8String;
    size_t len = u ? strlen(u) : 0;
    for (int part = 0; part < 2; part++) {
        char name[64];
        snprintf(name, sizeof(name), "com.aosaid.nsb.meta.%s.%d", slot, part);
        int tok = 0;
        notify_register_check(name, &tok);
        uint64_t packed = 0;
        for (int i = 0; i < 8; i++) {
            size_t idx = (size_t)part * 8 + (size_t)i;
            if (idx < len) packed |= ((uint64_t)(unsigned char)u[idx]) << (8 * i);
        }
        notify_set_state(tok, packed);
    }
}

static void NBIncrementStat(NSString *key) {
    // Mirror to notify state immediately — CFPreferences plist writes from a
    // sandboxed app are silently dropped by cfprefsd, so the dashboard can
    // only see counters through the notify channel.
    int stoken = 0;
    NSString *sname = [@"com.aosaid.nsb.stat." stringByAppendingString:key];
    if (notify_register_check(sname.UTF8String, &stoken) == NOTIFY_STATUS_OK) {
        uint64_t cur = 0;
        notify_get_state(stoken, &cur);
        notify_set_state(stoken, cur + 1);
    }

    // سجل الأحداث: مفاتيح الضجيج العالي تُعدّ فقط — الحلقة للأحداث المهمة
    static NSSet *quietKeys = nil;
    static dispatch_once_t qOnce;
    dispatch_once(&qOnce, ^{
        quietKeys = [NSSet setWithArray:@[@"idiom", @"systemName", @"localizedModel",
            @"screenBounds", @"screenScale", @"nativeScale", @"nativeBounds",
            @"processorCount", @"activeProcessorCount", @"physicalMemory",
            @"osVersionString", @"osVersion", @"tracking"]];
    });
    if (![quietKeys containsObject:key]) {
        uint16_t evCode = NBEventCodeForKey(key);
        if (evCode) NBLogEvent(evCode, 0);
    }

    dispatch_async(nbStatsQueue, ^{
        if (!stats) stats = [NSMutableDictionary dictionary];
        @synchronized(stats) {
            NSNumber *val = stats[key] ?: @0;
            stats[key] = @(val.integerValue + 1);
        }
    });
}

static NSDictionary* NBGetStatsCopy() {
    __block NSDictionary *copy = nil;
    dispatch_sync(nbStatsQueue, ^{
        @synchronized(stats) {
            copy = [stats copy];
        }
    });
    return copy ?: @{};
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Preference Loader
// ═══════════════════════════════════════════════════════════════════════════════

static void loadPreferences() {
    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] persistentDomainForName:kPrefsDomain];
    if (!prefs) prefs = @{};

    isEnabled = prefs[kKeyEnabled] == nil ? YES : [prefs[kKeyEnabled] boolValue];
    spoofDevice = prefs[kKeySpoofDevice] == nil ? YES : [prefs[kKeySpoofDevice] boolValue];
    spoofIDFV = prefs[kKeySpoofIDFV] == nil ? YES : [prefs[kKeySpoofIDFV] boolValue];
    spoofIDFA = prefs[kKeySpoofIDFA] == nil ? YES : [prefs[kKeySpoofIDFA] boolValue];
    spoofHeaders = prefs[kKeySpoofHeaders] == nil ? YES : [prefs[kKeySpoofHeaders] boolValue];
    spoofNetwork = prefs[kKeySpoofNetwork] == nil ? YES : [prefs[kKeySpoofNetwork] boolValue];
    blockKeychain = prefs[kKeyBlockKeychain] == nil ? YES : [prefs[kKeyBlockKeychain] boolValue];
    jbBypass = prefs[kKeyJBBypass] == nil ? YES : [prefs[kKeyJBBypass] boolValue];
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Persistent ID Generation
// ═══════════════════════════════════════════════════════════════════════════════

static NSString *persistentID(NSString *prefix) {
    NSString *key = [NSString stringWithFormat:@"%@.%@", kPrefsDomain, prefix];
    NSString *uuid = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    if (!uuid) {
        uuid = [[NSUUID UUID] UUIDString];
        [[NSUserDefaults standardUserDefaults] setObject:uuid forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return uuid;
}

static NSString *generateFakeIDFV() { return persistentID(@"idfv_v3"); }
static NSString *generateFakeIDFA() { return persistentID(@"idfa_v3"); }
static NSString *generateFakeDeviceID() { return persistentID(@"device_v3"); }
static NSString *generateFakeADID() { return persistentID(@"adid_v3"); }

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Heartbeat System (FIXED: Reduced frequency, background queue)
// ═══════════════════════════════════════════════════════════════════════════════

static dispatch_source_t heartbeatTimer = nil;

// CRASH/STATUS FIX: Direct writeToFile to /var/mobile/Library/Preferences is
// DENIED by the app sandbox (returns NO silently) - that's why the dashboard
// showed "غير محقن". CFPreferences routes through cfprefsd (unsandboxed daemon)
// so the file appears at the exact same path the dashboard reads.
// Each key is written as a TOP-LEVEL app value so the plist file structure
// matches what the dashboard expects: {timestamp:..., pid:..., ...}
static void CFPreferencesWriteDictFlat(NSDictionary *dict, CFStringRef domain) {
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        BOOL plistSafe = [obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]] ||
                         [obj isKindOfClass:[NSArray class]]  || [obj isKindOfClass:[NSDictionary class]] ||
                         [obj isKindOfClass:[NSDate class]]   || [obj isKindOfClass:[NSData class]];
        if (plistSafe) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)obj, domain);
        }
    }];
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

// LIVE SIGNAL: Darwin notifications are mach-port messages via notifyd -
// they work between ANY two processes (even sandboxed) with zero file I/O.
// cfprefsd silently DROPS writes to foreign domains from sandboxed apps,
// which is why no heartbeat file ever appeared. This channel cannot fail.
static void postDarwinHeartbeat(void) {
    // Payload channel: notify_set_state crosses sandbox boundaries (uint64).
    // Packed: [timestamp(32) | pid(32)] — the dashboard decodes both.
    int token = 0;
    notify_register_check("com.aosaid.nsb.alive", &token);
    uint32_t tsec = (uint32_t)[[NSDate date] timeIntervalSince1970];
    uint32_t pid  = (uint32_t)[[NSProcessInfo processInfo] processIdentifier];
    notify_set_state(token, ((uint64_t)tsec << 32) | (uint64_t)pid);

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.aosaid.nsb.alive"),
        NULL, NULL, true);
}

static void writeHeartbeat() {
    if (!isEnabled) return;
    postDarwinHeartbeat();
    @try {
        NSDictionary *heartbeat = @{
            @"timestamp": @([[NSDate date] timeIntervalSince1970]),
            @"bundleId": [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown",
            @"processName": [[NSProcessInfo processInfo] processName] ?: @"unknown",
            @"pid": @([[NSProcessInfo processInfo] processIdentifier]),
            @"active": @(isEnabled),
            @"version": @"3.3.10",
        };
        CFPreferencesWriteDictFlat(heartbeat, CFSTR("com.aosaid.naverseriesbypass.heartbeat"));
    } @catch (NSException *e) {
        // Silent fail - don't crash
    }
}

static void writeStats() {
    if (!isEnabled) return;
    @try {
        NSDictionary *copy = NBGetStatsCopy();
        NSMutableDictionary *statsDict = [copy mutableCopy] ?: [NSMutableDictionary dictionary];
        statsDict[@"lastUpdate"] = @([[NSDate date] timeIntervalSince1970]);
        statsDict[@"bundleId"] = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
        // CONTRACT FIX: the dashboard decides "injected" via hasInjectionMarker =
        // savedStats[@"loaded"] || savedStats[@"processBundle"]. These keys were
        // NEVER written by the tweak, so the dashboard always fell through to
        // "غير محقن" even when injection was fully working. Write them.
        statsDict[@"loaded"] = @YES;
        statsDict[@"processBundle"] = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
        statsDict[@"processName"] = [[NSProcessInfo processInfo] processName] ?: @"unknown";
        statsDict[@"lastEvent"] = @"heartbeat";
        // Same sandbox fix: write via cfprefsd so the dashboard can read the file
        CFPreferencesWriteDictFlat(statsDict, CFSTR("com.aosaid.naverseriesbypass.stats"));
    } @catch (NSException *e) {
        // Silent fail
    }
}

static void startHeartbeat() {
    if (heartbeatTimer) return;
    // FIXED: Reduced to 10 seconds, use background queue
    heartbeatTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    // Dashboard threshold is age < 10s — write every 5s to guarantee freshness margin
    dispatch_source_set_timer(heartbeatTimer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5.0 * NSEC_PER_SEC, 1.0 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(heartbeatTimer, ^{
        writeHeartbeat();
        writeStats();
    });
    dispatch_resume(heartbeatTimer);
}

static void stopHeartbeat() {
    if (heartbeatTimer) {
        dispatch_source_cancel(heartbeatTimer);
        heartbeatTimer = nil;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Keychain Cleanup (FIXED: Delayed, wrapped in try-catch)
// ═══════════════════════════════════════════════════════════════════════════════

static void cleanupKeychain() {
    if (!blockKeychain) return;
    @try {
        NSArray *servicesToDelete = @[@"com.nhncorp.NaverBooks", @"com.naver.series", @"com.naver.books"];
        NSArray *secClasses = @[
            (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecClassInternetPassword,
        ];

        for (NSString *service in servicesToDelete) {
            for (id secClass in secClasses) {
                NSDictionary *query = @{
                    (__bridge id)kSecClass: secClass,
                    (__bridge id)kSecAttrService: service
                };
                SecItemDelete((__bridge CFDictionaryRef)query);
            }
        }
    } @catch (NSException *e) {
        // Silent fail
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Device Identity Spoofing
// ═══════════════════════════════════════════════════════════════════════════════

%hook UIDevice

- (NSUUID *)identifierForVendor {
    if (!isEnabled || !spoofIDFV) return %orig;
    NBIncrementStat(@"idfv");
    NSString *uuid = generateFakeIDFV();
    NSUUID *result = [[NSUUID alloc] initWithUUIDString:uuid];
    return result ?: %orig;
}

- (NSString *)name {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"deviceName");
    return kSpoofDeviceName;
}

- (NSString *)model {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"model");
    return kSpoofModel;
}

- (NSString *)localizedModel {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"localizedModel");
    return kSpoofLocalizedModel;
}

- (NSString *)systemVersion {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"systemVersion");
    return kSpoofSystemVersion;
}

- (NSString *)systemName {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"systemName");
    return kSpoofSystemName;
}

- (UIUserInterfaceIdiom)userInterfaceIdiom {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"idiom");
    return UIUserInterfaceIdiomPhone;
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - IDFA Spoofing
// ═══════════════════════════════════════════════════════════════════════════════

%hook ASIdentifierManager

- (NSUUID *)advertisingIdentifier {
    if (!isEnabled || !spoofIDFA) return %orig;
    NBIncrementStat(@"idfa");
    NSString *uuid = generateFakeIDFA();
    NSUUID *result = [[NSUUID alloc] initWithUUIDString:uuid];
    return result ?: %orig;
}

- (BOOL)isAdvertisingTrackingEnabled {
    if (!isEnabled || !spoofIDFA) return %orig;
    NBIncrementStat(@"tracking");
    return NO;
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - uname / sysctl Spoofing (FIXED: Safe buffer handling)
// ═══════════════════════════════════════════════════════════════════════════════

static int (*orig_uname)(struct utsname *);
static int hook_uname(struct utsname *value) {
    if (!isEnabled || !spoofDevice) return orig_uname(value);
    int ret = orig_uname(value);
    if (ret == 0 && value) {
        // FIXED: Use snprintf for safety
        snprintf(value->machine, sizeof(value->machine), "%s", [kSpoofModel UTF8String]);
        // FIXED: Shortened kernel version to fit buffer
        snprintf(value->version, sizeof(value->version), "Darwin Kernel Version 22.6.0");
        NBIncrementStat(@"uname");
    }
    return ret;
}

static int (*orig_sysctl)(const int *, u_int, void *, size_t *, const void *, size_t);
static int hook_sysctl(const int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen) {
    if (!isEnabled || !spoofDevice) return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (ret == 0 && oldp && oldlenp && namelen >= 2 && name[0] == CTL_HW) {
        const char *fake = NULL;
        if (name[1] == HW_MACHINE) fake = [kSpoofModel UTF8String];
        else if (name[1] == HW_MODEL) fake = [kSpoofModel UTF8String];
        else if (name[1] == HW_MACHINE_ARCH) fake = "arm64e";

        if (fake) {
            size_t len = strlen(fake) + 1;
            if (*oldlenp >= len) {
                strcpy((char *)oldp, fake);
                *oldlenp = len;
                NBIncrementStat(@"sysctl");
            }
        }
    }
    return ret;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - NSProcessInfo Spoofing
// ═══════════════════════════════════════════════════════════════════════════════

%hook NSProcessInfo

- (NSString *)operatingSystemVersionString {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"osVersionString");
    return @"Version 18.3.1 (Build 22D72)";
}

- (NSOperatingSystemVersion)operatingSystemVersion {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"osVersion");
    return (NSOperatingSystemVersion){18, 3, 1};
}

- (NSUInteger)processorCount {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"processorCount");
    return 6;
}

- (NSUInteger)activeProcessorCount {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"activeProcessorCount");
    return 6;
}

- (unsigned long long)physicalMemory {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"physicalMemory");
    return 8589934592ULL;
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - UIScreen Spoofing
// ═══════════════════════════════════════════════════════════════════════════════

%hook UIScreen

- (CGRect)bounds {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"screenBounds");
    return CGRectMake(0, 0, 393, 852);
}

- (CGFloat)scale {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"screenScale");
    return 3.0;
}

- (CGFloat)nativeScale {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"nativeScale");
    return 3.0;
}

- (CGRect)nativeBounds {
    if (!isEnabled || !spoofDevice) return %orig;
    NBIncrementStat(@"nativeBounds");
    return CGRectMake(0, 0, 1179, 2556);
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Network Headers Spoofing
// ═══════════════════════════════════════════════════════════════════════════════

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (!isEnabled || !spoofHeaders) {
        %orig(value, field);
        return;
    }
    NSString *lower = [field lowercaseString];
    if ([lower isEqualToString:@"x-consumer-id"] || [lower isEqualToString:@"x-device-id"]) {
        NBIncrementStat(@"header_device");
        %orig(generateFakeDeviceID(), field);
    } else if ([lower isEqualToString:@"x-adid"] || [lower isEqualToString:@"x-advertising-id"]) {
        NBIncrementStat(@"header_adid");
        %orig(generateFakeADID(), field);
    } else if ([lower isEqualToString:@"user-agent"]) {
        NBIncrementStat(@"header_ua");
        NSString *fake = [NSString stringWithFormat:@"NaverSeries/1.0 (iPhone; CPU iPhone OS %@ like Mac OS X) AppleWebKit/605.1.15", kSpoofSystemVersion];
        %orig(fake, field);
    } else if ([lower isEqualToString:@"x-device-model"]) {
        NBIncrementStat(@"header_model");
        %orig(kSpoofModel, field);
    } else if ([lower isEqualToString:@"x-os-version"]) {
        NBIncrementStat(@"header_os");
        %orig(kSpoofSystemVersion, field);
    } else {
        %orig(value, field);
    }
}

%end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (!isEnabled || !spoofHeaders) return %orig;
    NSMutableURLRequest *mutable = [request mutableCopy];
    [mutable setValue:generateFakeDeviceID() forHTTPHeaderField:@"X-Consumer-Id"];
    [mutable setValue:generateFakeADID() forHTTPHeaderField:@"X-Adid"];
    [mutable setValue:kSpoofModel forHTTPHeaderField:@"X-Device-Model"];
    [mutable setValue:kSpoofSystemVersion forHTTPHeaderField:@"X-OS-Version"];
    NSString *ua = [NSString stringWithFormat:@"NaverSeries/1.0 (iPhone; CPU iPhone OS %@ like Mac OS X)", kSpoofSystemVersion];
    [mutable setValue:ua forHTTPHeaderField:@"User-Agent"];
    NBIncrementStat(@"dataTask");
    return %orig(mutable);
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Keychain Blocking (FIXED: Using MSHookFunction instead of %hookf)
// ═══════════════════════════════════════════════════════════════════════════════

static NSString *NBStringFromAttr(id value) {
    if (!value) return nil;
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value isKindOfClass:[NSData class]]) {
        NSString *s = [[NSString alloc] initWithData:(NSData *)value encoding:NSUTF8StringEncoding];
        if (s) return s;
        return [[NSString alloc] initWithData:(NSData *)value encoding:NSASCIIStringEncoding];
    }
    return [value description];
}

static BOOL NBStringMatches(NSString *s, NSArray *keywords) {
    if (!s) return NO;
    for (NSString *kw in keywords) {
        if ([s rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL isNaverKeychainItem(NSDictionary *dict) {
    // CRASH FIX: kSecAttrService/kSecAttrAccount/kSecAttrAccessGroup can be
    // CFDataRef (NSConcreteMutableData) not NSString - must convert before
    // calling NSString methods. This was the exact SIGABRT in crash log
    // incident 85457303 on queue com.appsflyer.serial.
    NSString *service = NBStringFromAttr(dict[(__bridge NSString *)kSecAttrService]);
    NSString *account = NBStringFromAttr(dict[(__bridge NSString *)kSecAttrAccount]);
    NSString *group   = NBStringFromAttr(dict[(__bridge NSString *)kSecAttrAccessGroup]);

    static NSArray *naverKeywords = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        naverKeywords = @[@"naver", @"series", @"NaverBooks", @"nhncorp", @"nid"];
    });

    return NBStringMatches(service, naverKeywords)
        || NBStringMatches(account, naverKeywords)
        || NBStringMatches(group, naverKeywords);
}

// FIXED: Using function pointers + MSHookFunction instead of %hookf
static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus hook_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (!isEnabled || !blockKeychain) return orig_SecItemAdd(attributes, result);
    if (isNaverKeychainItem((__bridge NSDictionary *)attributes)) {
        NBIncrementStat(@"keychain_add_blocked");
        if (result) *result = NULL;
        return errSecSuccess;
    }
    return orig_SecItemAdd(attributes, result);
}

static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus hook_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (!isEnabled || !blockKeychain) return orig_SecItemUpdate(query, attributesToUpdate);
    if (isNaverKeychainItem((__bridge NSDictionary *)query)) {
        NBIncrementStat(@"keychain_update_blocked");
        return errSecSuccess;
    }
    return orig_SecItemUpdate(query, attributesToUpdate);
}

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus hook_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (!isEnabled || !blockKeychain) return orig_SecItemCopyMatching(query, result);
    if (isNaverKeychainItem((__bridge NSDictionary *)query)) {
        NBIncrementStat(@"keychain_copy_blocked");
        return errSecItemNotFound;
    }
    return orig_SecItemCopyMatching(query, result);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Constructor (FIXED: Delayed initialization, safe hooks)
// ═══════════════════════════════════════════════════════════════════════════════

%ctor {
    @autoreleasepool {
        nbStatsQueue = dispatch_queue_create("com.aosaid.naverseriesbypass.stats", DISPATCH_QUEUE_SERIAL);
        loadPreferences();

        // Hook C functions
        MSHookFunction((void *)uname, (void *)hook_uname, (void **)&orig_uname);
        MSHookFunction((void *)sysctl, (void *)hook_sysctl, (void **)&orig_sysctl);

        // FIXED: Hook Security framework functions using MSHookFunction
        void *secItemAddPtr = dlsym(RTLD_DEFAULT, "SecItemAdd");
        void *secItemUpdatePtr = dlsym(RTLD_DEFAULT, "SecItemUpdate");
        void *secItemCopyMatchingPtr = dlsym(RTLD_DEFAULT, "SecItemCopyMatching");

        if (secItemAddPtr) {
            MSHookFunction(secItemAddPtr, (void *)hook_SecItemAdd, (void **)&orig_SecItemAdd);
        }
        if (secItemUpdatePtr) {
            MSHookFunction(secItemUpdatePtr, (void *)hook_SecItemUpdate, (void **)&orig_SecItemUpdate);
        }
        if (secItemCopyMatchingPtr) {
            MSHookFunction(secItemCopyMatchingPtr, (void *)hook_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching);
        }

        // FIXED: Delay keychain cleanup to avoid crash on locked keychain
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            cleanupKeychain();
        });

        // FIXED: Delay heartbeat start
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            startHeartbeat();
        });

        writeHeartbeat();
        writeStats();

        // Register for preference changes
        static CFNotificationCallback nbPrefsCallback = (CFNotificationCallback)loadPreferences;
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            nbPrefsCallback,
            CFSTR("com.aosaid.naverseriesbypass/preferences.changed"),
            NULL,
            CFNotificationSuspensionBehaviorCoalesce
        );
    }

    // نقل هوية التمويه للعرض الصادق في السجل
    NBMirrorString("model", kSpoofModel);
    NBMirrorString("os", kSpoofSystemVersion);

    // حدث إقلاع التويك — أول سطر في سجل الأحداث
    NBLogEvent(32, 0);
}
