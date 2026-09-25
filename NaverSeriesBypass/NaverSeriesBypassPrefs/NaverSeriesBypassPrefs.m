#import <Preferences/Preferences.h>
#import <UIKit/UIKit.h>
#import <float.h>

#include <notify.h>
#include <sys/utsname.h>

static uint32_t gAlivePID = 0;

// Reads the packed heartbeat state the tweak publishes via notify_set_state.
static BOOL NBReadAliveState(uint32_t *outPid, NSTimeInterval *outTime) {
    int token = 0;
    if (notify_register_check("com.aosaid.nsb.alive", &token) != NOTIFY_STATUS_OK) return NO;
    uint64_t state = 0;
    if (notify_get_state(token, &state) != NOTIFY_STATUS_OK || state == 0) return NO;
    uint32_t tsec = (uint32_t)(state >> 32);
    uint32_t pid  = (uint32_t)(state & 0xffffffffu);
    if (tsec == 0) return NO;
    *outPid = pid;
    *outTime = (NSTimeInterval)tsec;
    return YES;
}

// Live stat counter mirrored by the tweak through notify state.
static NSInteger NBReadStat(NSString *key) {
    int token = 0;
    NSString *sname = [@"com.aosaid.nsb.stat." stringByAppendingString:key];
    if (notify_register_check(sname.UTF8String, &token) != NOTIFY_STATUS_OK) return 0;
    uint64_t v = 0;
    if (notify_get_state(token, &v) != NOTIFY_STATUS_OK) return 0;
    return (NSInteger)v;
}

// Process name resolved from the tweak's OWN filter plist — injection only
// happens where the filter says, so the name is known by construction.
static NSString *NBReadMirroredString(const char *slot) {
    NSMutableString *out = [NSMutableString string];
    for (int part = 0; part < 2; part++) {
        char name[64];
        snprintf(name, sizeof(name), "com.aosaid.nsb.meta.%s.%d", slot, part);
        int tok = 0;
        if (notify_register_check(name, &tok) != NOTIFY_STATUS_OK) break;
        uint64_t packed = 0;
        if (notify_get_state(tok, &packed) != NOTIFY_STATUS_OK || packed == 0) break;
        for (int i = 0; i < 8; i++) {
            unsigned char c = (unsigned char)((packed >> (8 * i)) & 0xff);
            if (c == 0) break;
            [out appendFormat:@"%c", c];
        }
    }
    return out;
}

// قراءة مفاتيح التحكم من cfprefsd — نفس قناة الإعدادات، طازجة دائمًا.
// قراءة الملف المباشرة قد ترجع قيمة قديمة أو nil فتُسقط في افتراض "مفعّل" = تضليل.
static BOOL NBToggle(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                     CFSTR("com.aosaid.naverseriesbypass"));
    if (!v) return YES;   // الافتراضي من Root.plist = مفعّل
    BOOL on = CFBooleanGetTypeID() == CFGetTypeID(v) ? CFBooleanGetValue((CFBooleanRef)v) : YES;
    CFRelease(v);
    return on;
}

static NSString *NBTargetProcessName(void) {
    static NSString *cached;
    if (cached) return cached;
    NSArray *paths = @[
        @"/Library/MobileSubstrate/DynamicLibraries/NaverSeriesBypass.plist",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/NaverSeriesBypass.plist"
    ];
    NSString *bid = nil;
    for (NSString *p in paths) {
        NSArray *bundles = [NSDictionary dictionaryWithContentsOfFile:p][@"Filter"][@"Bundles"];
        if (bundles.count) { bid = bundles.firstObject; break; }
    }
    NSString *name = nil;
    if (bid.length) {
        // Resolve the private API dynamically; current SDKs do not declare this selector.
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:bid];
        name = [proxy valueForKey:@"localizedName"];
    }
    cached = name.length ? name : (bid.length ? bid : @"الهدف");
    return cached;
}

// The REAL device values — read directly by the dashboard on the same device.
static NSString *NBRealMachine(void) {
    struct utsname u;
    uname(&u);
    return [NSString stringWithUTF8String:u.machine];
}

#define LOG_FILE @"/var/mobile/Documents/NaverBypass_Diagnostics.log"
#define PREFS_PATH @"/var/mobile/Library/Preferences/com.aosaid.naverseriesbypass.plist"
#define STATS_PATH @"/var/mobile/Library/Preferences/com.aosaid.naverseriesbypass.stats.plist"

static UIWindow *NBActiveWindow(void) {
    UIApplication *application = [UIApplication sharedApplication];
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) return window;
        }
    }
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.windows.firstObject) return windowScene.windows.firstObject;
    }
    return nil;
}

// LIVE SIGNAL receiver: stamps every incoming heartbeat from the tweak.
static NSTimeInterval gLastAliveSignal = 0;
static void NBAliveCallback(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    gLastAliveSignal = [[NSDate date] timeIntervalSince1970];
}

@interface NaverSeriesBypassPrefsListController : PSListController
@property(nonatomic, strong) NSTimer *dashboardTimer;
@end

@implementation NaverSeriesBypassPrefsListController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationBecameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NBAliveCallback,
        CFSTR("com.aosaid.nsb.alive"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)applicationBecameActive:(NSNotification *)notification {
    (void)notification;
    [self refreshDashboard];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.dashboardTimer invalidate];
    self.dashboardTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CFSTR("com.aosaid.nsb.alive"), NULL);
}

- (void)dealloc {
    [self.dashboardTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)openDashboard {
    UIWindow *window = NBActiveWindow();
    if (!window) return;

    // Remove existing overlay if any
    UIView *existing = [window viewWithTag:99999];
    if (existing) [existing removeFromSuperview];

    // Create overlay
    CGFloat w = window.bounds.size.width;
    CGFloat h = window.bounds.size.height;

    UIView *overlay = [[UIView alloc] initWithFrame:window.bounds];
    overlay.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.06 alpha:1.0];
    overlay.tag = 99999;
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // Close button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w - 70, 50, 60, 36);
    [closeBtn setTitle:@"اغلاق" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeDashboard) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:closeBtn];

    CGFloat y = 100;
    CGFloat m = 16;

    // === Status ===
    UIView *sCard = [self cardAt:CGRectMake(m, y, w - m*2, 70) parent:overlay];
    [self titleLabel:@"حالة التطبيق" parent:sCard];
    UILabel *status = [self valueLabel:@"في الانتظار..." color:[UIColor grayColor] parent:sCard y:34];
    status.tag = 10001;
    y += 86;

    // === Stats ===
    UIView *stCard = [self cardAt:CGRectMake(m, y, w - m*2, 130) parent:overlay];
    [self titleLabel:@"الاحصائيات" parent:stCard];
    UILabel *stats = [self valueLabel:@"افتح Naver Series واضغط على فصل" color:[UIColor lightGrayColor] parent:stCard y:34];
    stats.numberOfLines = 0;
    stats.tag = 10002;
    y += 146;

    // === Logs ===
    UIView *lCard = [self cardAt:CGRectMake(m, y, w - m*2, h - y - 30) parent:overlay];
    [self titleLabel:@"سجل الاحداث" parent:lCard];

    UITextView *logView = [[UITextView alloc] initWithFrame:CGRectMake(m, 34, lCard.frame.size.width - m*2, lCard.frame.size.height - 80)];
    logView.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.03 alpha:1.0];
    logView.textColor = [UIColor colorWithRed:0.4 green:0.8 blue:0.4 alpha:1.0];
    logView.font = [UIFont fontWithName:@"Courier" size:9];
    logView.editable = NO;
    logView.scrollEnabled = YES;
    logView.alwaysBounceVertical = YES;
    logView.showsVerticalScrollIndicator = YES;
    logView.textAlignment = NSTextAlignmentRight;
    logView.tag = 10003;
    logView.text = @"لا يوجد سجل بعد...";
    [lCard addSubview:logView];

    UIButton *cpy = [UIButton buttonWithType:UIButtonTypeSystem];
    cpy.frame = CGRectMake(lCard.frame.size.width - m - 60, lCard.frame.size.height - 36, 55, 26);
    [cpy setTitle:@"نسخ" forState:UIControlStateNormal];
    cpy.titleLabel.font = [UIFont systemFontOfSize:11];
    [cpy setTitleColor:[UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    [cpy addTarget:self action:@selector(copyLogs) forControlEvents:UIControlEventTouchUpInside];
    [lCard addSubview:cpy];

    UIButton *clr = [UIButton buttonWithType:UIButtonTypeSystem];
    clr.frame = CGRectMake(m, lCard.frame.size.height - 36, 55, 26);
    [clr setTitle:@"مسح" forState:UIControlStateNormal];
    clr.titleLabel.font = [UIFont systemFontOfSize:11];
    [clr setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [clr addTarget:self action:@selector(clearLogs) forControlEvents:UIControlEventTouchUpInside];
    [lCard addSubview:clr];

    [window addSubview:overlay];

    // Start refresh
    [self refreshDashboard];
    [self.dashboardTimer invalidate];
    self.dashboardTimer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(refreshDashboard) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.dashboardTimer forMode:NSRunLoopCommonModes];
}

- (void)closeDashboard {
    UIWindow *window = NBActiveWindow();
    UIView *overlay = [window viewWithTag:99999];
    if (overlay) {
        [UIView animateWithDuration:0.2 animations:^{
            overlay.alpha = 0;
        } completion:^(BOOL finished) {
            [overlay removeFromSuperview];
        }];
    }
}

- (UIView *)cardAt:(CGRect)frame parent:(UIView *)parent {
    UIView *v = [[UIView alloc] initWithFrame:frame];
    v.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:1.0];
    v.layer.cornerRadius = 10;
    [parent addSubview:v];
    return v;
}

- (void)titleLabel:(NSString *)text parent:(UIView *)p {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, p.frame.size.width - 32, 18)];
    l.text = text;
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0];
    l.textAlignment = NSTextAlignmentRight;
    [p addSubview:l];
}

- (UILabel *)valueLabel:(NSString *)text color:(UIColor *)c parent:(UIView *)p y:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y, p.frame.size.width - 32, 22)];
    l.text = text;
    l.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    l.textColor = c;
    l.textAlignment = NSTextAlignmentRight;
    [p addSubview:l];
    return l;
}

- (void)refreshDashboard {
    @try {
        UIWindow *window = NBActiveWindow();
        UIView *overlay = [window viewWithTag:99999];
        if (!overlay) return;

        UILabel *status = (UILabel *)[overlay viewWithTag:10001];
        UILabel *stats = (UILabel *)[overlay viewWithTag:10002];
        UITextView *logView = (UITextView *)[overlay viewWithTag:10003];

        NSString *log = [self readLog];
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
        NSDictionary *savedStats = [NSDictionary dictionaryWithContentsOfFile:STATS_PATH];
        BOOL enabled = NBToggle(@"Enabled");   // طازج من cfprefsd — لا افتراض مضلل

        // Read heartbeat payload via notify_set_state — the ONLY channel that
        // survives sandboxing (cfprefsd drops foreign-domain plist writes from
        // sandboxed apps). Packed: [timestamp(32) | pid(32)].
        BOOL isInjected = NO;
        NSString *injectedProcess = @"غير معروف";
        NSTimeInterval heartbeatTimestamp = 0;

        uint32_t alivePid = 0;
        NSTimeInterval aliveTime = 0;
        if (NBReadAliveState(&alivePid, &aliveTime)) {
            NSTimeInterval stateAge = [[NSDate date] timeIntervalSince1970] - aliveTime;
            if (stateAge < 15.0) {
                isInjected = YES;
                heartbeatTimestamp = aliveTime;
                gAlivePID = alivePid;
                injectedProcess = NBTargetProcessName();
            }
        }

        // Merge live counters mirrored through notify state (sandbox-proof).
        NSMutableDictionary *mergedStats = savedStats ? [savedStats mutableCopy] : [NSMutableDictionary dictionary];
        for (NSString *key in @[@"uname", @"sysctl", @"idfa", @"tracking", @"idfv", @"model",
                                @"systemVersion", @"deviceName", @"localizedModel", @"systemName",
                                @"idiom", @"osVersionString", @"osVersion", @"processorCount",
                                @"activeProcessorCount", @"physicalMemory", @"screenBounds", @"screenScale",
                                @"nativeScale", @"nativeBounds", @"header_device", @"header_adid", @"header_ua",
                                @"header_model", @"header_os", @"dataTask", @"keychain_add_blocked",
                                @"keychain_update_blocked", @"keychain_copy_blocked", @"loaded", @"processBundle"]) {
            NSInteger live = NBReadStat(key);
            if (live > 0) {
                NSNumber *cur = mergedStats[key] ?: @0;
                if (live > [cur integerValue]) mergedStats[key] = @(live);
            }
        }
        savedStats = mergedStats;
        BOOL hasInjectionMarker = savedStats[@"loaded"] != nil || savedStats[@"processBundle"] != nil;
        // LIVE Darwin signal: if the tweak posted within the last 15s, it IS
        // injected and running right now - regardless of any file/plist state.
        NSTimeInterval aliveAge = [[NSDate date] timeIntervalSince1970] - gLastAliveSignal;
        BOOL liveSignal = (gLastAliveSignal > 0.0 && aliveAge < 15.0);
        // REAL injection status: heartbeat file OR live Darwin signal
        BOOL live = isInjected || liveSignal;
        BOOL launchRecentlyStopped = !isInjected && heartbeatTimestamp > 0;

        BOOL blocked = [log containsString:@"BLOCKED"] || [log containsString:@"BAN"];
        if (!enabled) {
            status.text = @"معطّل — أوقفته من المفتاح";
            status.textColor = [UIColor colorWithRed:0.9 green:0.35 blue:0.25 alpha:1.0];
        } else if (blocked) {
            status.text = @"مفعّل — حظر مكتشف من الخادم";
            status.text = @"تنبيه: رصد الخادم محاولة حظر";
        } else if (live) {
            status.text = @"مفعّل — Naver Series مفتوح والتويك يعمل الآن";
            status.text = [NSString stringWithFormat:@"محقن في: %@ (PID: %u) — التويك يعمل", injectedProcess, gAlivePID];
        } else if (!hasInjectionMarker) {
            status.text = @"غير محقن — لم تصل بصمة من Naver Series";
            status.text = @"❌ غير محقن — افتح Naver Series أولاً";
        } else if (launchRecentlyStopped) {
            status.text = @"فشل/انقطع — توقف heartbeat بعد فتح Naver Series";
            status.text = [NSString stringWithFormat:@"آخر نشاط قبل %.0f ثانية — أعد فتح Naver Series", [[NSDate date] timeIntervalSince1970] - heartbeatTimestamp];
        } else {
            status.text = @"مفعّل — بانتظار فتح Naver Series";
            status.text = @"بانتظار فتح Naver Series";
        }

        // Use persistent counters written by the tweak; fall back to old logs once.
        NSArray *lines = log.length ? [log componentsSeparatedByString:@"\n"] : @[];
        // مفاتيح حقيقية فقط — لا أصفار وهمية (الـ Tweak يكتب هذه المفاتيح فعليًا)
        NSInteger req = [savedStats[@"dataTask"] integerValue];
        NSInteger blk = [savedStats[@"keychain_add_blocked"] integerValue] +
                        [savedStats[@"keychain_update_blocked"] integerValue] +
                        [savedStats[@"keychain_copy_blocked"] integerValue];
        NSInteger spf = [savedStats[@"uname"] integerValue] + [savedStats[@"sysctl"] integerValue] +
                        [savedStats[@"model"] integerValue] + [savedStats[@"systemVersion"] integerValue] +
                        [savedStats[@"idfa"] integerValue] + [savedStats[@"idfv"] integerValue] +
                        [savedStats[@"header_ua"] integerValue] + [savedStats[@"header_device"] integerValue];
        NSInteger jb = [savedStats[@"uname"] integerValue] + [savedStats[@"sysctl"] integerValue];
        NSInteger neutralized = [savedStats[@"neutralized"] integerValue];
        NSInteger popups = [savedStats[@"popups"] integerValue];

        // Device Ban stats
        NSInteger deviceSpoofs = [savedStats[@"deviceName"] integerValue] + [savedStats[@"model"] integerValue] + 
                                  [savedStats[@"systemVersion"] integerValue] + [savedStats[@"uname"] integerValue];
        NSInteger idfvSpoofs = [savedStats[@"idfv"] integerValue];
        NSInteger idfaSpoofs = [savedStats[@"idfa"] integerValue];
        NSInteger keychainBlocked = [savedStats[@"keychain_add_blocked"] integerValue] + 
                                     [savedStats[@"keychain_update_blocked"] integerValue] +
                                     [savedStats[@"keychain_copy_blocked"] integerValue];
        NSInteger headerSpoofs = [savedStats[@"header_ua"] integerValue] + [savedStats[@"header_device"] integerValue];

        if (!savedStats.count) {
            for (NSString *ln in lines) {
                if ([ln containsString:@"[NETWORK] Request"]) req++;
                if ([ln containsString:@"[ALERT]"]) blk++;
                if ([ln containsString:@"[SPOOF]"]) spf++;
                if ([ln containsString:@"[JB-BYPASS]"]) jb++;
            }
        }
        BOOL hasActivity = req || blk || spf || jb || neutralized || popups || deviceSpoofs || idfvSpoofs || idfaSpoofs;
        NSString *lastEvent = savedStats[@"lastEvent"] ?: @"لا يوجد حدث بعد";
        NSString *process = savedStats[@"processBundle"] ?: @"لم تُسجل عملية الهدف";
        stats.text = [NSString stringWithFormat:
            @"الطلبات: %ld | الحظر: %ld | التعديل: %ld\n"
            @"Device: %ld | IDFV: %ld | IDFA: %ld\n"
            @"Keychain: %ld | Headers: %ld | JB: %ld\n"
            @"%@\nالعملية: %@\nآخر حدث: %@",
            (long)req, (long)blk, (long)spf,
            (long)deviceSpoofs, (long)idfvSpoofs, (long)idfaSpoofs,
            (long)keychainBlocked, (long)headerSpoofs, (long)jb,
            hasActivity ? @"يوجد نشاط مسجل — التويك يعمل" : @"لا يوجد نشاط — افتح Naver Series أولًا",
            process, lastEvent];

        // الخام والدقيق: الجهاز الفعلي مقابل ما يواجهه التطبيق فعليًا
        stats.text = [stats.text stringByAppendingFormat:@"\nالجهاز الحقيقي: %@ · iOS %@\nيواجهه التطبيق: قيم مموّهة (uname/sysctl/IDFA/Keychain)",
                       NBRealMachine(), [UIDevice currentDevice].systemVersion];

        // Logs: preserve the statistical header and all available ring events.
        logView.text = log;
        if (logView.text.length > 0) {
            [logView scrollRangeToVisible:NSMakeRange(logView.text.length - 1, 1)];
        }
    }
    @catch (NSException *e) {
        NSLog(@"[NaverBypass] Dashboard refresh error: %@", e.reason);
    }
}

- (NSString *)readLog {
    // سجل الأحداث الحقيقي: حلقة notify_set_state (32 خانة) — القناة الوحيدة
    // التي تعبر sandbox التطبيق. كل حدث = [timestamp:32|code:16|detail:16].
    int countTok = 0;
    if (notify_register_check("com.aosaid.nsb.log.count", &countTok) != NOTIFY_STATUS_OK)
        return @"السجل غير متاح";
    uint64_t count = 0;
    if (notify_get_state(countTok, &count) != NOTIFY_STATUS_OK || count == 0)
        return @"لا توجد أحداث بعد — افتح Naver Series";

    NSDictionary *names = @{
        @1:@"uname مموّه", @2:@"sysctl مموّه", @3:@"IDFA مموّه", @4:@"Tracking معطّل",
        @5:@"IDFV مموّه", @6:@"Model مموّه", @7:@"systemVersion مموّه", @8:@"deviceName مموّه",
        @9:@"localizedModel", @10:@"systemName", @11:@"idiom", @12:@"osVersionString",
        @13:@"osVersion", @14:@"processorCount", @15:@"activeProcessorCount", @16:@"physicalMemory",
        @17:@"screenBounds", @18:@"screenScale", @19:@"nativeScale", @20:@"nativeBounds",
        @21:@"header Device معدّل", @22:@"header ADID معدّل", @23:@"header UA معدّل",
        @24:@"header Model معدّل", @25:@"header OS معدّل", @26:@"طلب شبكة مراقب",
        @27:@"Keychain Add محظور", @28:@"Keychain Update محظور", @29:@"Keychain Copy محظور",
        @30:@"تنظيف Keychain", @31:@"تفضيلات محدّثة", @32:@"إقلاع التويك"
    };
    static NSDateFormatter *df = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm:ss";
    });

    NSMutableArray *lines = [NSMutableArray array];
    uint64_t oldest = count > 32 ? count - 31 : 1;
    for (uint64_t n = count; n >= oldest; n--) {
        char nm[64];
        snprintf(nm, sizeof(nm), "com.aosaid.nsb.log.%llu", (unsigned long long)(n % 32));
        int tok = 0;
        if (notify_register_check(nm, &tok) != NOTIFY_STATUS_OK) continue;
        uint64_t ev = 0;
        if (notify_get_state(tok, &ev) != NOTIFY_STATUS_OK || ev == 0) continue;
        uint32_t tsec = (uint32_t)(ev >> 32);
        uint16_t code = (uint16_t)((ev >> 16) & 0xffff);
        NSString *label = names[@(code)] ?: [NSString stringWithFormat:@"حدث %u", code];
        [lines addObject:[NSString stringWithFormat:@"%@ — %@",
                          [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:tsec]], label]];
        if (n == 1) break;   // حارس uint64
    }

    // ═══ الترويسة الصادقة: كل سطر مشروط بمفتاحه الحقيقي من الإعدادات ═══
    NSString *spoofModel = NBReadMirroredString("model");
    NSString *spoofOS = NBReadMirroredString("os");
    NSInteger unameN = NBReadStat(@"uname"), sysctlN = NBReadStat(@"sysctl");
    NSInteger kcN = NBReadStat(@"keychain_add_blocked") + NBReadStat(@"keychain_update_blocked") + NBReadStat(@"keychain_copy_blocked");
    BOOL tDevice = NBToggle(@"SpoofDevice"), tIDFV = NBToggle(@"SpoofIDFV"),
         tIDFA = NBToggle(@"SpoofIDFA"), tHeaders = NBToggle(@"SpoofHeaders"),
         tKeychain = NBToggle(@"BlockKeychain"), tJB = NBToggle(@"JBBypass"),
         tEnabled = NBToggle(@"Enabled");
    // "مخفي" فقط إذا: التويك مفعّل + تجاوز JB مفعّل + حدث تمويه فعلي
    BOOL jbHidden = (tEnabled && tJB && (unameN > 0 || sysctlN > 0));

    NSMutableArray *full = [NSMutableArray array];
    [full addObject:@"═══ الحماية ═══"];
    [full addObject:[NSString stringWithFormat:@"حالة التويك: %@",
                      tEnabled ? @"مفعّل" : @"معطّل — من مفتاح الإعدادات"]];
    [full addObject:@"═══ هوية الجهاز ═══"];
    [full addObject:[NSString stringWithFormat:@"الجهاز الحقيقي: %@ — iOS %@",
                      NBRealMachine(), [UIDevice currentDevice].systemVersion]];
    [full addObject:[NSString stringWithFormat:@"يقرأه التطبيق: %@ — iOS %@",
                      (tEnabled && tDevice && spoofModel.length) ? spoofModel : @"الحقيقي (بلا تمويه)",
                      (tEnabled && tDevice && spoofOS.length) ? spoofOS : @"الإصدار الحقيقي"]];
    [full addObject:[NSString stringWithFormat:@"كشف الجلبريك: %@",
                      jbHidden ? @"متجاوَز — uname/sysctl مموّهان فعليًا" :
                      (!tEnabled ? @"غير متجاوَز — التويك معطّل" :
                       (!tJB ? @"غير متجاوَز — التجاوز معطّل من الإعدادات" :
                        @"بلا تمويه بعد"))]];
    [full addObject:@"═══ المفاتيح (حالتها من إعداداتك الآن) ═══"];
    [full addObject:[NSString stringWithFormat:@"تغيير الجهاز: %@ | IDFV: %@ | IDFA: %@ | Headers: %@ | Keychain: %@ | تجاوز JB: %@",
                      tDevice ? @"مفعّل" : @"معطّل", tIDFV ? @"مفعّل" : @"معطّل",
                      tIDFA ? @"مفعّل" : @"معطّل", tHeaders ? @"مفعّل" : @"معطّل",
                      tKeychain ? @"مفعّل" : @"معطّل", tJB ? @"مفعّل" : @"معطّل"]];
    [full addObject:[NSString stringWithFormat:@"نشاط تراكمي: uname: %ld | sysctl: %ld | Keychain محظور: %ld | Headers معدّلة: %ld | شبكة: %ld",
                      (long)unameN, (long)sysctlN, (long)kcN,
                      (long)(NBReadStat(@"header_ua") + NBReadStat(@"header_device") + NBReadStat(@"header_adid") + NBReadStat(@"header_model") + NBReadStat(@"header_os")),
                      (long)NBReadStat(@"dataTask")]];
    [full addObject:@"═══ الأحداث (الأحدث أولًا) ═══"];
    [full addObjectsFromArray:lines];
    return [full componentsJoinedByString:@"\n"];
}

- (void)copyLogs {
    @try {
        NSString *s = [self readLog];
        if (s.length > 0) {
            UIPasteboard.generalPasteboard.string = s;
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"تم" message:@"تم النسخ" preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"حسنا" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        }
    }
    @catch (NSException *e) {
        NSLog(@"[NaverBypass] Copy error: %@", e.reason);
    }
}

- (void)clearLogs {
    @try {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"تأكيد" message:@"مسح السجل؟" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"الغاء" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"مسح" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
            [[NSFileManager defaultManager] removeItemAtPath:LOG_FILE error:nil];
            int countTok = 0;
            if (notify_register_check("com.aosaid.nsb.log.count", &countTok) == NOTIFY_STATUS_OK) {
                notify_set_state(countTok, 0);
                for (NSUInteger i = 0; i < 32; i++) {
                    char name[64];
                    snprintf(name, sizeof(name), "com.aosaid.nsb.log.%lu", (unsigned long)i);
                    int slotTok = 0;
                    if (notify_register_check(name, &slotTok) == NOTIFY_STATUS_OK)
                        notify_set_state(slotTok, 0);
                }
            }
            [self refreshDashboard];
        }]];
        [self presentViewController:a animated:YES completion:nil];
    }
    @catch (NSException *e) {
        NSLog(@"[NaverBypass] Clear error: %@", e.reason);
    }
}

@end
