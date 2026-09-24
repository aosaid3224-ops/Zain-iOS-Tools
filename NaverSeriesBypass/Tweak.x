/*
 * NaverSeriesBypass - Enhanced Device Ban Bypass
 * Target: iPhone 8 (iOS 16) -> Spoof to iPhone 15 Pro (iOS 18.3.1)
 * Author: aosaid3224-ops (Enhanced by Consultant)
 */

#import <substrate.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <AdSupport/AdSupport.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Configuration
// ═══════════════════════════════════════════════════════════════════════════════

static BOOL isEnabled = YES;
static BOOL spoofIDFV = YES;
static BOOL spoofIDFA = YES;
static BOOL spoofHeaders = YES;
static BOOL spoofDevice = YES;
static BOOL spoofNetwork = YES;

// Target spoof identity: iPhone 15 Pro, iOS 18.3.1
static NSString *const kSpoofModel = @"iPhone16,1";
static NSString *const kSpoofLocalizedModel = @"iPhone";
static NSString *const kSpoofSystemVersion = @"18.3.1";
static NSString *const kSpoofSystemName = @"iOS";
static NSString *const kSpoofDeviceName = @"iPhone";
static NSString *const kSpoofUserAgent = @"iPhone16,1/18.3.1";

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
// MARK: - Persistent ID Generation (Deterministic per-app-install)
// ═══════════════════════════════════════════════════════════════════════════════

static NSString *persistentID(NSString *prefix) {
    NSString *key = [NSString stringWithFormat:@"com.aosaid.naverseriesbypass.%@", prefix];
    NSString *uuid = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    if (!uuid) {
        uuid = [[NSUUID UUID] UUIDString];
        [[NSUserDefaults standardUserDefaults] setObject:uuid forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return uuid;
}

static NSString *generateFakeIDFV() {
    return persistentID(@"idfv_v2");
}

static NSString *generateFakeIDFA() {
    return persistentID(@"idfa_v2");
}

static NSString *generateFakeDeviceID() {
    return persistentID(@"device_v2");
}

static NSString *generateFakeADID() {
    return persistentID(@"adid_v2");
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
        strncpy(value->version, "Darwin Kernel Version 22.6.0", sizeof(value->version) - 1);
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

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - NSUUID Spoofing (All UUID generation)
// ═══════════════════════════════════════════════════════════════════════════════

%hook NSUUID

+ (NSUUID *)UUID {
    NSUUID *uuid = %orig;
    if (isEnabled && spoofDevice) {
        NSString *fake = generateFakeDeviceID();
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
    // iPhone 15 Pro: 393 x 852 points @ 3x
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
        NSString *fake = [NSString stringWithFormat:@"NaverSeries/%@ (iPhone; iOS %@; Scale/3.0)", kSpoofSystemVersion, kSpoofSystemVersion];
        NBLog(@"[SPOOF] User-Agent: %@ -> %@", value, fake);
        NBIncrementStat(@"header_ua");
        %orig(fake, field);
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
    [mutable setValue:[NSString stringWithFormat:@"NaverSeries/%@ (iPhone; iOS %@; Scale/3.0)", kSpoofSystemVersion, kSpoofSystemVersion] forHTTPHeaderField:@"User-Agent"];
    NBLog(@"[SPOOF] dataTaskWithRequest - injected spoof headers");
    NBIncrementStat(@"dataTask");
    return %orig(mutable);
}

%end

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Keychain Cleanup (Remove old ban data)
// ═══════════════════════════════════════════════════════════════════════════════

%hookf(OSStatus, SecItemAdd, CFDictionaryRef attributes, CFTypeRef *result) {
    if (!isEnabled) return %orig;
    NSDictionary *dict = (__bridge NSDictionary *)attributes;
    NSString *account = dict[(__bridge NSString *)kSecAttrAccount];
    if ([account containsString:@"naver"] || [account containsString:@"series"] || [account containsString:@"device"] || [account containsString:@"ban"]) {
        NBLog(@"[BLOCK] SecItemAdd - Account:%@ -> Fake Success", account);
        NBIncrementStat(@"keychain_add_blocked");
        if (result) *result = NULL;
        return errSecSuccess;
    }
    return %orig;
}

%hookf(OSStatus, SecItemUpdate, CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (!isEnabled) return %orig;
    NSDictionary *dict = (__bridge NSDictionary *)query;
    NSString *account = dict[(__bridge NSString *)kSecAttrAccount];
    if ([account containsString:@"naver"] || [account containsString:@"series"] || [account containsString:@"device"] || [account containsString:@"ban"]) {
        NBLog(@"[BLOCK] SecItemUpdate - Account:%@ -> Fake Success", account);
        NBIncrementStat(@"keychain_update_blocked");
        return errSecSuccess;
    }
    return %orig;
}

%hookf(OSStatus, SecItemDelete, CFDictionaryRef query) {
    if (!isEnabled) return %orig;
    // Allow deletion (cleanup old data)
    return %orig;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Constructor
// ═══════════════════════════════════════════════════════════════════════════════

%ctor {
    @autoreleasepool {
        NBLog(@"=== NaverSeriesBypass v3.0 - DEVICE BAN BYPASS ===");
        NBLog(@"Target: iPhone 8 iOS 16 -> Spoof as iPhone 15 Pro iOS 18.3.1");

        nbStatsQueue = dispatch_queue_create("com.aosaid.naverseriesbypass.stats", DISPATCH_QUEUE_SERIAL);

        // Hook uname/sysctl at C level
        MSHookFunction((void *)uname, (void *)hook_uname, (void **)&orig_uname);
        MSHookFunction((void *)sysctl, (void *)hook_sysctl, (void **)&orig_sysctl);

        // Clear any existing persistent IDs to get fresh identity
        // (Uncomment next 4 lines to force new identity on every reinstall)
        // [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"com.aosaid.naverseriesbypass.idfv_v2"];
        // [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"com.aosaid.naverseriesbypass.idfa_v2"];
        // [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"com.aosaid.naverseriesbypass.device_v2"];
        // [[NSUserDefaults standardUserDefaults] synchronize];

        NBLog(@"Bypass engine initialized - All device identifiers spoofed");
        NBLogStats();
    }
}
