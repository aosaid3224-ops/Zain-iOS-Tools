//
//  CLGameDiscovery.h
//  Crack Lab — discovers and classifies installed games.
//
//  Layers (engine detection is NOT classification):
//    1. Application Discovery   (mechanism chain)
//    2. Application Metadata    (category / genres / app type)
//    3. Game Classification     (multi-signal scoring + fallback)
//    4. Engine Detection        (display only, via CLEngineDetector)
//
//  Every scanned app produces a CLDiscoveryRecord explaining the decision.
//

#import <Foundation/Foundation.h>
#import "CLGame.h"
#import "CLDiscoveryRecord.h"

@interface CLGameDiscovery : NSObject

/// Full scan; completion on main queue. Success only when a real list returns.
- (void)discoverGamesWithCompletion:(void (^)(NSArray<CLGame *> *games, NSString *error))completion;

/// Diagnostics of the LAST scan — one record per scanned app (games + non-games).
- (NSArray<CLDiscoveryRecord *> *)lastDiagnostics;

+ (long long)bundleSizeAtPath:(NSString *)path;
@end
