// GameRecon — استطلاع DragonCheat داخل اللعبة (استطلاع نقي، لا تزوير)
#include <UIKit/UIKit.h>
#include <Security/Security.h>
#include <CommonCrypto/CommonHMAC.h>

#define GRLOG(...) do { \
    NSString *grs = [NSString stringWithFormat:__VA_ARGS__]; \
    const char *grc = [grs UTF8String]; if (!grc) break; \
    FILE *grf = fopen("/var/mobile/Documents/gamerecon.log","a"); \
    if (grf) { fprintf(grf, "%s\n", grc); fclose(grf); } \
} while(0)

static NSString *grTrunc(id v) {
    NSString *d = [v description];
    if (!d) return @"(nil)";
    if ([d length] > 200) d = [d substringToIndex:200];
    return d;
}

/* ---- NSUserDefaults ---- */
static BOOL grInteresting(NSString *k) {
    NSString *low = [k lowercaseString];
    return ([low hasPrefix:@"dragon"] || [low hasPrefix:@"dc"] || [low hasPrefix:@"cheat"] ||
            [low hasPrefix:@"key"] || [low hasPrefix:@"udid"] || [low hasPrefix:@"vip"] ||
            [low hasPrefix:@"licen"] || [low hasPrefix:@"device"]);
}
%hook NSUserDefaults
- (id)objectForKey:(NSString *)k {
    id v = %orig;
    if (k && grInteresting(k)) GRLOG(@"UD-GET %@ = %@", k, grTrunc(v));
    return v;
}
- (void)setObject:(id)v forKey:(NSString *)k {
    if (k && grInteresting(k)) GRLOG(@"UD-SET %@ = %@", k, grTrunc(v));
    %orig(v, k);
}
- (void)removeObjectForKey:(NSString *)k {
    if (k && grInteresting(k)) GRLOG(@"UD-DEL %@", k);
    %orig(k);
}
- (NSString *)stringForKey:(NSString *)k {
    NSString *v = %orig;
    if (k && grInteresting(k)) GRLOG(@"UD-GETS %@ = %@", k, v ?: @"(nil)");
    return v;
}
%end

/* ---- Keychain ---- */
static void grKC(NSString *tag, OSStatus st, CFDictionaryRef q) {
    NSString *sv = q ? (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("svce")) : nil;
    NSString *ac = q ? (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("acct")) : nil;
    GRLOG(@"%@ status=%d svce=%@ acct=%@", tag, (int)st, sv ?: @"-", ac ?: @"-");
}
%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef q, CFTypeRef *result) {
    OSStatus s = %orig(q, result);
    grKC(@"KC-FIND", s, q);
    if (s == 0 && result && *result) GRLOG(@"KC-HIT %@", grTrunc((__bridge id)*result));
    return s;
}
%hookf(OSStatus, SecItemAdd, CFDictionaryRef q, CFTypeRef *r) {
    grKC(@"KC-ADD", 0, q);
    return %orig(q, r);
}
%hookf(OSStatus, SecItemUpdate, CFDictionaryRef q, CFDictionaryRef a) {
    grKC(@"KC-UPD", 0, q);
    if (a) GRLOG(@"KC-UPDattr %@", grTrunc((__bridge id)a));
    return %orig(q, a);
}
%hookf(OSStatus, SecItemDelete, CFDictionaryRef q) {
    grKC(@"KC-DEL", 0, q);
    return %orig(q);
}

/* ---- Network ---- */
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)req completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    GRLOG(@"REQ %@ %@", req.HTTPMethod ?: @"?", req.URL.absoluteString ?: @"?");
    if (req.HTTPBody) GRLOG(@"REQ-BODY %@", grTrunc([[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding]));
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e){
        GRLOG(@"RESP %@ | %ld", req.URL.absoluteString ?: @"?", (long)[(NSHTTPURLResponse *)r statusCode]);
        if (d) GRLOG(@"RESP-BODY %@", grTrunc([[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]));
        if (cb) cb(d, r, e);
    };
    return %orig(req, wrapped);
}
%end
%hook NSURLConnection
+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error {
    GRLOG(@"REQ-SYNC %@", request.URL.absoluteString ?: @"?");
    NSData *d = %orig(request, response, error);
    if (d) GRLOG(@"RESP-SYNC %@", grTrunc([[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]));
    return d;
}
%end
%hook NSURLRequest
- (instancetype)initWithURL:(NSURL *)url {
    GRLOG(@"REQ-INIT %@", url.absoluteString ?: @"?");
    return %orig(url);
}
%end
%hook NSMutableURLRequest
- (instancetype)initWithURL:(NSURL *)url {
    GRLOG(@"REQ-MINIT %@", url.absoluteString ?: @"?");
    return %orig(url);
}
%end

/* ---- JSON ---- */
%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)err {
    id obj = %orig(data, opt, err);
    if (obj && data && [data length] > 8 && [data length] < 8192) {
        GRLOG(@"JSON-IN %@", grTrunc([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]));
    }
    return obj;
}
%end

/* ---- Crypto ---- */
%hookf(void, CCHmac, CCHmacAlgorithm alg, const void *key, size_t keyLen, const void *data, size_t dataLen, void *macOut) {
    NSMutableString *kb = [NSMutableString string];
    for (size_t i = 0; key && i < keyLen && i < 48; i++) [kb appendFormat:@"%02x", ((const uint8_t *)key)[i]];
    NSMutableString *db = [NSMutableString string];
    for (size_t i = 0; data && i < dataLen && i < 160; i++) [db appendFormat:@"%02x", ((const uint8_t *)data)[i]];
    GRLOG(@"CCHMAC alg=%lu keyLen=%zu key=%@ dataLen=%zu data=%@", (unsigned long)alg, keyLen, kb, dataLen, db);
    %orig(alg, key, keyLen, data, dataLen, macOut);
    NSMutableString *mb = [NSMutableString string];
    for (int i = 0; i < 32; i++) [mb appendFormat:@"%02x", ((const uint8_t *)macOut)[i]];
    GRLOG(@"CCHMAC-OUT %@", mb);
}

/* ---- File writes ---- */
%hook NSData
- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)mask error:(NSError **)error {
    GRLOG(@"WRITE-NSData %@", path ?: @"?");
    return %orig(path, mask, error);
}
%end
%hook NSString
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)u encoding:(NSStringEncoding)enc error:(NSError **)error {
    GRLOG(@"WRITE-NSString %@", path ?: @"?");
    return %orig(path, u, enc, error);
}
%end
%hook NSDictionary
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)flag {
    GRLOG(@"WRITE-Dict %@", path ?: @"?");
    return %orig(path, flag);
}
%end

/* ---- NSLog ---- */
%hookf(void, NSLog, NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *s = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    GRLOG(@"NSLOG %@", grTrunc(s));
    %orig(@"%@", s);
}
