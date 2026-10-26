// GameForge v1.0 — فورج تحقق DragonCheat (udid/lookup) + استطلاع كامل للمرحلة التالية
#include <UIKit/UIKit.h>
#include <Security/Security.h>
#include <CommonCrypto/CommonHMAC.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>

#define GFLOG(...) do { \
    NSString *gs = [NSString stringWithFormat:__VA_ARGS__]; \
    const char *gc = [gs UTF8String]; if (!gc) break; \
    FILE *gf = fopen("/var/mobile/Documents/gamerecon.log","a"); \
    if (!gf) { const char *gh = getenv("HOME"); if (gh) { char gp[512]; snprintf(gp,sizeof(gp),"%s/tmp/gamerecon.log",gh); gf = fopen(gp,"a"); } } \
    if (gf) { fprintf(gf, "%s\n", gc); fclose(gf); } \
} while(0)

static BOOL gfAllSameByte(const void *p, size_t n) {
    if (!p) return NO;
    const uint8_t *b = (const uint8_t *)p;
    uint8_t v = b[0];
    for (size_t i = 1; i < n; i++) if (b[i] != v) return NO;
    return YES;
}


static void gfWalkDump(UIView *v, int dep) {
    if (!v || dep > 10) return;
    NSString *cls = NSStringFromClass([v class]);
    NSString *tx = @"";
    if ([v isKindOfClass:[UILabel class]]) tx = [((UILabel *)v) text] ?: @"";
    if ([v isKindOfClass:[UITextField class]]) tx = [((UITextField *)v) text] ?: @"";
    GFLOG(@"U%02d %@ | %@", dep, cls, tx);
    for (UIView *c in v.subviews) gfWalkDump(c, dep + 1);
}

static BOOL gForceSig = NO;

#include <string.h>
%hookf(int, memcmp, const void *s1, const void *s2, size_t n) {
    if (n == 32 && (gfAllSameByte(s1, 32) || gfAllSameByte(s2, 32))) {
        GFLOG(@"MEMCMP-ZERO-SIDE-PASS");
        return 0;
    }
    return %orig(s1, s2, n);
}

static bool gIV = false;
static bool gIV512 = false;

static NSString *gfUDID(void) {
    NSString *f = @"/var/mobile/Documents/gf_udid.txt";
    NSString *u = [[NSString alloc] initWithContentsOfFile:f encoding:NSUTF8StringEncoding error:nil];
    u = [u stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([u length] > 5) return u;
    return @"00008020-00091DCE0EF1002E";
}

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)req completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    NSString *url = req.URL.absoluteString ?: @"";
    /* --- الفورج القاتل: lookup يجيب ok+udid دائمًا --- */
    if ([url containsString:@"api.hackgamefile.com"] && [url containsString:@"/udid/lookup"]) {
        GFLOG(@"GF-FORGE lookup %@", url);
        NSString *json = [NSString stringWithFormat:@"{\"ok\":true,\"udid\":\"%@\"}", gfUDID()];
        NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:req.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
        if (cb) cb(d, resp, nil);
        return nil;
    }
    /* --- فورج التحقق من المفتاح: رد قابل للتعديل من ملف --- */
    if ([url containsString:@"api.hackgamefile.com"] && [url containsString:@"/verify"]) {
        GFLOG(@"GF-FORGE verify %@", url);
        gIV = true; gIV512 = true;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ gIV512 = false; });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ gIV = false; });
        NSString *tpl = [[NSString alloc] initWithContentsOfFile:@"/var/mobile/Documents/gf_verify.json" encoding:NSUTF8StringEncoding error:nil];
                if (!tpl || [tpl length] < 5) {
            long gnow = (long)[[NSDate date] timeIntervalSince1970];
            tpl = [NSString stringWithFormat:@"{\"valid\":true,\"code\":\"success\",\"message\":\"ok\",\"expires\":\"2099-12-31 23:59:59\",\"expire\":\"2099-12-31\",\"remaining_seconds\":31536000,\"remaining_text\":\"365 days\",\"sig\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"server_time\":%ld}", gnow];
        }
        NSData *d = [tpl dataUsingEncoding:NSUTF8StringEncoding];
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:req.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
        if (cb) cb(d, resp, nil);
        /* v3.0: تفعيل تطابق التوقيع الإجباري لـ15 ثانية */
        gForceSig = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ gForceSig = NO; });
        /* v3.1: الفتح القسري معطّل افتراضيًا — DragonCheat يجري مساره الذاتي الكامل.
           لتفعيله يدويًا: touch /var/mobile/Documents/gf_force_unlock */
        if (access("/var/mobile/Documents/gf_force_unlock", F_OK) != 0) return nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSArray *wins = [UIApplication sharedApplication].windows;
            GFLOG(@"GF-UNLOCK-SEARCH windows=%lu", (unsigned long)wins.count);
            UIView *bv = nil;
            for (UIWindow *w in wins) {
                NSMutableArray *q = [NSMutableArray arrayWithObject:w];
                while (q.count && !bv) {
                    UIView *c = q.firstObject; [q removeObjectAtIndex:0];
                    if ([NSStringFromClass([c class]) isEqualToString:@"StreamBypassView"]) { bv = c; break; }
                    [q addObjectsFromArray:c.subviews];
                }
                if (bv) break;
            }
            if (bv) {
                SEL s1 = NSSelectorFromString(@"setBypassEnabled:");
                if ([bv respondsToSelector:s1])
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(bv, s1, YES);
                [bv removeFromSuperview];
                GFLOG(@"GF-UNLOCK-FIRED");
            } else {
                GFLOG(@"GF-UNLOCK-NOTFOUND");
                for (UIWindow *w in wins) gfWalkDump(w, 0);
            }
        });
        return nil;
    }
    /* --- استطلاع باقي الرحلة --- */
    GFLOG(@"REQ %@ %@", req.HTTPMethod ?: @"?", url);
    if (req.HTTPBody) GFLOG(@"REQ-BODY %@", [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding]);
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e){
        GFLOG(@"RESP %@ | %ld", url, (long)[(NSHTTPURLResponse *)r statusCode]);
        if (d) GFLOG(@"RESP-BODY %@", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]);
        if (cb) cb(d, r, e);
        /* v2.0: بعد رد /verify — نفذ الفتح بأنفسنا من المسار الذي يشتعل فعلًا */
        if ([url containsString:@"/verify"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                for (UIWindow *w in [UIApplication sharedApplication].windows) {
                    NSMutableArray *q = [NSMutableArray arrayWithObject:w];
                    UIView *bv = nil;
                    while (q.count && !bv) {
                        UIView *c = q.firstObject; [q removeObjectAtIndex:0];
                        if ([NSStringFromClass([c class]) isEqualToString:@"StreamBypassView"]) { bv = c; break; }
                        [q addObjectsFromArray:c.subviews];
                    }
                    /* v2.1: كشف كامل */
                    GFLOG(@"GF-UNLOCK-SEARCH windows=%lu", (unsigned long)[UIApplication sharedApplication].windows.count);
                    if (bv) {
                        SEL s1 = NSSelectorFromString(@"setBypassEnabled:");
                        if ([bv respondsToSelector:s1])
                            ((void (*)(id, SEL, BOOL))objc_msgSend)(bv, s1, YES);
                        [bv removeFromSuperview];
                        GFLOG(@"GF-UNLOCK-FIRED");
                    } else {
                        GFLOG(@"GF-UNLOCK-NOTFOUND — hierarchy:");
                        for (UIWindow *w2 in [UIApplication sharedApplication].windows)
                            gfWalkDump(w2, 0);
                    }
                }
            });
        }
    };
    return %orig(req, wrapped);
}
%end

/* v4.6 — تمييز إطارات DG في Keychain + hex كامل */
static uintptr_t gDGbaseKC = 0;
static uintptr_t gDGendKC = 0;
static void gfDGFindStrict(void) {
    if (gDGbaseKC) return;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "/DragonGA.dylib")) {
            const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(i);
            uintptr_t base = (uintptr_t)mh, end = base;
            const uint8_t *p = (const uint8_t *)(mh + 1);
            for (uint32_t k = 0; k < mh->ncmds; k++) {
                const struct load_command *lc = (const struct load_command *)p;
                if (lc->cmd == 0x19) {
                    const struct segment_command_64 *sg = (const struct segment_command_64 *)p;
                    if (base + sg->vmaddr + sg->vmsize > end) end = base + sg->vmaddr + sg->vmsize;
                }
                p += lc->cmdsize;
            }
            gDGbaseKC = base; gDGendKC = end;
            GFLOG(@"DG-INFO base=%p size=0x%lx", (void *)base, (unsigned long)(end - base));
            break;
        }
    }
}
static BOOL gfDGFrameKC(void) {
    gfDGFindStrict();
    if (!gDGbaseKC || !gDGendKC) return NO;
    for (NSNumber *a in [NSThread callStackReturnAddresses]) {
        uintptr_t ad = [a unsignedIntegerValue];
        if (ad >= gDGbaseKC && ad < gDGendKC) return YES;
    }
    return NO;
}
static NSString *gfHex(id obj) {
    if (!obj) return @"-";
    if ([obj isKindOfClass:[NSString class]]) return obj;
    if (![obj isKindOfClass:[NSData class]]) return [obj description];
    NSData *d = (NSData *)obj;
    const unsigned char *b = (const unsigned char *)d.bytes;
    NSMutableString *m = [NSMutableString stringWithCapacity:d.length * 2];
    for (NSUInteger i = 0; i < d.length; i++) [m appendFormat:@"%02x", b[i]];
    return m;
}

/* استطلاع مساند */
/* v4.7 — استطلاع Security API دون تعديل نتيجة التحقق */
%hookf(CFDataRef, SecKeyCreateDecryptedData, SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef ciphertext, CFErrorRef *error) {
    CFDataRef out = %orig(key, algorithm, ciphertext, error);
    if (gfDGFrameKC()) {
        GFLOG(@"DEC alg=%@ in=%@", algorithm, ciphertext ? gfHex((__bridge id)ciphertext) : @"-");
        if (out) GFLOG(@"DEC-OUT %@", gfHex((__bridge id)out));
        if (error && *error) GFLOG(@"DEC-ERR %@", *error);
    }
    return out;
}
%hookf(CFDataRef, SecKeyCreateEncryptedData, SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef plaintext, CFErrorRef *error) {
    if (gfDGFrameKC() && plaintext) GFLOG(@"ENC alg=%@ plain=%@", algorithm, gfHex((__bridge id)plaintext));
    return %orig(key, algorithm, plaintext, error);
}
%hookf(CFTypeRef, SecKeyGeneratePair, CFDictionaryRef parameters, CFTypeRef *publicKey, CFTypeRef *privateKey) {
    CFTypeRef r = %orig(parameters, publicKey, privateKey);
    if (gfDGFrameKC()) GFLOG(@"GEN-PAIR");
    return r;
}

/* v6.3 — فخ التواقيع: SecKeyVerifySignature / SecKeyRawVerify مع قلب اختياري */
static int gfSigFlip(void) {
    static int flip = -1, last = 0;
    int now = (int)time(NULL);
    if (now - last >= 5) {
        last = now;
        NSString *home = [NSString stringWithUTF8String:(getenv("HOME") ?: "")];
        for (NSString *p in @[[home stringByAppendingPathComponent:@"tmp/gf_sig.txt"], @"/var/mobile/Documents/gf_sig.txt", @"/var/mobile/tmp/gf_sig.txt"]) {
            NSString *fv = [[NSString alloc] initWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
            if (fv && [fv length] > 0) { flip = (int)[fv integerValue]; break; }
        }
    }
    return flip;
}
%hookf(OSStatus, SecKeyVerifySignature, SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef signedData, CFDataRef signature, CFErrorRef *error) {
    OSStatus s = %orig(key, algorithm, signedData, signature, error);
    if (gfDGFrameKC()) {
        GFLOG(@"SIG-VERIFY st=%d alg=%@ dataLen=%ld sigLen=%ld", (int)s, algorithm, signedData ? (long)CFDataGetLength(signedData) : -1, signature ? (long)CFDataGetLength(signature) : -1);
        int f = gfSigFlip();
        if (f == 1 && s != 0) { GFLOG(@"SIG-FORCE ok"); if (error) *error = NULL; return 0; }
    }
    return s;
}
%hookf(OSStatus, SecKeyRawVerify, SecKeyRef key, SecPadding padding, const uint8_t *signedData, size_t dataLen, const uint8_t *sig, size_t sigLen) {
    OSStatus s = %orig(key, padding, signedData, dataLen, sig, sigLen);
    if (gfDGFrameKC()) {
        GFLOG(@"SIG-RAW st=%d padding=%ld dataLen=%zu sigLen=%zu", (int)s, (long)padding, dataLen, sigLen);
        int f = gfSigFlip();
        if (f == 1 && s != 0) { GFLOG(@"SIG-RAW-FORCE ok"); return 0; }
    }
    return s;
}

%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef q, CFTypeRef *result) {
    OSStatus s = %orig(q, result);
    NSString *sv = q ? (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("svce")) : nil;
    NSString *ac = q ? (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("acct")) : nil;
    {
        (void)gfDGFrameKC();
        NSArray *bt = [NSThread callStackReturnAddresses];
        NSString *caller = @"-";
        for (NSUInteger fi = 0; fi < bt.count && fi < 4; fi++) {
            uintptr_t a0 = [bt[fi] unsignedIntegerValue];
            if (gDGbaseKC && a0 > gDGbaseKC && a0 < gDGbaseKC + 0x2000000) {
                caller = [NSString stringWithFormat:@"DG+%lx", (unsigned long)(a0 - gDGbaseKC)];
                break;
            }
        }
        GFLOG(@"KC-FIND dg=%d %d svce=%@ acct=%@ from=%@", (int)gfDGFrameKC(), (int)s, sv ?: @"-", ac ?: @"-", caller);
    }
    if (s == 0 && result && *result) GFLOG(@"KC-HIT-RAW dg=%d %@", (int)gfDGFrameKC(), gfHex((__bridge id)*result));
    return s;
}
%hookf(OSStatus, SecItemAdd, CFDictionaryRef q, CFTypeRef *r) {
    NSString *sv = q ? (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("svce")) : nil;
    NSString *ac = q ? (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("acct")) : nil;
    GFLOG(@"KC-ADD dg=%d svce=%@ acct=%@ data=%@", (int)gfDGFrameKC(), sv ?: @"-", ac ?: @"-", q ? gfHex((__bridge id)CFDictionaryGetValue(q, CFSTR("v_Data"))) : @"-");
    return %orig(q, r);
}
%hookf(void, CCHmac, CCHmacAlgorithm alg, const void *key, size_t keyLen, const void *data, size_t dataLen, void *macOut) {
    NSMutableString *kb = [NSMutableString string];
    for (size_t i = 0; key && i < keyLen && i < 48; i++) [kb appendFormat:@"%02x", ((const uint8_t *)key)[i]];
    NSMutableString *db = [NSMutableString string];
    for (size_t i = 0; data && i < dataLen && i < 160; i++) [db appendFormat:@"%02x", ((const uint8_t *)data)[i]];
    GFLOG(@"CCHMAC alg=%lu key=%@ data=%@", (unsigned long)alg, kb, db);
    %orig(alg, key, keyLen, data, dataLen, macOut);
}
%hookf(void, NSLog, NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *s = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    GFLOG(@"NSLOG %@", s);
    %orig(@"%@", s);
}
%hook NSData
- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)mask error:(NSError **)error {
    GFLOG(@"WRITE %@", path ?: @"?");
    return %orig(path, mask, error);
}
%end

/* v1.4: جرد أكلاسات وصور DragonCheat الحية */
#include <objc/runtime.h>
#include <mach-o/dyld.h>
__attribute__((constructor))
static void gf_recon_ctor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @autoreleasepool {
            GFLOG(@"=== IMAGE DUMP ===");
            uint32_t nic = _dyld_image_count();
            for (uint32_t i = 0; i < nic; i++) {
                const char *nm = _dyld_get_image_name(i);
                if (nm) GFLOG(@"IMG %s", nm);
            }
            GFLOG(@"=== CLASS SCAN ===");
            int num = objc_getClassList(NULL, 0);
            if (num > 0) {
                Class *lst = (Class *)malloc(sizeof(Class) * num);
                objc_getClassList(lst, num);
                for (int i = 0; i < num; i++) {
                    NSString *n = NSStringFromClass(lst[i]);
                    if (!n) continue;
                    NSString *low = [n lowercaseString];
                    if ([low rangeOfString:@"dragon"].location != NSNotFound ||
                        [low rangeOfString:@"cheat"].location != NSNotFound ||
                        [low hasPrefix:@"stream"] ||
                        [low hasPrefix:@"bypass"]) {
                        GFLOG(@"CLASS %@ IMG=%s", n, class_getImageName(lst[i]) ?: "?");
                        unsigned mc = 0;
                        Method *ml = class_copyMethodList(lst[i], &mc);
                        for (unsigned j = 0; j < mc; j++) {
                            GFLOG(@"  M %@ %@ +%u -%u args", n,
                                  NSStringFromSelector(method_getName(ml[j])),
                                  (unsigned)method_getNumberOfArguments(ml[j]),
                                  0u);
                        }
                        free(ml);
                    }
                }
                free(lst);
            }
            GFLOG(@"=== SCAN DONE ===");
        }
    });
}

/* v1.5: جرد شجرة الواجهات — نلتقط كائن حوار DragonCheat أياً كان مصدره */
static void gfViewWalk(UIView *v, int depth) {
    if (!v || depth > 14) return;
    NSString *cls = NSStringFromClass([v class]);
    NSString *txt = @"";
    if ([v isKindOfClass:[UILabel class]]) txt = [((UILabel *)v) text] ?: @"";
    if ([v isKindOfClass:[UITextField class]]) txt = [((UITextField *)v) text] ?: @"";
    if ([v isKindOfClass:[UIButton class]]) txt = [((UIButton *)v) currentTitle] ?: @"";
    GFLOG(@"V%02d %@ | %@", depth, cls, txt);
    for (UIView *c in v.subviews) gfViewWalk(c, depth + 1);
}
__attribute__((constructor))
static void gf_ui_ctor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @autoreleasepool {
            GFLOG(@"=== UI DUMP ===");
            for (UIWindow *w in [UIApplication sharedApplication].windows) gfViewWalk(w, 0);
            GFLOG(@"=== UI END ===");
        }
    });
}

/* v1.7 — الضربة القاضية: Yes-Man على DragonGA — كل BOOL تحقق = YES */
#include <objc/runtime.h>

static BOOL gfYesMan(id self, SEL _cmd) {
    GFLOG(@"YESMAN-FIRED %@ %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    return YES;
}

__attribute__((constructor))
static void gf_yesman_ctor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @autoreleasepool {
            int num = objc_getClassList(NULL, 0);
            if (num <= 0) return;
            Class *lst = (Class *)malloc(sizeof(Class) * num);
            objc_getClassList(lst, num);
            int swizzled = 0;
            for (int i = 0; i < num; i++) {
                const char *img = class_getImageName(lst[i]);
                if (!img || !strstr(img, "/DragonGA.dylib")) continue;
                unsigned mc = 0;
                Method *ml = class_copyMethodList(lst[i], &mc);
                for (unsigned j = 0; j < mc; j++) {
                    Method m = ml[j];
                    SEL sel = method_getName(m);
                    NSString *sn = NSStringFromSelector(sel);
                    char rt[8] = {0};
                    method_getReturnType(m, rt, sizeof(rt));
                    /* BOOL returns (B/c) with verification-ish names */
                    if ((rt[0] == 'B' || rt[0] == 'c') &&
                        ([sn rangeOfString:@"verif" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                         [sn rangeOfString:@"valid" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                         [sn rangeOfString:@"unlock" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                         [sn rangeOfString:@"activ" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                         [sn rangeOfString:@"check" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                         [sn rangeOfString:@"licen" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                         [sn rangeOfString:@"isVip" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                         [sn rangeOfString:@"passed" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                         [sn rangeOfString:@"allowed" options:NSCaseInsensitiveSearch].location != NSNotFound)) {
                        class_replaceMethod(lst[i], sel, (IMP)gfYesMan, method_getTypeEncoding(m));
                        GFLOG(@"YESMAN-SWIZZLE %@ %@", NSStringFromClass(lst[i]), sn);
                        swizzled++;
                    } else {
                        GFLOG(@"DC-METHOD %@ %@", NSStringFromClass(lst[i]), sn);
                    }
                }
                free(ml);
            }
            free(lst);
            GFLOG(@"YESMAN-DONE total=%d", swizzled);
        }
    });
}

/* v1.9 — سوizzling وقت التشغيل (بعد تحميل DragonGA) — يحل مشكلة ترتيب التحميل */
#include <objc/runtime.h>
#include <objc/message.h>

static void (*orig_gate_done)(id, SEL, id, id, id);
static void (*orig_gate_dlf)(id, SEL, id, id, id);

static void gf_gate_dlf(id self, SEL _cmd, id s, id t, id loc) {
    NSString *u = @"?"; NSString *p = @"?";
    @try { u = [[(NSURLSessionTask *)t originalRequest].URL absoluteString] ?: @"?"; } @catch (NSException *ex) {}
    @try { p = [(NSURL *)loc path] ?: @"?"; } @catch (NSException *ex) {}
    GFLOG(@"GATE-DLF %@ -> %@", u, p);
    if (orig_gate_dlf) orig_gate_dlf(self, _cmd, s, t, loc);
}

static void gf_gate_done(id self, SEL _cmd, id s, id t, id e) {
    NSString *u = @"?";
    @try { u = [[(NSURLSessionTask *)t originalRequest].URL absoluteString] ?: @"?"; } @catch (NSException *ex) {}
    GFLOG(@"GATE-DONE %@ err=%@", u, e ?: @"(nil)");
    if (orig_gate_done) orig_gate_done(self, _cmd, s, t, e);
    if ([u containsString:@"/verify"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                UIView *bv = nil;
                /* بحث BFS سريع */
                NSMutableArray *q = [NSMutableArray arrayWithObject:w];
                while (q.count && !bv) {
                    UIView *c = q.firstObject; [q removeObjectAtIndex:0];
                    if ([NSStringFromClass([c class]) isEqualToString:@"StreamBypassView"]) { bv = c; break; }
                    [q addObjectsFromArray:c.subviews];
                }
                if (bv) {
                    SEL s1 = NSSelectorFromString(@"setBypassEnabled:");
                    if ([bv respondsToSelector:s1]) {
                        ((void (*)(id, SEL, BOOL))objc_msgSend)(bv, s1, YES);
                        GFLOG(@"GF-FORCE-UNLOCK bypassEnabled=YES");
                    }
                    [bv removeFromSuperview];
                    GFLOG(@"GF-DIALOG-REMOVED");
                }
            }
        });
    }
}

static void (*orig_bypass_set)(id, SEL, BOOL);
static void gf_bypass_set(id self, SEL _cmd, BOOL v) {
    GFLOG(@"BYPASS-SET called=%d", v);
    if (orig_bypass_set) orig_bypass_set(self, _cmd, YES);
}
static BOOL (*orig_bypass_get)(id, SEL);
static BOOL gf_bypass_get(id self, SEL _cmd) {
    GFLOG(@"BYPASS-GET");
    return YES;
}
static void (*orig_fixlogin)(id, SEL);
static void gf_fixlogin(id self, SEL _cmd) {
    GFLOG(@"FIXLOGIN-FIRED");
    if (orig_fixlogin) orig_fixlogin(self, _cmd);
}

__attribute__((constructor))
static void gf_swizzle_ctor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @autoreleasepool {
            Class gate = NSClassFromString(@"__PXSysGate");
            if (gate) {
                Method m = class_getInstanceMethod(gate, NSSelectorFromString(@"URLSession:task:didCompleteWithError:"));
                if (m) { do { IMP _i = method_getImplementation(m); memcpy(&orig_gate_done, &_i, sizeof(_i)); } while(0); method_setImplementation(m, (IMP)gf_gate_done); GFLOG(@"SWIZZLED gate done"); }
                Method mdl = class_getInstanceMethod(gate, NSSelectorFromString(@"URLSession:downloadTask:didFinishDownloadingToURL:"));
                if (mdl) { do { IMP _i = method_getImplementation(mdl); memcpy(&orig_gate_dlf, &_i, sizeof(_i)); } while(0); method_setImplementation(mdl, (IMP)gf_gate_dlf); GFLOG(@"SWIZZLED gate dlf"); }
            } else GFLOG(@"GATE CLASS NOT FOUND");
            Class bv = NSClassFromString(@"StreamBypassView");
            if (bv) {
                Method ms = class_getInstanceMethod(bv, NSSelectorFromString(@"setBypassEnabled:"));
                if (ms) { do { IMP _i = method_getImplementation(ms); memcpy(&orig_bypass_set, &_i, sizeof(_i)); } while(0); method_setImplementation(ms, (IMP)gf_bypass_set); GFLOG(@"SWIZZLED bypass set"); }
                Method mg = class_getInstanceMethod(bv, NSSelectorFromString(@"bypassEnabled"));
                if (!mg) mg = class_getInstanceMethod(bv, NSSelectorFromString(@"isBypassEnabled"));
                if (mg) { do { IMP _i = method_getImplementation(mg); memcpy(&orig_bypass_get, &_i, sizeof(_i)); } while(0); method_setImplementation(mg, (IMP)gf_bypass_get); GFLOG(@"SWIZZLED bypass get"); }
            }
            Class dc = NSClassFromString(@"DrawViewController");
            if (dc) {
                Method m = class_getInstanceMethod(dc, NSSelectorFromString(@"fixLogin"));
                if (m) { do { IMP _i = method_getImplementation(m); memcpy(&orig_fixlogin, &_i, sizeof(_i)); } while(0); method_setImplementation(m, (IMP)gf_fixlogin); GFLOG(@"SWIZZLED fixLogin"); }
            }
            GFLOG(@"SWIZZLE-SETUP-COMPLETE");
        }
    });
}

/* v2.4 — القاضي: memcmp(,,32) مع طرف صفري = متطابق دائمًا
   + التقاط CC_SHA256 (HMAC اليدوي يكشف المفتاح عبر key^ipad) */
#include <string.h>




extern "C" unsigned char *CC_SHA256(const void *data, CC_LONG len, unsigned char *md);
static const uint8_t gKprefix[32] = {0xe3,0xb0,0xc4,0x42,0x98,0xfc,0x1c,0x14,0x9a,0xfb,0xf4,0xc8,0x99,0x6f,0xb9,0x24,0x27,0xae,0x41,0xe4,0x64,0x9b,0x93,0x4c,0xa4,0x95,0x99,0x1b,0x78,0x52,0xb8,0x55};
%hookf(unsigned char *, CC_SHA256, const void *data, CC_LONG len, unsigned char *md) {
    /* v3.5: تسميم حساب MAC — أي نداء بمفتاح DragonCheat (بادئة K) نُصفّر ناتجه
       → التوقيع المتوقع = أصفار = توقيع ردنا المزوّر → المقارنة تنجح */
    if (data && len == 64 && md && memcmp(data, gKprefix, 32) == 0) {
        unsigned char *r = %orig(data, len, md);
        if (r) { memset(r, 0, 32); GFLOG(@"MAC-POISONED (expected-sig zeroed)"); }
        return r;
    }
    if (data && len > 0 && len < 4096) {
        const uint8_t *b = (const uint8_t *)data;
        NSMutableString *hs = [NSMutableString string];
        for (CC_LONG i = 0; i < len && i < 320; i++) [hs appendFormat:@"%02x", b[i]];
        GFLOG(@"CC_SHA256 len=%u data=%@%@", (unsigned)len, hs, len > 320 ? @"..." : @"");
    }
    unsigned char *gr = %orig(data, len, md);
    if (gr) { NSMutableString *mo=[NSMutableString string]; for(int k=0;k<32;k++) [mo appendFormat:@"%02x",gr[k]];
        GFLOG(@"CC_SHA256-OUT len=%u out=%@", (unsigned)len, mo); }
    return gr;
}

/* v3.3 — مقارنة التوقيع نصية: توقيعنا 64-صفر = أي توقيع محسوب */
static BOOL gfIsZeroHex64(NSString *s) {
    if (!s || [s length] != 64) return NO;
    const char *c = [s UTF8String];
    if (!c) return NO;
    for (int i = 0; i < 64; i++) if (c[i] != '0') return NO;
    return YES;
}
static BOOL gfIsHex64(NSString *s) {
    if (!s || [s length] != 64) return NO;
    const char *c = [s UTF8String];
    if (!c) return NO;
    for (int i = 0; i < 64; i++) if (!isxdigit((unsigned char)c[i])) return NO;
    return YES;
}
%hook NSString
- (BOOL)isEqualToString:(NSString *)other {
    NSString *me = (NSString *)self;
    if (gfIsZeroHex64(me) && gfIsHex64(other)) {
        GFLOG(@"SIG-STRCMP-PASS zero-vs-%@", other);
        return YES;
    }
    if (gfIsZeroHex64(other) && gfIsHex64(me)) {
        GFLOG(@"SIG-STRCMP-PASS %@-vs-zero", me);
        return YES;
    }
    return %orig(other);
}
%end

/* v3.7 — عقّ SHA256 الداخلي الحقيقي (base+0xdc5d4) → تسميم الحالة → التوقيع المتوقع أصفار */
#include <substrate.h>
#include <mach-o/dyld.h>

static void (*orig_isha)(void *a, void *b);
static void hooked_isha(void *a, void *b) {
    if (orig_isha) orig_isha(a, b);
    if (gIV && a) {
        memset(a, 0, 32);
        GFLOG(@"ISHA-POISONED a=%p b=%p", a, b);
    } else if (a && b) {
        GFLOG(@"ISHA-CALL a=%p b=%p head=%02x%02x%02x%02x", a, b,
              ((uint8_t*)a)[0], ((uint8_t*)a)[1], ((uint8_t*)a)[2], ((uint8_t*)a)[3]);
    }
}

__attribute__((constructor))
static void gf_isha_ctor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @autoreleasepool {
            for (uint32_t i = 0; i < _dyld_image_count(); i++) {
                const char *nm = _dyld_get_image_name(i);
                if (nm && strstr(nm, "/DragonGA.dylib")) {
                    const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(i);
                    void *target = (void *)((uintptr_t)mh + 0xdc5d4);
                    MSHookFunction(target, (void *)hooked_isha, (void **)&orig_isha);
                    GFLOG(@"ISHA-HOOKED %p (base %p)", target, mh);
                    break;
                }
            }
        }
    });
}

/* v3.8 — تسميم SHA-512 (محرك Ed25519) أثناء نافذة التحقق */
#include <CommonCrypto/CommonDigest.h>
extern "C" unsigned char *CC_SHA512(const void *data, CC_LONG len, unsigned char *md);
%hookf(unsigned char *, CC_SHA512, const void *data, CC_LONG len, unsigned char *md) {
    unsigned char *r = %orig(data, len, md);
    if (gIV512 && r) {
        memset(r, 0, 64);
        GFLOG(@"SHA512-POISONED len=%u", (unsigned)len);
    }
    return r;
}

/* v4.0 — كاشف مسار التحقق: backtrace لحظة قراءة حقول الرد داخل DragonGA */
#include <mach-o/dyld.h>

static uintptr_t gDGbase = 0;
static void gfFindDG(void) {
    if (gDGbase) return;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "/DragonGA.dylib")) {
            gDGbase = (uintptr_t)_dyld_get_image_header(i);
            break;
        }
    }
}

%hook NSDictionary
- (id)objectForKey:(id)aKey {
    id v = %orig(aKey);
    if ([aKey isKindOfClass:[NSString class]]) {
        NSString *k = (NSString *)aKey;
        if ([k isEqualToString:@"sig"] || [k isEqualToString:@"valid"] ||
            [k isEqualToString:@"code"] || [k isEqualToString:@"sig_ed"]) {
            gfFindDG();
            NSArray *bt = [NSThread callStackReturnAddresses];
            NSMutableString *offs = [NSMutableString string];
            int n = 0;
            for (NSNumber *a in bt) {
                uintptr_t ad = [a unsignedIntegerValue];
                if (gDGbase && ad > gDGbase && ad < gDGbase + 0x2000000 && n < 10) {
                    [offs appendFormat:@"+%lx ", (unsigned long)(ad - gDGbase)];
                    n++;
                }
            }
            if ([offs length] > 0)
                GFLOG(@"TRACE %@ = %@ | DG:%@", k, v ? @"Y" : @"N", offs);
        }
    }
    return v;
}

/* v4.1 — نفس التتبع عبر مسار subscript الحديث */
- (id)objectForKeyedSubscript:(id)aKey {
    id v = %orig(aKey);
    if ([aKey isKindOfClass:[NSString class]]) {
        NSString *k = (NSString *)aKey;
        if ([k isEqualToString:@"sig"] || [k isEqualToString:@"valid"] ||
            [k isEqualToString:@"code"] || [k isEqualToString:@"sig_ed"] ||
            [k isEqualToString:@"message"] || [k isEqualToString:@"expires"]) {
            gfFindDG();
            NSArray *bt = [NSThread callStackReturnAddresses];
            NSMutableString *offs = [NSMutableString string];
            int n = 0;
            for (NSNumber *a in bt) {
                uintptr_t ad = [a unsignedIntegerValue];
                if (gDGbase && ad > gDGbase && ad < gDGbase + 0x2000000 && n < 12) {
                    [offs appendFormat:@"+%lx ", (unsigned long)(ad - gDGbase)];
                    n++;
                }
            }
            if ([offs length] > 0)
                GFLOG(@"TRACE2 %@ = %@ | DG:%@", k, v ? @"Y" : @"N", offs);
        }
    }
    return v;
}

%end


/* v4.3 — إصلاح مسار gf_state.txt (sandbox) + إعادة تحميل الإجبار كل 30ث
   v4.2 — مراقب بايت الحالة (base+0xd0c7a0) + كاتب تجريبي اختياري — ذاكرة فقط، لا ملف */
#include <mach-o/dyld.h>
#include <unistd.h>

static volatile uint8_t *gStateByte = NULL;
static uint8_t gLastState = 0xFF;
/* v6.1 — تركيب مبكر عبر add-image (قبل بدايات DG) */
static void gfInstallValHook(uintptr_t dgbase) {
    (void)dgbase;
    GFLOG(@"VAL-HOOK disabled (phantom address retired)");
}
static void gfDGImageAdded(const struct mach_header *mh, intptr_t slide) {
    Dl_info info;
    if (dladdr(mh, &info) && info.dli_fname && strstr(info.dli_fname, "/DragonGA.dylib")) {
        gfInstallValHook((uintptr_t)mh);
    }
}

__attribute__((constructor))
static void gf_statewatch_ctor(void) {
    _dyld_register_func_for_add_image(&gfDGImageAdded);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        for (int t = 0; t < 120 && !gStateByte; t++) {
            for (uint32_t i = 0; i < _dyld_image_count(); i++) {
                const char *nm = _dyld_get_image_name(i);
                if (nm && strstr(nm, "/DragonGA.dylib")) {
                    gStateByte = (volatile uint8_t *)((uintptr_t)_dyld_get_image_header(i) + 0xd0c7a0);
                    break;
                }
            }
            if (!gStateByte) usleep(500000);
        }
        if (!gStateByte) { GFLOG(@"STATE-WATCH DragonGA not found"); return; }

        gfInstallValHook((uintptr_t)gStateByte - 0xd0c7a0);

        /* v7.0 — ماسح LDRB [x?,#0x7a0] في ذاكرة DG الحية + نوافذ للتفكيك */
        {
            uintptr_t dgbase = (uintptr_t)gStateByte - 0xd0c7a0;
            const unsigned char *p = (const unsigned char *)dgbase;
            GFLOG(@"SCAN start base=%p", (void *)dgbase);
            int hits = 0;
            for (uint32_t off = 0; off + 4 < 0xd98000 && hits < 8; off += 4) {
                uint32_t w;
                memcpy(&w, p + off, 4);
                if ((w & 0xFFFFFC00u) == 0x395E8000u) {   /* ldrb w?,[x?,#0x7a0] */
                    hits++;
                    GFLOG(@"HIT #%d at DG+%x", hits, off);
                    const unsigned char *m = p + off - 0x30;
                    NSMutableString *acc = [NSMutableString string];
                    for (int i = 0; i < 0xA0; i++) {
                        [acc appendFormat:@"%02x", m[i]];
                        if ((i % 32) == 31) { GFLOG(@"WIN %x+%03x %@", off - 0x30, i - 31, acc); [acc setString:@""]; }
                    }
                }
            }
            GFLOG(@"SCAN end hits=%d", hits);
        }

        int forceVal = -1;
        NSString *forcePath = @"-";
        NSString *home = [NSString stringWithUTF8String:(getenv("HOME") ?: "")];
        NSArray *cands = @[
            [home stringByAppendingPathComponent:@"tmp/gf_state.txt"],
            @"/var/mobile/Documents/gf_state.txt",
            @"/var/mobile/tmp/gf_state.txt",
        ];
        for (NSString *c in cands) {
            NSString *fv = [[NSString alloc] initWithContentsOfFile:c encoding:NSUTF8StringEncoding error:nil];
            if (fv && [fv length] > 0) { forceVal = (int)[fv integerValue]; forcePath = c; break; }
        }
        #define GF_RELOAD_FORCE() do { \
            for (NSString *c in cands) { \
                NSString *fv = [[NSString alloc] initWithContentsOfFile:c encoding:NSUTF8StringEncoding error:nil]; \
                if (fv && [fv length] > 0) { forceVal = (int)[fv integerValue]; forcePath = c; break; } \
            } \
        } while (0)

        gLastState = *gStateByte;
        GFLOG(@"STATE-WATCH armed addr=%p initial=%u force=%d path=%@", (void *)gStateByte, gLastState, forceVal, forcePath);

        int lastForcedLog = 0;
        for (int iter = 0; iter < 720; iter++) {          /* ~6 دقائق */
            uint8_t cur = *gStateByte;
            if (cur != gLastState) {
                GFLOG(@"STATE-CHANGE 0x%02x -> 0x%02x (iter %d)", gLastState, cur, iter);
                gLastState = cur;
            }
            if ((iter % 60) == 0) GF_RELOAD_FORCE();
            if (forceVal >= 0 && forceVal <= 255 && cur != (uint8_t)forceVal) {
                *gStateByte = (uint8_t)forceVal;
                if (iter - lastForcedLog >= 40) { GFLOG(@"STATE-FORCED -> %d", forceVal); lastForcedLog = iter; }
            }
            usleep(500000);
        }
        GFLOG(@"STATE-WATCH end");
    });
}
