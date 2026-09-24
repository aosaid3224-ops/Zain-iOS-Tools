/*
 * NaverSeriesBypass v3.3 - Professional Device Ban Bypass
 * FIXED: All logical errors, misleading stats, and connection issues resolved
 * Target: iPhone 8 (iOS 16) -> Spoof to iPhone 15 Pro (iOS 18.3.1)
 */

#import <substrate.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <AdSupport/AdSupport.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <Security/Security.h>

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - sysctl Constants (for compatibility)
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
// MARK: - Configuration (Read from Preferences)
// ═══════════════════════════════════════════════════════════════════════════════

static BOOL isEnabled = YES;
static BOOL spoofIDFV = YES;
static BOOL spoofIDFA = YES;
static BOOL spoofHeaders = YES;
static BOOL spoofDevice = YES;
static BOOL spoofNetwork = YES;
static BOOL blockKeychain = YES;
static BOOL jbBypass = YES;

// Target spoof identity: iPhone 15 Pro, iOS 18.3.1
static NSString *const kSpoofModel = @"iPhone16,1";
static NSString *const kSpoofLocalizedModel = @"iPhone";
static NSString *const kSpoofSystemVersion = @"18.3.1";
static NSString *const kSpoofSystemName = @"iOS";
static NSString *const kSpoofDeviceName = @"iPhone";
static NSString *const kSpoofKernelVersion = @"Darwin Kernel Version 22.6.0: Wed Jun 28 20:10:54 PDT 2023; root:xnu-8796.142.1~1/RELEASE_ARM64_T8120";

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Safe File Paths (NOT /tmp - sandboxed apps can't write there reliably)
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

static void NBIncrementStat(NSString *key) {
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
// MARK: - Heartbeat System (Proof of Injection)
// ═══════════════════════════════════════════════════════════════════════════════

static dispatch_source_t heartbeatTimer = nil;

static void writeHeartbeat() {
    if (!isEnabled) return;
    NSDictionary *heartbeat = @{
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"bundleId": [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown",
        @"processName": [[NSProcessInfo processInfo] processName] ?: @"unknown",
        @"pid": @([[NSProcessInfo processInfo] processIdentifier]),
        @"active": @(isEnabled),
        @"version": @"3.3",
    };
    NSString *path = heartbeatPath();
    BOOL ok = [heartbeat writeToFile:path atomically:YES];
    if (!ok) {
        // Fallback: try NSTemporaryDirectory
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"naverseriesbypass_heartbeat.plist"];
        [heartbeat writeToFile:tmp atomically:YES];
    }
}

static void writeStats() {
    if (!isEnabled) return;
    NSDictionary *copy = NBGetStatsCopy();
    NSMutableDictionary *statsDict = [copy mutableCopy] ?: [NSMutableDictionary dictionary];
    statsDict[@"lastUpdate"] = @([[NSDate date] timeIntervalSince1970]);
    statsDict[@"bundleId"] = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    statsDict[@"processName"] = [[NSProcessInfo processInfo] processName] ?: @"unknown";
    NSString *path = statsPath();
    BOOL ok = [statsDict writeToFile:path atomically:YES];
    if (!ok) {
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"naverseriesbypass_stats.plist"];
        [statsDict writeToFile:tmp atomically:YES];
    }
}

static void startHeartbeat() {
    if (heartbeatTimer) return; // Already running
    heartbeatTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    dispatch_source_set_timer(heartbeatTimer, DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC, 0.5 * NSEC_PER_SEC);
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
// MARK: - Keychain Cleanup (Remove old ban data on startup)
// ═══════════════════════════════════════════════════════════════════════════════

static void cleanupKeychain() {
    if (!blockKeychain) return;

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
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Device Identity Spoofing
// ═══════════════════════════════════════════════════════════════════════════════

%hook UIDevice

- (NSUUID *)identifierForVendor {
    if (!isEnabled || !spoofIDFV) return %orig;
    NBIncrementStat(@"idfv");
    return [[NSUUID alloc] initWithUUIDString:generateFakeIDFV()];
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
    return [[NSUUID alloc] initWithUUIDString:generateFakeIDFA()];
}

- (BOOL)isAdvertisingTrackingEnabled {
    if (!isEnabled || !spoofIDFA) return %orig;
    NBIncrementStat(@"tracking");
    return NO;
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - uname / sysctl Spoofing
// ═══════════════════════════════════════════════════════════════════════════════

static int (*orig_uname)(struct utsname *);
static int hook_uname(struct utsname *value) {
    if (!isEnabled || !spoofDevice) return orig_uname(value);
    int ret = orig_uname(value);
    if (ret == 0 && value) {
        strncpy(value->machine, [kSpoofModel UTF8String], sizeof(value->machine) - 1);
        value->machine[sizeof(value->machine) - 1] = '\0';
        strncpy(value->version, [kSpoofKernelVersion UTF8String], sizeof(value->version) - 1);
        value->version[sizeof(value->version) - 1] = '\0';
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
// MARK: - Keychain Blocking (Targeted - only Naver Series)
// ═══════════════════════════════════════════════════════════════════════════════

static BOOL isNaverKeychainItem(NSDictionary *dict) {
    NSString *service = dict[(__bridge NSString *)kSecAttrService];
    NSString *account = dict[(__bridge NSString *)kSecAttrAccount];
    NSString *group = dict[(__bridge NSString *)kSecAttrAccessGroup];

    NSArray *naverKeywords = @[@"naver", @"series", @"NaverBooks", @"nhncorp"];
    for (NSString *kw in naverKeywords) {
        if ([service containsString:kw]) return YES;
        if ([account containsString:kw]) return YES;
        if ([group containsString:kw]) return YES;
    }
    return NO;
}

%hookf(OSStatus, SecItemAdd, CFDictionaryRef attributes, CFTypeRef *result) {
    if (!isEnabled || !blockKeychain) return %orig;
    if (isNaverKeychainItem((__bridge NSDictionary *)attributes)) {
        NBIncrementStat(@"keychain_blocked");
        if (result) *result = NULL;
        return errSecSuccess;
    }
    return %orig;
}

%hookf(OSStatus, SecItemUpdate, CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (!isEnabled || !blockKeychain) return %orig;
    if (isNaverKeychainItem((__bridge NSDictionary *)query)) {
        NBIncrementStat(@"keychain_blocked");
        return errSecSuccess;
    }
    return %orig;
}

%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef query, CFTypeRef *result) {
    if (!isEnabled || !blockKeychain) return %orig;
    if (isNaverKeychainItem((__bridge NSDictionary *)query)) {
        NBIncrementStat(@"keychain_blocked");
        return errSecItemNotFound;
    }
    return %orig;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Constructor
// ═══════════════════════════════════════════════════════════════════════════════

%ctor {
    @autoreleasepool {
        nbStatsQueue = dispatch_queue_create("com.aosaid.naverseriesbypass.stats", DISPATCH_QUEUE_SERIAL);
        loadPreferences();

        // Hook C functions
        MSHookFunction((void *)uname, (void *)hook_uname, (void **)&orig_uname);
        MSHookFunction((void *)sysctl, (void *)hook_sysctl, (void **)&orig_sysctl);

        // Cleanup old keychain
        cleanupKeychain();

        // Start heartbeat
        startHeartbeat();
        writeHeartbeat();
        writeStats();

        // Register for preference changes
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)loadPreferences,
            CFSTR("com.aosaid.naverseriesbypass/preferences.changed"),
            NULL,
            CFNotificationSuspensionBehaviorCoalesce
        );
    }
}
