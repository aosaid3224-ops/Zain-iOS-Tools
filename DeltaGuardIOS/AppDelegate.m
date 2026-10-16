#import "AppDelegate.h"
#import "RootViewController.h"

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [RootViewController new];
    [self.window makeKeyAndVisible];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(dgForeground) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(dgBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    if (DGMonitorEnabled()) [[DGProcessMonitor shared] start];
    return YES;
}
- (void)dgForeground { if (DGMonitorEnabled()) [[DGProcessMonitor shared] start]; }
- (void)dgBackground { [[DGProcessMonitor shared] stop]; }
@end
