#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <sys/sysctl.h>
#import <CommonCrypto/CommonDigest.h>
#include <string.h>
#include <math.h>
#include <notify.h>

#define NB_TRIAL_KEYCHAIN_SERVICE @"com.aosaid.nsb.trial.v1"
#define NB_TRIAL_DURATION (72.0 * 60.0 * 60.0)
#define NB_TRIAL_CLOCK_TOLERANCE 600.0
#define NB_TRIAL_SENTINEL_KEY @"TrialEverStarted"

static NSData *NBTrialKeychainRead(void) {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: NB_TRIAL_KEYCHAIN_SERVICE,
                        (__bridge id)kSecAttrAccount: @"state",
                        (__bridge id)kSecReturnData: @YES,
                        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
    CFTypeRef result = NULL;
    OSStatus s = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
    if (s != errSecSuccess || !result) return nil;
    return CFBridgingRelease(result);
}

static void NBTrialKeychainWrite(NSData *data) {
    if (!data) return;
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: NB_TRIAL_KEYCHAIN_SERVICE,
                        (__bridge id)kSecAttrAccount: @"state"};
    NSDictionary *attrs = @{(__bridge id)kSecValueData: data,
                            (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock};
    OSStatus s = SecItemUpdate((__bridge CFDictionaryRef)q, (__bridge CFDictionaryRef)attrs);
    if (s == errSecItemNotFound) {
        NSMutableDictionary *add = [q mutableCopy];
        [add addEntriesFromDictionary:attrs];
        SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
}

static NSString *NBTrialMachineFingerprint(void) {
    char machine[128] = {0};
    size_t size = sizeof(machine);
    if (sysctlbyname("hw.machine", machine, &size, NULL, 0) != 0) strcpy(machine, "unknown");
    return [NSString stringWithUTF8String:machine] ?: @"unknown";
}

static NSString *NBTrialHash(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [out appendFormat:@"%02x", digest[i]];
    return out;
}

static NSDictionary *NBTrialReadState(void) {
    NSData *data = NBTrialKeychainRead();
    if (!data) return nil;
    return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
}

static void NBTrialWriteState(NSDictionary *state) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    NBTrialKeychainWrite(data);
}

static void NBTrialPublishRemaining(uint64_t value) {
    int token = 0;
    if (notify_register_check("com.aosaid.nsb.trial.remaining", &token) == NOTIFY_STATUS_OK) {
        notify_set_state(token, value);
        notify_post("com.aosaid.nsb.trial.updated");
    }
}

static uint64_t NBTrialPublishedRemaining(void) {
    int token = 0; uint64_t value = 0;
    if (notify_register_check("com.aosaid.nsb.trial.remaining", &token) != NOTIFY_STATUS_OK) return 0;
    if (notify_get_state(token, &value) != NOTIFY_STATUS_OK) return 0;
    return value;
}

// The evaluation starts only when Naver Series launches, not when Settings opens.
static BOOL NBTrialEnsureActive(void) {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval uptime = NSProcessInfo.processInfo.systemUptime;
    NSDictionary *state = NBTrialReadState();
    if (!state) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:NB_TRIAL_SENTINEL_KEY]) { NBTrialPublishRemaining(UINT64_MAX); return NO; }
        NSString *nonce = [NSUUID UUID].UUIDString;
        NSString *deviceHash = NBTrialHash([NSString stringWithFormat:@"%@|%@", NBTrialMachineFingerprint(), nonce]);
        NBTrialWriteState(@{@"start": @(now), @"last": @(now), @"uptime": @(uptime),
                            @"device": deviceHash, @"nonce": nonce, @"edition": @"trial-72h"});
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:NB_TRIAL_SENTINEL_KEY];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NBTrialPublishRemaining((uint64_t)NB_TRIAL_DURATION);
        return YES;
    }
    NSNumber *start = state[@"start"], *last = state[@"last"], *lastUptime = state[@"uptime"];
    NSString *device = state[@"device"], *nonce = state[@"nonce"];
    NSString *expected = NBTrialHash([NSString stringWithFormat:@"%@|%@", NBTrialMachineFingerprint(), nonce ?: @""]);
    if (!start || !last || !lastUptime || !nonce.length || ![device isEqualToString:expected]) { NBTrialPublishRemaining(UINT64_MAX); return NO; }
    if (now + NB_TRIAL_CLOCK_TOLERANCE < last.doubleValue) { NBTrialPublishRemaining(UINT64_MAX); return NO; }
    if (now >= start.doubleValue + NB_TRIAL_DURATION) { NBTrialPublishRemaining(UINT64_MAX); return NO; }
    NSMutableDictionary *updated = [state mutableCopy];
    updated[@"last"] = @(now);
    updated[@"uptime"] = @(uptime);
    NBTrialWriteState(updated);
    NBTrialPublishRemaining((uint64_t)(start.doubleValue + NB_TRIAL_DURATION - now));
    return YES;
}

static NSString *NBTrialDisplayStatus(void) {
    NSDictionary *state = NBTrialReadState();
    if (!state) {
        uint64_t published = NBTrialPublishedRemaining();
        if (published == UINT64_MAX) return @"التجربة: انتهت أو أصبحت غير صالحة — يلزم ترخيص كامل";
        if (published > 0) return [NSString stringWithFormat:@"التجربة: مفعّلة — متبقٍ تقريبًا %llu ساعة — مرتبطة بهذا الجهاز", (unsigned long long)ceil((double)published / 3600.0)];
        return @"التجربة: لم تبدأ بعد — تبدأ عند تشغيل Naver Series";
    }
    NSNumber *start = state[@"start"], *last = state[@"last"];
    NSString *nonce = state[@"nonce"], *device = state[@"device"];
    NSString *expected = NBTrialHash([NSString stringWithFormat:@"%@|%@", NBTrialMachineFingerprint(), nonce ?: @""]);
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (!start || !last || !nonce.length || ![device isEqualToString:expected] || now + NB_TRIAL_CLOCK_TOLERANCE < last.doubleValue) return @"التجربة: غير صالحة — تم رصد تغيير في بيانات الجهاز أو الوقت";
    NSTimeInterval remaining = start.doubleValue + NB_TRIAL_DURATION - now;
    if (remaining <= 0) return @"التجربة: انتهت — يلزم ترخيص كامل";
    return [NSString stringWithFormat:@"التجربة: مفعّلة — متبقٍ تقريبًا %ld ساعة — مرتبطة بهذا الجهاز", (long)ceil(remaining / 3600.0)];
}

static BOOL NBTrialIsActiveForDashboard(void) {
    NSDictionary *state = NBTrialReadState();
    if (!state) return NBTrialPublishedRemaining() > 0 && NBTrialPublishedRemaining() != UINT64_MAX;
    NSNumber *start = state[@"start"], *last = state[@"last"];
    NSString *nonce = state[@"nonce"], *device = state[@"device"];
    NSString *expected = NBTrialHash([NSString stringWithFormat:@"%@|%@", NBTrialMachineFingerprint(), nonce ?: @""]);
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    return start && last && nonce.length && [device isEqualToString:expected] && now + NB_TRIAL_CLOCK_TOLERANCE >= last.doubleValue && now < start.doubleValue + NB_TRIAL_DURATION;
}
