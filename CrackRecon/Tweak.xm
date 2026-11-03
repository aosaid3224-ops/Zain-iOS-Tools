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
#include <sys/uio.h>
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

static uint8_t cr_bait_digest[32];
static BOOL cr_have_digest = NO;
#define CR_BAIT "ABCD1234ABCD1234ABCD1234ABCD1234"

%hookf(unsigned char *, CC_SHA256, const void *d, CC_LONG len, unsigned char *md) {
    unsigned char *r = %orig;
    if (len != 2 && len != 14 && len != 48) {
        CRLog("SHA256* in(len=%d)=%s out=%s", len,
              [[NSData dataWithBytes:d length:MIN(len,64)] description].UTF8String,
              [[NSData dataWithBytes:r length:16] description].UTF8String);
        if (len >= 8 && d && memmem(d, len, "ABCD1234", 8)) {
            memcpy(cr_bait_digest, r, 32);
            cr_have_digest = YES;
            CRLog("BAIT-DIGEST %s", [[NSData dataWithBytes:r length:32] description].UTF8String);
        }
    }
    return r;
}

%hookf(int, memcmp, const void *a, const void *b, size_t len) {
    if (len == 32 && cr_have_digest && a && b) {
        const uint8_t *pa = (const uint8_t *)a, *pb = (const uint8_t *)b;
        BOOL ma = YES, mb = YES;
        for (int i = 0; i < 32; i++) { if (pa[i] != cr_bait_digest[i]) ma = NO; if (pb[i] != cr_bait_digest[i]) mb = NO; }
        if (ma || mb) { CRLog("MEMCMP32-HIT -> forced EQUAL"); return 0; }
    }
    return %orig;
}

%hookf(int, bcmp, const void *a, const void *b, size_t len) {
    if (len == 32 && cr_have_digest && a && b) {
        const uint8_t *pa = (const uint8_t *)a, *pb = (const uint8_t *)b;
        BOOL ma = YES, mb = YES;
        for (int i = 0; i < 32; i++) { if (pa[i] != cr_bait_digest[i]) ma = NO; if (pb[i] != cr_bait_digest[i]) mb = NO; }
        if (ma || mb) { CRLog("BCMP32-HIT -> forced EQUAL"); return 0; }
    }
    return %orig;
}

%hookf(int, strcmp, const char *a, const char *b) {
    if (a && b && (strstr(a, "ABCD1234") || strstr(b, "ABCD1234")))
        CRLog("STRCMP-BAIT [%s] vs [%s]", a, b);
    return %orig;
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


// ─── 6ج) طبقة nghttp2 عبر hook بالعنوان (الرموز static داخل التطبيق) ───
#include <substrate.h>
#include <mach-o/nlist.h>
#include <mach-o/loader.h>

typedef void *cr_nghttp2_session;
typedef long cr_nghttp2_ssize;
typedef struct { uint8_t *name; uint8_t *value; size_t namelen; size_t valuelen; uint8_t flags; } cr_nghttp2_nv;
static int my_submit_req(cr_nghttp2_session, const void *, const cr_nghttp2_nv *, size_t, const void *, void *);
static int (*orig_submit_req)(cr_nghttp2_session, const void *, const cr_nghttp2_nv *, size_t, const void *, void *) = NULL;

static cr_nghttp2_ssize (*orig_mrecv)(cr_nghttp2_session, const uint8_t *, size_t);
static cr_nghttp2_ssize (*orig_mrecv2)(cr_nghttp2_session, const uint8_t *, size_t);
static cr_nghttp2_ssize (*orig_msend)(cr_nghttp2_session, const uint8_t **);
static cr_nghttp2_ssize (*orig_msend2)(cr_nghttp2_session, const uint8_t **);

static cr_nghttp2_ssize my_mrecv(cr_nghttp2_session s, const uint8_t *data, size_t len) {
    if (data && len > 0)
        CRLog("H2-RECV len=%zu %s", len,
              [[NSData dataWithBytes:data length:MIN(len, 3000)] description].UTF8String);
    return orig_mrecv(s, data, len);
}
static cr_nghttp2_ssize my_mrecv2(cr_nghttp2_session s, const uint8_t *data, size_t len) {
    if (data && len > 0)
        CRLog("H2-RECV2 len=%zu %s", len,
              [[NSData dataWithBytes:data length:MIN(len, 3000)] description].UTF8String);
    return orig_mrecv2(s, data, len);
}
static cr_nghttp2_ssize my_msend(cr_nghttp2_session s, const uint8_t **data_ptr) {
    cr_nghttp2_ssize r = orig_msend(s, data_ptr);
    if (r > 0 && data_ptr && *data_ptr)
        CRLog("H2-SEND len=%zd %s", (ssize_t)r,
              [[NSData dataWithBytes:*data_ptr length:MIN((size_t)r, 3000)] description].UTF8String);
    return r;
}
static cr_nghttp2_ssize my_msend2(cr_nghttp2_session s, const uint8_t **data_ptr) {
    cr_nghttp2_ssize r = orig_msend2(s, data_ptr);
    if (r > 0 && data_ptr && *data_ptr)
        CRLog("H2-SEND2 len=%zd %s", (ssize_t)r,
              [[NSData dataWithBytes:*data_ptr length:MIN((size_t)r, 3000)] description].UTF8String);
    return r;
}

static const void *cr_off2mem(const struct mach_header_64 *mh, intptr_t slide, uint64_t fileoff) {
    uint32_t ncmds = mh->ncmds;
    const uint8_t *q = (const uint8_t *)(mh + 1);
    for (uint32_t i = 0; i < ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)q;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *sg = (const struct segment_command_64 *)lc;
            if (sg->filesize && fileoff >= sg->fileoff && fileoff < sg->fileoff + sg->filesize)
                return (const void *)(slide + sg->vmaddr + (fileoff - sg->fileoff));
        }
        q += lc->cmdsize;
    }
    return NULL;
}

static void *cr_find_sym(const char *name) {
    const struct mach_header_64 *mh = NULL;
    intptr_t slide = 0;
    uint32_t cnt = _dyld_image_count();
    for (uint32_t i = 0; i < cnt; i++) {
        const char *p = _dyld_get_image_name(i);
        if (p && strstr(p, "TempMail")) {
            mh = (const struct mach_header_64 *)_dyld_get_image_header(i);
            slide = _dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    if (!mh) return NULL;
    uint32_t ncmds = mh->ncmds;
    const uint8_t *q = (const uint8_t *)(mh + 1);
    uint32_t symoff = 0, nsyms = 0, stroff = 0;
    for (uint32_t i = 0; i < ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)q;
        if (lc->cmd == LC_SYMTAB) {
            const struct symtab_command *sc = (const struct symtab_command *)lc;
            symoff = sc->symoff; nsyms = sc->nsyms; stroff = sc->stroff;
            break;
        }
        q += lc->cmdsize;
    }
    if (!symoff || !nsyms) return NULL;
    const struct nlist_64 *syms = (const struct nlist_64 *)cr_off2mem(mh, slide, symoff);
    const char *strs = (const char *)cr_off2mem(mh, slide, stroff);
    if (!syms || !strs) return NULL;
    for (uint32_t i = 0; i < nsyms; i++) {
        const struct nlist_64 *nl = &syms[i];
        if (!nl->n_value) continue;
        if (strcmp(strs + nl->n_un.n_strx, name) == 0)
            return (void *)(nl->n_value + slide);
    }
    return NULL;
}

static void cr_hook_h2(void) {
    void *p;
    if ((p = cr_find_sym("nghttp2_session_mem_recv")))
        MSHookFunction(p, (void *)my_mrecv, (void **)&orig_mrecv);
    if ((p = cr_find_sym("nghttp2_session_mem_recv2")))
        MSHookFunction(p, (void *)my_mrecv2, (void **)&orig_mrecv2);
    if ((p = cr_find_sym("nghttp2_session_mem_send")))
        MSHookFunction(p, (void *)my_msend, (void **)&orig_msend);
    if ((p = cr_find_sym("nghttp2_session_mem_send2")))
        MSHookFunction(p, (void *)my_msend2, (void **)&orig_msend2);
    if ((p = cr_find_sym("nghttp2_submit_request")))
        MSHookFunction(p, (void *)my_submit_req, (void **)&orig_submit_req);
    CRLog("H2 hooks installed: %d", (orig_mrecv||orig_mrecv2||orig_msend||orig_msend2||orig_submit_req)?1:0);
}


// ─── 6د) الفجوة الأخيرة: write/read (POSIX sockets) + sendmsg/recvmsg ───
static BOOL cr_issock(int fd, char *host, size_t hlen, int *port) {
    struct sockaddr_storage ss; socklen_t sl = sizeof ss;
    if (getpeername(fd, (struct sockaddr *)&ss, &sl) != 0) return NO;
    if (ss.ss_family == AF_INET) {
        inet_ntop(AF_INET, &((struct sockaddr_in *)&ss)->sin_addr, host, hlen);
        if (port) *port = ntohs(((struct sockaddr_in *)&ss)->sin_port);
        return YES;
    }
    if (ss.ss_family == AF_INET6) {
        inet_ntop(AF_INET6, &((struct sockaddr_in6 *)&ss)->sin6_addr, host, hlen);
        if (port) *port = ntohs(((struct sockaddr_in6 *)&ss)->sin6_port);
        return YES;
    }
    return NO;
}

%hookf(ssize_t, write, int fd, const void *buf, size_t len) {
    if (len > 0) {
        char host[128] = {0}; int port = 0;
        if (cr_issock(fd, host, sizeof host, &port))
            CRLog("WRITE %s:%d len=%zu %s", host, port, len,
                  [[NSData dataWithBytes:buf length:MIN(len,768)] description].UTF8String);
    }
    return %orig;
}

%hookf(ssize_t, read, int fd, void *buf, size_t len) {
    ssize_t r = %orig;
    if (r > 0) {
        char host[128] = {0}; int port = 0;
        if (cr_issock(fd, host, sizeof host, &port))
            CRLog("READ %s:%d len=%zd %s", host, port, r,
                  [[NSData dataWithBytes:buf length:MIN((size_t)r,768)] description].UTF8String);
    }
    return r;
}

%hookf(ssize_t, sendmsg, int s, const struct msghdr *m, int flags) {
    if (m && m->msg_name) {
        const struct sockaddr *sa = (const struct sockaddr *)m->msg_name;
        char host[128] = {0};
        if (sa->sa_family == AF_INET) inet_ntop(AF_INET, &((struct sockaddr_in *)sa)->sin_addr, host, sizeof host);
        else if (sa->sa_family == AF_INET6) inet_ntop(AF_INET6, &((struct sockaddr_in6 *)sa)->sin6_addr, host, sizeof host);
        if (host[0]) CRLog("SENDMSG %s len=%zu", host, m->msg_iovlen ? (size_t)m->msg_iov[0].iov_len : 0);
    }
    return %orig;
}

%hookf(ssize_t, recvmsg, int s, struct msghdr *m, int flags) {
    ssize_t r = %orig;
    if (r > 0 && m && m->msg_name) {
        const struct sockaddr *sa = (const struct sockaddr *)m->msg_name;
        char host[128] = {0};
        if (sa->sa_family == AF_INET) inet_ntop(AF_INET, &((struct sockaddr_in *)sa)->sin_addr, host, sizeof host);
        else if (sa->sa_family == AF_INET6) inet_ntop(AF_INET6, &((struct sockaddr_in6 *)sa)->sin6_addr, host, sizeof host);
        if (host[0]) CRLog("RECVMSG %s len=%zd", host, r);
    }
    return r;
}

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    CRLog("NET URL-TASK %s", [url.absoluteString UTF8String]);
    return %orig;
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    CRLog("NET URL-TASK2 %s", [url.absoluteString UTF8String]);
    if (cb) {
        void (^w)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *resp, NSError *e) {
            CRLog("NET URL-RESP %s len=%lu", [url.absoluteString UTF8String], (unsigned long)d.length);
            if (d) CRLog("NET URL-DATA %s", [[[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] description] UTF8String]);
            cb(d, resp, e);
        };
        return %orig(url, w);
    }
    return %orig;
}
%end


// ─── 6ه) v1.8: submit_request (headers) + readv/writev ───
extern "C" int nghttp2_submit_request(cr_nghttp2_session, const void *, const cr_nghttp2_nv *, size_t, const void *, void *);

static int my_submit_req(cr_nghttp2_session s, const void *pri, const cr_nghttp2_nv *nva,
                         size_t nvlen, const void *prd, void *ud) {
    CRLog("H2-REQUEST nv=%zu", nvlen);
    for (size_t i = 0; i < nvlen && nva; i++) {
        NSString *k = [[NSString alloc] initWithBytes:nva[i].name length:nva[i].namelen encoding:NSUTF8StringEncoding];
        NSString *v = [[NSString alloc] initWithBytes:nva[i].value length:nva[i].valuelen encoding:NSUTF8StringEncoding];
        CRLog("  %s: %s", k ? [k UTF8String] : "?", v ? [v UTF8String] : "?");
    }
    return orig_submit_req(s, pri, nva, nvlen, prd, ud);
}

%hookf(ssize_t, writev, int fd, const struct iovec *iov, int iovcnt) {
    if (iovcnt > 0) {
        char host[128] = {0}; int port = 0;
        if (cr_issock(fd, host, sizeof host, &port)) {
            NSMutableData *all = [NSMutableData data];
            for (int i = 0; i < iovcnt && i < 8; i++)
                if (iov[i].iov_base && iov[i].iov_len) [all appendBytes:iov[i].iov_base length:iov[i].iov_len];
            CRLog("WRITEV %s:%d iov=%d %s", host, port, iovcnt,
                  [[NSData dataWithBytes:all.bytes length:MIN(all.length,768)] description].UTF8String);
        }
    }
    return %orig;
}

%hookf(ssize_t, readv, int fd, const struct iovec *iov, int iovcnt) {
    ssize_t r = %orig;
    if (r > 0) {
        char host[128] = {0}; int port = 0;
        if (cr_issock(fd, host, sizeof host, &port)) {
            NSMutableData *all = [NSMutableData data];
            size_t left = (size_t)r;
            for (int i = 0; i < iovcnt && i < 8 && left > 0; i++) {
                size_t take = MIN(left, iov[i].iov_len);
                if (iov[i].iov_base && take) [all appendBytes:iov[i].iov_base length:take];
                left -= take;
            }
            CRLog("READV %s:%d len=%zd %s", host, port, r,
                  [[NSData dataWithBytes:all.bytes length:MIN(all.length,768)] description].UTF8String);
        }
    }
    return r;
}

#import <execinfo.h>
%hook UIAlertController
- (instancetype)initWithTitle:(id)title message:(id)message preferredStyle:(long)style {
    if ([message isKindOfClass:[NSString class]] &&
        [(NSString *)message containsString:@"Key not found"]) {
        void *cs[24]; int n = backtrace(cs, 24);
        char **s = backtrace_symbols(cs, n);
        CRLog("ALERT-BT frames=%d", n);
        for (int i = 0; i < n; i++) CRLog("  %s", s[i]);
        free(s);
    }
    return %orig;
}
%end

%ctor {
    cr_hook_h2();
    CRLog("=== CrackRecon v1.0 injected | pid=%d ===", getpid());
}
