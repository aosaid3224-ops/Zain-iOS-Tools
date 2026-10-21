// NetWatch v0.6 — صدى timestamp الحرفي من الطلب
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <os/log.h>
#import <CommonCrypto/CommonHMAC.h>
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

// استخرج قيمة معامل من رابط
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

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)req completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    RLogC("REQ %s %s", req.HTTPMethod.UTF8String ?: "-", req.URL.absoluteString.UTF8String ?: "-");
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        RLogC("RESP %s | status=%ld | body=%.*s", req.URL.absoluteString.UTF8String ?: "-",
              (long)[(NSHTTPURLResponse *)r statusCode],
              (int)MIN((NSUInteger)2000, d.length), d ? (const char *)d.bytes : "(nil)");
        if (cb && [req.URL.absoluteString containsString:@"Cheack.php"]) {
            RLogC("FORGE >>> echo-timestamp fake success");
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

%hook NSDictionary
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)u {
    RLogC("WRITE-Dict %s", path.UTF8String ?: "?");
    return %orig(path, u);
}
%end

