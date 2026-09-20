//
//  CLGameDiscovery.h
//  Crack Lab — discovers and classifies installed games.
//

#import <Foundation/Foundation.h>
#import "CLGame.h"

@interface CLGameDiscovery : NSObject
/// Full scan. Completion on main queue. Never throws — reports via error string.
- (void)discoverGamesWithCompletion:(void (^)(NSArray<CLGame *> *games, NSString *error))completion;
/// Size of a bundle in bytes (nil on failure).
+ (long long)bundleSizeAtPath:(NSString *)path;
@end
