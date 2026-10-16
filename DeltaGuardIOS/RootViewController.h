#import <UIKit/UIKit.h>
@interface DGProcessMonitor : NSObject
@property(nonatomic,readonly) pid_t lastPID;
@property(nonatomic,readonly,strong) NSDate *sessionStart;
@property(nonatomic,readonly) NSInteger startCount;
+ (instancetype)shared;
- (void)start;
- (void)stop;
@end
BOOL DGMonitorEnabled(void);
@interface RootViewController : UITabBarController
@end
