#import <substrate.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <Foundation/Foundation.h>

// ============================================
// PREFERENCES - Settings from Arabic UI
// ============================================

#define PREFS_PATH @"/var/mobile/Library/Preferences/com.aosaid.naverseriesbypass.plist"

static BOOL isEnabled = YES;
static BOOL spoofIDFV = YES;
static BOOL blockKeychain = YES;
static BOOL spoofHeaders = YES;
static BOOL jbBypass = YES;
static BOOL autoDismissPopup = YES;
static BOOL neutralizeResponses = YES;

static void loadPrefs() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    if (prefs) {
        isEnabled = [prefs[@"Enabled"] boolValue];
        spoofIDFV = [prefs[@"SpoofIDFV"] boolValue];
        blockKeychain = [prefs[@"BlockKeychain"] boolValue];
        spoofHeaders = [prefs[@"SpoofHeaders"] boolValue];
        jbBypass = [prefs[@"JBBypass"] boolValue];
        if (prefs[@"AutoDismissPopup"] != nil) autoDismissPopup = [prefs[@"AutoDismissPopup"] boolValue];
        if (prefs[@"NeutralizeResponses"] != nil) neutralizeResponses = [prefs[@"NeutralizeResponses"] boolValue];
    }
}

// ============================================
// DIAGNOSTIC ENGINE - Built-in Logger
// ============================================

#define LOG_FILE @"/var/mobile/Documents/NaverBypass_Diagnostics.log"
#define MAX_LOG_SIZE (5 * 1024 * 1024)

static void NBLog(NSString *format, ...) {
    if (!isEnabled) return;

    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] 
                                                         dateStyle:NSDateFormatterNoStyle 
                                                         timeStyle:NSDateFormatterMediumStyle];
    NSString *logLine = [NSString stringWithFormat:@"[%@] [NaverBypass] %@\n", timestamp, msg];

    // Always log to NSLog (visible in system console)
    NSLog(@"%@", logLine);

    // Try to write to file
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *docsDir = @"/var/mobile/Documents";

        // Ensure directory exists
        if (![fm fileExistsAtPath:docsDir]) {
            [fm createDirectoryAtPath:docsDir withIntermediateDirectories:YES attributes:@{NSFileOwnerAccountName:@"mobile", NSFileGroupOwnerAccountName:@"mobile"} error:nil];
        }

        // Create file if not exists
        if (![fm fileExistsAtPath:LOG_FILE]) {
            [fm createFileAtPath:LOG_FILE contents:[@"" dataUsingEncoding:NSUTF8StringEncoding] attributes:@{NSFileOwnerAccountName:@"mobile", NSFileGroupOwnerAccountName:@"mobile", NSFilePosixPermissions:@0644}];
        }

        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:LOG_FILE];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        } else {
            NSLog(@"[NaverBypass] WARNING: Could not open log file for writing");
        }

        // Rotate if too big
        NSDictionary *attrs = [fm attributesOfItemAtPath:LOG_FILE error:nil];
        if (attrs && attrs.fileSize > MAX_LOG_SIZE) {
            NSString *oldLog = [LOG_FILE stringByAppendingString:@".old"];
            [fm removeItemAtPath:oldLog error:nil];
            [fm moveItemAtPath:LOG_FILE toPath:oldLog error:nil];
        }
    }
    @catch (NSException *e) {
        NSLog(@"[NaverBypass] ERROR writing log: %@", e.reason);
    }
}

// ============================================
// DEVICE IDENTITY SPOOFING ENGINE
// ============================================

// هويات مثبتة: تُولّد مرة واحدة وتُخزّن — نفس الهوية في كل الجلسات والنداءات
// (العشوائية في كل نداء تنتج تناقضاً داخلياً يكشفه خادم مكافحة الاحتيال)
#define IDS_PATH @"/var/mobile/Library/Preferences/com.aosaid.naverseriesbypass.ids.plist"

static NSString *persistentID(NSString *key) {
    static NSMutableDictionary *cache = nil;
    if (!cache) {
        cache = [NSMutableDictionary dictionaryWithContentsOfFile:IDS_PATH] ?: [NSMutableDictionary dictionary];
    }
    NSString *value = cache[key];
    if (!value) {
        value = [[NSUUID UUID] UUIDString];
        cache[key] = value;
        [cache writeToFile:IDS_PATH atomically:YES];
    }
    return value;
}

static NSString *generateFakeIDFV() {
    return persistentID(@"idfv");
}

static NSString *generateFakeADID() {
    return persistentID(@"adid");
}

static NSString *generateFakeDeviceID() {
    NSString *chars = @"abcdefghijklmnopqrstuvwxyz0123456789";
    NSMutableString *result = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < 32; i++) {
        uint32_t r = arc4random_uniform((uint32_t)[chars length]);
        [result appendFormat:@"%C", [chars characterAtIndex:r]];
    }
    return result;
}

// ============================================
// 1. UIDevice Hooks (iOS 16 & 18 Compatible)
// ============================================

%hook UIDevice

- (NSUUID *)identifierForVendor {
    if (!isEnabled || !spoofIDFV) return %orig;
    NSString *fake = generateFakeIDFV();
    NSUUID *originalIdentifier = %orig;
    NBLog(@"[SPOOF] identifierForVendor: %@ -> %@", originalIdentifier, fake);
    return [[NSUUID alloc] initWithUUIDString:fake];
}

- (NSString *)name {
    if (!isEnabled) return %orig;
    NSString *originalName = %orig;
    NBLog(@"[SPOOF] deviceName: %@ -> iPhone", originalName);
    return @"iPhone";
}

- (NSString *)model {
    if (!isEnabled) return %orig;
    NSString *originalModel = %orig;
    NBLog(@"[SPOOF] model: %@ -> iPhone15,2", originalModel);
    return @"iPhone";
}

- (NSString *)localizedModel {
    return @"iPhone";
}

- (NSString *)systemVersion {
    if (!isEnabled) return %orig;
    NSString *originalSystemVersion = %orig;
    NBLog(@"[SPOOF] systemVersion: %@ -> 18.3.1", originalSystemVersion);
    return @"18.3.1";
}

- (NSString *)systemName {
    return @"iOS";
}

%end

// ============================================
// 2. NSBundle Hooks - App Identity
// ============================================

%hook NSBundle

- (NSString *)bundleIdentifier {
    NSString *orig = %orig;
    NBLog(@"[INFO] bundleIdentifier accessed: %@", orig);
    return orig;
}

%end

// ============================================
// 3. Keychain Hooks - Naver Data Interception
// ============================================

static BOOL isNaverKeychainItem(NSDictionary *dict) {
    if (!dict) return NO;
    if (!isEnabled || !blockKeychain) return NO;

    NSString *account = dict[(__bridge NSString *)kSecAttrAccount];
    NSString *service = dict[(__bridge NSString *)kSecAttrService];
    NSString *accessGroup = dict[(__bridge NSString *)kSecAttrAccessGroup];
    NSString *generic = dict[(__bridge NSString *)kSecAttrGeneric];

    NSArray *naverKeywords = @[
        @"naver", @"series", @"ntracker", @"nhncorp",
        @"YAZD8YA78S", @"device", @"ban", @"block",
        @"safety", @"action", @"previous", @"idfv",
        @"consumer", @"hmac", @"adid"
    ];

    for (NSString *keyword in naverKeywords) {
        if ((account && [account rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) ||
            (service && [service rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) ||
            (accessGroup && [accessGroup rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) ||
            (generic && [generic rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound)) {
            return YES;
        }
    }
    return NO;
}

%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef query, CFTypeRef *result) {
    if (!isEnabled || !blockKeychain) return %orig;

    NSDictionary *dict = (__bridge NSDictionary *)query;
    if (isNaverKeychainItem(dict)) {
        NSString *account = dict[(__bridge NSString *)kSecAttrAccount] ?: @"(nil)";
        NSString *service = dict[(__bridge NSString *)kSecAttrService] ?: @"(nil)";
        NBLog(@"[BLOCK] SecItemCopyMatching - Account:%@ Service:%@ -> errSecItemNotFound", account, service);
        return errSecItemNotFound;
    }
    return %orig;
}

%hookf(OSStatus, SecItemAdd, CFDictionaryRef attributes, CFTypeRef *result) {
    if (!isEnabled || !blockKeychain) return %orig;

    NSDictionary *dict = (__bridge NSDictionary *)attributes;
    if (isNaverKeychainItem(dict)) {
        NSString *account = dict[(__bridge NSString *)kSecAttrAccount] ?: @"(nil)";
        NBLog(@"[BLOCK] SecItemAdd - Account:%@ -> Fake Success", account);
        return errSecSuccess;
    }
    return %orig;
}

%hookf(OSStatus, SecItemUpdate, CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (!isEnabled || !blockKeychain) return %orig;

    NSDictionary *dict = (__bridge NSDictionary *)query;
    if (isNaverKeychainItem(dict)) {
        NBLog(@"[BLOCK] SecItemUpdate -> Fake Success");
        return errSecSuccess;
    }
    return %orig;
}

%hookf(OSStatus, SecItemDelete, CFDictionaryRef query) {
    if (!isEnabled || !blockKeychain) return %orig;

    NSDictionary *dict = (__bridge NSDictionary *)query;
    if (isNaverKeychainItem(dict)) {
        NBLog(@"[BLOCK] SecItemDelete -> Fake Success");
        return errSecSuccess;
    }
    return %orig;
}

// ============================================
// 4. NSUserDefaults Hooks
// ============================================

%hook NSUserDefaults

- (id)objectForKey:(NSString *)defaultName {
    if (!isEnabled) return %orig;

    NSArray *blockedKeys = @[
        @"naver", @"series", @"device", @"ban", @"block",
        @"safety", @"action", @"previous", @"idfv", @"fingerprint"
    ];

    for (NSString *keyword in blockedKeys) {
        if ([defaultName rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NBLog(@"[BLOCK] NSUserDefaults objectForKey:%@ -> nil", defaultName);
            return nil;
        }
    }

    id result = %orig;
    if (result) {
        NBLog(@"[INFO] NSUserDefaults objectForKey:%@ -> %@", defaultName, result);
    }
    return result;
}

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    if (!isEnabled) {
        %orig;
        return;
    }

    for (NSString *keyword in @[@"ban", @"block", @"device_id", @"fingerprint"]) {
        if ([defaultName rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NBLog(@"[BLOCK] NSUserDefaults setObject:forKey:%@ -> Skipped", defaultName);
            return;
        }
    }
    %orig;
}

%end

// ============================================
// 5. sysctl / uname Hooks
// ============================================

%hookf(int, uname, struct utsname *value) {
    if (!isEnabled) return %orig;

    int result = %orig;
    if (result == 0 && value) {
        strncpy(value->machine, "iPhone15,2", sizeof(value->machine) - 1);
        strncpy(value->nodename, "iPhone", sizeof(value->nodename) - 1);
        strncpy(value->release, "23.3.0", sizeof(value->release) - 1);
        strncpy(value->version, "Darwin Kernel Version 23.3.0", sizeof(value->version) - 1);
        strncpy(value->sysname, "Darwin", sizeof(value->sysname) - 1);
        NBLog(@"[SPOOF] uname -> machine:iPhone15,2 sysname:Darwin");
    }
    return result;
}

%hookf(int, sysctl, int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!isEnabled) return %orig;
    if (name && namelen >= 2) {
        NBLog(@"[INFO] sysctl called: name[0]=%d name[1]=%d", name[0], name[1]);
    }
    return %orig;
}

%hookf(int, sysctlbyname, const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!isEnabled) return %orig;
    if (name) {
        NSString *nameStr = [NSString stringWithUTF8String:name];
        NBLog(@"[INFO] sysctlbyname called: %@", nameStr);
    }
    return %orig;
}

// ============================================
// 6. Jailbreak Detection Bypass
// ============================================

%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    if (!isEnabled || !jbBypass) return %orig;

    NSArray *jailbreakPaths = @[
        @"/Applications/Cydia.app",
        @"/Applications/blackra1n.app",
        @"/Applications/SBSettings.app",
        @"/Library/MobileSubstrate/DynamicLibraries/LiveClock.plist",
        @"/private/var/lib/cydia",
        @"/usr/sbin/sshd",
        @"/var/lib/cydia",
        @"/etc/apt",
        @"/private/var/stash",
        @"/var/tmp/cydia.log",
        @"/var/mobile/Library/SBSettings/Themes",
        @"/Library/MobileSubstrate/MobileSubstrate.dylib",
        @"/var/cache/apt",
        @"/var/lib/apt",
        @"/var/mobile/Documents/Cydia"
    ];

    for (NSString *jbPath in jailbreakPaths) {
        if ([path isEqualToString:jbPath]) {
            NBLog(@"[JB-BYPASS] Hid path: %@", path);
            return NO;
        }
    }
    return %orig;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (!isEnabled || !jbBypass) return %orig;

    NSArray *jailbreakPaths = @[
        @"/Applications/Cydia.app",
        @"/Library/MobileSubstrate",
        @"/var/lib/cydia"
    ];

    for (NSString *jbPath in jailbreakPaths) {
        if ([path isEqualToString:jbPath]) {
            NBLog(@"[JB-BYPASS] Hid directory: %@", path);
            if (isDirectory) *isDirectory = YES;
            return NO;
        }
    }
    return %orig;
}

%end

%hook UIApplication

- (BOOL)canOpenURL:(NSURL *)url {
    if (!isEnabled || !jbBypass) return %orig;

    if (url) {
        NSString *scheme = url.scheme;
        if ([scheme isEqualToString:@"cydia"] || 
            [scheme isEqualToString:@"sileo"] ||
            [scheme isEqualToString:@"zbra"]) {
            NBLog(@"[JB-BYPASS] Blocked canOpenURL for scheme: %@", scheme);
            return NO;
        }
    }
    return %orig;
}

%end

// ============================================
// 7. Network Request Interception & Spoofing
// ============================================

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (!isEnabled || !spoofHeaders) {
        %orig;
        return;
    }

    NSString *lowerField = [field lowercaseString];

    if ([lowerField isEqualToString:@"x-consumer-id"]) {
        NSString *fake = generateFakeDeviceID();
        NBLog(@"[SPOOF] Header x-consumer-id: %@ -> %@", value, fake);
        %orig(fake, field);
        return;
    }

    // ⚠️ حقول HMAC توقّع الطلب — تعديلها يكسر التحقق الخادمي وقد يسبب حضراً إضافياً
    // سجل فقط، لا تعديل
    if ([lowerField isEqualToString:@"x-hmac-msgpad"]) {
        NBLog(@"[INFO] Header x-hmac-msgpad: %@ (logged only — never modified)", value);
        %orig;
        return;
    }

    if ([lowerField isEqualToString:@"x-hmac-md"]) {
        NBLog(@"[INFO] Header x-hmac-md: %@ (logged only — never modified)", value);
        %orig;
        return;
    }

    if ([lowerField isEqualToString:@"x-adid"]) {
        NSString *fake = generateFakeADID();
        NBLog(@"[SPOOF] Header x-adid: %@ -> %@", value, fake);
        %orig(fake, field);
        return;
    }

    if ([lowerField isEqualToString:@"user-agent"]) {
        NBLog(@"[INFO] User-Agent: %@", value);
    }

    %orig;
}

%end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!isEnabled) return %orig;

    NSURL *url = request.URL;
    NBLog(@"[NETWORK] Request: %@ %@", request.HTTPMethod, url.absoluteString);

    NSDictionary *headers = request.allHTTPHeaderFields;
    for (NSString *key in headers) {
        NBLog(@"[NETWORK] Header %@: %@", key, headers[key]);
    }

    if (request.HTTPBody) {
        NSString *body = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
        if (body) {
            NBLog(@"[NETWORK] Body: %@", body);
        }
    }

    // وسّع التغليف لكل طلبات naver — رد الحظر قد يأتي من أي endpoint
    if ([url.absoluteString containsString:@"naver.com"] ||
        [url.absoluteString containsString:@"naver.net"]) {
        NBLog(@"[DETECT] Naver API request - Monitoring response: %@", url.absoluteString);

        void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse) {
                NBLog(@"[NETWORK] Response Status: %ld", (long)httpResponse.statusCode);
                NBLog(@"[NETWORK] Response Headers: %@", httpResponse.allHeaderFields);

                if (httpResponse.statusCode == 403 || httpResponse.statusCode == 401) {
                    NBLog(@"[ALERT] BLOCKED! Server returned %ld - Device ban confirmed server-side", (long)httpResponse.statusCode);
                }
            }

            if (data) {
                NSString *responseBody = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (responseBody) {
                    NBLog(@"[NETWORK] Response Body: %@", responseBody);

                    if ([responseBody containsString:@"안전조치"] || 
                        [responseBody containsString:@"차단"] ||
                        [responseBody containsString:@"보호"] ||
                        [responseBody containsString:@"safety"] ||
                        [responseBody containsString:@"block"]) {
                        NBLog(@"[ALERT] BAN MESSAGE DETECTED IN RESPONSE!");
                    }
                }
            }

            if (error) {
                NBLog(@"[NETWORK] Error: %@", error.localizedDescription);
            }

            // تحييد حقول الأمان في الرد قبل تسليمه للتطبيق
            // (التقرير يثبت: result.safetyMeasureUrl → طبقة العرض — شطب الحقل يقتل المسار)
            if (neutralizeResponses && data) {
                NSData *cleaned = neutralizeSafetyFields(data);
                if (cleaned != data) {
                    data = cleaned;
                    NBLog(@"[NEUTRALIZE] ✅ Response stripped of safety fields");
                }
            }

            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };

        return %orig(request, wrappedCompletion);
    }

    return %orig(request, completionHandler);
}

%end

// ============================================
// 8. WebView Monitoring
// ============================================

%hook WKWebView

- (void)loadRequest:(NSURLRequest *)request {
    if (isEnabled) {
        NBLog(@"[WEBVIEW] loadRequest: %@", request.URL.absoluteString);
    }
    %orig;
}

%end

// ============================================
// 9. AppsFlyer / Tracker ID Spoofing
// ============================================

%hook NSUUID

+ (instancetype)UUID {
    NSUUID *uuid = %orig;
    if (isEnabled) {
        NBLog(@"[SPOOF] NSUUID.UUID generated: %@", uuid.UUIDString);
    }
    return uuid;
}

%end

// ============================================
// 10. Process Info Spoofing
// ============================================

%hook NSProcessInfo

- (NSString *)operatingSystemVersionString {
    // لا تُنتحل: إنتحال 18.x على جهاز iOS 16 قد يفعّل مسارات غير موجودة → كراش
    return %orig;
}

%end

// ============================================
// 11. UIScreen Spoofing
// ============================================

%hook UIScreen

- (CGRect)bounds {
    CGRect orig = %orig;
    if (isEnabled) {
        NBLog(@"[SPOOF] Screen bounds: %@", NSStringFromCGRect(orig));
    }
    return orig;
}

- (CGFloat)scale {
    return %orig;  // iPhone 8 = @2x — لا تُنتحل
}

%end

// ============================================
// Response Neutralization — شطب حقول الأمان من JSON
// ============================================
static NSData *neutralizeSafetyFields(NSData *data) {
    if (!data || data.length == 0) return data;
    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (error || !json) return data;

    __block BOOL changed = NO;
    NSArray *badKeys = @[@"safetyMeasureUrl", @"stolenSuspicionUrl", @"suspicionUrl"];

    void (^strip)(id) = ^(id obj) {
        if ([obj isKindOfClass:[NSMutableDictionary class]]) {
            for (NSString *key in badKeys) {
                if (obj[key]) {
                    NBLog(@"[NEUTRALIZE] removing field: %@ = %@", key, obj[key]);
                    [obj removeObjectForKey:key];
                    changed = YES;
                }
            }
            for (id v in [obj allValues]) strip(v);
        } else if ([obj isKindOfClass:[NSMutableArray class]]) {
            for (id v in obj) strip(v);
        }
    };
    strip(json);

    if (!changed) return data;
    NSError *outErr = nil;
    NSData *result = [NSJSONSerialization dataWithJSONObject:json options:0 error:&outErr];
    return result ?: data;
}

// ============================================
// Presentation Layer — كشف "نقطة الحظر" وكبت النافذة
// ============================================
%hook UIViewController

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    if (isEnabled && viewControllerToPresent) {
        NSString *title = @"";
        NSString *message = @"";

        if ([viewControllerToPresent isKindOfClass:[UIAlertController class]]) {
            UIAlertController *alert = (UIAlertController *)viewControllerToPresent;
            title = alert.title ?: @"";
            message = alert.message ?: @"";
        }

        NBLog(@"[PRESENT] %@ | title=%@ | msg=%@",
              NSStringFromClass([viewControllerToPresent class]), title, message);
        NBLog(@"[PRESENT] presented by: %@", NSStringFromClass([self class]));

        NSString *combined = [NSString stringWithFormat:@"%@%@", title, message];
        if ([combined containsString:@"안전조치"] || [combined containsString:@"차단"] ||
            [combined containsString:@"도용"] || [combined containsString:@"고객센터"]) {
            NBLog(@"[BAN-POPUP] ⚠️ Ban popup detected! presenter=%@",
                  NSStringFromClass([self class]));
            NBLog(@"[BAN-POPUP] stack: %@", [[NSThread callStackSymbols] componentsJoinedByString:@" | "]);

            if (autoDismissPopup) {
                NBLog(@"[BAN-POPUP] auto-dismissing in 0.5s");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [viewControllerToPresent dismissViewControllerAnimated:YES completion:nil];
                    NBLog(@"[BAN-POPUP] ✅ popup dismissed");
                });
            }
        }
    }
    %orig;
}

%end

// ============================================
// 12. CONSTRUCTOR
// ============================================

%ctor {
    loadPrefs();

    // Watch for preference changes
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)loadPrefs,
        CFSTR("com.aosaid.naverseriesbypass/prefsChanged"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    NBLog(@"========================================");
    NBLog(@"NaverSeriesBypass v2.2 - ROOTLESS");
    NBLog(@"Target: com.nhncorp.NaverBooks");
    NBLog(@"iOS Support: 16.x - 18.x");
    NBLog(@"Status: %@", isEnabled ? @"ENABLED" : @"DISABLED");
    NBLog(@"Features: IDFV=%@ | Keychain=%@ | Headers=%@ | JB=%@ | Neutralize=%@ | AutoDismiss=%@",
          spoofIDFV ? @"ON" : @"OFF",
          blockKeychain ? @"ON" : @"OFF",
          spoofHeaders ? @"ON" : @"OFF",
          jbBypass ? @"ON" : @"OFF",
          neutralizeResponses ? @"ON" : @"OFF",
          autoDismissPopup ? @"ON" : @"OFF");
    NBLog(@"HMAC headers: LOG-ONLY (never modified)");
    NBLog(@"========================================");

    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    objc_getClassList(classes, numClasses);

    for (int i = 0; i < numClasses; i++) {
        NSString *className = NSStringFromClass(classes[i]);
        if ([className rangeOfString:@"Naver" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [className rangeOfString:@"Series" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [className rangeOfString:@"NHN" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NBLog(@"[DISCOVERY] Found Naver class: %@", className);
        }
    }

    free(classes);

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docsPath = @"/var/mobile/Documents";
    if (![fm fileExistsAtPath:docsPath]) {
        [fm createDirectoryAtPath:docsPath withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NBLog(@"[INIT] Diagnostics log: %@", LOG_FILE);
    NBLog(@"[INIT] Tweak loaded successfully");
}
