// NetWatch v0.7 — كشف schema عبر قراءات الـJSON + إخفاء التويك
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonHMAC.h>
#import <mach-o/dyld.h>
#import <fcntl.h>
#include <unistd.h>
#include <stdarg.h>
#include <time.h>
#include <string.h>

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
    long now = (long)time(NULL);
    char json[1400];
    snprintf(json, sizeof(json),
        "{\"status\":\"success\",\"code\":\"success\",\"messenger\":\"Kich hoat thanh cong\","
        "\"key\":\"%s\",\"expired_time\":\"2099-12-31 23:59:59\",\"expire\":\"2099-12-31\","
        "\"device_id\":\"00008020-00091DCE0EF1002E\","
        "\"timestamp\":%s,\"server_time\":%ld,\"server_timestamp\":%s,\"time\":%ld,\"nonce\":\"%s\","
        "\"data\":{\"status\":\"active\",\"expire\":\"2099-12-31\",\"type\":\"VIP\",\"timestamp\":%s}}",
        keyv[0]?keyv:"TEST123", ts[0]?ts:"0", now, ts[0]?ts:"0", now,
        nonce[0]?nonce:"", ts[0]?ts:"0");
    return [NSData dataWithBytesNoCopy:json length:strlen(json) freeWhenDone:NO];
}

// كشف schema: أي مفتاح يقرأه التطبيق من أي قاموس
%hook NSDictionary
- (id)objectForKey:(id)aKey {
    id v = %orig(aKey);
    if (aKey) RLogC("DICT-READ key=%s -> %s", [aKey description].UTF8String ?: "?", v ? [[v description] UTF8String] : "(nil)");
    return v;
}
- (id)objectForKeyedSubscript:(id)key {
    id v = %orig(key);
    if (key) RLogC("DICT-SUB key=%s -> %s", [key description].UTF8String ?: "?", v ? [[v description] UTF8String] : "(nil)");
    return v;
}
%end

%hook NSUserDefaults
- (void)setObject:(id)v forKey:(NSString *)k {
    RLogC("DEFAULTS-SET %s = %.*s", k.UTF8String ?: "?", (int)MIN((NSUInteger)300, [[v description] length]), [[v description] UTF8String] ?: "");
    %orig(v, k);
}
- (id)objectForKey:(NSString *)k {
    id v = %orig(k);
    RLogC("DEFAULTS-GET %s -> %s", k.UTF8String ?: "?", v ? "YES" : "(nil)");
    return v;
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)req completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    RLogC("REQ %s %s", req.HTTPMethod.UTF8String ?: "-", req.URL.absoluteString.UTF8String ?: "-");
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        RLogC("RESP %s | status=%ld", req.URL.absoluteString.UTF8String ?: "-", (long)[(NSHTTPURLResponse *)r statusCode]);
        if (cb && [req.URL.absoluteString containsString:@"Cheack.php"]) {
            RLogC("FORGE >>> echo fake success");
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
    RLogC("WRITE-NSData %s (%lu bytes)", path.UTF8String ?: "?", (unsigned long)self.length);
    return %orig(path, mask, error);
}
%end

%hook NSString
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)u encoding:(NSStringEncoding)e error:(NSError **)err {
    RLogC("WRITE-NSString %s", path.UTF8String ?: "?");
    return %orig(path, u, e, err);
}
%end

%hook NSDictionary(writeToFile)
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)u {
    RLogC("WRITE-Dict %s", path.UTF8String ?: "?");
    return %orig(path, u);
}
%end

// إخفاء التويك من فحوصات الصور المحقونة
%hookf(const char *, _dyld_get_image_name, uint32_t idx) {
    const char *n = %orig(idx);
    if (n && (strstr(n, "LoaderRecon") || strstr(n, "MobileSubstrate") || strstr(n, "TweakInject") || strstr(n, "ellekit"))) {
        return "/usr/lib/libobjc.A.dylib";
    }
    return n;
}

static int interesting(const char *f) {
    if (!f) return 0;
    return (strstr(f,"Cheack")||strstr(f,"Key")||strstr(f,"key")||strstr(f,"lua")||strstr(f,"Lua")||
            strstr(f,"patch")||strstr(f,"Patch")||strstr(f,"AUTO")||strstr(f,"Loader")||
            strstr(f,"session")||strstr(f,"Session")||strstr(f,"token")||strstr(f,"Token")||
            strstr(f,"expire")||strstr(f,"Expire")||strstr(f,"VIP")||strstr(f,"time")||
            strstr(f,"Time")||strstr(f,"sync")||strstr(f,"Sync")) ? 1 : 0;
}

%hookf(void, os_log, os_log_t log, const char *fmt, ...) {
    if (interesting(fmt)) RLogC("APP-OSLOG %s", fmt);
}

%hookf(void, NSLog, NSString *format, ...) {
    RLogC("NSLOG %s", format ? [format UTF8String] : "(nil)");
}

%hookf(void, CCHmac, CCHmacAlgorithm algorithm, const void *key, size_t keyLength, const void *data, size_t dataLength, void *macOut) {
    RLogC("CCHMAC alg=%lu keyLen=%lu | dataLen=%lu", (unsigned long)algorithm, (unsigned long)keyLength, (unsigned long)dataLength);
    %orig(algorithm, key, keyLength, data, dataLength, macOut);
}

%hookf(OSStatus, SecTrustEvaluate, SecTrustRef trust, SecTrustResultType *res) {
    if (res) *res = kSecTrustResultProceed;
    return errSecSuccess;
}
