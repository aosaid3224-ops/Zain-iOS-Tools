// NetWatch v0.3 — عين ساهرة + خداع رد النجاح
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>

static void RLog(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a];
    va_end(a);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], s];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *p = @"/var/mobile/Documents/loader_recon.log";
    if (![fm fileExistsAtPath:p]) [fm createFileAtPath:p contents:nil attributes:@{NSFileProtectionKey:NSFileProtectionNone}];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    [h seekToEndOfFile];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

// رد النجاح المزور
static NSData *ForgedSuccess(void) {
    NSDictionary *fake = @{
        @"status": @"success",
        @"code": @"success",
        @"messenger": @"Kich hoat thanh cong",
        @"key": @"TEST123",
        @"expired_time": @"2099-12-31 23:59:59",
        @"device_id": @"00008020-00091DCE0EF1002E",
        @"data": @{ @"status": @"active", @"expire": @"2099-12-31", @"type": @"VIP" }
    };
    return [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];
}

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)req completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    NSString *body = req.HTTPBody ? [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding] : @"(empty)";
    RLog(@"REQ %@ %@ | hdr=%@ | body=%@", req.HTTPMethod, req.URL.absoluteString, req.allHTTPHeaderFields, body);
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        NSString *resp = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"(nil)";
        RLog(@"RESP %@ | status=%ld | err=%@ | body=%@", req.URL.absoluteString,
             (long)[(NSHTTPURLResponse *)r statusCode], e,
             resp.length > 3000 ? [resp substringToIndex:3000] : resp);
        if ([req.URL.absoluteString containsString:@"Cheack.php"] && cb) {
            RLog(@"FORGE >>> استبدال رد Cheack.php برسالة نجاح مزورة");
            cb(ForgedSuccess(), r, nil);
            return;
        }
        if (cb) cb(d, r, e);
    };
    return %orig(req, wrapped);
}
%end

%hook NSData
- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)mask error:(NSError **)error {
    RLog(@"WRITE-NSData %@ (%lu bytes)", path, (unsigned long)self.length);
    return %orig(path, mask, error);
}
%end

%hook NSString
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)u encoding:(NSStringEncoding)e error:(NSError **)err {
    NSString *preview = self.length > 400 ? [self substringToIndex:400] : self;
    RLog(@"WRITE-NSString %@ : %@", path, preview);
    return %orig(path, u, e, err);
}
%end

%hook NSDictionary
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)u {
    RLog(@"WRITE-Dict %@", path);
    return %orig(path, u);
}
%end

// التقاط سجلات التطبيق الذاتية
%hookf(void, os_log, os_log_t log, const char *fmt, ...) {
    if (fmt) RLog(@"APP-OSLOG %s", fmt);
}
%hookf(void, NSLog, NSString *format, ...) {
    va_list a; va_start(a, format);
    NSString *s = [[NSString alloc] initWithFormat:format arguments:a];
    va_end(a);
    RLog(@"APP-NSLOG %@", s);
}

%hookf(void, CCHmac, CCHmacAlgorithm algorithm, const void *key, size_t keyLength, const void *data, size_t dataLength, void *macOut) {
    NSString *keyS = key ? [[NSString alloc] initWithBytes:key length:MIN(keyLength,200) encoding:NSUTF8StringEncoding] : @"(nil)";
    NSString *dataS = data ? [[NSString alloc] initWithBytes:data length:MIN(dataLength,4000) encoding:NSUTF8StringEncoding] : @"(nil)";
    RLog(@"CCHMAC alg=%lu keyLen=%lu key=[%@] | dataLen=%lu data=[%@]",
         (unsigned long)algorithm, (unsigned long)keyLength, keyS, (unsigned long)dataLength, dataS);
    %orig(algorithm, key, keyLength, data, dataLength, macOut);
    if (macOut) {
        NSData *mac = [NSData dataWithBytes:macOut length:32];
        RLog(@"CCHMAC-RESULT %@", mac);
    }
}

%hookf(unsigned char *, CC_SHA256, const void *data, CC_LONG len, unsigned char *md) {
    return %orig(data, len, md);
}

%hookf(OSStatus, SecTrustEvaluate, SecTrustRef trust, SecTrustResultType *res) {
    if (res) *res = kSecTrustResultProceed;
    return errSecSuccess;
}
