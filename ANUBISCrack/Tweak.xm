// ANUBISCrack v4 — Protocol Capture Edition (Zain Ghost Protocol)
// التقاط البروتوكول الخام عبر OpenSSL — لا اعتماد على التنبيهات
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <substrate.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <objc/runtime.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>

static uintptr_t g_checkFuncAddr = 0x0; // يُملأ من اللوغ لاحقًا

#pragma mark ── flog: تسجيل لملف (tmp داخل الحاوية = مضمون ضد الساندبوكس)
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

#pragma mark ── استخراج السلاسل القابلة للقراءة من بفر خام (HTTP/1.1 يظهر نصًا)
static void logbuf(const char *tag, const void *buf, int len) {
    if (!buf || len <= 0) return;
    const unsigned char *p = (const unsigned char *)buf;
    NSMutableString *runs = [NSMutableString string];
    NSMutableString *cur = [NSMutableString string];
    int cap = len > 4096 ? 4096 : len;
    for (int i = 0; i < cap; i++) {
        unsigned char c = p[i];
        if (c >= 32 && c < 127) [cur appendFormat:@"%c", c];
        else {
            if (cur.length >= 4) { [runs appendString:cur]; [runs appendString:@" | "]; }
            [cur setString:@""];
        }
    }
    if (cur.length >= 4) [runs appendString:cur];
    if (runs.length > 0) flog(@"[%s len=%d] %@", tag, len, runs);
}

#pragma mark ── SSL hooks (النقل المؤكد للودر)
static int (*orig_SSL_write)(void *, const void *, int);
static int hook_SSL_write(void *ssl, const void *buf, int num) {
    logbuf("SSL_write", buf, num);
    return orig_SSL_write(ssl, buf, num);
}
static int (*orig_SSL_read)(void *, void *, int);
static int hook_SSL_read(void *ssl, void *buf, int num) {
    int r = orig_SSL_read(ssl, buf, num);
    if (r > 0) logbuf("SSL_read", buf, r);
    else flog(@"[SSL_read] ret=%d", r);
    return r;
}
static int (*orig_SSL_connect)(void *);
static int hook_SSL_connect(void *ssl) {
    flog(@"[SSL_connect] TLS handshake starting");
    return orig_SSL_connect(ssl);
}

#pragma mark ── Alert hooks (نسختان + باك تريس كامل)
static void log_bt(void) {
    void *bt[20]; int n = backtrace(bt, 20);
    char **syms = backtrace_symbols(bt, n);
    for (int i = 0; i < n; i++) flog(@"  bt[%d] %s", i, syms[i]);
    free(syms);
}
static id (*orig_alert)(id, SEL, id, id, NSInteger);
static id hook_alert(id self, SEL _cmd, id title, id message, NSInteger style) {
    if (message && [message isKindOfClass:[NSString class]] &&
        [message rangeOfString:@"[ZAIN]"].location == NSNotFound)
        message = [NSString stringWithFormat:@"%@ [ZAIN]", message];
    flog(@"[ALERT+] title=%@ msg=%@", title, message);
    log_bt();
    return orig_alert(self, _cmd, title, message, style);
}
static id (*orig_initA)(id, SEL, id, id, NSInteger);
static id hook_initA(id self, SEL _cmd, id title, id message, NSInteger style) {
    if (message && [message isKindOfClass:[NSString class]] &&
        [message rangeOfString:@"[ZAIN]"].location == NSNotFound)
        message = [NSString stringWithFormat:@"%@ [ZAIN]", message];
    flog(@"[ALERT-init] title=%@ msg=%@", title, message);
    log_bt();
    return orig_initA(self, _cmd, title, message, style);
}

#pragma mark ── AUTO-PATCH (يُفعّل بعد معرفة العنوان)
static void applyPatch(void) {
    if (!g_checkFuncAddr) return;
    uint32_t *p = (uint32_t *)g_checkFuncAddr;
    uintptr_t page = (uintptr_t)p & ~(uintptr_t)0x3FFF;
    mprotect((void *)page, 0x8000, PROT_READ|PROT_WRITE|PROT_EXEC);
    p[0] = 0x52800020u; p[1] = 0xD65F03C0u;
    sys_icache_invalidate(p, 8);
    flog(@"[PATCH] APPLIED @ %p — any key passes", (void *)p);
}

%ctor {
    @autoreleasepool {
        flog(@"v4-INJECTED pid=%d", getpid());
        void *h = dlopen(NULL, RTLD_LAZY);
        const char *want[] = {"SSL_read","SSL_write","SSL_connect",0};
        for (int i = 0; want[i]; i++)
            flog(@"sym %s => %p", want[i], dlsym(h, want[i]));
        void *w, *r, *c;
        if ((w = dlsym(h,"SSL_write")))  MSHookFunction(w, (void*)hook_SSL_write, (void**)&orig_SSL_write);
        if ((r = dlsym(h,"SSL_read")))   MSHookFunction(r, (void*)hook_SSL_read,  (void**)&orig_SSL_read);
        if ((c = dlsym(h,"SSL_connect"))) MSHookFunction(c, (void*)hook_SSL_connect,(void**)&orig_SSL_connect);
        flog(@"[ssl] hooks installed");

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            Class ac = objc_getClass("UIAlertController");
            if (ac) {
                MSHookMessageEx(ac, @selector(alertControllerWithTitle:message:preferredStyle:),
                                (IMP)hook_alert, (IMP *)&orig_alert);
                MSHookMessageEx(ac, @selector(initWithTitle:message:preferredStyle:),
                                (IMP)hook_initA, (IMP *)&orig_initA);
                flog(@"[objc] alert hooks installed");
            } else flog(@"[objc] UIAlertController NIL");
        });
        applyPatch();
    }
}
