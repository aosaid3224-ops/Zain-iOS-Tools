//
//  CLAppDelegate.m
//

#import "CLAppDelegate.h"
#import "CLRootViewController.h"
#import "CLTheme.h"

@implementation CLAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    CLRootViewController *root = [CLRootViewController new];
    [CLTheme applyToNavigationController:(UINavigationController *)root.viewControllers.firstObject];
    self.window.rootViewController = root;
    self.window.backgroundColor = [CLTheme backgroundColor];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
