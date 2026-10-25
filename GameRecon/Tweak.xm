// GameRecon — استطلاع DragonCheat داخل اللعبة (استطلاع نقي، لا تزوير)
#include <UIKit/UIKit.h>
#include <Security/Security.h>
#include <CommonCrypto/CommonHMAC.h>

#define GRLOG(...) do { \
    NSString *s = [NSString stringWithFormat:__VA_ARGS__]; \
    const char *c = [s UTF8String]; if (!c) break; \
    FILE *f = fopen("/var/mobile/Documents/gamerecon.log","a"); \
    if (f) { fprintf(f, "%s\n", c); fclose(f); } \
} while(0)

static void gr_dictdump(NSString *tag, NSDictionary *d) {
    if (!d) return;
    for (NSString *k in d) {
        GRLOG(@"%@ %s=%s", tag, [k UTF8String] ?: "?",
              [[(id)[d objectForKey:k] description] UTF8String] ?: "?");
    }
}

/* ---- NSUserDefaults ---- */
%hook NSUserDefaults
- (id)objectForKey:(NSString *)k {
    id v = %orig;
    NSString *ks = [k description];
    if ([ks rangeOfString:@"."].location == NSNotFound || [ks hasPrefix:@"dragon"] || [ks hasPrefix:@"DC"] || [ks hasPrefix:@"cheat"] || [ks hasPrefix:@"key"] || [ks hasPrefix:@"UDID"] || [ks hasPrefix:@"vip"] || [ks hasPrefix:@"licen"])
        NSString *vs = [v description];
        GRLOG(@"UD-GET %@=%s", ks, v ? [[vs substringToIndex:MIN((NSUInteger)100, [vs length])] UTF8String] : "(nil)");
    return v;
}
- (void)setObject:(id)v forKey:(NSString *)k {
    NSString *vs2 = [v description];
    GRLOG(@"UD-SET %@=%s", k, v ? [[vs2 substringToIndex:MIN((NSUInteger)100, [vs2 length])] UTF8String] : "(nil)");
    %orig(v, k);
}
- (void)removeObjectForKey:(NSString *)k {
    GRLOG(@"UD-DEL %s", [k UTF8String] ?: "?");
    %orig(k);
}
%end

/* ---- Keychain ---- */
static void gr_kcdump(NSString *tag, CFDictionaryRef q) {
    if (!q) return;
    NSString *sv = (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("svce"));
    NSString *ac = (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("acct"));
    NSString *cl = (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("class"));
    GRLOG(@"%@ svce=%@ acct=%@ class=%@", tag, sv ?: @"-", ac ?: @"-", cl ?: @"-");
}
%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef q, CFTypeRef *result) {
    OSStatus s = %orig(q, result);
    GRLOG(@"KC-FIND status=%d", (int)s);
    gr_kcdump(@"KC-FIND", q);
    if (s == 0 && result && *result) {
        NSString *ds = [(__bridge id)*result description];
        GRLOG(@"KC-HIT data=%s", [[ds substringToIndex:MIN((NSUInteger)120, [ds length])] UTF8String]);
    }
    return s;
}
%hookf(OSStatus, SecItemAdd, CFDictionaryRef q, CFTypeRef *r) {
    GRLOG(@"KC-ADD"); gr_kcdump(@"KC-ADD", q);
    return %orig(q, r);
}
%hookf(OSStatus, SecItemUpdate, CFDictionaryRef q, CFDictionaryRef a) {
    GRLOG(@"KC-UPD"); gr_kcdump(@"KC-UPD", q); gr_dictdump(@"KC-UPDattr", (__bridge NSDictionary *)a);
    return %orig(q, a);
}
%hookf(OSStatus, SecItemDelete, CFDictionaryRef q) {
    GRLOG(@"KC-DEL"); gr_kcdump(@"KC-DEL", q);
    return %orig(q);
}

/* ---- Network: كل شيء ---- */
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)req completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    GRLOG(@"REQ %s %s", req.HTTPMethod.UTF8String ?: "-", req.URL.absoluteString.UTF8String ?: "-");
    if (req.HTTPBody) GRLOG(@"REQ-BODY %.*s", (int)MIN((NSUInteger)800, req.HTTPBody.length), (const char *)req.HTTPBody.bytes);
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e){
        GRLOG(@"RESP %s | %ld", req.URL.absoluteString.UTF8String ?: "-", (long)[(NSHTTPURLResponse *)r statusCode]);
        if (d) GRLOG(@"RESP-BODY %.*s", (int)MIN((NSUInteger)1500, d.length), (const char *)[d bytes] ?: "");
        if (cb) cb(d, r, e);
    };
    return %orig(req, wrapped);
}
%end
%hook NSURLConnection
+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error {
    GRLOG(@"REQ-SYNC %s", request.URL.absoluteString.UTF8String ?: "-");
    NSData *d = %orig(request, response, error);
    if (d) GRLOG(@"RESP-SYNC %.*s", (int)MIN((NSUInteger)1500, d.length), (const char *)[d bytes] ?: "");
    return d;
}
%end
%hook NSURLRequest
- (instancetype)initWithURL:(NSURL *)url {
    GRLOG(@"REQ-INIT %s", url.absoluteString.UTF8String ?: "-");
    return %orig(url);
}
%end
%hook NSMutableURLRequest
- (instancetype)initWithURL:(NSURL *)url {
    GRLOG(@"REQ-MINIT %s", url.absoluteString.UTF8String ?: "-");
    return %orig(url);
}
%end

/* ---- JSON parse dump ---- */
%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)err {
    id obj = %orig(data, opt, err);
    if (obj && data && [data length] > 8 && [data length] < 8192) {
        GRLOG(@"JSON-IN %.*s", (int)MIN((NSUInteger)1500, data.length), (const char *)[data bytes] ?: "");
    }
    return obj;
}
%end

/* ---- Crypto (أسرار DragonCheat) ---- */
%hookf(void, CCHmac, CCHmacAlgorithm alg, const void *key, size_t keyLen, const void *data, size_t dataLen, void *macOut) {
    char kb[128], db[400]; size_t ko = 0, d2 = 0;
    for (size_t i = 0; key && i < keyLen && i < 48 && ko < sizeof(kb)-4; i++) ko += snprintf(kb+ko, sizeof(kb)-ko, "%02x", ((const uint8_t*)key)[i]);
    kb[ko] = 0;
    for (size_t i = 0; data && i < dataLen && i < 160 && d2 < sizeof(db)-6; i++) d2 += snprintf(db+d2, sizeof(db)-d2, "%02x", ((const uint8_t*)data)[i]);
    db[d2] = 0;
    GRLOG(@"CCHMAC alg=%lu keyLen=%zu key=%s dataLen=%zu data=%s", (unsigned long)alg, keyLen, kb, dataLen, db);
    %orig(alg, key, keyLen, data, dataLen, macOut);
    char mb[80]; size_t mo = 0;
    for (int i = 0; i < 32 && mo < sizeof(mb)-4; i++) mo += snprintf(mb+mo, sizeof(mb)-mo, "%02x", ((const uint8_t*)macOut)[i]);
    GRLOG(@"CCHMAC-OUT %s", mb);
}

/* ---- File writes (أين يخزن اللقاح/المفتاح) ---- */
%hook NSData
- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)mask error:(NSError **)error {
    GRLOG(@"WRITE-NSData %s", [path UTF8String] ?: "-");
    return %orig(path, mask, error);
}
%end
%hook NSString
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile encoding:(NSStringEncoding)enc error:(NSError **)error {
    GRLOG(@"WRITE-NSString %s", [path UTF8String] ?: "-");
    return %orig(path, useAuxiliaryFile, enc, error);
}
%end
%hook NSDictionary
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)flag {
    GRLOG(@"WRITE-Dict %s", [path UTF8String] ?: "-");
    return %orig(path, flag);
}
%end

/* ---- NSLog (تصريحات DragonCheat) ---- */
%hookf(void, NSLog, NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *s = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    GRLOG(@"NSLOG %s", [s UTF8String] ?: "?");
    %orig(@"%@", s);
}
