// ANUBISCrack v5 — Full-Spectrum Capture (Zain Ghost Protocol)
// اختبار تحكم + NSURLSession + NSURLConnection + OpenSSL-direct + كل مسارات التنبيه
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <substrate.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <objc/runtime.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <libkern/OSCacheControl.h>

static uintptr_t g_checkFuncAddr = 0x0;

#pragma mark flog
static void flog(NSString *fmt, ...) {
    @try {
        va_list ap; va_start(ap, fmt);
        NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
        va_end(ap);
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *paths = @[
            [NSTemporaryDirectory() stringByAppendingPathComponent:@"anubis_crack.log"],
            @"/var/mobile/anubis_crack.log"
        ];
        for (NSString *path in paths) {
            if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
            if (!h) continue;
            [h seekToEndOfFile];
            [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [h closeFile];
        }
    } @catch (NSException *e) {}
}
#define RL(name, maxn, ...) do { static int c_##name = 0; if (c_##name < (maxn)) { c_##name++; flog(__VA_ARGS__); } } while (0)

static void logbuf(const char *tag, const void *buf, int len) {
    if (!buf || len <= 0) return;
    const unsigned char *p = (const unsigned char *)buf;
    NSMutableString *runs = [NSMutableString string];
    NSMutableString *cur = [NSMutableString string];
    int cap = len > 4096 ? 4096 : len;
    for (int i = 0; i < cap; i++) {
        unsigned char c = p[i];
        if (c >= 32 && c < 127) [cur appendFormat:@"%c", c];
        else { if (cur.length >= 4) { [runs appendString:cur]; [runs appendString:@" | "]; } [cur setString:@""]; }
    }
    if (cur.length >= 4) [runs appendString:cur];
    if (runs.length > 0) flog(@"[%s len=%d] %@", tag, len, runs);
}

#pragma mark اختبار التحكم: UIView
static id (*orig_view)(id, SEL, CGRect);
static id hook_view(id self, SEL _cmd, CGRect f) {
    RL(ctrl, 3, @"[CTRL] UIView initWithFrame fired — MSHook WORKS");
    return orig_view(self, _cmd, f);
}

#pragma mark التنبيهات: كل المسارات
static void log_bt(void) {
    void *bt[20]; int n = backtrace(bt, 20);
    char **syms = backtrace_symbols(bt, n);
    for (int i = 0; i < n; i++) flog(@"  bt[%d] %s", i, syms[i]);
    free(syms);
}
static id (*orig_alert)(id, SEL, id, id, NSInteger);
static id hook_alert(id self, SEL _cmd, id t, id m, NSInteger s) {
    RL(al, 30, @"[ALERT+] t=%@ m=%@", t, m); log_bt();
    return orig_alert(self, _cmd, t, m, s);
}
static id (*orig_initA)(id, SEL, id, id, NSInteger);
static id hook_initA(id self, SEL _cmd, id t, id m, NSInteger s) {
    RL(ai, 30, @"[ALERT-init] t=%@ m=%@", t, m); log_bt();
    return orig_initA(self, _cmd, t, m, s);
}
static void (*orig_addAction)(id, SEL, id);
static void hook_addAction(id self, SEL _cmd, id a) {
    RL(aa, 30, @"[ALERT addAction] %@", a);
    orig_addAction(self, _cmd, a);
}
static id (*orig_av)(id, SEL, id, id, id, id, ...);
static id hook_av(id self, SEL _cmd, id t, id m, id d, id c, ...) {
    RL(av, 30, @"[ALERTVIEW] t=%@ m=%@", t, m); log_bt();
    va_list ap; va_start(ap, c);
    id arg; NSMutableString *o = [NSMutableString string];
    while ((arg = va_arg(ap, id))) [o appendFormat:@"%@,", arg];
    va_end(ap);
    if (o.length) { RL(av2, 5, @"[ALERTVIEW] other=%@", o); }
    return ((id (*)(id, SEL, id, id, id, id, ...))orig_av)(self, _cmd, t, m, d, c, nil);
}

#pragma mark NSURLSession
typedef void (^Comp)(NSData *, NSURLResponse *, NSError *);
static NSURLSessionDataTask *(*orig_dtr)(id, SEL, id, Comp);
static NSURLSessionDataTask *hook_dtr(id self, SEL _cmd, id req, Comp comp) {
    NSString *body = nil;
    NSData *bd = [req HTTPBody];
    if (bd) body = [[NSString alloc] initWithData:bd encoding:NSUTF8StringEncoding];
    RL(dtr, 50, @"[DT] %@ %@ body=%@", [req HTTPMethod], [[req URL] absoluteString], body);
    if (!comp) return orig_dtr(self, _cmd, req, comp);
    Comp wrapped = ^(NSData *d, NSURLResponse *resp, NSError *e) {
        NSString *rb = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        RL(dtresp, 50, @"[DT-RESP] %@ -> %ld body=%@", [resp URL], (long)[(NSHTTPURLResponse *)resp statusCode], rb);
        if (comp) comp(d, resp, e);
    };
    return orig_dtr(self, _cmd, req, wrapped);
}
static NSURLSessionDataTask *(*orig_dt)(id, SEL, id);
static NSURLSessionDataTask *hook_dt(id self, SEL _cmd, id req) {
    RL(dt, 50, @"[DT-noc] %@ %@", [req HTTPMethod], [[req URL] absoluteString]);
    return orig_dt(self, _cmd, req);
}
static NSURLSessionDataTask *(*orig_dtu)(id, SEL, id, Comp);
static NSURLSessionDataTask *hook_dtu(id self, SEL _cmd, id url, Comp comp) {
    RL(dtu, 50, @"[DTU] %@", [url absoluteString]);
    return orig_dtu(self, _cmd, url, comp);
}
static NSURLSessionUploadTask *(*orig_ut)(id, SEL, id, id, Comp);
static NSURLSessionUploadTask *hook_ut(id self, SEL _cmd, id req, id data, Comp comp) {
    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    RL(ut, 50, @"[UT] %@ body=%@", [[req URL] absoluteString], body);
    Comp wrapped = ^(NSData *d, NSURLResponse *resp, NSError *e) {
        NSString *rb = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        RL(utresp, 50, @"[UT-RESP] %@ -> %ld body=%@", [resp URL], (long)[(NSHTTPURLResponse *)resp statusCode], rb);
        if (comp) comp(d, resp, e);
    };
    return orig_ut(self, _cmd, req, data, wrapped);
}

#pragma mark NSURLConnection (legacy)
static id (*orig_sync)(id, SEL, id, id *, id *);
static id hook_sync(id self, SEL _cmd, id req, id *resp, id *err) {
    RL(ncs, 20, @"[NC-SYNC] %@", [[req URL] absoluteString]);
    id r = orig_sync(self, _cmd, req, resp, err);
    if (r) RL(ncsr, 20, @"[NC-SYNC-RESP] %@", [[NSString alloc] initWithData:r encoding:NSUTF8StringEncoding]);
    return r;
}
typedef void (^NCComp)(id, id, id);
static void (*orig_async)(id, SEL, id, id, NCComp);
static void hook_async(id self, SEL _cmd, id req, id q, NCComp comp) {
    RL(nca, 20, @"[NC-ASYNC] %@", [[req URL] absoluteString]);
    NCComp wrapped = ^(id resp, id d, id e) {
        RL(ncar, 20, @"[NC-ASYNC-RESP] %@", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]);
        if (comp) comp(resp, d, e);
    };
    orig_async(self, _cmd, req, q, wrapped);
}

#pragma mark OpenSSL-direct (SSL_do_handshake / BIO / *_ex)
static int (*orig_shake)(void *);
static int hook_shake(void *s) {
    RL(shk, 10, @"[SSL_do_handshake] — direct TLS!");
    return orig_shake(s);
}
static int (*orig_rdx)(void *, void *, int, int *);
static int hook_rdx(void *s, void *buf, int n, int *rd) {
    int r = orig_rdx(s, buf, n, rd);
    if (r > 0) logbuf("SSL_read_ex", buf, rd ? *rd : r);
    return r;
}
static int (*orig_wrx)(void *, const void *, int, int *);
static int hook_wrx(void *s, const void *buf, int n, int *wr) {
    logbuf("SSL_write_ex", buf, n);
    return orig_wrx(s, buf, n, wr);
}
static int (*orig_bioread)(void *, void *, int);
static int hook_bioread(void *b, void *buf, int n) {
    int r = orig_bioread(b, buf, n);
    if (r > 0) logbuf("BIO_read", buf, r);
    return r;
}
static int (*orig_biowrite)(void *, const void *, int);
static int hook_biowrite(void *b, const void *buf, int n) {
    logbuf("BIO_write", buf, n);
    return orig_biowrite(b, buf, n);
}
static int (*orig_wr)(void *, const void *, int);
static int hook_wr(void *s, const void *buf, int n) {
    logbuf("SSL_write", buf, n);
    return orig_wr(s, buf, n);
}
static int (*orig_rd)(void *, void *, int);
static int hook_rd(void *s, void *buf, int n) {
    int r = orig_rd(s, buf, n);
    if (r > 0) logbuf("SSL_read", buf, r);
    return r;
}
static int (*orig_con)(void *);
static int hook_con(void *s) {
    RL(con, 10, @"[SSL_connect]");
    return orig_con(s);
}

#pragma mark TCP connect (بورت 443 فقط)
static int (*orig_conn)(int, const struct sockaddr *, socklen_t);
static int hook_conn(int fd, const struct sockaddr *addr, socklen_t len) {
    if (addr && (addr->sa_family == AF_INET)) {
        const struct sockaddr_in *a = (const struct sockaddr_in *)addr;
        if (ntohs(a->sin_port) == 443)
            RL(tcp, 20, @"[TCP443] connect to %s:%d", inet_ntoa(a->sin_addr), ntohs(a->sin_port));
    }
    return orig_conn(fd, addr, len);
}

#pragma mark AUTO-PATCH
static void applyPatch(void) {
    if (!g_checkFuncAddr) return;
    uint32_t *p = (uint32_t *)g_checkFuncAddr;
    uintptr_t page = (uintptr_t)p & ~(uintptr_t)0x3FFF;
    mprotect((void *)page, 0x8000, PROT_READ|PROT_WRITE|PROT_EXEC);
    p[0] = 0x52800020u; p[1] = 0xD65F03C0u;
    sys_icache_invalidate(p, 8);
    flog(@"[PATCH] APPLIED @ %p", (void *)p);
}

#define HKFN(sym, hook, orig) do { void *_p = dlsym(_h, sym); if (_p) { MSHookFunction(_p, (void*)hook, (void**)orig); _ok++; } else flog(@"[miss] %s", sym); } while (0)
#define HKMSG(cls, sel, hook, orig) do { Class _c = objc_getClass(cls); if (_c) { MSHookMessageEx(_c, sel, (IMP)hook, (IMP*)orig); _ok++; } else flog(@"[miss cls] %s", cls); } while (0)

%ctor {
    @autoreleasepool {
        flog(@"v5-INJECTED pid=%d", getpid());
        void *_h = dlopen(NULL, RTLD_LAZY);
        int _ok = 0;

        // اختبار تحكم
        HKMSG("UIView", @selector(initWithFrame:), hook_view, &orig_view);
        // تنبيهات
        HKMSG("UIAlertController", @selector(alertControllerWithTitle:message:preferredStyle:), hook_alert, &orig_alert);
        HKMSG("UIAlertController", @selector(initWithTitle:message:preferredStyle:), hook_initA, &orig_initA);
        HKMSG("UIAlertController", @selector(addAction:), hook_addAction, &orig_addAction);
        HKMSG("UIAlertView", @selector(initWithTitle:message:delegate:cancelButtonTitle:otherButtonTitles:), hook_av, &orig_av);
        // NSURLSession
        HKMSG("NSURLSession", @selector(dataTaskWithRequest:completionHandler:), hook_dtr, &orig_dtr);
        HKMSG("NSURLSession", @selector(dataTaskWithRequest:), hook_dt, &orig_dt);
        HKMSG("NSURLSession", @selector(dataTaskWithURL:completionHandler:), hook_dtu, &orig_dtu);
        HKMSG("NSURLSession", @selector(uploadTaskWithRequest:fromData:completionHandler:), hook_ut, &orig_ut);
        // NSURLConnection
        HKMSG("NSURLConnection", @selector(sendSynchronousRequest:returningResponse:error:), hook_sync, &orig_sync);
        HKMSG("NSURLConnection", @selector(sendAsynchronousRequest:queue:completionHandler:), hook_async, &orig_async);
        // OpenSSL-direct
        HKFN("SSL_do_handshake", hook_shake, &orig_shake);
        HKFN("SSL_read_ex", hook_rdx, &orig_rdx);
        HKFN("SSL_write_ex", hook_wrx, &orig_wrx);
        HKFN("BIO_read", hook_bioread, &orig_bioread);
        HKFN("BIO_write", hook_biowrite, &orig_biowrite);
        HKFN("SSL_write", hook_wr, &orig_wr);
        HKFN("SSL_read", hook_rd, &orig_rd);
        HKFN("SSL_connect", hook_con, &orig_con);
        // TCP
        HKFN("connect", hook_conn, &orig_conn);

        flog(@"[v5] %d hooks installed", _ok);
        applyPatch();
    }
}
