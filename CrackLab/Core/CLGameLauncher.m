//
//  CLGameLauncher.m
//
//  Layer 1: LSApplicationWorkspace openApplicationWithBundleID:
//  Layer 2: fallback — first URL scheme from the game's Info.plist
//  Both are attempted honestly; the error says which mechanism failed.
//

#import "CLGameLauncher.h"

@implementation CLGameLauncher

- (void)launchGame:(CLGame *)game completion:(void (^)(BOOL, NSString *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *mechanism = nil;
        NSString *error = nil;
        BOOL ok = NO;

        // ── Mechanism 1: LSApplicationWorkspace ──
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        id workspace = ([wsClass respondsToSelector:@selector(defaultWorkspace)])
            ? [wsClass performSelector:@selector(defaultWorkspace)] : nil;
        if (workspace) {
            SEL sel = NSSelectorFromString(@"openApplicationWithBundleID:");
            if ([workspace respondsToSelector:sel]) {
                @try {
                    NSMethodSignature *sig = [workspace methodSignatureForSelector:sel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:workspace];
                    [inv setSelector:sel];
                    NSString *bid = game.bundleID;
                    [inv setArgument:&bid atIndex:2];
                    [inv invoke];
                    BOOL ret = NO;
                    [inv getReturnValue:&ret];
                    ok = ret;
                    mechanism = ok ? @"LSApplicationWorkspace" : nil;
                    if (!ok) error = @"LSApplicationWorkspace رفض فتح التطبيق.";
                } @catch (NSException *e) {
                    error = [NSString stringWithFormat:@"استثناء: %@", e.reason ?: @"?"];
                }
            } else {
                error = @"defaultWorkspace لا يستجيب لـ openApplicationWithBundleID:.";
            }
        } else {
            error = @"تعذّر الوصول إلى LSApplicationWorkspace.";
        }

        // ── Mechanism 2: first CFBundleURLSchemes from Info.plist ──
        if (!ok) {
            NSString *plist = [game.bundlePath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plist];
            NSArray *types = info[@"CFBundleURLTypes"];
            NSString *scheme = nil;
            if ([types isKindOfClass:[NSArray class]]) {
                for (NSDictionary *t in types) {
                    NSArray *schemes = t[@"CFBundleURLSchemes"];
                    if ([schemes isKindOfClass:[NSArray class]] && schemes.count) { scheme = schemes.firstObject; break; }
                }
            }
            if (scheme.length) {
                NSURL *url = [NSURL URLWithString:[scheme stringByAppendingString:@"://"]];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([[UIApplication sharedApplication] canOpenURL:url]
                        && [[UIApplication sharedApplication] openURL:url]) {
                        completion(YES, nil);
                    } else {
                        completion(NO, [NSString stringWithFormat:@"فشل فتح الـ scheme %@. %@", scheme, error ?: @""]);
                    }
                });
                return;
            }
            error = [NSString stringWithFormat:@"لا يوجد URL scheme. %@", error ?: @""];
        }

        dispatch_async(dispatch_get_main_queue(), ^{ completion(ok, error); });
    });
}

@end
