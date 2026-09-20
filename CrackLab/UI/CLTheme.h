//
//  CLTheme.h
//  Crack Lab — Design System "Copper Precision" v1.0
//
//  Identity: Technical. Quiet. Powerful. Copper accent.
//

#import <UIKit/UIKit.h>

@interface CLTheme (Colors)
+ (UIColor *)backgroundColor;
+ (UIColor *)surfaceColor;
+ (UIColor *)surfaceSubtleColor;
+ (UIColor *)fillColor;

+ (UIColor *)textPrimaryColor;
+ (UIColor *)textSecondaryColor;
+ (UIColor *)textTertiaryColor;
+ (UIColor *)textQuaternaryColor;

/// Copper accent — the Crack Lab identity.
+ (UIColor *)accentColor;
+ (UIColor *)accentMutedColor;

+ (UIColor *)successColor;
+ (UIColor *)warningColor;
+ (UIColor *)errorColor;
+ (UIColor *)infoColor;

+ (UIColor *)separatorColor;
+ (UIColor *)separatorStrongColor;
+ (UIColor *)selectionColor;
@end

@interface CLTheme (Typography)
+ (UIFont *)largeTitleFont;
+ (UIFont *)titleFont;
+ (UIFont *)headlineFont;
+ (UIFont *)bodyFont;
+ (UIFont *)captionFont;
+ (UIFont *)monoFont;
@end

@interface CLTheme (Spacing)
+ (CGFloat)space4; + (CGFloat)space8; + (CGFloat)space12;
+ (CGFloat)space16; + (CGFloat)space20; + (CGFloat)space24;
+ (CGFloat)space32; + (CGFloat)pageMargin;
@end

@interface CLTheme (Radius)
+ (CGFloat)radiusSmall; + (CGFloat)radiusMedium;
+ (CGFloat)radiusLarge; + (CGFloat)radiusIcon;
@end

@interface CLTheme (Motion)
+ (NSTimeInterval)durationFast;
+ (NSTimeInterval)durationStandard;
+ (NSTimeInterval)durationEmphasis;
+ (UIViewAnimationOptions)easing;
@end

@interface CLTheme (Appearance)
+ (void)applyToNavigationController:(UINavigationController *)nc;
+ (void)applyTabBarAppearance:(UITabBar *)tabBar;
@end
