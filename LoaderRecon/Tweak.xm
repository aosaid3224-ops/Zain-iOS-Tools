// LoaderRecon — عين ساهرة داخل DELTA_LOADER: يلتقط الشبكة + الكتابات + يعطل TLS pinning
#import <UIKit/UIKit.h>
#import <Security/Security.h>

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

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)req completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))cb {
    NSString *body = req.HTTPBody ? [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding] : @"(empty)";
    RLog(@"REQ %@ %@ | hdr=%@ | body=%@", req.HTTPMethod, req.URL.absoluteString, req.allHTTPHeaderFields, body);
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        NSString *resp = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"(nil)";
        RLog(@"RESP %@ | status=%ld | err=%@ | body=%@", req.URL.absoluteString,
             (long)[(NSHTTPURLResponse *)r statusCode], e,
             resp.length > 3000 ? [resp substringToIndex:3000] : resp);
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

// تعطيل TLS pinning (احتياطي — إن وجد)
%hookf(OSStatus, SecTrustEvaluate, SecTrustRef trust, SecTrustResultType *res) {
    if (res) *res = kSecTrustResultProceed;
    return errSecSuccess;
}

#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>

// v0.2: كشف خوارزمية التوقيع عند المصدر
%hookf(void, CCHmac, CCHmacAlgorithm algorithm, const void *key, size_t keyLength, const void *data, size_t dataLength, void *macOut) {
    NSString *keyS = key ? [[NSString alloc] initWithBytes:key length:MIN(keyLength,200) encoding:NSUTF8StringEncoding] : @"(nil)";
    NSString *dataS = data ? [[NSString alloc] initWithBytes:data length:MIN(dataLength,4000) encoding:NSUTF8StringEncoding] : @"(nil)";
    RLog(@"CCHMAC alg=%lu keyLen=%lu key=[%@] | dataLen=%lu data=[%@]",
         (unsigned long)algorithm, (unsigned long)keyLength, keyS,
         (unsigned long)dataLength, dataS);
    %orig(algorithm, key, keyLength, data, dataLength, macOut);
    if (macOut) {
        NSData *mac = [NSData dataWithBytes:macOut length:32];
        RLog(@"CCHMAC-RESULT %@", mac);
    }
}

%hookf(int, CCHmacInit, CCHmacContext *ctx, CCHmacAlgorithm algorithm, const void *key, size_t keyLength) {
    NSString *keyS = key ? [[NSString alloc] initWithBytes:key length:MIN(keyLength,200) encoding:NSUTF8StringEncoding] : @"(nil)";
    RLog(@"CCHMAC-INIT alg=%lu keyLen=%lu key=[%@]", (unsigned long)algorithm, (unsigned long)keyLength, keyS);
    return %orig(ctx, algorithm, key, keyLength);
}

%hookf(unsigned char *, CC_SHA256, const void *data, CC_LONG len, unsigned char *md) {
    NSString *dataS = data ? [[NSString alloc] initWithBytes:data length:MIN((int)len,4000) encoding:NSUTF8StringEncoding] : @"(nil)";
    RLog(@"CCSHA256 len=%d data=[%@]", (int)len, dataS);
    return %orig(data, len, md);
}
