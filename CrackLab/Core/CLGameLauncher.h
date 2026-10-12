//
//  CLGameLauncher.h
//  Crack Lab — honest two-mechanism app launcher.
//

#import <Foundation/Foundation.h>
#import "CLGame.h"

@interface CLGameLauncher : NSObject
/// Mechanism chain: LSApplicationWorkspace → URL scheme. Always calls back on main queue.
- (void)launchGame:(CLGame *)game completion:(void (^)(BOOL success, NSString *error))completion;
@end
