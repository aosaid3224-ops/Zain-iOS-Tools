//
//  IPTheme.m
//  IPAInstallerPro — Design System "Quiet Precision" v2.0
//

#import "IPTheme.h"

@implementation IPTheme
@end

@implementation IPTheme (Colors)

+ (UIColor *)backgroundColor {
    return [UIColor colorWithRed:0.05 green:0.055 blue:0.065 alpha:1.0]; // #0D0E11 quiet near-black
}
+ (UIColor *)surfaceColor {
    return [UIColor colorWithRed:0.085 green:0.09 blue:0.105 alpha:1.0]; // #161A1B raised
}
+ (UIColor *)surfaceSubtleColor {
    return [UIColor colorWithRed:0.11 green:0.115 blue:0.13 alpha:1.0];  // #1C1D21 subtle
}
+ (UIColor *)fillColor {
    return [UIColor colorWithRed:0.14 green:0.145 blue:0.165 alpha:1.0]; // fill / pressed
}
+ (UIColor *)textPrimaryColor {
    return [UIColor colorWithRed:0.96 green:0.965 blue:0.975 alpha:1.0];
}
+ (UIColor *)textSecondaryColor {
    return [UIColor colorWithRed:0.68 green:0.70 blue:0.73 alpha:1.0];
}
+ (UIColor *)textTertiaryColor {
    return [UIColor colorWithRed:0.48 green:0.50 blue:0.54 alpha:1.0];
}
+ (UIColor *)textQuaternaryColor {
    return [UIColor colorWithRed:0.34 green:0.36 blue:0.40 alpha:1.0];
}
+ (UIColor *)accentColor {
    return [UIColor colorWithRed:0.36 green:0.62 blue:0.95 alpha:1.0]; // #5C9EF2 calm blue
}
+ (UIColor *)accentMutedColor {
    return [UIColor colorWithRed:0.36 green:0.62 blue:0.95 alpha:0.16];
}
+ (UIColor *)successColor {
    return [UIColor colorWithRed:0.30 green:0.76 blue:0.46 alpha:1.0];
}
+ (UIColor *)warningColor {
    return [UIColor colorWithRed:0.95 green:0.65 blue:0.20 alpha:1.0];
}
+ (UIColor *)errorColor {
    return [UIColor colorWithRed:0.86 green:0.32 blue:0.32 alpha:1.0];
}
+ (UIColor *)infoColor {
    return [UIColor colorWithRed:0.40 green:0.70 blue:0.95 alpha:1.0];
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

@implementation IPTheme (Typography)

+ (UIFont *)largeTitleFont { return [UIFont systemFontOfSize:28 weight:UIFontWeightBold]; }
+ (UIFont *)titleFont       { return [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold]; }
+ (UIFont *)headlineFont    { return [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]; }
+ (UIFont *)bodyFont        { return [UIFont systemFontOfSize:15 weight:UIFontWeightRegular]; }
+ (UIFont *)captionFont     { return [UIFont systemFontOfSize:13 weight:UIFontWeightRegular]; }
+ (UIFont *)monoFont        {
    UIFont *m = [UIFont fontWithName:@"Menlo" size:12];
    return m ?: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
}

@end

@implementation IPTheme (Spacing)

+ (CGFloat)space2  { return 2; }
+ (CGFloat)space4  { return 4; }
+ (CGFloat)space8  { return 8; }
+ (CGFloat)space12 { return 12; }
+ (CGFloat)space16 { return 16; }
+ (CGFloat)space20 { return 20; }
+ (CGFloat)space24 { return 24; }
+ (CGFloat)space32 { return 32; }
+ (CGFloat)space40 { return 40; }
+ (CGFloat)pageMargin { return 20; }

@end

@implementation IPTheme (Radius)

+ (CGFloat)radiusSmall  { return 6; }
+ (CGFloat)radiusMedium { return 10; }
+ (CGFloat)radiusLarge  { return 14; }
+ (CGFloat)radiusIcon   { return 9; }

@end

@implementation IPTheme (Motion)

+ (NSTimeInterval)durationStandard { return 0.28; }
+ (NSTimeInterval)durationFast     { return 0.16; }
+ (NSTimeInterval)durationEmphasis { return 0.42; }
+ (UIViewAnimationOptions)easing   { return UIViewAnimationOptionCurveEaseInOut; }

@end

@implementation IPTheme (Appearance)

+ (void)applyToNavigationController:(UINavigationController *)navigationController {
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = [IPTheme backgroundColor];
    appearance.shadowColor = [UIColor clearColor];
    appearance.titleTextAttributes = @{
        NSForegroundColorAttributeName: [IPTheme textPrimaryColor],
        NSFontAttributeName: [IPTheme headlineFont]
    };
    appearance.largeTitleTextAttributes = @{
        NSForegroundColorAttributeName: [IPTheme textPrimaryColor],
        NSFontAttributeName: [IPTheme largeTitleFont]
    };
    navigationController.navigationBar.standardAppearance = appearance;
    navigationController.navigationBar.scrollEdgeAppearance = appearance;
    navigationController.navigationBar.compactAppearance = appearance;
    navigationController.navigationBar.tintColor = [IPTheme accentColor];
}

+ (void)applyGlobalAppearance {
    // Quiet, precise — no system-wide gimmicks. The canvas is the screen.
    [[UIView appearance] setTintColor:[IPTheme accentColor]];
}

@end

#pragma mark - Legacy Compatibility Aliases

@implementation IPTheme (LegacyCompat)

+ (UIColor *)cardColor           { return [IPTheme surfaceColor]; }
+ (UIColor *)secondaryCardColor  { return [IPTheme surfaceSubtleColor]; }
+ (UIColor *)mutedTextColor      { return [IPTheme textSecondaryColor]; }
+ (UIColor *)subtleBorderColor   { return [IPTheme separatorColor]; }
+ (UIColor *)dividerColor        { return [IPTheme separatorColor]; }
+ (UIFont  *)sectionFont         { return [IPTheme titleFont]; }

@end
