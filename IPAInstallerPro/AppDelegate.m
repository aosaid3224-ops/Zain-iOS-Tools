#import "AppDelegate.h"
#import "UI/MainViewController.h"
#import "UI/IPAUnpackViewController.h"
#import "UI/InstalledAppsViewController.h"
#import "UI/SettingsViewController.h"
#import "Core/Logger.h"
#import "Core/JailbreakEnvironment.h"
#import "UI/IPTheme.h"

@interface AppDelegate ()
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Initialize logger and environment (safe, no heavy blocking)
    [Logger sharedLogger];
    [JailbreakEnvironment sharedEnvironment];  // detectEnvironment is now called in init

    [IPTheme applyGlobalAppearance];
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    UITabBarController *tabBarController = [[UITabBarController alloc] init];

    MainViewController *mainVC = [[MainViewController alloc] init];
    UINavigationController *mainNav = [[UINavigationController alloc] initWithRootViewController:mainVC];
    mainNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"ملفات IPA"
                                                         image:[UIImage systemImageNamed:@"doc.zipper"]
                                                 selectedImage:[UIImage systemImageNamed:@"doc.zipper"]];

    InstalledAppsViewController *installedVC = [[InstalledAppsViewController alloc] init];
    UINavigationController *installedNav = [[UINavigationController alloc] initWithRootViewController:installedVC];
    installedNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"التطبيقات المثبتة"
                                                            image:[UIImage systemImageNamed:@"apps.iphone"]
                                                    selectedImage:[UIImage systemImageNamed:@"apps.iphone"]];

    IPAUnpackViewController *unpackVC = [[IPAUnpackViewController alloc] init];
    UINavigationController *unpackNav = [[UINavigationController alloc] initWithRootViewController:unpackVC];
    unpackNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"فك الحزمة"
                                                         image:[UIImage systemImageNamed:@"archivebox"]
                                                 selectedImage:[UIImage systemImageNamed:@"archivebox.fill"]];

    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"الإعدادات"
                                                           image:[UIImage systemImageNamed:@"gearshape"]
                                                   selectedImage:[UIImage systemImageNamed:@"gearshape.fill"]];

    tabBarController.viewControllers = @[mainNav, installedNav, unpackNav, settingsNav];
    UIColor *glassTint = [IPTheme accentColor];
    UIColor *glassBackground = [UIColor colorWithRed:0.045 green:0.045 blue:0.052 alpha:0.86];

    UITabBarAppearance *tabAppearance = [[UITabBarAppearance alloc] init];
    [tabAppearance configureWithDefaultBackground];
    tabAppearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    tabAppearance.backgroundColor = glassBackground;
    tabAppearance.shadowColor = [IPTheme separatorColor];
    tabAppearance.stackedLayoutAppearance.normal.iconColor = [IPTheme separatorStrongColor];
    tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.48], NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightMedium]};
    tabAppearance.stackedLayoutAppearance.selected.iconColor = glassTint;
    tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = @{NSForegroundColorAttributeName: glassTint, NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]};
    tabBarController.tabBar.standardAppearance = tabAppearance;
    if (@available(iOS 15.0, *)) {
        tabBarController.tabBar.scrollEdgeAppearance = tabAppearance;
    }
    tabBarController.tabBar.tintColor = glassTint;
    tabBarController.tabBar.unselectedItemTintColor = [IPTheme separatorStrongColor];
    tabBarController.tabBar.translucent = YES;

    for (UINavigationController *nav in tabBarController.viewControllers) {
        nav.navigationBar.prefersLargeTitles = YES;
        UINavigationBarAppearance *navAppearance = [[UINavigationBarAppearance alloc] init];
        [navAppearance configureWithTransparentBackground];
        navAppearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
        navAppearance.backgroundColor = [UIColor colorWithRed:0.025 green:0.028 blue:0.035 alpha:0.72];
        navAppearance.shadowColor = [UIColor colorWithRed:0.72 green:0.08 blue:0.11 alpha:0.22];
        navAppearance.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]};
        navAppearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [UIColor colorWithRed:0.96 green:0.96 blue:1.0 alpha:1.0], NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightBold]};
        nav.navigationBar.standardAppearance = navAppearance;
        nav.navigationBar.scrollEdgeAppearance = navAppearance;
        nav.navigationBar.compactAppearance = navAppearance;
        [IPTheme applyToNavigationController:nav];
    }

    self.window.rootViewController = tabBarController;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
