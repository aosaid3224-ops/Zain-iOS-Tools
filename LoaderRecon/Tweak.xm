// NetWatch v0.8 — فلترة صارمة لمفاتيح الجلسة فقط
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

// مفتاح جلسة حقيقي؟ (يستبعد مفاتيح UIKit كلها)
static int session_key(const char *k) {
    if (!k || k[0] == 0) return 0;
    if (strncmp(k, "NS", 2) == 0 || strncmp(k, "UI", 2) == 0 || strncmp(k, "CT", 2) == 0) return 0;
    const char *kw[] = {"status","code","mess","token","key","lua","Lua","data","expire","session",
        "Session","sign","Sign","licen","time","Time","nonce","device","url","URL","file","File",
        "patch","Patch","hack","Hack","source","Source","script","version","hash","uuid","type","vip","VIP", NULL};
    for (int i = 0; kw[i]; i++) if (strstr(k, kw[i])) return 1;
    return 0;
}

%hook NSDictionary
- (id)objectForKey:(id)aKey {
    id v = %orig(aKey);
    const char *ks = [aKey description].UTF8String;
    if (ks && session_key(ks)) {
        RLogC("DICT-READ key=%s -> %.*s", ks, (int)MIN((NSUInteger)300, [[v description] length]), v ? [[v description] UTF8String] : "(nil)");
    }
    return v;
}
- (id)objectForKeyedSubscript:(id)key {
    id v = %orig(key);
    const char *ks = [key description].UTF8String;
    if (ks && session_key(ks)) {
        RLogC("DICT-SUB key=%s -> %.*s", ks, (int)MIN((NSUInteger)300, [[v description] length]), v ? [[v description] UTF8String] : "(nil)");
    }
    return v;
}
%end

%hook NSUserDefaults
- (void)setObject:(id)v forKey:(NSString *)k {
    RLogC("DEFAULTS-SET %s", k.UTF8String ?: "?");
    %orig(v, k);
}
- (id)objectForKey:(NSString *)k {
    id v = %orig(k);
    const char *ks = k.UTF8String;
    if (ks && strncmp(ks, "NS", 2) != 0 && strncmp(ks, "AK", 2) != 0 && strncmp(ks, "UI", 2) != 0)
        RLogC("DEFAULTS-GET %s -> %s", ks, v ? "YES" : "(nil)");
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

%hook NSDictionary(w2f)
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
            strstr(f,"AUTO")||strstr(f,"token")||strstr(f,"Token")||strstr(f,"sync")||strstr(f,"Sync")) ? 1 : 0;
}

%hookf(void, os_log, os_log_t log, const char *fmt, ...) {
    if (interesting(fmt)) RLogC("APP-OSLOG %s", fmt);
}

%hookf(void, NSLog, NSString *format, ...) {
    const char *f = format ? [format UTF8String] : "(nil)";
    if (f && (strstr(f,"AntiCrack")||strstr(f,"Key")||strstr(f,"key")||strstr(f,"DEBUG")||strstr(f,"lua")||strstr(f,"patch")||strstr(f,"time")||strstr(f,"Time")||strstr(f,"sync")||strstr(f,"Session")||strstr(f,"token")))
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
