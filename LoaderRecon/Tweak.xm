// NetWatch v2.4 — بوابة auth_failed: اكتمال مخطط successPayload (remaining_text/new_token/notification/updates) + تعقيم آخر خطأ
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <os/log.h>
#import <CommonCrypto/CommonHMAC.h>
#import <mach-o/dyld.h>
#import <fcntl.h>
#include <unistd.h>
#include <stdarg.h>
#include <time.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>

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

// كاش القيم عبر كل المخازن
static char g_chal[512]="", g_ckey[512]="", g_creq[512]="", g_cded[128]="";
static void cache_put(const char *k, const char *v) {
    if (!k || !v || !v[0]) return;
    if (strstr(k,"UDIDChallenge")||strstr(k,"challenge")) snprintf(g_chal,sizeof(g_chal),"%s",v);
    else if (strstr(k,"UDIDKey")) snprintf(g_ckey,sizeof(g_ckey),"%s",v);
    else if (strstr(k,"UDIDRequest")) snprintf(g_creq,sizeof(g_creq),"%s",v);
    else if (strstr(k,"UDIDDeadline")) snprintf(g_cded,sizeof(g_cded),"%s",v);
}

static void cfstr(CFTypeRef v, char *out, size_t n) {
    out[0]=0;
    if (!v) return;
    if (CFGetTypeID(v)==CFStringGetTypeID()) {
        CFStringGetCString((CFStringRef)v, out, n, kCFStringEncodingUTF8);
    } else if (CFGetTypeID(v)==CFDataGetTypeID()) {
        CFDataRef d=(CFDataRef)v; long len=CFDataGetLength(d);
        const unsigned char *b=CFDataGetBytePtr(d);
        size_t o=0;
        for(long i=0;i<len && i<120 && o<n-4;i++) o+=snprintf(out+o,n-o,"%02x",b[i]);
        if(len>120) snprintf(out+o,n-o,"...");
    } else if (CFGetTypeID(v)==CFNumberGetTypeID()) {
        CFNumberRef num=(CFNumberRef)v;
        if(CFNumberIsFloatType(num)){double d;CFNumberGetValue(num,kCFNumberDoubleType,&d);snprintf(out,n,"%.3f",d);}
        else{long long l;CFNumberGetValue(num,kCFNumberLongLongType,&l);snprintf(out,n,"%lld",l);}
    } else if (CFGetTypeID(v)==CFDictionaryGetTypeID()) {
        snprintf(out,n,"{dict}");
    } else if (CFGetTypeID(v)==CFArrayGetTypeID()) {
        snprintf(out,n,"[array %ld]",CFArrayGetCount((CFArrayRef)v));
    } else if (CFGetTypeID(v)==CFBooleanGetTypeID()) {
        snprintf(out,n,"%s",CFBooleanGetValue((CFBooleanRef)v)?"true":"false");
    }
}

static void log_dict(const char *tag, CFDictionaryRef d) {
    if (!d) return;
    const void *vals[8]; const void *keys[8];
    (void)vals; (void)keys;
    const char *want[] = {"class","svce","acct","v_Data","pdmn","agrp","desc","gena"};
    for (int i=0;i<8;i++) {
        CFStringRef k = CFStringCreateWithCString(NULL, want[i], kCFStringEncodingUTF8);
        CFTypeRef v = CFDictionaryGetValue(d, k);
        CFRelease(k);
        if (v) { char b[1400]; cfstr(v,b,sizeof(b)); RLogC("%s %s=%s", tag, want[i], b); }
    }
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

/* v1.3: فك حقول التحدي من ردود السيرفر الحقيقية */
static void DGScanChallenge(const char *body) {
    if (!body) return;
    struct { const char *key; int which; } fields[] = {
        {"\"udid_challenge\"\":\"\"", 1}, {"\"challenge\"\":\"\"", 1},
        {"\"server_challenge\"\":\"\"", 1}, {"\"request_id\"\":\"\"", 2},
        {"\"requestId\"\":\"\"", 2}, {"\"udidKey\"\":\"\"", 3}, {"\"udid_key\"\":\"\"", 3},
    };
    for (int i = 0; i < 7; i++) {
        const char *p = strstr(body, fields[i].key);
        if (!p) continue;
        p += strlen(fields[i].key);
        char v[256]; int n = 0;
        while (p[n] && p[n] != '"' && n < 255) { v[n] = p[n]; n++; }
        v[n] = 0;
        if (!v[0]) continue;
        if (fields[i].which == 1) snprintf(g_chal, sizeof(g_chal), "%s", v);
        else if (fields[i].which == 2) snprintf(g_creq, sizeof(g_creq), "%s", v);
        else snprintf(g_ckey, sizeof(g_ckey), "%s", v);
        RLogC("SCAN-CH %s", v);
    }
    const char *dl = strstr(body, "\"expired_time\"\":\"\"");
    if (dl) { dl += 16; char v[64]; int n = 0;
        while (dl[n] && dl[n] != '"' && n < 63) { v[n] = dl[n]; n++; }
        v[n] = 0; snprintf(g_cded, sizeof(g_cded), "%s", v); RLogC("SCAN-CH deadline=%s", v); }
}

/* v1.5: نزع السلاح — وجود الملف يوقف كل التزوير لجولة التقاط حقيقية */
static bool nw_disarmed(void) { return access("/var/mobile/Documents/nw_disarm", F_OK) == 0; }

static NSData *ForgedSuccess(const char *url) {
    /* v1.7: بطارية حقول تاريخ مرقّمة — كل حقل بقيمة فريدة تكشف اسمه من DATE-FMT */
    char ts[32], keyv[64], udid[64];
    param_value(url, "timestamp", ts, sizeof(ts));
    param_value(url, "key", keyv, sizeof(keyv));
    param_value(url, "uuid", udid, sizeof(udid));
    time_t now = time(NULL);
    char dts[40];
    struct tm *tmn = gmtime(&now);   /* v2.3: UTC — المحلل يفسرها بتوقيت ثابت GMT؛ المحلي كان يخلق فرق 3 ساعات */
    if (tmn) strftime(dts, sizeof(dts), "%Y-%m-%d %H:%M:%S", tmn);
    else snprintf(dts, sizeof(dts), "2099-12-31 23:59:59");
    RLogC("FORGE-DTS %s", dts);
    char buf[2048];
    snprintf(buf, sizeof(buf),
        "{\"status\":\"success\","
        "\"messenger\":\"Kích hoạt thành công\","
        "\"code\":\"success\","
        "\"key\":\"%s\","
        "\"device_id\":\"%s\","
        "\"timestamp\":\"%s\","
        "\"server_time\":\"%s\","
        "\"server_timestamp\":\"%s\","
        "\"serverTime\":\"%s\","
        "\"time\":\"%s\","
        "\"expired_time\":\"2099-12-31 23:59:59\","
        "\"expire\":\"2099-12-31\","
        "\"expiry\":\"31-12-2099 23:59:59\","
        "\"expiry_date\":\"2099-12-31 23:59:59\","
        "\"expired\":\"2099/12/31 23:59:59\","
        "\"valid_until\":\"12/31/2099 23:59:59\","
        "\"valid_to\":\"2099.12.31 23:59:59\","
        "\"end_time\":\"2099-12-31T23:59:59\","
        "\"time_end\":\"Mon, 31 Dec 2099 23:59:59 +0000\","
        "\"date_end\":\"31 Dec 2099\","
        "\"deadline\":\"31-12-2099\","
        "\"server_date\":\"31/12/2099\","
        "\"date\":\"2099-12-31\","
        "\"ngayhethan\":\"31-12-2099 23:59\","
        "\"ngay_het_han\":\"31/12/2099 23:59\","
        "\"han_su_dung\":\"2099-12-31 23:59\","
        "\"thoigianhethan\":\"31-12-2099\","
        "\"hansudung\":\"2099/12/31\","
        "\"expiredDate\":\"31-12-2099 23:59:59\","
        "\"expireDate\":\"31/12/2099 23:59:59\","
        "\"expirationDate\":\"2099/12/31 23:59:59\","
        "\"expiration\":\"12/31/2099 23:59:59\","
        "\"expiryDate\":\"2099.12.31 23:59:59\","
        "\"validUntil\":\"2099-12-31T23:59:59\","
        "\"endTime\":\"Mon, 31 Dec 2099 23:59:59 +0000\","
        "\"expiredTime\":\"31 Dec 2099\","
        "\"timeExpire\":\"31-12-2099\","
        "\"expireAt\":\"31/12/2099\","
        "\"remaining_seconds\":999999999,\"remaining_text\":\"999999 days\",\"new_token\":\"TEST123\",\"notification\":\"\",\"update_available\":false,\"force_update\":false,\"data\":{\"status\":\"active\",\"expire\":\"2099-12-31\",\"expired_time\":\"2099-12-31 23:59:59\"}}",
        keyv[0] ? keyv : "TEST123",
        udid[0] ? udid : "00008020-00091DCE0EF1002E",
        ts[0] ? ts : "0",
        dts,
        ts[0] ? ts : "0",
        dts,
        dts);
    RLogC("FORGE-BAT %s", buf);
    /* v1.8: حقنة المفاتيح المنتظرة — اللودر يفرغها قبل الطلب ويتوقع ملءها من bootstrap.
       نملؤها لحظة الفورج: اللودر يقرأها بعد الرد → deadline يُحلل بنجاح (yyyy-MM-dd HH:mm:ss) */
    NSUserDefaults *dd = [NSUserDefaults standardUserDefaults];
    [dd setObject:@"2099-12-31 23:59:59" forKey:@"pendingUDIDDeadline"];
    [dd setObject:[NSString stringWithUTF8String:udid[0] ? udid : "00008020-00091DCE0EF1002E"] forKey:@"pendingUDIDChallenge"];
    [dd setObject:[NSString stringWithUTF8String:keyv[0] ? keyv : "TEST123"] forKey:@"pendingUDIDKey"];
    RLogC("FORGE-INJECT deadline=2099 chal+key filled");
    return [NSData dataWithBytes:buf length:strlen(buf)];
}

// Keychain hooks
%hookf(OSStatus, SecItemAdd, CFDictionaryRef attrs, CFTypeRef *result) {
    if (attrs) {
        RLogC("KC-ADD:");
        log_dict("KC-ADD", attrs);
        const void *v = CFDictionaryGetValue(attrs, CFSTR("v_Data"));
        if (v) { char b[1400]; cfstr(v,b,sizeof(b)); cache_put("challenge", b); }
        const void *a = CFDictionaryGetValue(attrs, CFSTR("acct"));
        if (a) { char b[512]; cfstr(a,b,sizeof(b)); }
    }
    return %orig(attrs, result);
}
%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef query, CFTypeRef *result) {
    OSStatus s = %orig(query, result);
    if (query) {
        RLogC("KC-FIND status=%d:", (int)s);
        log_dict("KC-FIND", query);
    }
    /* v1.3 KC-FORGE: الترخيص المزروع — نجيب "موجود" على savedKey */
    if (s == -25300 && query && result && !nw_disarmed()) {
        char sb[128], ab[128]; sb[0]=ab[0]=0;
        cfstr(CFDictionaryGetValue(query, CFSTR("svce")), sb, sizeof(sb));
        cfstr(CFDictionaryGetValue(query, CFSTR("acct")), ab, sizeof(ab));
        if (strstr(sb, "sharkios") && strcmp(ab, "savedKey") == 0) {
            CFDataRef fake = CFDataCreate(NULL, (const UInt8 *)"TEST123", 7);
            if (CFDictionaryGetValue(query, CFSTR("r_Att"))) {
                CFMutableDictionaryRef md = CFDictionaryCreateMutable(NULL, 0,
                    &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                CFDictionarySetValue(md, CFSTR("class"), kSecClassGenericPassword);
                CFDictionarySetValue(md, CFSTR("svce"), CFSTR("com.sharkios.license"));
                CFDictionarySetValue(md, CFSTR("acct"), CFSTR("savedKey"));
                CFDictionarySetValue(md, CFSTR("v_Data"), fake);
                *result = md;
            } else { *result = fake; }
            RLogC("KC-FORGE savedKey=TEST123 returned");
            s = 0;
        } else if (strstr(sb, "sharkios")) {
            RLogC("KC-MISS acct=%s", ab);
        }
    }
    if ((result && *result) || s == 0) {
        if (CFGetTypeID(*result)==CFDataGetTypeID()) {
            char b[1400]; cfstr(*result,b,sizeof(b)); RLogC("KC-RESULT data=%s", b); cache_put("challenge", b);
        } else if (CFGetTypeID(*result)==CFDictionaryGetTypeID()) {
            RLogC("KC-RESULT dict:");
            log_dict("KC-RES", (CFDictionaryRef)*result);
            const void *v = CFDictionaryGetValue((CFDictionaryRef)*result, CFSTR("v_Data"));
            if (v) { char b[1400]; cfstr(v,b,sizeof(b)); cache_put("challenge", b); }
        }
    }
    return s;
}
%hookf(OSStatus, SecItemDelete, CFDictionaryRef query) {
    if (query) { RLogC("KC-DEL:"); log_dict("KC-DEL", query); }
    return %orig(query);
}
%hookf(OSStatus, SecItemUpdate, CFDictionaryRef query, CFDictionaryRef attrs) {
    if (query) { RLogC("KC-UPDATE-Q:"); log_dict("KC-UPDQ", query); }
    if (attrs) { RLogC("KC-UPDATE-A:"); log_dict("KC-UPDA", attrs); }
    return %orig(query, attrs);
}

%hook NSUserDefaults
- (void)setObject:(id)v forKey:(NSString *)k {
    RLogC("DEFAULTS-SET %s = %.*s", k.UTF8String ?: "?", (int)MIN((NSUInteger)400, [[v description] length]), v ? [[v description] UTF8String] : "(nil)");
    if (v) cache_put(k.UTF8String, [[v description] UTF8String]);
    %orig(v, k);
}
- (id)objectForKey:(NSString *)k {
    id v = %orig(k);
    const char *ks = k.UTF8String;
    if (ks && strncmp(ks, "NS", 2) != 0 && strncmp(ks, "AK", 2) != 0 && strncmp(ks, "UI", 2) != 0 && strncmp(ks, "Log", 3) != 0 && strncmp(ks, "_", 1) != 0 && strncmp(ks, "Metal", 5) != 0)
        RLogC("DEFAULTS-GET %s -> %.*s", ks, (int)MIN((NSUInteger)200, v?[[v description]length]:6), v ? [[v description] UTF8String] : "(nil)");
    if (v && ks) cache_put(ks, [[v description] UTF8String]);
    if (ks && [k isEqualToString:@"pendingUDIDDeadline"] && (!v || [[v description] length] == 0)) {
        RLogC("UD-FORGE pendingUDIDDeadline=2099");
        return @"2099-12-31 23:59:59";
    }
    return v;
}
%end

%hook NSUbiquitousKeyValueStore
- (void)setObject:(id)v forKey:(NSString *)k {
    RLogC("KVS-SET %s = %.*s", k.UTF8String ?: "?", (int)MIN((NSUInteger)300, [[v description] length]), v ? [[v description] UTF8String] : "(nil)");
    if (v) cache_put(k.UTF8String, [[v description] UTF8String]);
    %orig(v, k);
}
- (id)objectForKey:(NSString *)k {
    id v = %orig(k);
    if (v) { RLogC("KVS-GET %s -> %.*s", k.UTF8String ?: "?", (int)MIN((NSUInteger)300, [[v description] length]), [[v description] UTF8String]); cache_put(k.UTF8String, [[v description] UTF8String]); }
    return v;
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)req completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    RLogC("REQ %s %s", req.HTTPMethod.UTF8String ?: "-", req.URL.absoluteString.UTF8String ?: "-");
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        RLogC("RESP %s | status=%ld", req.URL.absoluteString.UTF8String ?: "-", (long)[(NSHTTPURLResponse *)r statusCode]);
        /* v1.3: فورج انتقائي — فقط محاولات التفعيل التي تحمل key= */
        if (cb && !nw_disarmed() && [req.URL.absoluteString containsString:@"Cheack.php"]
            && [req.URL.absoluteString containsString:@"key="]) {
            RLogC("FORGE >>> keyed fake success");
            cb(ForgedSuccess(req.URL.absoluteString.UTF8String), r, nil);
            return;
        }
        /* v1.3: فحص كل ردود haxvip الحقيقية — التحدي يُلتقط هنا */
        if (cb && d && [req.URL.absoluteString containsString:@"haxvip.pro"]) {
            const char *b = (const char *)[d bytes];
            RLogC("RESP-BODY %.*s", (int)MIN((NSUInteger)1200, d.length), b ? b : "");
            DGScanChallenge(b);
        }
        if (cb) cb(d, r, e);
    };
    return %orig(req, wrapped);
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    return [self dataTaskWithRequest:[NSURLRequest requestWithURL:url] completionHandler:cb];
}
%end

%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)err {
    id obj = %orig(data, opt, err);
    if (data && [data length] > 10 && [data length] < 8192) {
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (s && [s containsString:@"\"status\""]) {
            RLogC("PARSED-IN %.*s", (int)MIN((NSUInteger)1400, [s length]), [s UTF8String]);
            if ([obj isKindOfClass:[NSDictionary class]]) {
                for (NSString *k in (NSDictionary *)obj) {
                    RLogC("PARSED-KEY %s=%s", [k UTF8String] ?: "?", [[[(NSDictionary*)obj objectForKey:k] description] UTF8String] ?: "?");
                }
            }
        }
    }
    return obj;
}
%end

%hook NSDictionary
- (id)objectForKeyedSubscript:(id)key {
    id v = %orig(key);
    if ([key isKindOfClass:[NSString class]]) {
        NSString *k = (NSString *)key;
        if ([k containsString:@"time"] || [k containsString:@"deadline"] || [k containsString:@"expir"]
            || [k containsString:@"key"] || [k containsString:@"udid"] || [k containsString:@"status"]
            || [k containsString:@"chal"] || [k containsString:@"hash"] || [k containsString:@"server"]
            || [k containsString:@"nonce"] || [k containsString:@"sig"] || [k containsString:@"message"]
            || [k containsString:@"error"] || [k containsString:@"success"] || [k containsString:@"token"]) {
            NSString *d = v ? [[v description] substringToIndex:MIN((NSUInteger)120, [[v description] length])] : @"(nil)";
            RLogC("DICT-GET[%s]=%s", [k UTF8String] ?: "?", [d UTF8String]);
        }
    }
    return v;
}
- (id)objectForKey:(id)aKey {
    id v = %orig(aKey);
    if ([aKey isKindOfClass:[NSString class]]) {
        NSString *k = (NSString *)aKey;
        if ([k containsString:@"time"] || [k containsString:@"deadline"] || [k containsString:@"expir"]
            || [k containsString:@"key"] || [k containsString:@"udid"] || [k containsString:@"status"]
            || [k containsString:@"chal"] || [k containsString:@"hash"] || [k containsString:@"server"]
            || [k containsString:@"nonce"] || [k containsString:@"sig"] || [k containsString:@"message"]
            || [k containsString:@"error"] || [k containsString:@"success"] || [k containsString:@"token"]) {
            NSString *d = v ? [[v description] substringToIndex:MIN((NSUInteger)120, [[v description] length])] : @"(nil)";
            RLogC("DICT-GET(%s)=%s", [k UTF8String] ?: "?", [d UTF8String]);
        }
    }
    return v;
}
%end

%hook NSDateFormatter
- (void)setTimeZone:(NSTimeZone *)tz {
    RLogC("DATE-TZ-SET %s", [[tz name] UTF8String] ?: "?");
    %orig(tz);
}
- (void)setDateFormat:(NSString *)f {
    RLogC("DATE-FMT-SET %s", [f UTF8String] ?: "?");
    %orig(f);
}
- (NSDate *)dateFromString:(NSString *)s {
    NSDate *d = %orig(s);
    RLogC("DATE-FMT in=%s out=%s", [s UTF8String] ?: "?", d ? "OK" : "NIL");
    return d;
}
%end

%hook NSISO8601DateFormatter
- (NSDate *)dateFromString:(NSString *)s {
    NSDate *d = %orig(s);
    RLogC("ISO-FMT in=%s out=%s", [s UTF8String] ?: "?", d ? "OK" : "NIL");
    return d;
}
%end

%hook NSDictionary
- (id)valueForKey:(NSString *)k {
    id v = %orig(k);
    if ([k isKindOfClass:[NSString class]]) {
        NSString *ks = (NSString *)k;
        if ([ks containsString:@"time"] || [ks containsString:@"deadline"] || [ks containsString:@"expir"]
            || [ks containsString:@"key"] || [ks containsString:@"udid"] || [ks containsString:@"chal"]) {
            NSString *d = v ? [[v description] substringToIndex:MIN((NSUInteger)120, [[v description] length])] : @"(nil)";
            RLogC("DICT-VFK(%s)=%s", [ks UTF8String] ?: "?", [d UTF8String]);
        }
    }
    return v;
}
%end

%hook NSUserDefaults
- (NSString *)stringForKey:(NSString *)k {
    NSString *v = %orig(k);
    if (v && ([k containsString:@"lastError"] || [k isEqualToString:@"last_error_code"])) {
        RLogC("UD-FORGE-CLEAN %s", [k UTF8String] ?: "?");
        return @"";
    }
    if (v && [k containsString:@"retry_count"]) {
        RLogC("UD-FORGE-CLEAN retry_count");
        return @"0";
    }
    return v;
}
- (instancetype)initWithSuiteName:(NSString *)sn {
    RLogC("UD-SUITE %s", [sn UTF8String] ?: "?");
    return %orig(sn);
}
- (NSDictionary *)dictionaryRepresentation {
    NSDictionary *d = %orig;
    id dl = [d objectForKey:@"pendingUDIDDeadline"];
    if (dl) RLogC("UD-DICT deadline=%s", [[dl description] UTF8String]);
    return d;
}
- (NSString *)stringForKey:(NSString *)k {
    NSString *v = %orig(k);
    if ([k isEqualToString:@"pendingUDIDDeadline"] && (!v || [v length] == 0)) {
        RLogC("UD-FORGE-S pendingUDIDDeadline=2099");
        return @"2099-12-31 23:59:59";
    }
    return v;
}
%end

%hookf(time_t, time, time_t *t) {
    time_t r = %orig(t);
    static int tc = 0;
    if (tc < 60) { tc++; RLogC("TIME() = %ld", (long)r); }
    return r;
}

%hook NSURLConnection
+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error {
    RLogC("REQ-SYNC %s %s", request.HTTPMethod.UTF8String ?: "-", request.URL.absoluteString.UTF8String ?: "-");
    NSData *d = %orig(request, response, error);
    RLogC("RESP-SYNC %s | %lu bytes", request.URL.absoluteString.UTF8String ?: "-", (unsigned long)d.length);
    return d;
}
+ (void)sendAsynchronousRequest:(NSURLRequest *)request queue:(NSOperationQueue *)queue completionHandler:(void (^)(NSURLResponse *, NSData *, NSError *))handler {
    RLogC("REQ-ASYNC %s %s", request.HTTPMethod.UTF8String ?: "-", request.URL.absoluteString.UTF8String ?: "-");
    void (^wrapped)(NSURLResponse *, NSData *, NSError *) = ^(NSURLResponse *r, NSData *d, NSError *e){
        RLogC("RESP-ASYNC %s | %lu bytes", request.URL.absoluteString.UTF8String ?: "-", (unsigned long)d.length);
        if(handler) handler(r,d,e);
    };
    %orig(request, queue, wrapped);
}
- (instancetype)initWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    RLogC("REQ-CONN %s %s", request.HTTPMethod.UTF8String ?: "-", request.URL.absoluteString.UTF8String ?: "-");
    return %orig(request, delegate);
}
%end

%hook NSURLRequest
- (instancetype)initWithURL:(NSURL *)url {
    if (url) RLogC("REQ-INIT %s", url.absoluteString.UTF8String ?: "-");
    return %orig(url);
}
+ (instancetype)requestWithURL:(NSURL *)url {
    if (url) RLogC("REQ-WITH %s", url.absoluteString.UTF8String ?: "-");
    return %orig(url);
}
%end

%hook NSMutableURLRequest
- (instancetype)initWithURL:(NSURL *)url {
    if (url) RLogC("REQ-MINIT %s", url.absoluteString.UTF8String ?: "-");
    return %orig(url);
}
+ (instancetype)requestWithURL:(NSURL *)url {
    if (url) RLogC("REQ-MWITH %s", url.absoluteString.UTF8String ?: "-");
    return %orig(url);
}
%end

%hook NSData
+ (instancetype)dataWithContentsOfURL:(NSURL *)url {
    RLogC("REQ-DATAURL %s", url.absoluteString.UTF8String ?: "-");
    return %orig(url);
}
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

%hook NSDictionary
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
            strstr(f,"AUTO")||strstr(f,"token")||strstr(f,"Token")||strstr(f,"sync")||strstr(f,"Sync")||strstr(f,"UDID")||strstr(f,"challenge")) ? 1 : 0;
}
%hookf(void, _os_log_impl, void *dso, os_log_t log, os_log_type_t type, const char *fmt, uint8_t *buffer, uint32_t size) {
    if (interesting(fmt)) RLogC("APP-OSLOG type=%u size=%u fmt=%s", (unsigned)type, (unsigned)size, fmt);
    %orig(dso, log, type, fmt, buffer, size);
}
%hookf(void, NSLog, NSString *format, ...) {
    const char *f = format ? [format UTF8String] : "(nil)";
    if (f && (strstr(f,"AntiCrack")||strstr(f,"Key")||strstr(f,"key")||strstr(f,"DEBUG")||strstr(f,"lua")||strstr(f,"patch")||strstr(f,"time")||strstr(f,"Time")||strstr(f,"sync")||strstr(f,"Session")||strstr(f,"token")||strstr(f,"UDID")||strstr(f,"Challenge")||strstr(f,"challenge")))
        RLogC("NSLOG %s", f);
}
%hookf(void, CCHmac, CCHmacAlgorithm algorithm, const void *key, size_t keyLength, const void *data, size_t dataLength, void *macOut) {
    char kb[192], db[700], mb[160];
    size_t ko=0, d2=0, mo=0;
    for(size_t i=0; key && i<keyLength && i<64 && ko<sizeof(kb)-4; i++) ko+=snprintf(kb+ko,sizeof(kb)-ko,"%02x",((const uint8_t*)key)[i]);
    kb[ko]=0;
    for(size_t i=0; data && i<dataLength && i<200 && d2<sizeof(db)-8; i++) d2+=snprintf(db+d2,sizeof(db)-d2,"%02x",((const uint8_t*)data)[i]);
    if(dataLength>200) snprintf(db+d2,sizeof(db)-d2,"...(+%lu)",(unsigned long)(dataLength-200));
    RLogC("CCHMAC alg=%lu keyLen=%lu key=%s dataLen=%lu data=%s", (unsigned long)algorithm, (unsigned long)keyLength, kb, (unsigned long)dataLength, db);
    %orig(algorithm, key, keyLength, data, dataLength, macOut);
    for(int i=0; macOut && i<32 && mo<sizeof(mb)-4; i++) mo+=snprintf(mb+mo,sizeof(mb)-mo,"%02x",((const uint8_t*)macOut)[i]);
    RLogC("CCHMAC-OUT %s", mb);
}
%hookf(OSStatus, SecTrustEvaluate, SecTrustRef trust, SecTrustResultType *res) {
    if (res) *res = kSecTrustResultProceed;
    return errSecSuccess;
}
