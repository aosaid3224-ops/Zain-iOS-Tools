//
//  CLTheme.m
//

#import "CLTheme.h"

@implementation CLTheme (Colors)
+ (UIColor *)backgroundColor {
    return [UIColor colorWithRed:0.055 green:0.052 blue:0.058 alpha:1.0]; // #0E0D0F warm near-black
}
+ (UIColor *)surfaceColor {
    return [UIColor colorWithRed:0.094 green:0.088 blue:0.094 alpha:1.0]; // #181618
}
+ (UIColor *)surfaceSubtleColor {
    return [UIColor colorWithRed:0.125 green:0.117 blue:0.121 alpha:1.0]; // #201E1F
}
+ (UIColor *)fillColor {
    return [UIColor colorWithRed:0.161 green:0.150 blue:0.153 alpha:1.0]; // #292627
}
+ (UIColor *)textPrimaryColor {
    return [UIColor colorWithRed:0.965 green:0.958 blue:0.952 alpha:1.0];
}
+ (UIColor *)textSecondaryColor {
    return [UIColor colorWithRed:0.692 green:0.665 blue:0.648 alpha:1.0];
}
+ (UIColor *)textTertiaryColor {
    return [UIColor colorWithRed:0.495 green:0.470 blue:0.455 alpha:1.0];
}
+ (UIColor *)textQuaternaryColor {
    return [UIColor colorWithRed:0.350 green:0.330 blue:0.320 alpha:1.0];
}
/// Copper: #C87F42 — warm metal, powerful without noise.
+ (UIColor *)accentColor {
    return [UIColor colorWithRed:0.784 green:0.498 blue:0.259 alpha:1.0];
}
+ (UIColor *)accentMutedColor {
    return [UIColor colorWithRed:0.784 green:0.498 blue:0.259 alpha:0.16];
}
+ (UIColor *)successColor {
    return [UIColor colorWithRed:0.298 green:0.760 blue:0.459 alpha:1.0];
}
+ (UIColor *)warningColor {
    return [UIColor colorWithRed:0.937 green:0.651 blue:0.208 alpha:1.0];
}
+ (UIColor *)errorColor {
    return [UIColor colorWithRed:0.851 green:0.325 blue:0.314 alpha:1.0];
}
+ (UIColor *)infoColor {
    return [UIColor colorWithRed:0.416 green:0.658 blue:0.894 alpha:1.0];
}
+ (UIColor *)separatorColor {
    return [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.07];
}
+ (UIColor *)separatorStrongColor {
    return [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.13];
}
+ (UIColor *)selectionColor {
    return [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.05];
}
@end

@implementation CLTheme (Typography)
+ (UIFont *)largeTitleFont { return [UIFont systemFontOfSize:28 weight:UIFontWeightBold]; }
+ (UIFont *)titleFont       { return [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold]; }
+ (UIFont *)headlineFont    { return [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]; }
+ (UIFont *)bodyFont        { return [UIFont systemFontOfSize:15 weight:UIFontWeightRegular]; }
+ (UIFont *)captionFont     { return [UIFont systemFontOfSize:13 weight:UIFontWeightRegular]; }
+ (UIFont *)monoFont {
    UIFont *m = [UIFont fontWithName:@"Menlo" size:12];
    return m ?: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
}
@end

@implementation CLTheme (Spacing)
+ (CGFloat)space4 { return 4; } + (CGFloat)space8 { return 8; }
+ (CGFloat)space12 { return 12; } + (CGFloat)space16 { return 16; }
+ (CGFloat)space20 { return 20; } + (CGFloat)space24 { return 24; }
+ (CGFloat)space32 { return 32; } + (CGFloat)pageMargin { return 20; }
@end

@implementation CLTheme (Radius)
+ (CGFloat)radiusSmall { return 6; } + (CGFloat)radiusMedium { return 10; }
+ (CGFloat)radiusLarge { return 14; } + (CGFloat)radiusIcon { return 9; }
@end

@implementation CLTheme (Motion)
+ (NSTimeInterval)durationFast { return 0.16; }
+ (NSTimeInterval)durationStandard { return 0.28; }
+ (NSTimeInterval)durationEmphasis { return 0.42; }
+ (UIViewAnimationOptions)easing { return UIViewAnimationOptionCurveEaseInOut; }
@end

@implementation CLTheme (Appearance)
+ (void)applyToNavigationController:(UINavigationController *)nc {
    UINavigationBarAppearance *a = [UINavigationBarAppearance new];
    [a configureWithTransparentBackground];
    a.backgroundColor = [CLTheme backgroundColor];
    a.shadowColor = UIColor.clearColor;
    a.titleTextAttributes = @{ NSForegroundColorAttributeName: [CLTheme textPrimaryColor],
                               NSFontAttributeName: [CLTheme headlineFont] };
    a.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: [CLTheme textPrimaryColor],
                                    NSFontAttributeName: [CLTheme largeTitleFont] };
    nc.navigationBar.standardAppearance = a;
    nc.navigationBar.scrollEdgeAppearance = a;
    nc.navigationBar.compactAppearance = a;
    nc.navigationBar.tintColor = [CLTheme accentColor];
}
+ (void)applyTabBarAppearance:(UITabBar *)tabBar {
    UITabBarAppearance *a = [UITabBarAppearance new];
    [a configureWithOpaqueBackground];
    a.backgroundColor = [CLTheme surfaceColor];
    a.shadowColor = UIColor.clearColor;
    a.stackedLayoutAppearance.normal.iconColor = [CLTheme textQuaternaryColor];
    a.stackedLayoutAppearance.normal.titleTextAttributes = @{
        NSForegroundColorAttributeName: [CLTheme textTertiaryColor],
        NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightMedium] };
    a.stackedLayoutAppearance.selected.iconColor = [CLTheme accentColor];
    a.stackedLayoutAppearance.selected.titleTextAttributes = @{
        NSForegroundColorAttributeName: [CLTheme accentColor],
        NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold] };
    tabBar.standardAppearance = a;
    tabBar.scrollEdgeAppearance = a;
    tabBar.unselectedItemTintColor = [CLTheme textQuaternaryColor];
}
@end
