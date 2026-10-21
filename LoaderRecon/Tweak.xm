// NetWatch v0.4 — تسجيل C صرف، صفر إعادة دخول، خداع الرد
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

static const char *FAKE_JSON = "{\"status\":\"success\",\"code\":\"success\",\"messenger\":\"Kich hoat thanh cong\",\"key\":\"TEST123\",\"expired_time\":\"2099-12-31 23:59:59\",\"device_id\":\"00008020-00091DCE0EF1002E\",\"data\":{\"status\":\"active\",\"expire\":\"2099-12-31\",\"type\":\"VIP\"}}";

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)req completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    RLogC("REQ %s %s", req.HTTPMethod.UTF8String ?: "-", req.URL.absoluteString.UTF8String ?: "-");
    if (req.HTTPBody) RLogC("REQ-BODY %.*s", (int)MIN((NSUInteger)2000, req.HTTPBody.length), (const char *)req.HTTPBody.bytes);
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        RLogC("RESP %s | status=%ld | err=%s | body=%.*s", req.URL.absoluteString.UTF8String ?: "-",
              (long)[(NSHTTPURLResponse *)r statusCode], e ? "ERR" : "ok",
              (int)MIN((NSUInteger)3000, d.length), d ? (const char *)d.bytes : "(nil)");
        if (cb && [req.URL.absoluteString containsString:@"Cheack.php"]) {
            RLogC("FORGE >>> replaced Cheack.php response with fake success");
            cb([NSData dataWithBytesNoCopy:(void *)FAKE_JSON length:strlen(FAKE_JSON) freeWhenDone:NO], r, nil);
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
    RLogC("WRITE-NSString %s : %.*s", path.UTF8String ?: "?", (int)MIN((NSUInteger)400, self.length), self.UTF8String ?: "");
    return %orig(path, u, e, err);
}
%end

%hook NSDictionary
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)u {
    RLogC("WRITE-Dict %s", path.UTF8String ?: "?");
    return %orig(path, u);
}
%end

%hookf(void, _os_log_impl, void *dso, os_log_t log, os_log_type_t type, const char *fmt, uint8_t *buffer, uint32_t size) {
    if (fmt) RLogC("APP-OSLOG type=%u size=%u fmt=%s", (unsigned)type, (unsigned)size, fmt);
    %orig(dso, log, type, fmt, buffer, size);
}

%hookf(void, NSLog, NSString *format, ...) {
    RLogC("NSLOG-FMT %s", format ? [format UTF8String] : "(nil)");
}

%hookf(void, CCHmac, CCHmacAlgorithm algorithm, const void *key, size_t keyLength, const void *data, size_t dataLength, void *macOut) {
    RLogC("CCHMAC alg=%lu keyLen=%lu key=%.*s | dataLen=%lu data=%.*s",
          (unsigned long)algorithm, (unsigned long)keyLength, (int)MIN(keyLength,(size_t)200), key?(const char*)key:"",
          (unsigned long)dataLength, (int)MIN(dataLength,(size_t)4000), data?(const char*)data:"");
    %orig(algorithm, key, keyLength, data, dataLength, macOut);
}

%hookf(OSStatus, SecTrustEvaluate, SecTrustRef trust, SecTrustResultType *res) {
    if (res) *res = kSecTrustResultProceed;
    return errSecSuccess;
}
