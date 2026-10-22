// DeviceMask — تزوير هوية الجهاز لحماية من حظر الأجهزة
// MGCopyAnswer + UIDevice + ASIdentifierManager + sysctl(hw.machine)
#include <Foundation/Foundation.h>
#include <AdSupport/AdSupport.h>
#include <string.h>
#include <sys/sysctl.h>

extern "C" CFTypeRef MGCopyAnswer(CFStringRef property);

static NSDictionary *gP = nil;

static NSString *randHex(int n) {
    char buf[64]; for (int i = 0; i < n; i++) buf[i] = "0123456789ABCDEF"[arc4random_uniform(16)];
    buf[n] = 0; return [NSString stringWithUTF8String:buf];
}
static NSString *randUUID(void) {
    return [[NSUUID UUID] UUIDString];
}
static NSString *randSerial(void) {
    return [NSString stringWithFormat:@"F%s%s%s", randHex(2).UTF8String, randHex(3).UTF8String, randHex(2).UTF8String];
}

static void DMLoad(void) {
    if (gP) return;
    @autoreleasepool {
        NSString *bundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
        NSString *dir = @"/var/mobile/Documents/DeviceMask";
        NSString *path = [NSString stringWithFormat:@"%@/%@.plist", dir, bundle];
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:path];
        if (!d) {
            d = [@{
                @"SerialNumber": randSerial(),
                @"ProductType": @"iPhone14,2",
                @"ProductVersion": @"17.5.1",
                @"UniqueDeviceID": randUUID(),
                @"IDFV": randUUID(),
                @"IDFA": randUUID(),
                @"DeviceName": @"iPhone"
            } mutableCopy];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            [d writeToFile:path atomically:YES];
        }
        gP = d;
    }
}

// MobileGestalt
%hookf(CFTypeRef, MGCopyAnswer, CFStringRef prop) {
    if (!gP) return %orig(prop);
    NSString *key = (__bridge NSString *)prop;
    static NSDictionary *map = nil;
    if (!map) map = @{
        @"SerialNumber": gP[@"SerialNumber"],
        @"ProductType": gP[@"ProductType"],
        @"ProductVersion": gP[@"ProductVersion"],
        @"UniqueDeviceID": gP[@"UniqueDeviceID"],
        @"DeviceName": gP[@"DeviceName"],
        @"BluetoothAddress": @"5C:F3:70:A1:B2:C4",
        @"WifiAddress": @"5C:F3:70:A1:B2:C5",
    };
    id v = map[key];
    if (v) return (CFTypeRef)CFBridgingRetain(v);
    return %orig(prop);
}

// UIDevice
%hook UIDevice
- (NSString *)name { DMLoad(); return gP[@"DeviceName"] ?: %orig; }
- (NSString *)systemVersion { DMLoad(); return gP[@"ProductVersion"] ?: %orig; }
- (NSUUID *)identifierForVendor {
    DMLoad();
    NSString *u = gP[@"IDFV"];
    return u ? [[NSUUID alloc] initWithUUIDString:u] : %orig;
}
%end

// IDFA
%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    DMLoad();
    NSString *u = gP[@"IDFA"];
    return u ? [[NSUUID alloc] initWithUUIDString:u] : %orig;
}
- (BOOL)isAdvertisingTrackingEnabled { return NO; }
%end

// sysctl hw.machine
%hookf(int, sysctlbyname, const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (oldp && name && strcmp(name, "hw.machine") == 0 && gP) {
        const char *m = [gP[@"ProductType"] UTF8String];
        size_t need = strlen(m) + 1;
        if (oldlenp && *oldlenp >= need) { strcpy((char *)oldp, m); return 0; }
    }
    return %orig(name, oldp, oldlenp, newp, newlen);
}

%ctor {
    DMLoad();
}
