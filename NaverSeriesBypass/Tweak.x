/*
 * NaverSeriesBypass v3.1 - Professional Device Ban Bypass
 * Target: iPhone 8 (iOS 16) -> Spoof to iPhone 15 Pro (iOS 18.3.1)
 * Author: aosaid3224-ops (Enhanced by Consultant)
 * 
 * This tweak performs COMPLETE device identity spoofing to bypass server-side device bans.
 * It changes ALL device identifiers that Naver Series uses for fingerprinting.
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
static NSString *const kSpoofUserAgent = @"iPhone16,1/18.3.1";
static NSString *const kSpoofKernelVersion = @"Darwin Kernel Version 22.6.0: Wed Jun 28 20:10:54 PDT 2023; root:xnu-8796.142.1~1/RELEASE_ARM64_T8120";

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Statistics & Logging
// ═══════════════════════════════════════════════════════════════════════════════

static NSMutableDictionary *stats = nil;
static dispatch_queue_t nbStatsQueue = nil;

#define NBLog(fmt, ...) NSLog(@"[NaverBypass] " fmt, ##__VA_ARGS__)

static void NBIncrementStat(NSString *key) {
    dispatch_async(nbStatsQueue, ^{
        if (!stats) stats = [NSMutableDictionary dictionary];
        NSNumber *val = stats[key] ?: @0;
        stats[key] = @(val.integerValue + 1);
    });
}

static void NBLogStats() {
    dispatch_async(nbStatsQueue, ^{
        NBLog(@"=== STATS ===");
        [stats enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            NBLog(@"  %@: %@", k, v);
        }];
    });
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

    NBLog(@"Preferences loaded: Enabled=%d Device=%d IDFV=%d IDFA=%d Headers=%d Network=%d Keychain=%d JB=%d",
          isEnabled, spoofDevice, spoofIDFV, spoofIDFA, spoofHeaders, spoofNetwork, blockKeychain, jbBypass);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Persistent ID Generation (Deterministic per-app-install)
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

static NSString *generateFakeIDFV() {
    return persistentID(@"idfv_v3");
}

static NSString *generateFakeIDFA() {
    return persistentID(@"idfa_v3");
}

static NSString *generateFakeDeviceID() {
    return persistentID(@"device_v3");
}

static NSString *generateFakeADID() {
    return persistentID(@"adid_v3");
}

static NSString *generateFakeUUID() {
    return persistentID(@"uuid_v3");
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Keychain Cleanup (CRITICAL for Device Ban)
// ═══════════════════════════════════════════════════════════════════════════════

static void cleanupKeychain() {
    if (!blockKeychain) return;

    NBLog(@"[CLEANUP] Starting Keychain cleanup...");

    // Delete ALL keychain items for Naver Series
    NSArray *secClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];

    for (id secClass in secClasses) {
        NSDictionary *query = @{
            (__bridge id)kSecClass: secClass,
            (__bridge id)kSecAttrService: @"com.nhncorp.NaverBooks"
        };
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecSuccess) {
            NBLog(@"[CLEANUP] Deleted keychain items for class %@", secClass);
        }

        // Also try with com.naver.series
        query = @{
            (__bridge id)kSecClass: secClass,
            (__bridge id)kSecAttrService: @"com.naver.series"
        };
        status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecSuccess) {
            NBLog(@"[CLEANUP] Deleted keychain items for com.naver.series");
        }
    }

    // Delete ALL keychain items (nuclear option - be careful)
    // Uncomment if needed:
    /*
    for (id secClass in secClasses) {
        NSDictionary *query = @{
            (__bridge id)kSecClass: secClass
        };
        SecItemDelete((__bridge CFDictionaryRef)query);
    }
    */

    NBLog(@"[CLEANUP] Keychain cleanup complete");
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Device Identity Spoofing Engine
// ═══════════════════════════════════════════════════════════════════════════════

%hook UIDevice

- (NSUUID *)identifierForVendor {
    if (!isEnabled || !spoofIDFV) return %orig;
    NSString *fake = generateFakeIDFV();
    NSUUID *orig = %orig;
    NBLog(@"[SPOOF] identifierForVendor: %@ -> %@", orig, fake);
    NBIncrementStat(@"idfv");
    return [[NSUUID alloc] initWithUUIDString:fake];
}

- (NSString *)name {
    if (!isEnabled || !spoofDevice) return %orig;
    NSString *orig = %orig;
    NBLog(@"[SPOOF] deviceName: %@ -> %@", orig, kSpoofDeviceName);
    NBIncrementStat(@"deviceName");
    return kSpoofDeviceName;
}

- (NSString *)model {
    if (!isEnabled || !spoofDevice) return %orig;
    NSString *orig = %orig;
    NBLog(@"[SPOOF] model: %@ -> %@", orig, kSpoofModel);
    NBIncrementStat(@"model");
    return kSpoofModel;
}

- (NSString *)localizedModel {
    if (!isEnabled || !spoofDevice) return %orig;
    NSString *orig = %orig;
    NBLog(@"[SPOOF] localizedModel: %@ -> %@", orig, kSpoofLocalizedModel);
    NBIncrementStat(@"localizedModel");
    return kSpoofLocalizedModel;
}

- (NSString *)systemVersion {
    if (!isEnabled || !spoofDevice) return %orig;
    NSString *orig = %orig;
    NBLog(@"[SPOOF] systemVersion: %@ -> %@", orig, kSpoofSystemVersion);
    NBIncrementStat(@"systemVersion");
    return kSpoofSystemVersion;
}

- (NSString *)systemName {
    if (!isEnabled || !spoofDevice) return %orig;
    NSString *orig = %orig;
    NBLog(@"[SPOOF] systemName: %@ -> %@", orig, kSpoofSystemName);
    NBIncrementStat(@"systemName");
    return kSpoofSystemName;
}

- (UIUserInterfaceIdiom)userInterfaceIdiom {
    if (!isEnabled || !spoofDevice) return %orig;
    UIUserInterfaceIdiom orig = %orig;
    UIUserInterfaceIdiom fake = UIUserInterfaceIdiomPhone;
    NBLog(@"[SPOOF] userInterfaceIdiom: %ld -> %ld", (long)orig, (long)fake);
    NBIncrementStat(@"idiom");
    return fake;
}

- (NSString *)systemVersionString {
    if (!isEnabled || !spoofDevice) return %orig;
    NBLog(@"[SPOOF] systemVersionString -> %@", kSpoofSystemVersion);
    NBIncrementStat(@"systemVersionString");
    return kSpoofSystemVersion;
}

- (NSString *)uniqueIdentifier {
    if (!isEnabled || !spoofDevice) return %orig;
    NSString *fake = generateFakeDeviceID();
    NBLog(@"[SPOOF] uniqueIdentifier -> %@", fake);
    NBIncrementStat(@"uniqueIdentifier");
    return fake;
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - IDFA (Advertising Identifier) Spoofing
// ═══════════════════════════════════════════════════════════════════════════════

%hook ASIdentifierManager

- (NSUUID *)advertisingIdentifier {
    if (!isEnabled || !spoofIDFA) return %orig;
    NSString *fake = generateFakeIDFA();
    NSUUID *orig = %orig;
    NBLog(@"[SPOOF] advertisingIdentifier: %@ -> %@", orig, fake);
    NBIncrementStat(@"idfa");
    return [[NSUUID alloc] initWithUUIDString:fake];
}

- (BOOL)isAdvertisingTrackingEnabled {
    if (!isEnabled || !spoofIDFA) return %orig;
    NBLog(@"[SPOOF] isAdvertisingTrackingEnabled -> NO");
    NBIncrementStat(@"tracking");
    return NO;
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - uname / sysctl Spoofing (Critical for hw.machine)
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
        NBLog(@"[SPOOF] uname -> machine:%s version:%s", value->machine, value->version);
        NBIncrementStat(@"uname");
    }
    return ret;
}

static int (*orig_sysctl)(const int *, u_int, void *, size_t *, const void *, size_t);
static int hook_sysctl(const int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen) {
    if (!isEnabled || !spoofDevice) return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (ret == 0 && oldp && oldlenp) {
        if (namelen >= 2 && name[0] == CTL_HW) {
            if (name[1] == HW_MACHINE) {
                const char *fake = [kSpoofModel UTF8String];
                size_t len = strlen(fake) + 1;
                if (*oldlenp >= len) {
                    strcpy((char *)oldp, fake);
                    *oldlenp = len;
                    NBLog(@"[SPOOF] sysctl HW_MACHINE -> %s", fake);
                    NBIncrementStat(@"sysctl_machine");
                }
            } else if (name[1] == HW_MODEL) {
                const char *fake = [kSpoofModel UTF8String];
                size_t len = strlen(fake) + 1;
                if (*oldlenp >= len) {
                    strcpy((char *)oldp, fake);
                    *oldlenp = len;
                    NBLog(@"[SPOOF] sysctl HW_MODEL -> %s", fake);
                    NBIncrementStat(@"sysctl_model");
                }
            } else if (name[1] == HW_MACHINE_ARCH) {
                const char *fake = "arm64e";
                size_t len = strlen(fake) + 1;
                if (*oldlenp >= len) {
                    strcpy((char *)oldp, fake);
                    *oldlenp = len;
                    NBLog(@"[SPOOF] sysctl HW_MACHINE_ARCH -> %s", fake);
                    NBIncrementStat(@"sysctl_arch");
                }
            }
        }
    }
    return ret;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - NSProcessInfo Spoofing
// ═══════════════════════════════════════════════════════════════════════════════

%hook NSProcessInfo

- (NSString *)hostName {
    if (!isEnabled || !spoofDevice) return %orig;
    NBLog(@"[SPOOF] hostName -> iPhone");
    NBIncrementStat(@"hostName");
    return @"iPhone";
}

- (NSString *)operatingSystemVersionString {
    if (!isEnabled || !spoofDevice) return %orig;
    NSString *fake = @"Version 18.3.1 (Build 22D72)";
    NBLog(@"[SPOOF] operatingSystemVersionString -> %@", fake);
    NBIncrementStat(@"osVersionString");
    return fake;
}

- (NSOperatingSystemVersion)operatingSystemVersion {
    if (!isEnabled || !spoofDevice) return %orig;
    NSOperatingSystemVersion fake = {18, 3, 1};
    NBLog(@"[SPOOF] operatingSystemVersion -> 18.3.1");
    NBIncrementStat(@"osVersion");
    return fake;
}

- (NSUInteger)processorCount {
    if (!isEnabled || !spoofDevice) return %orig;
    NBLog(@"[SPOOF] processorCount -> 6");
    NBIncrementStat(@"processorCount");
    return 6;
}

- (NSUInteger)activeProcessorCount {
    if (!isEnabled || !spoofDevice) return %orig;
    NBLog(@"[SPOOF] activeProcessorCount -> 6");
    NBIncrementStat(@"activeProcessorCount");
    return 6;
}

- (unsigned long long)physicalMemory {
    if (!isEnabled || !spoofDevice) return %orig;
    NBLog(@"[SPOOF] physicalMemory -> 8GB");
    NBIncrementStat(@"physicalMemory");
    return 8589934592ULL; // 8GB
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - NSUUID Spoofing (All UUID generation)
// ═══════════════════════════════════════════════════════════════════════════════

%hook NSUUID

+ (NSUUID *)UUID {
    NSUUID *uuid = %orig;
    if (isEnabled && spoofDevice) {
        NSString *fake = generateFakeUUID();
        NBLog(@"[SPOOF] NSUUID.UUID generated: %@ -> %@", uuid.UUIDString, fake);
        NBIncrementStat(@"nsuuid");
        return [[NSUUID alloc] initWithUUIDString:fake];
    }
    return uuid;
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - UIScreen Spoofing (iPhone 15 Pro dimensions)
// ═══════════════════════════════════════════════════════════════════════════════

%hook UIScreen

- (CGRect)bounds {
    if (!isEnabled || !spoofDevice) return %orig;
    CGRect orig = %orig;
    CGRect fake = CGRectMake(0, 0, 393, 852);
    NBLog(@"[SPOOF] Screen bounds: %@ -> %@", NSStringFromCGRect(orig), NSStringFromCGRect(fake));
    NBIncrementStat(@"screenBounds");
    return fake;
}

- (CGFloat)scale {
    if (!isEnabled || !spoofDevice) return %orig;
    NBLog(@"[SPOOF] Screen scale -> 3.0");
    NBIncrementStat(@"screenScale");
    return 3.0;
}

- (CGFloat)nativeScale {
    if (!isEnabled || !spoofDevice) return %orig;
    NBLog(@"[SPOOF] Screen nativeScale -> 3.0");
    NBIncrementStat(@"nativeScale");
    return 3.0;
}

- (CGRect)nativeBounds {
    if (!isEnabled || !spoofDevice) return %orig;
    CGRect fake = CGRectMake(0, 0, 1179, 2556);
    NBLog(@"[SPOOF] nativeBounds -> %@", NSStringFromCGRect(fake));
    NBIncrementStat(@"nativeBounds");
    return fake;
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Network Request Interception & Spoofing
// ═══════════════════════════════════════════════════════════════════════════════

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (!isEnabled || !spoofHeaders) {
        %orig(value, field);
        return;
    }
    NSString *lower = [field lowercaseString];
    if ([lower isEqualToString:@"x-consumer-id"] || [lower isEqualToString:@"x-device-id"]) {
        NSString *fake = generateFakeDeviceID();
        NBLog(@"[SPOOF] Header %@: %@ -> %@", field, value, fake);
        NBIncrementStat(@"header_device");
        %orig(fake, field);
    } else if ([lower isEqualToString:@"x-adid"] || [lower isEqualToString:@"x-advertising-id"]) {
        NSString *fake = generateFakeADID();
        NBLog(@"[SPOOF] Header %@: %@ -> %@", field, value, fake);
        NBIncrementStat(@"header_adid");
        %orig(fake, field);
    } else if ([lower isEqualToString:@"user-agent"]) {
        NSString *fake = [NSString stringWithFormat:@"NaverSeries/1.0 (iPhone; CPU iPhone OS %@ like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22D72", kSpoofSystemVersion];
        NBLog(@"[SPOOF] User-Agent: %@ -> %@", value, fake);
        NBIncrementStat(@"header_ua");
        %orig(fake, field);
    } else if ([lower isEqualToString:@"x-device-model"]) {
        NBLog(@"[SPOOF] X-Device-Model: %@ -> %@", value, kSpoofModel);
        NBIncrementStat(@"header_model");
        %orig(kSpoofModel, field);
    } else if ([lower isEqualToString:@"x-os-version"]) {
        NBLog(@"[SPOOF] X-OS-Version: %@ -> %@", value, kSpoofSystemVersion);
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
    [mutable setValue:[NSString stringWithFormat:@"NaverSeries/1.0 (iPhone; CPU iPhone OS %@ like Mac OS X)", kSpoofSystemVersion] forHTTPHeaderField:@"User-Agent"];
    NBLog(@"[SPOOF] dataTaskWithRequest - injected spoof headers");
    NBIncrementStat(@"dataTask");
    return %orig(mutable);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    if (!isEnabled || !spoofHeaders) return %orig;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:generateFakeDeviceID() forHTTPHeaderField:@"X-Consumer-Id"];
    [req setValue:generateFakeADID() forHTTPHeaderField:@"X-Adid"];
    NBLog(@"[SPOOF] dataTaskWithURL - injected spoof headers");
    NBIncrementStat(@"dataTaskURL");
    return %orig(req);
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Keychain Blocking (Prevent storing ban fingerprint)
// ═══════════════════════════════════════════════════════════════════════════════

%hookf(OSStatus, SecItemAdd, CFDictionaryRef attributes, CFTypeRef *result) {
    if (!isEnabled || !blockKeychain) return %orig;
    NSDictionary *dict = (__bridge NSDictionary *)attributes;
    NSString *account = dict[(__bridge NSString *)kSecAttrAccount];
    NSString *service = dict[(__bridge NSString *)kSecAttrService];
    NSString *group = dict[(__bridge NSString *)kSecAttrAccessGroup];

    if ([service containsString:@"naver"] || [service containsString:@"series"] ||
        [account containsString:@"naver"] || [account containsString:@"series"] ||
        [account containsString:@"device"] || [account containsString:@"ban"] ||
        [account containsString:@"fingerprint"] || [account containsString:@"id"] ||
        [group containsString:@"naver"] || [group containsString:@"series"]) {
        NBLog(@"[BLOCK] SecItemAdd - Account:%@ Service:%@ -> Fake Success", account, service);
        NBIncrementStat(@"keychain_add_blocked");
        if (result) *result = NULL;
        return errSecSuccess;
    }
    return %orig;
}

%hookf(OSStatus, SecItemUpdate, CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (!isEnabled || !blockKeychain) return %orig;
    NSDictionary *dict = (__bridge NSDictionary *)query;
    NSString *account = dict[(__bridge NSString *)kSecAttrAccount];
    NSString *service = dict[(__bridge NSString *)kSecAttrService];

    if ([service containsString:@"naver"] || [service containsString:@"series"] ||
        [account containsString:@"naver"] || [account containsString:@"series"] ||
        [account containsString:@"device"] || [account containsString:@"ban"]) {
        NBLog(@"[BLOCK] SecItemUpdate - Account:%@ Service:%@ -> Fake Success", account, service);
        NBIncrementStat(@"keychain_update_blocked");
        return errSecSuccess;
    }
    return %orig;
}

%hookf(OSStatus, SecItemDelete, CFDictionaryRef query) {
    if (!isEnabled || !blockKeychain) return %orig;
    // Allow deletion (cleanup old data)
    return %orig;
}

%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef query, CFTypeRef *result) {
    if (!isEnabled || !blockKeychain) return %orig;
    NSDictionary *dict = (__bridge NSDictionary *)query;
    NSString *account = dict[(__bridge NSString *)kSecAttrAccount];
    NSString *service = dict[(__bridge NSString *)kSecAttrService];

    if ([service containsString:@"naver"] || [service containsString:@"series"] ||
        [account containsString:@"naver"] || [account containsString:@"series"] ||
        [account containsString:@"device"] || [account containsString:@"ban"]) {
        NBLog(@"[BLOCK] SecItemCopyMatching - Account:%@ Service:%@ -> Not Found", account, service);
        NBIncrementStat(@"keychain_copy_blocked");
        return errSecItemNotFound;
    }
    return %orig;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - NSBundle Spoofing (Bundle Identifier protection)
// ═══════════════════════════════════════════════════════════════════════════════

%hook NSBundle

- (NSString *)bundleIdentifier {
    if (!isEnabled || !spoofDevice) return %orig;
    NSString *orig = %orig;
    // Don't spoof our own bundle ID, but spoof if app asks for system bundles
    if ([orig isEqualToString:@"com.apple.springboard"] || 
        [orig isEqualToString:@"com.apple.UIKit"] ||
        [orig hasPrefix:@"com.apple."]) {
        return orig;
    }
    NBLog(@"[SPOOF] bundleIdentifier: %@", orig);
    NBIncrementStat(@"bundleId");
    return orig;
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Constructor
// ═══════════════════════════════════════════════════════════════════════════════

%ctor {
    @autoreleasepool {
        NBLog(@"=== NaverSeriesBypass v3.1 - DEVICE BAN BYPASS ===");
        NBLog(@"Target: iPhone 8 iOS 16 -> Spoof as iPhone 15 Pro iOS 18.3.1");

        nbStatsQueue = dispatch_queue_create("com.aosaid.naverseriesbypass.stats", DISPATCH_QUEUE_SERIAL);

        // Load preferences
        loadPreferences();

        // Hook uname/sysctl at C level
        MSHookFunction((void *)uname, (void *)hook_uname, (void **)&orig_uname);
        MSHookFunction((void *)sysctl, (void *)hook_sysctl, (void **)&orig_sysctl);

        // Clean keychain on first run
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            cleanupKeychain();
        });

        // Register for preference changes
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)loadPreferences,
            CFSTR("com.aosaid.naverseriesbypass/preferences.changed"),
            NULL,
            CFNotificationSuspensionBehaviorCoalesce
        );

        NBLog(@"Bypass engine initialized - All device identifiers spoofed");
        NBLogStats();
    }
}
