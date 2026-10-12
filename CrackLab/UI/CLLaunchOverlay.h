//
//  CLLaunchOverlay.h
//  Crack Lab — animated launch transition (Copper Precision).
//

#import <UIKit/UIKit.h>
#import "CLGame.h"

@interface CLLaunchOverlay : UIView
/// Presents the animated overlay over the key window. Returns the instance so the caller can dismiss on failure.
+ (instancetype)presentWithGame:(CLGame *)game;
- (void)dismiss;
@end
