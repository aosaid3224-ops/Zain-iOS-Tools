//
//  CLRootViewController.m
//

#import "CLRootViewController.h"
#import "CLGamesViewController.h"
#import "CLLogViewController.h"
#import "CLSettingsViewController.h"
#import "CLTheme.h"

@implementation CLRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [CLTheme applyTabBarAppearance:self.tabBar];

    CLGamesViewController *games = [CLGamesViewController new];
    UINavigationController *gamesNav = [[UINavigationController alloc] initWithRootViewController:games];
    [CLTheme applyToNavigationController:gamesNav];
    gamesNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"الألعاب"
        image:[UIImage systemImageNamed:@"gamecontroller"]
        selectedImage:[UIImage systemImageNamed:@"gamecontroller.fill"]];

    CLLogViewController *log = [CLLogViewController new];
    UINavigationController *logNav = [[UINavigationController alloc] initWithRootViewController:log];
    [CLTheme applyToNavigationController:logNav];
    logNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"السجل"
        image:[UIImage systemImageNamed:@"list.bullet.rectangle"]
        selectedImage:[UIImage systemImageNamed:@"list.bullet.rectangle.fill"]];

    CLSettingsViewController *settings = [CLSettingsViewController new];
    UINavigationController *setNav = [[UINavigationController alloc] initWithRootViewController:settings];
    [CLTheme applyToNavigationController:setNav];
    setNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"حول"
        image:[UIImage systemImageNamed:@"info.circle"]
        selectedImage:[UIImage systemImageNamed:@"info.circle.fill"]];

    self.viewControllers = @[gamesNav, logNav, setNav];
    self.selectedIndex = 0;
}

@end
