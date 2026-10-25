// GameForge v1.0 — فورج تحقق DragonCheat (udid/lookup) + استطلاع كامل للمرحلة التالية
#include <UIKit/UIKit.h>
#include <Security/Security.h>
#include <CommonCrypto/CommonHMAC.h>

#define GFLOG(...) do { \
    NSString *gs = [NSString stringWithFormat:__VA_ARGS__]; \
    const char *gc = [gs UTF8String]; if (!gc) break; \
    FILE *gf = fopen("/var/mobile/Documents/gamerecon.log","a"); \
    if (!gf) { const char *gh = getenv("HOME"); if (gh) { char gp[512]; snprintf(gp,sizeof(gp),"%s/tmp/gamerecon.log",gh); gf = fopen(gp,"a"); } } \
    if (gf) { fprintf(gf, "%s\n", gc); fclose(gf); } \
} while(0)

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
        NSString *tpl = [[NSString alloc] initWithContentsOfFile:@"/var/mobile/Documents/gf_verify.json" encoding:NSUTF8StringEncoding error:nil];
        if (!tpl || [tpl length] < 5) {
            long gnow = (long)[[NSDate date] timeIntervalSince1970];
            tpl = [NSString stringWithFormat:@"{\"valid\":true,\"code\":\"ok\",\"message\":\"activated\",\"expires\":\"2099-12-31 23:59:59\",\"sig\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"sig_ed\":\"00\",\"sig_ed2\":\"00\",\"server_time\":%ld}", gnow];
        }
        NSData *d = [tpl dataUsingEncoding:NSUTF8StringEncoding];
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:req.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
        if (cb) cb(d, resp, nil);
        return nil;
    }
    /* --- استطلاع باقي الرحلة --- */
    GFLOG(@"REQ %@ %@", req.HTTPMethod ?: @"?", url);
    if (req.HTTPBody) GFLOG(@"REQ-BODY %@", [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding]);
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e){
        GFLOG(@"RESP %@ | %ld", url, (long)[(NSHTTPURLResponse *)r statusCode]);
        if (d) GFLOG(@"RESP-BODY %@", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]);
        if (cb) cb(d, r, e);
    };
    return %orig(req, wrapped);
}
%end

/* استطلاع مساند */
%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef q, CFTypeRef *result) {
    OSStatus s = %orig(q, result);
    NSString *sv = q ? (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("svce")) : nil;
    NSString *ac = q ? (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("acct")) : nil;
    GFLOG(@"KC-FIND %d svce=%@ acct=%@", (int)s, sv ?: @"-", ac ?: @"-");
    if (s == 0 && result && *result) GFLOG(@"KC-HIT %@", [(__bridge id)*result description]);
    return s;
}
%hookf(OSStatus, SecItemAdd, CFDictionaryRef q, CFTypeRef *r) {
    NSString *sv = q ? (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("svce")) : nil;
    NSString *ac = q ? (__bridge NSString *)CFDictionaryGetValue(q, CFSTR("acct")) : nil;
    GFLOG(@"KC-ADD svce=%@ acct=%@ data=%@", sv ?: @"-", ac ?: @"-", q ? [(__bridge id)CFDictionaryGetValue(q, CFSTR("v_Data")) description] : @"-");
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
                        [low rangeOfString:@"dckey"].location != NSNotFound ||
                        [low rangeOfString:@"hack"].location != NSNotFound ||
                        [low hasPrefix:@"dc"]) {
                        GFLOG(@"CLASS %@", n);
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
