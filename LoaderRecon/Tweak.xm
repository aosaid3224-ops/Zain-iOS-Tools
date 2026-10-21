// NetWatch v1.0 — مراقبة Keychain + KVS + كل التخزين للتحدي الحقيقي
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <os/log.h>
#import <CommonCrypto/CommonHMAC.h>
#import <mach-o/dyld.h>
#import <fcntl.h>
#include <unistd.h>
#include <stdarg.h>
#include <time.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>

static void RLogC(const char *fmt, ...) {
    char buf[16384];
    time_t t = time(NULL); struct tm tv; gmtime_r(&t, &tv);
    int n = snprintf(buf, sizeof(buf), "%04d-%02d-%02d %02d:%02d:%02d ",
        tv.tm_year+1900, tv.tm_mon+1, tv.tm_mday, tv.tm_hour, tv.tm_min, tv.tm_sec);
    va_list a; va_start(a, fmt);
    vsnprintf(buf+n, sizeof(buf)-n-2, fmt, a);
    va_end(a);
    size_t len = strlen(buf);
    buf[len]='\n'; buf[len+1]=0;
    int fd = open("/var/mobile/Documents/loader_recon.log", O_WRONLY|O_CREAT|O_APPEND, 0644);
    if (fd >= 0) { ssize_t w = write(fd, buf, strlen(buf)); (void)w; close(fd); }
}

// كاش القيم عبر كل المخازن
static char g_chal[512]="", g_ckey[512]="", g_creq[512]="", g_cded[128]="";
static void cache_put(const char *k, const char *v) {
    if (!k || !v || !v[0]) return;
    if (strstr(k,"UDIDChallenge")||strstr(k,"challenge")) snprintf(g_chal,sizeof(g_chal),"%s",v);
    else if (strstr(k,"UDIDKey")) snprintf(g_ckey,sizeof(g_ckey),"%s",v);
    else if (strstr(k,"UDIDRequest")) snprintf(g_creq,sizeof(g_creq),"%s",v);
    else if (strstr(k,"UDIDDeadline")) snprintf(g_cded,sizeof(g_cded),"%s",v);
}

static void cfstr(CFTypeRef v, char *out, size_t n) {
    out[0]=0;
    if (!v) return;
    if (CFGetTypeID(v)==CFStringGetTypeID()) {
        CFStringGetCString((CFStringRef)v, out, n, kCFStringEncodingUTF8);
    } else if (CFGetTypeID(v)==CFDataGetTypeID()) {
        CFDataRef d=(CFDataRef)v; long len=CFDataGetLength(d);
        const unsigned char *b=CFDataGetBytePtr(d);
        size_t o=0;
        for(long i=0;i<len && i<120 && o<n-4;i++) o+=snprintf(out+o,n-o,"%02x",b[i]);
        if(len>120) snprintf(out+o,n-o,"...");
    } else if (CFGetTypeID(v)==CFNumberGetTypeID()) {
        CFNumberRef num=(CFNumberRef)v;
        if(CFNumberIsFloatType(num)){double d;CFNumberGetValue(num,kCFNumberDoubleType,&d);snprintf(out,n,"%.3f",d);}
        else{long long l;CFNumberGetValue(num,kCFNumberLongLongType,&l);snprintf(out,n,"%lld",l);}
    } else if (CFGetTypeID(v)==CFDictionaryGetTypeID()) {
        snprintf(out,n,"{dict}");
    } else if (CFGetTypeID(v)==CFArrayGetTypeID()) {
        snprintf(out,n,"[array %ld]",CFArrayGetCount((CFArrayRef)v));
    } else if (CFGetTypeID(v)==CFBooleanGetTypeID()) {
        snprintf(out,n,"%s",CFBooleanGetValue((CFBooleanRef)v)?"true":"false");
    }
}

static void log_dict(const char *tag, CFDictionaryRef d) {
    if (!d) return;
    const void *vals[8]; const void *keys[8];
    (void)vals; (void)keys;
    const char *want[] = {"class","svce","acct","v_Data","pdmn","agrp","desc","gena"};
    for (int i=0;i<8;i++) {
        CFStringRef k = CFStringCreateWithCString(NULL, want[i], kCFStringEncodingUTF8);
        CFTypeRef v = CFDictionaryGetValue(d, k);
        CFRelease(k);
        if (v) { char b[1400]; cfstr(v,b,sizeof(b)); RLogC("%s %s=%s", tag, want[i], b); }
    }
}

static void param_value(const char *url, const char *key, char *out, size_t outsz) {
    out[0] = 0;
    char pat[64]; snprintf(pat, sizeof(pat), "%s=", key);
    const char *p = strstr(url, pat);
    if (!p) return;
    p += strlen(pat);
    size_t i = 0;
    while (p[i] && p[i] != '&' && i < outsz-1) { out[i] = p[i]; i++; }
    out[i] = 0;
}

static NSData *ForgedSuccess(const char *url) {
    char ts[32], nonce[64], keyv[64];
    param_value(url, "timestamp", ts, sizeof(ts));
    param_value(url, "nonce", nonce, sizeof(nonce));
    param_value(url, "key", keyv, sizeof(keyv));
    // اقرأ من الكاش (كل المخازن) مع مباشر
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    const char *cs = g_chal[0] ? g_chal : ([d objectForKey:@"pendingUDIDChallenge"] ? [[d objectForKey:@"pendingUDIDChallenge"] UTF8String] : "");
    const char *cks = g_ckey[0] ? g_ckey : "";
    const char *crs = g_creq[0] ? g_creq : "";
    RLogC("CHALLENGE chal=[%s] key=[%s] req=[%s] ded=[%s]", cs, cks, crs, g_cded);
    long now = (long)time(NULL);
    char json[4096];
    snprintf(json, sizeof(json),
        "{\"status\":\"success\",\"code\":\"success\",\"messenger\":\"Kich hoat thanh cong\","
        "\"key\":\"%s\",\"expired_time\":\"2099-12-31 23:59:59\",\"expire\":\"2099-12-31\","
        "\"device_id\":\"00008020-00091DCE0EF1002E\","
        "\"timestamp\":%s,\"server_time\":%ld,\"server_timestamp\":%s,\"time\":%ld,\"nonce\":\"%s\","
        "\"udid_challenge\":\"%s\",\"challenge\":\"%s\",\"challenge_response\":\"%s\",\"server_challenge\":\"%s\","
        "\"udidKey\":\"%s\",\"udid_key\":\"%s\",\"request_id\":\"%s\",\"requestId\":\"%s\",\"echo\":\"%s\",\"pong\":\"%s\",\"answer\":\"%s\","
        "\"data\":{\"status\":\"active\",\"expire\":\"2099-12-31\",\"type\":\"VIP\",\"timestamp\":%s,"
        "\"udid_challenge\":\"%s\",\"challenge\":\"%s\",\"request_id\":\"%s\",\"udidKey\":\"%s\"}}",
        keyv[0]?keyv:"TEST123", ts[0]?ts:"0", now, ts[0]?ts:"0", now, nonce[0]?nonce:"",
        cs, cs, cs, cs, cks, cks, crs, crs, cs, cs, cs,
        ts[0]?ts:"0", cs, cs, crs, cks);
    return [NSData dataWithBytesNoCopy:json length:strlen(json) freeWhenDone:NO];
}

// Keychain hooks
%hookf(OSStatus, SecItemAdd, CFDictionaryRef attrs, CFTypeRef *result) {
    if (attrs) {
        RLogC("KC-ADD:");
        log_dict("KC-ADD", attrs);
        const void *v = CFDictionaryGetValue(attrs, CFSTR("v_Data"));
        if (v) { char b[1400]; cfstr(v,b,sizeof(b)); cache_put("challenge", b); }
        const void *a = CFDictionaryGetValue(attrs, CFSTR("acct"));
        if (a) { char b[512]; cfstr(a,b,sizeof(b)); }
    }
    return %orig(attrs, result);
}
%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef query, CFTypeRef *result) {
    OSStatus s = %orig(query, result);
    if (query) {
        RLogC("KC-FIND status=%d:", (int)s);
        log_dict("KC-FIND", query);
    }
    if (result && *result) {
        if (CFGetTypeID(*result)==CFDataGetTypeID()) {
            char b[1400]; cfstr(*result,b,sizeof(b)); RLogC("KC-RESULT data=%s", b); cache_put("challenge", b);
        } else if (CFGetTypeID(*result)==CFDictionaryGetTypeID()) {
            RLogC("KC-RESULT dict:");
            log_dict("KC-RES", (CFDictionaryRef)*result);
            const void *v = CFDictionaryGetValue((CFDictionaryRef)*result, CFSTR("v_Data"));
            if (v) { char b[1400]; cfstr(v,b,sizeof(b)); cache_put("challenge", b); }
        }
    }
    return s;
}
%hookf(OSStatus, SecItemUpdate, CFDictionaryRef query, CFDictionaryRef attrs) {
    if (query) { RLogC("KC-UPDATE-Q:"); log_dict("KC-UPDQ", query); }
    if (attrs) { RLogC("KC-UPDATE-A:"); log_dict("KC-UPDA", attrs); }
    return %orig(query, attrs);
}

%hook NSUserDefaults
- (void)setObject:(id)v forKey:(NSString *)k {
    RLogC("DEFAULTS-SET %s = %.*s", k.UTF8String ?: "?", (int)MIN((NSUInteger)400, [[v description] length]), v ? [[v description] UTF8String] : "(nil)");
    if (v) cache_put(k.UTF8String, [[v description] UTF8String]);
    %orig(v, k);
}
- (id)objectForKey:(NSString *)k {
    id v = %orig(k);
    const char *ks = k.UTF8String;
    if (ks && strncmp(ks, "NS", 2) != 0 && strncmp(ks, "AK", 2) != 0 && strncmp(ks, "UI", 2) != 0 && strncmp(ks, "Log", 3) != 0 && strncmp(ks, "_", 1) != 0 && strncmp(ks, "Metal", 5) != 0)
        RLogC("DEFAULTS-GET %s -> %.*s", ks, (int)MIN((NSUInteger)200, v?[[v description]length]:6), v ? [[v description] UTF8String] : "(nil)");
    if (v && ks) cache_put(ks, [[v description] UTF8String]);
    return v;
}
%end

%hook NSUbiquitousKeyValueStore
- (void)setObject:(id)v forKey:(NSString *)k {
    RLogC("KVS-SET %s = %.*s", k.UTF8String ?: "?", (int)MIN((NSUInteger)300, [[v description] length]), v ? [[v description] UTF8String] : "(nil)");
    if (v) cache_put(k.UTF8String, [[v description] UTF8String]);
    %orig(v, k);
}
- (id)objectForKey:(NSString *)k {
    id v = %orig(k);
    if (v) { RLogC("KVS-GET %s -> %.*s", k.UTF8String ?: "?", (int)MIN((NSUInteger)300, [[v description] length]), [[v description] UTF8String]); cache_put(k.UTF8String, [[v description] UTF8String]); }
    return v;
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)req completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    RLogC("REQ %s %s", req.HTTPMethod.UTF8String ?: "-", req.URL.absoluteString.UTF8String ?: "-");
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        RLogC("RESP %s | status=%ld", req.URL.absoluteString.UTF8String ?: "-", (long)[(NSHTTPURLResponse *)r statusCode]);
        if (cb && [req.URL.absoluteString containsString:@"Cheack.php"]) {
            RLogC("FORGE >>> echo+challenge fake success");
            cb(ForgedSuccess(req.URL.absoluteString.UTF8String), r, nil);
            return;
        }
        if (cb) cb(d, r, e);
    };
    return %orig(req, wrapped);
}
%end

%hook NSData
- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)mask error:(NSError **)error {
    RLogC("WRITE-NSData %s (%lu)", path.UTF8String ?: "?", (unsigned long)self.length);
    return %orig(path, mask, error);
}
%end

%hook NSString
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)u encoding:(NSStringEncoding)e error:(NSError **)err {
    RLogC("WRITE-NSString %s", path.UTF8String ?: "?");
    return %orig(path, u, e, err);
}
%end

%hook NSDictionary
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)u {
    RLogC("WRITE-Dict %s", path.UTF8String ?: "?");
    return %orig(path, u);
}
%end

%hookf(const char *, _dyld_get_image_name, uint32_t idx) {
    const char *n = %orig(idx);
    if (n && (strstr(n, "LoaderRecon") || strstr(n, "MobileSubstrate") || strstr(n, "TweakInject") || strstr(n, "ellekit")))
        return "/usr/lib/libobjc.A.dylib";
    return n;
}

static int interesting(const char *f) {
    if (!f) return 0;
    return (strstr(f,"Cheack")||strstr(f,"AntiCrack")||strstr(f,"lua")||strstr(f,"Lua")||
            strstr(f,"AUTO")||strstr(f,"token")||strstr(f,"Token")||strstr(f,"sync")||strstr(f,"Sync")||strstr(f,"UDID")||strstr(f,"challenge")) ? 1 : 0;
}
%hookf(void, _os_log_impl, void *dso, os_log_t log, os_log_type_t type, const char *fmt, uint8_t *buffer, uint32_t size) {
    if (interesting(fmt)) RLogC("APP-OSLOG type=%u size=%u fmt=%s", (unsigned)type, (unsigned)size, fmt);
    %orig(dso, log, type, fmt, buffer, size);
}
%hookf(void, NSLog, NSString *format, ...) {
    const char *f = format ? [format UTF8String] : "(nil)";
    if (f && (strstr(f,"AntiCrack")||strstr(f,"Key")||strstr(f,"key")||strstr(f,"DEBUG")||strstr(f,"lua")||strstr(f,"patch")||strstr(f,"time")||strstr(f,"Time")||strstr(f,"sync")||strstr(f,"Session")||strstr(f,"token")||strstr(f,"UDID")||strstr(f,"Challenge")||strstr(f,"challenge")))
        RLogC("NSLOG %s", f);
}
%hookf(void, CCHmac, CCHmacAlgorithm algorithm, const void *key, size_t keyLength, const void *data, size_t dataLength, void *macOut) {
    RLogC("CCHMAC alg=%lu dataLen=%lu", (unsigned long)algorithm, (unsigned long)dataLength);
    %orig(algorithm, key, keyLength, data, dataLength, macOut);
}
%hookf(OSStatus, SecTrustEvaluate, SecTrustRef trust, SecTrustResultType *res) {
    if (res) *res = kSecTrustResultProceed;
    return errSecSuccess;
}
