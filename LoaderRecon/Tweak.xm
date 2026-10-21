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
