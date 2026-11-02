// ═══════════════════════════════════════════════════════════════
//  CrackRecon v1.0 — استطلاع ANUBIS (PUBG) | ZAIN iOS Tools
//  سلبي 100%: يلتقط الترخيص الحي بدون أي تداخل
//  اللوق: /var/mobile/Documents/crack_recon.log
// ═══════════════════════════════════════════════════════════════
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <objc/runtime.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <os/log.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>

static const char *cr_logpath(void) {
    static char path[1024] = {0};
    if (path[0]) return path;
    // المسار داخل حاوية التطبيق (يخترق Sandbox) — مع fallback
    NSString *home = NSHomeDirectory();
    NSString *docs = [home stringByAppendingPathComponent:@"Documents/crack_recon.log"];
    if ([docs length] < 900) {
        strcpy(path, [docs UTF8String]);
    } else {
        strcpy(path, "/tmp/crack_recon.log");
    }
    return path;
}

static void CRLog(const char *fmt, ...) {
    static __thread int inlog = 0;
    if (inlog) return;
    inlog = 1;
    char b[2048];
    va_list a; va_start(a, fmt); vsnprintf(b, sizeof b, fmt, a); va_end(a);
    struct timeval tv; gettimeofday(&tv, NULL);
    time_t t = tv.tv_sec;
    struct tm gm; gmtime_r(&t, &gm);
    char line[2600];
    snprintf(line, sizeof line, "%04d-%02d-%02d %02d:%02d:%02d.%03d %s\n",
        gm.tm_year+1900, gm.tm_mon+1, gm.tm_mday, gm.tm_hour, gm.tm_min, gm.tm_sec,
        (int)(tv.tv_usec/1000), b);
    int fd = open(cr_logpath(), O_WRONLY|O_CREAT|O_APPEND, 0644);
    if (fd >= 0) { write(fd, line, strlen(line)); close(fd); }
    inlog = 0;
}

static NSString *cr_hex(NSData *d, NSUInteger max) {
    if (!d) return @"(nil)";
    const unsigned char *b = (const unsigned char *)[d bytes];
    NSUInteger n = MIN([d length], max);
    NSMutableString *s = [NSMutableString stringWithCapacity:n*2];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%02X", b[i]];
    if ([d length] > max) [s appendString:@"..."];
    return s;
}

static BOOL cr_interesting(NSString *k) {
    if (!k) return NO;
    NSString *l = [k lowercaseString];
    NSArray *w = @[@"key",@"licen",@"token",@"expir",@"uid",@"hwid",@"device",
                   @"serial",@"auth",@"valid",@"sub",@"vip",@"user",@"pass",
                   @"session",@"uuid",@"idfa",@"idfv",@"anubis",@"pubg"];
    for (NSString *x in w) if ([l containsString:x]) return YES;
    return NO;
}

// ─── 1) Keychain الكامل ───
static void cr_kcdesc(CFDictionaryRef query, const char *tag) {
    if (!query) return;
    NSString *svce = (__bridge NSString *)CFDictionaryGetValue(query, kSecAttrService);
    NSString *acct = (__bridge NSString *)CFDictionaryGetValue(query, kSecAttrAccount);
    NSString *klass = CFDictionaryGetValue(query, kSecClass) == kSecClassGenericPassword ? @"genp" : @"?";
    CRLog("KC-%s class=%s svce=%s acct=%s", tag, [klass UTF8String],
          svce ? [svce UTF8String] : "?", acct ? [acct UTF8String] : "?");
}

%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef q, CFTypeRef *res) {
    if (q) {
        cr_kcdesc(q, "FIND");
        NSString *svce = (__bridge NSString *)CFDictionaryGetValue(q, kSecAttrService);
        if (svce && ([svce.lowercaseString containsString:@"anubis"] ||
                     [svce.lowercaseString containsString:@"pubg"] ||
                     [svce.lowercaseString containsString:@"license"] ||
                     [svce.lowercaseString containsString:@"tempmail"])) {
            CRLog("KC-INTERESTING svce=%s", [svce UTF8String]);
        }
    }
    OSStatus s = %orig;
    if (s == errSecSuccess && res && *res) {
        if (CFGetTypeID(*res) == CFDataGetTypeID()) {
            CRLog("KC-RESULT data=%s", [cr_hex((__bridge NSData *)*res, 64) UTF8String]);
        } else if (CFGetTypeID(*res) == CFDictionaryGetTypeID()) {
            NSDictionary *d = (__bridge NSDictionary *)*res;
            NSData *v = d[(__bridge id)kSecValueData];
            if (v) CRLog("KC-RESULT dict data=%s", [cr_hex(v, 64) UTF8String]);
        }
    } else if (s != errSecSuccess) {
        CRLog("KC-MISS status=%d", (int)s);
    }
    return s;
}

%hookf(OSStatus, SecItemAdd, CFDictionaryRef q, CFTypeRef *res) {
    if (q) {
        cr_kcdesc(q, "ADD");
        NSData *v = (__bridge NSData *)CFDictionaryGetValue(q, kSecValueData);
        if (v) CRLog("KC-ADD data=%s", [cr_hex(v, 64) UTF8String]);
    }
    return %orig;
}

%hookf(OSStatus, SecItemUpdate, CFDictionaryRef q, CFDictionaryRef attr) {
    if (q) cr_kcdesc(q, "UPDATE");
    if (attr) {
        NSData *v = (__bridge NSData *)CFDictionaryGetValue(attr, kSecValueData);
        if (v) CRLog("KC-UPDATE data=%s", [cr_hex(v, 64) UTF8String]);
    }
    return %orig;
}

%hookf(OSStatus, SecItemDelete, CFDictionaryRef q) {
    if (q) cr_kcdesc(q, "DELETE");
    return %orig;
}

// ─── 2) NSUserDefaults ───
%hook NSUserDefaults
- (id)objectForKey:(NSString *)k {
    id v = %orig;
    if (cr_interesting(k)) CRLog("UD-GET %s -> %s", [k UTF8String], [[v description] UTF8String]);
    return v;
}
- (void)setObject:(id)v forKey:(NSString *)k {
    if (cr_interesting(k)) CRLog("UD-SET %s = %s", [k UTF8String], [[v description] UTF8String]);
    %orig;
}
- (NSString *)stringForKey:(NSString *)k {
    NSString *v = %orig;
    if (cr_interesting(k)) CRLog("UD-STR %s -> %s", [k UTF8String], [v UTF8String]);
    return v;
}
- (BOOL)boolForKey:(NSString *)k {
    BOOL v = %orig;
    if (cr_interesting(k)) CRLog("UD-BOOL %s -> %d", [k UTF8String], v);
    return v;
}
%end

// ─── 3) الشبكة: NSURLSession + NSURLConnection ───
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)req completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    CRLog("NET REQ %s %s", [req.HTTPMethod UTF8String], [req.URL.absoluteString UTF8String]);
    if (req.HTTPBody) CRLog("NET BODY %s", [cr_hex(req.HTTPBody, 512) UTF8String]);
    if (cb) {
        void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *resp, NSError *e) {
            NSHTTPURLResponse *h = (NSHTTPURLResponse *)resp;
            CRLog("NET RESP %s status=%ld len=%lu", [req.URL.absoluteString UTF8String],
                  (long)h.statusCode, (unsigned long)d.length);
            if (d) CRLog("NET DATA %s", [[[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] description] UTF8String]);
            cb(d, resp, e);
        };
        return %orig(req, wrapped);
    }
    return %orig;
}
%end

%hook NSURLConnection
+ (void)sendAsynchronousRequest:(NSURLRequest *)req queue:(NSOperationQueue *)q completionHandler:(void (^)(NSURLResponse *, NSData *, NSError *))cb {
    CRLog("NET ASYNC %s", [req.URL.absoluteString UTF8String]);
    if (cb) {
        void (^wrapped)(NSURLResponse *, NSData *, NSError *) = ^(NSURLResponse *resp, NSData *d, NSError *e) {
            CRLog("NET ASYNC RESP %s len=%lu", [req.URL.absoluteString UTF8String], (unsigned long)d.length);
            if (d) CRLog("NET ASYNC DATA %s", [[[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] description] UTF8String]);
            cb(resp, d, e);
        };
        %orig(req, q, wrapped);
        return;
    }
    %orig;
}
%end

%hook NSURLRequest
- (id)initWithURL:(NSURL *)url {
    CRLog("REQ-INIT %s", [url.absoluteString UTF8String]);
    return %orig;
}
%end

// ─── 4) JSON المُستلم ───
%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)d options:(NSJSONReadingOptions)o error:(NSError **)e {
    id v = %orig;
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (s && ![s containsString:@"AHAP"] && ![s containsString:@"Haptic"])
        CRLog("JSON-IN %s", [s UTF8String]);
    return v;
}
%end

%hook NSDictionary
- (id)objectForKey:(id)k {
    id v = %orig;
    if ([k isKindOfClass:[NSString class]] && cr_interesting((NSString *)k))
        CRLog("DICT-GET %s -> %s", [(NSString *)k UTF8String], [[v description] UTF8String]);
    return v;
}
%end

// ─── 5) الأسرار: CCHmac + هاشات ───
%hookf(void, CCHmac, CCHmacAlgorithm alg, const void *key, size_t keyLen,
       const void *data, size_t dataLen, void *macOut) {
    CRLog("HMAC alg=%d keyLen=%zu key=%s data=%s", (int)alg, keyLen,
          [[NSData dataWithBytes:key length:MIN(keyLen,64)] description].UTF8String,
          [[NSData dataWithBytes:data length:MIN(dataLen,64)] description].UTF8String);
    %orig;
}

%hookf(unsigned char *, CC_SHA256, const void *d, CC_LONG len, unsigned char *md) {
    unsigned char *r = %orig;
    CRLog("SHA256 in=%s out=%s", [[NSData dataWithBytes:d length:MIN(len,48)] description].UTF8String,
          [[NSData dataWithBytes:r length:16] description].UTF8String);
    return r;
}

// ─── 6) اكتشاف السيرفر حتى مع curl: connect + getaddrinfo ───
%hookf(int, connect, int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (addr && (addr->sa_family == AF_INET || addr->sa_family == AF_INET6)) {
        char host[128] = {0};
        if (addr->sa_family == AF_INET)
            inet_ntop(AF_INET, &((struct sockaddr_in *)addr)->sin_addr, host, sizeof host);
        else
            inet_ntop(AF_INET6, &((struct sockaddr_in6 *)addr)->sin6_addr, host, sizeof host);
        CRLog("CONNECT %s", host);
    }
    return %orig;
}

%hookf(int, getaddrinfo, const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res) {
    int r = %orig;
    if (node) CRLog("DNS %s", node);
    return r;
}

// ─── 7) سجل التطبيق نفسه (NSLog/os_log قد يكشفان التدفق) ───
%hookf(void, NSLog, NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a];
    va_end(a);
    CRLog("APP-NSLOG %s", [s UTF8String]);
    // تمرير آمن بدون استدعاء NSLog الأصلي المخطوف
    static void (*orig_nslog)(NSString *, ...);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        orig_nslog = (void (*)(NSString *, ...))dlsym(RTLD_NEXT, "NSLog");
    });
    if (orig_nslog) orig_nslog(@"%@", s);
}

// ─── 8) ملفات الترخيص + dlopen ───
%hook NSString
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)at encoding:(NSStringEncoding)enc error:(NSError **)err {
    CRLog("WRITE %s len=%lu", [path UTF8String], (unsigned long)[self length]);
    return %orig;
}
%end

%hookf(void *, dlopen, const char *path, int mode) {
    void *r = %orig;
    if (path) CRLog("DLOPEN %s -> %s", path, r ? "ok" : "FAIL");
    return r;
}

// ─── 9) الثقة (مراقبة فقط) ───
%hookf(OSStatus, SecTrustEvaluate, SecTrustRef trust, SecTrustResultType *res) {
    OSStatus s = %orig;
    CRLog("TRUST result=%d", res ? (int)*res : -1);
    return s;
}


// ─── 6ب) Network.framework — كشف مسار nw/QUIC الخفي ───
#import <Network/Network.h>

%hookf(nw_connection_t, nw_connection_create, nw_endpoint_t endpoint, nw_parameters_t params) {
    const char *host = endpoint ? nw_endpoint_get_hostname(endpoint) : NULL;
    uint16_t port = endpoint ? nw_endpoint_get_port(endpoint) : 0;
    CRLog("NW-CONN host=%s port=%u", host ? host : "?", port);
    return %orig;
}

%hookf(void, nw_connection_send, nw_connection_t conn, dispatch_data_t content,
       nw_content_context_t ctx, bool complete, nw_connection_send_completion_t completion) {
    if (content) {
        const void *buf = NULL; size_t len = 0;
        dispatch_data_create_map(content, &buf, &len);
        CRLog("NW-SEND len=%zu %s", len,
              [[NSData dataWithBytes:buf length:MIN(len, 768)] description].UTF8String);
    }
    %orig;
}

%hookf(void, nw_connection_receive, nw_connection_t conn, uint32_t minimum,
       uint32_t maximum, nw_connection_receive_completion_t completion) {
    if (completion) {
        nw_connection_receive_completion_t wrapped =
        ^(dispatch_data_t content, nw_content_context_t ctx, bool complete, nw_error_t error) {
            if (content) {
                const void *buf = NULL; size_t len = 0;
                dispatch_data_create_map(content, &buf, &len);
                CRLog("NW-RECV len=%zu %s", len,
                      [[NSData dataWithBytes:buf length:MIN(len, 2048)] description].UTF8String);
            }
            completion(content, ctx, complete, error);
        };
        %orig(conn, minimum, maximum, wrapped);
        return;
    }
    %orig;
}

%hookf(int, connectx, int sockfd, const sa_endpoints_t *endpoints, sae_associd_t associd,
       unsigned int flags, const struct iovec *iov, unsigned int iovcnt,
       size_t *bytes_sent, int *reserved) {
    if (endpoints && endpoints->sae_dstaddr) {
        char host[128] = {0};
        const struct sockaddr *sa = endpoints->sae_dstaddr;
        if (sa->sa_family == AF_INET)
            inet_ntop(AF_INET, &((struct sockaddr_in *)sa)->sin_addr, host, sizeof host);
        else if (sa->sa_family == AF_INET6)
            inet_ntop(AF_INET6, &((struct sockaddr_in6 *)sa)->sin6_addr, host, sizeof host);
        CRLog("CONNECTX %s", host);
    }
    return %orig;
}


// ─── 6ج) طبقة التطبيق الصريحة: nghttp2 (H2 على ذاكرة مفكوكة) + send/recv ───
typedef void *cr_nghttp2_session;
typedef long cr_nghttp2_ssize;
extern "C" {
extern cr_nghttp2_ssize nghttp2_session_mem_recv(cr_nghttp2_session, const uint8_t *, size_t);
extern cr_nghttp2_ssize nghttp2_session_mem_recv2(cr_nghttp2_session, const uint8_t *, size_t);
extern cr_nghttp2_ssize nghttp2_session_mem_send(cr_nghttp2_session, const uint8_t **);
extern cr_nghttp2_ssize nghttp2_session_mem_send2(cr_nghttp2_session, const uint8_t **);
}

%hookf(cr_nghttp2_ssize, nghttp2_session_mem_recv, cr_nghttp2_session session, const uint8_t *data, size_t len) {
    CRLog("H2-RECV len=%zu %s", len,
          [[NSData dataWithBytes:data length:MIN(len, 3000)] description].UTF8String);
    return %orig;
}

%hookf(cr_nghttp2_ssize, nghttp2_session_mem_recv2, cr_nghttp2_session session, const uint8_t *data, size_t len) {
    CRLog("H2-RECV2 len=%zu %s", len,
          [[NSData dataWithBytes:data length:MIN(len, 3000)] description].UTF8String);
    return %orig;
}

%hookf(cr_nghttp2_ssize, nghttp2_session_mem_send, cr_nghttp2_session session, const uint8_t **data_ptr) {
    ssize_t r = %orig;
    if (r > 0 && data_ptr && *data_ptr)
        CRLog("H2-SEND len=%zd %s", r,
              [[NSData dataWithBytes:*data_ptr length:MIN((size_t)r, 3000)] description].UTF8String);
    return r;
}

%hookf(cr_nghttp2_ssize, nghttp2_session_mem_send2, cr_nghttp2_session session, const uint8_t **data_ptr) {
    cr_nghttp2_ssize r = %orig;
    if (r > 0 && data_ptr && *data_ptr)
        CRLog("H2-SEND2 len=%zd %s", (ssize_t)r,
              [[NSData dataWithBytes:*data_ptr length:MIN((size_t)r, 3000)] description].UTF8String);
    return r;
}

static void cr_peer(int sockfd, char *host, size_t hostlen, int *port) {
    struct sockaddr_storage ss; socklen_t sl = sizeof ss;
    if (getpeername(sockfd, (struct sockaddr *)&ss, &sl) == 0) {
        if (ss.ss_family == AF_INET) {
            inet_ntop(AF_INET, &((struct sockaddr_in *)&ss)->sin_addr, host, hostlen);
            if (port) *port = ntohs(((struct sockaddr_in *)&ss)->sin_port);
        } else if (ss.ss_family == AF_INET6) {
            inet_ntop(AF_INET6, &((struct sockaddr_in6 *)&ss)->sin6_addr, host, hostlen);
            if (port) *port = ntohs(((struct sockaddr_in6 *)&ss)->sin6_port);
        }
    }
}

%hookf(ssize_t, send, int sockfd, const void *buf, size_t len, int flags) {
    char host[128] = {0}; int port = 0;
    cr_peer(sockfd, host, sizeof host, &port);
    if (host[0]) CRLog("SEND %s:%d len=%zu %s", host, port, len,
                       [[NSData dataWithBytes:buf length:MIN(len,384)] description].UTF8String);
    return %orig;
}

%hookf(ssize_t, recv, int sockfd, void *buf, size_t len, int flags) {
    ssize_t r = %orig;
    if (r > 0) {
        char host[128] = {0}; int port = 0;
        cr_peer(sockfd, host, sizeof host, &port);
        if (host[0]) CRLog("RECV %s:%d len=%zd %s", host, port, r,
                           [[NSData dataWithBytes:buf length:MIN((size_t)r,384)] description].UTF8String);
    }
    return r;
}

%hookf(ssize_t, sendto, int sockfd, const void *buf, size_t len, int flags,
       const struct sockaddr *dest, socklen_t destlen) {
    if (dest) {
        char host[128] = {0};
        if (dest->sa_family == AF_INET) inet_ntop(AF_INET, &((struct sockaddr_in *)dest)->sin_addr, host, sizeof host);
        else if (dest->sa_family == AF_INET6) inet_ntop(AF_INET6, &((struct sockaddr_in6 *)dest)->sin6_addr, host, sizeof host);
        if (host[0]) CRLog("SENDTO %s len=%zu", host, len);
    }
    return %orig;
}

%hookf(ssize_t, recvfrom, int sockfd, void *buf, size_t len, int flags,
       struct sockaddr *src, socklen_t *srclen) {
    ssize_t r = %orig;
    if (r > 0 && src) {
        char host[128] = {0};
        if (src->sa_family == AF_INET) inet_ntop(AF_INET, &((struct sockaddr_in *)src)->sin_addr, host, sizeof host);
        else if (src->sa_family == AF_INET6) inet_ntop(AF_INET6, &((struct sockaddr_in6 *)src)->sin6_addr, host, sizeof host);
        if (host[0]) CRLog("RECVFROM %s len=%zd", host, r);
    }
    return r;
}

%ctor {
    CRLog("=== CrackRecon v1.0 injected | pid=%d ===", getpid());
}
