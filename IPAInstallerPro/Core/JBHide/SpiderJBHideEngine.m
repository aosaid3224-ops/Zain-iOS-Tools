//
//  SpiderJBHideEngine.m
//

#import "SpiderJBHideEngine.h"
#import "SpiderJBHideStateStore.h"
#import "../RootlessManager.h"
#import "../OperationLog.h"
#import "../ProcessRunner.h"
#import "../CommandResult.h"
#import "../RuntimeDiagnostics.h"
#import <UIKit/UIKit.h>

static NSString *const kDylibBaseName = @"libspiderjbhide";

@implementation SpiderJBHideResult
+ (instancetype)resultWithSuccess:(BOOL)success status:(SpiderJBHideStatus)status error:(NSString *)error report:(NSString *)report {
    SpiderJBHideResult *r = [self new];
    r.success = success; r.status = status; r.errorMessage = error; r.detailReport = report;
    r.completedAt = [NSDate date];
    return r;
}
@end

@implementation SpiderJBHideEngine

+ (instancetype)sharedEngine {
    static SpiderJBHideEngine *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

#pragma mark - Paths

- (NSArray<NSString *> *)tweakInjectDirectories {
    static NSArray<NSString *> *dirs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        RootlessManager *rm = [RootlessManager sharedManager];
        NSMutableArray *candidates = [NSMutableArray array];
        for (NSString *logical in @[ @"/usr/lib/TweakInject",
                                     @"/Library/MobileSubstrate/DynamicLibraries" ]) {
            NSString *resolved = [rm resolvePath:logical];
            BOOL isDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:resolved isDirectory:&isDir] && isDir) {
                [candidates addObject:resolved];
            }
        }
        dirs = [candidates copy];
    });
    return dirs;
}

- (NSString *)helperPath {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        RootlessManager *rm = [RootlessManager sharedManager];
        path = [rm resolvePath:@"/usr/bin/ipainstallerpro_helper"];
    });
    return path;
}

+ (NSString *)markerDirectoryPath { return @"/var/mobile/Library/SpiderJB"; }

- (BOOL)isMechanismAvailableWithReason:(NSString **)reason {
    if (self.tweakInjectDirectories.count == 0) {
        if (reason) *reason = @"لم يتم العثور على مجلد TweakInject في بيئة الجلبريك الحالية.";
        return NO;
    }
    NSString *bundled = [[NSBundle mainBundle] pathForResource:kDylibBaseName ofType:@"dylib"];
    if (!bundled.length) {
        if (reason) *reason = @"مكتبة الإخفاء غير موجودة داخل حزمة Spider.";
        return NO;
    }
    return YES;
}

#pragma mark - Names

- (NSString *)safeNameForBundleID:(NSString *)bundleID {
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < bundleID.length; i++) {
        unichar c = [bundleID characterAtIndex:i];
        [s appendFormat:@"%C", (isalnum(c) || c == '_') ? c : (unichar)'_'];
    }
    return [NSString stringWithFormat:@"SpiderJBHide_%@", s];
}

- (NSString *)dylibPathForBundleID:(NSString *)bundleID inDirectory:(NSString *)dir {
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.dylib", [self safeNameForBundleID:bundleID]]];
}

- (NSString *)filterPlistPathForBundleID:(NSString *)bundleID inDirectory:(NSString *)dir {
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", [self safeNameForBundleID:bundleID]]];
}

#pragma mark - Apply

- (void)applyHidingForBundleID:(NSString *)bundleID completion:(void (^)(SpiderJBHideResult *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        SpiderJBHideResult *result = [self applyHidingForBundleIDSync:bundleID];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
    });
}

- (SpiderJBHideResult *)applyHidingForBundleIDSync:(NSString *)bundleID {
    NSString *reason = nil;
    if (![self isMechanismAvailableWithReason:&reason]) {
        [[SpiderJBHideStateStore sharedStore] updateStatus:SpiderJBHideStatusConfigured
                                                     error:reason forBundleID:bundleID];
        return [SpiderJBHideResult resultWithSuccess:NO status:SpiderJBHideStatusConfigured
                                              error:reason report:nil];
    }

    NSString *dir = self.tweakInjectDirectories.firstObject;
    NSString *dylibDest = [self dylibPathForBundleID:bundleID inDirectory:dir];
    NSString *plistDest = [self filterPlistPathForBundleID:bundleID inDirectory:dir];
    NSString *bundledDylib = [[NSBundle mainBundle] pathForResource:kDylibBaseName ofType:@"dylib"];

    // Stage files in a temp dir then promote via the root helper (TweakInject
    // is root-owned on rootless bootstraps).
    NSString *stage = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:stage withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *stageDylib = [stage stringByAppendingPathComponent:dylibDest.lastPathComponent];
    NSString *stagePlist = [stage stringByAppendingPathComponent:plistDest.lastPathComponent];

    NSError *err = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:bundledDylib toPath:stageDylib error:&err]) {
        return [self failApply:bundleID error:[NSString stringWithFormat:@"فشل تجهيز المكتبة: %@", err.localizedDescription]];
    }
    NSDictionary *filter = @{ @"Filter": @{ @"Bundles": @[bundleID] } };
    if (![filter writeToFile:stagePlist atomically:YES]) {
        return [self failApply:bundleID error:@"فشل إنشاء ملف الترشيح (plist)."];
    }
    [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0755 }
                                     ofItemAtPath:stageDylib error:nil];
    [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0644 }
                                     ofItemAtPath:stagePlist error:nil];

    NSString *helper = [self helperPath];
    for (NSString *pair in @[ @[stageDylib, dylibDest], @[stagePlist, plistDest] ]) {
        CommandResult *pr = [[ProcessRunner sharedRunner] runCommand:helper arguments:@[@"--copy-tree", pair[0], pair[1]] timeout:10];
        if (pr.exitCode != 0) {
            return [self failApply:bundleID error:[NSString stringWithFormat:@"فشل النسخ إلى TweakInject (exit %d). %@", pr.exitCode, pr.stderrText ?: @""]];
        }
    }
    [[NSFileManager defaultManager] removeItemAtPath:stage error:nil];

    // Static verification
    SpiderJBHideResult *st = [self staticStatusForBundleID:bundleID];
    if (!st.success) {
        [[SpiderJBHideStateStore sharedStore] updateStatus:SpiderJBHideStatusConfigured
                                                     error:st.errorMessage forBundleID:bundleID];
        return st;
    }

    [[SpiderJBHideStateStore sharedStore] updateStatus:SpiderJBHideStatusApplied error:nil forBundleID:bundleID];

    // Runtime verification: kill + relaunch + marker file + process liveness.
    return [self verifyHidingForBundleID:bundleID];
}

- (SpiderJBHideResult *)failApply:(NSString *)bundleID error:(NSString *)error {
    [[SpiderJBHideStateStore sharedStore] updateStatus:SpiderJBHideStatusConfigured
                                                 error:error forBundleID:bundleID];
    return [SpiderJBHideResult resultWithSuccess:NO status:SpiderJBHideStatusConfigured
                                          error:error report:nil];
}

#pragma mark - Verify (runtime)

- (SpiderJBHideResult *)verifyHidingForBundleID:(NSString *)bundleID {
    // Clear stale marker
    NSString *marker = [[[self class] markerDirectoryPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.load.plist", bundleID]];
    [[NSFileManager defaultManager] removeItemAtPath:marker error:nil];

    [self killAppWithBundleID:bundleID];

    NSDate *probeStart = [NSDate date];
    __block BOOL launched = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        launched = [self launchAppWithBundleID:bundleID];
        dispatch_semaphore_signal(sem);
    });
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

    if (!launched) {
        NSString *msg = @"تعذّر طلب إطلاق التطبيق. إذا كان التطبيق مخفيًا في مكتبة التطبيقات فأعد ترتيبه.";
        [[SpiderJBHideStateStore sharedStore] updateStatus:SpiderJBHideStatusApplied error:msg forBundleID:bundleID];
        return [SpiderJBHideResult resultWithSuccess:NO status:SpiderJBHideStatusApplied error:msg report:nil];
    }

    // Poll marker (written by the injected dylib inside the target process).
    BOOL markerOK = NO;
    for (int i = 0; i < 20; i++) {
        [NSThread sleepForTimeInterval:0.5];
        NSDictionary *m = [NSDictionary dictionaryWithContentsOfFile:marker];
        NSDate *ts = m[@"timestamp"];
        if (ts && [ts compare:probeStart] != NSOrderedAscending) { markerOK = YES; break; }
        if (m && !ts) { markerOK = YES; break; }
    }

    if (!markerOK) {
        NSString *msg = @"المكتبة لم تُحمَّل داخل التطبيق. السبب الأكثر شيوعًا: تعطيل «Tweak Injection» لهذا التطبيق من إعدادات Dopamine، أو أن نوع الكشف يتجاوز آلية الإخفاء المتاحة.";
        [[SpiderJBHideStateStore sharedStore] updateStatus:SpiderJBHideStatusApplied error:msg forBundleID:bundleID];
        return [SpiderJBHideResult resultWithSuccess:NO status:SpiderJBHideStatusApplied error:msg report:nil];
    }

    [[SpiderJBHideStateStore sharedStore] markVerifiedForBundleID:bundleID];
    NSString *report = [NSString stringWithFormat:@"تم تفعيل إخفاء الجلبريك وإثبات تحميل الآلية داخل العملية (%@).", bundleID];
    return [SpiderJBHideResult resultWithSuccess:YES status:SpiderJBHideStatusVerified
                                          error:nil report:report];
}

#pragma mark - Remove

- (void)removeHidingForBundleID:(NSString *)bundleID completion:(void (^)(SpiderJBHideResult *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *dir = self.tweakInjectDirectories.firstObject;
        NSString *helper = self.helperPath;
        for (NSString *p in @[ [self dylibPathForBundleID:bundleID inDirectory:dir],
                               [self filterPlistPathForBundleID:bundleID inDirectory:dir] ]) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                [[ProcessRunner sharedRunner] runCommand:helper arguments:@[@"/bin/rm", @"-f", p] timeout:10];
            }
        }
        [self killAppWithBundleID:bundleID];
        [[SpiderJBHideStateStore sharedStore] setEnabled:NO forBundleID:bundleID];
        SpiderJBHideResult *r = [SpiderJBHideResult resultWithSuccess:YES status:SpiderJBHideStatusOff
                                                               error:nil report:@"تمت إزالة آلية الإخفاء."];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(r); });
    });
}

#pragma mark - Static status

- (SpiderJBHideResult *)staticStatusForBundleID:(NSString *)bundleID {
    NSString *dir = self.tweakInjectDirectories.firstObject;
    NSString *dylib = [self dylibPathForBundleID:bundleID inDirectory:dir];
    NSString *plist = [self filterPlistPathForBundleID:bundleID inDirectory:dir];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dylib]) {
        return [SpiderJBHideResult resultWithSuccess:NO status:SpiderJBHideStatusConfigured
                                            error:@"ملف المكتبة غير موجود في TweakInject." report:nil];
    }
    NSDictionary *filter = [NSDictionary dictionaryWithContentsOfFile:plist];
    NSArray *bundles = filter[@"Filter"][@"Bundles"];
    if (![bundles containsObject:bundleID]) {
        return [SpiderJBHideResult resultWithSuccess:NO status:SpiderJBHideStatusConfigured
                                            error:@"ملف الترشيح مفقود أو لا يطابق معرّف الحزمة." report:nil];
    }
    NSString *bundled = [[NSBundle mainBundle] pathForResource:kDylibBaseName ofType:@"dylib"];
    NSDictionary *a = [fm attributesOfItemAtPath:dylib error:nil];
    NSDictionary *b = [fm attributesOfItemAtPath:bundled error:nil];
    if (!a || !b || ![a[NSFileSize] isEqual:b[NSFileSize]]) {
        return [SpiderJBHideResult resultWithSuccess:NO status:SpiderJBHideStatusConfigured
                                            error:@"حجم مكتبة الإخفاء لا يطابق النسخة المُوزَّعة مع Spider." report:nil];
    }
    return [SpiderJBHideResult resultWithSuccess:YES status:SpiderJBHideStatusApplied error:nil report:nil];
}

#pragma mark - Process control (mirrors ApplicationManager patterns)

- (BOOL)launchAppWithBundleID:(NSString *)bundleID {
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!wsClass) return NO;
    id workspace = [wsClass performSelector:@selector(defaultWorkspace)];
    if (!workspace) return NO;
    if ([workspace respondsToSelector:@selector(openApplicationWithBundleID:)]) {
        BOOL ok = (BOOL)(intptr_t)[workspace performSelector:@selector(openApplicationWithBundleID:) withObject:bundleID];
        return ok;
    }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", [bundleID componentsSeparatedByString:@"."].lastObject.lowercaseString]];
    if (url) {
        id app = [UIApplication sharedApplication];
        if ([app respondsToSelector:@selector(canOpenURL:)] && [app canOpenURL:url]) {
            [app performSelector:@selector(openURL:options:completionHandler:) withObject:url withObject:@{} withObject:nil];
            return YES;
        }
    }
    return NO;
}

- (void)killAppWithBundleID:(NSString *)bundleID {
    Class fbsClass = NSClassFromString(@"FBSSystemService");
    if (!fbsClass) return;
    id service = [fbsClass performSelector:@selector(sharedService)];
    if (!service) return;
    NSNumber *pid = nil;
    CommandResult *ps = [[ProcessRunner sharedRunner] runCommand:@"/usr/bin/pgrep" arguments:@[@"-f", bundleID] timeout:5];
    if (ps.exitCode == 0 && ps.stdoutText.length) {
        NSString *firstLine = [ps.stdoutText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]].firstObject;
        NSInteger parsed = firstLine.integerValue;
        if (parsed > 0) pid = @(parsed);
    }
    if (pid) {
        [service performSelector:@selector(killApplication:options:withResult:) withObject:bundleID withObject:@{} withObject:nil];
    }
}

@end
