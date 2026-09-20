//
//  CLGameStateInspector.m
//

#import "CLGameStateInspector.h"
#include <CommonCrypto/CommonDigest.h>

@implementation CLGameStateInspector

static NSString *CLBaselinePath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"CLBaselines.plist"];
}

+ (NSString *)sha256OfFile:(NSString *)path {
    NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!h) return nil;
    CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx);
    while (YES) {
        NSData *chunk = [h readDataOfLength:1024 * 1024];
        if (!chunk.length) break;
        CC_SHA256_Update(&ctx, chunk.bytes, (CC_LONG)chunk.length);
    }
    [h closeFile];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:64];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

+ (NSDictionary *)baselines {
    return [NSDictionary dictionaryWithContentsOfFile:CLBaselinePath()] ?: @{};
}

- (void)inspectGame:(CLGame *)game completion:(void (^)(CLGame *, NSString *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error = nil;
        if (!game.executablePath.length || ![[NSFileManager defaultManager] fileExistsAtPath:game.executablePath]) {
            error = @"لم يتم العثور على الملف التنفيذي للعبة.";
            game.modState = CLGameModStateUnknown;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(game, error); });
            return;
        }
        game.executableSHA256 = [CLGameStateInspector sha256OfFile:game.executablePath];
        NSDictionary *base = [CLGameStateInspector baselines];
        NSString *stored = base[game.bundleID];
        if (!stored.length) {
            game.modState = CLGameModStateNoBaseline;
        } else if ([stored isEqualToString:game.executableSHA256]) {
            game.modState = CLGameModStateOriginal;
        } else {
            game.modState = CLGameModStateModified;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(game, error); });
    });
}

- (void)establishBaselineForGame:(CLGame *)game completion:(void (^)(BOOL, NSString *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *hash = game.executableSHA256.length ? game.executableSHA256
            : [CLGameStateInspector sha256OfFile:game.executablePath];
        if (!hash.length) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"تعذّر حساب بصمة اللعبة."); });
            return;
        }
        NSMutableDictionary *base = [[CLGameStateInspector baselines] mutableCopy];
        base[game.bundleID] = hash;
        BOOL ok = [base writeToFile:CLBaselinePath() atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(ok, ok ? nil : @"فشل حفظ خط الأساس.");
        });
    });
}

@end
