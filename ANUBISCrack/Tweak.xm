// ANUBIS Loader Crack — Zain Ghost Protocol
// يحقن في اللودر فقط (com.tempmail.ios) — لا يلمس اللعبة إطلاقًا
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <substrate.h>
#include <dlfcn.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>

// ── ضع عنوان دالة الفحص هنا بعد التقاطه من اللوغ ──
static uintptr_t g_checkFuncAddr = 0x0;  // مثال: 0x100f4a2c0

#pragma mark 1) التقاط تنبيه المفتاح + تتبّع الرجوع لدالة الفحص
static id (*orig_alert)(id, SEL, id, id, NSInteger);
static id hook_alert(id self, SEL _cmd, id title, id message, NSInteger style) {
    NSLog(@"[ANUBIS-Crack] ALERT title=%@ msg=%@", title, message);
    void *ret = __builtin_return_address(0);
    Dl_info info = {0};
    if (dladdr(ret, &info) && info.dli_fbase) {
        NSLog(@"[ANUBIS-Crack] [CHECK-FUNC] caller offset = 0x%llx  (base=%p)",
              (unsigned long long)((uintptr_t)ret - (uintptr_t)info.dli_fbase),
              info.dli_fbase);
    } else {
        NSLog(@"[ANUBIS-Crack] [CHECK-FUNC] caller abs = %p", ret);
    }
    return orig_alert(self, _cmd, title, message, style);
}

#pragma mark 2) التقاط endpoint + نتيجة الطلب
typedef int CURLcode;
static CURLcode (*orig_perform)(void*);
static CURLcode hook_perform(void *h) {
    CURLcode r = orig_perform(h);
    NSLog(@"[ANUBIS-Crack] curl_easy_perform → %d", (int)r);
    return r;
}
typedef int (*curl_setopt_t)(void*, int, ...);
static curl_setopt_t orig_setopt;
static int hook_setopt(void *h, int opt, ...) {
    va_list ap; va_start(ap, opt);
    if (opt == 10002) { // CURLOPT_URL
        const char *u = va_arg(ap, const char*);
        NSLog(@"[ANUBIS-Crack] [ENDPOINT] %s", u ? u : "(null)");
    }
    if (opt == 10015) { // CURLOPT_POSTFIELDS
        const char *b = va_arg(ap, const char*);
        NSLog(@"[ANUBIS-Crack] [BODY] %s", b ? b : "(null)");
    }
    va_end(ap);
    return 0;
}

#pragma mark 3) AUTO-PATCH — قلب قرار الفحص دائمًا
// mov w0, #1 ; ret  → أي مفتاح (حتى TEST123) يُعتبر صالح
static void applyPatch(void) {
    if (!g_checkFuncAddr) return;
    uint32_t *p = (uint32_t*)g_checkFuncAddr;
    uintptr_t page = (uintptr_t)p & ~(uintptr_t)0x3FFF;
    mprotect((void*)page, 0x8000, PROT_READ|PROT_WRITE|PROT_EXEC);
    p[0] = 0x52800020u;  // mov w0, #1
    p[1] = 0xD65F03C0u;  // ret
    sys_icache_invalidate(p, 8);
    NSLog(@"[ANUBIS-Crack] ✅ PATCH APPLIED @ %p — أي مفتاح ينفع", (void*)p);
}

%ctor {
    Class ac = NSClassFromString(@"UIAlertController");
    if (ac) MSHookMessageEx(ac, @selector(alertControllerWithTitle:message:preferredStyle:),
                            (IMP)hook_alert, (IMP*)&orig_alert);

    void *h = dlopen(NULL, RTLD_LAZY);
    void *perf = dlsym(h, "curl_easy_perform");
    if (perf) MSHookFunction(perf, (void*)hook_perform, (void**)&orig_perform);
    void *seto = dlsym(h, "curl_easy_setopt");
    if (seto) MSHookFunction(seto, (void*)hook_setopt, (void**)&orig_setopt);

    applyPatch();
    NSLog(@"[ANUBIS-Crack] armed (checkFunc=%p)", (void*)g_checkFuncAddr);
}
