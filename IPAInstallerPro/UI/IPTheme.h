//
//  IPTheme.h
//  IPAInstallerPro — Design System "Quiet Precision" v2.0
//
//  One system. Every screen. No exceptions.
//  Less UI, More Intent.
//
//  Legacy selectors (cardColor, mutedTextColor, …) are preserved as
//  compatibility aliases so existing screens keep building while they are
//  migrated onto the new tokens incrementally.
//

#import <UIKit/UIKit.h>

#pragma mark - Color Tokens

@interface IPTheme (Colors)

/// Base canvas — the screen itself is the canvas.
+ (UIColor *)backgroundColor;

/// Surface hierarchy (quiet, layered, never card-walls).
+ (UIColor *)surfaceColor;        // primary raised surface
+ (UIColor *)surfaceSubtleColor;  // secondary surface
+ (UIColor *)fillColor;           // tertiary fill / pressed

/// Text hierarchy (strict).
+ (UIColor *)textPrimaryColor;
+ (UIColor *)textSecondaryColor;
+ (UIColor *)textTertiaryColor;
+ (UIColor *)textQuaternaryColor; // metadata, monospace paths

/// Single accent — one identity.
+ (UIColor *)accentColor;
+ (UIColor *)accentMutedColor;

/// Semantic — only when meaning demands it.
+ (UIColor *)successColor;
+ (UIColor *)warningColor;
+ (UIColor *)errorColor;
+ (UIColor *)infoColor;

/// Hairlines & separators.
+ (UIColor *)separatorColor;
+ (UIColor *)separatorStrongColor;

/// Selection / highlight.
+ (UIColor *)selectionColor;
@end

#pragma mark - Typography Scale

@interface IPTheme (Typography)
+ (UIFont *)largeTitleFont;   // screen headers
+ (UIFont *)titleFont;        // section header
+ (UIFont *)headlineFont;     // row primary label
+ (UIFont *)bodyFont;         // description
+ (UIFont *)captionFont;      // secondary label
+ (UIFont *)monoFont;         // micro metadata (paths, versions)
@end

#pragma mark - Spacing (4pt grid)

@interface IPTheme (Spacing)
+ (CGFloat)space2;
+ (CGFloat)space4;
+ (CGFloat)space8;
+ (CGFloat)space12;
+ (CGFloat)space16;
+ (CGFloat)space20;
+ (CGFloat)space24;
+ (CGFloat)space32;
+ (CGFloat)space40;
+ (CGFloat)pageMargin;
@end

#pragma mark - Radius & Motion

@interface IPTheme (Radius)
+ (CGFloat)radiusSmall;
+ (CGFloat)radiusMedium;
+ (CGFloat)radiusLarge;
+ (CGFloat)radiusIcon;
@end

@interface IPTheme (Motion)
+ (NSTimeInterval)durationStandard;
+ (NSTimeInterval)durationFast;
+ (NSTimeInterval)durationEmphasis;
+ (UIViewAnimationOptions)easing;
@end

#pragma mark - Appearance

@interface IPTheme (Appearance)
+ (void)applyToNavigationController:(UINavigationController *)navigationController;
+ (void)applyGlobalAppearance;
@end

#pragma mark - Legacy Compatibility Aliases (do not use in new code)

@interface IPTheme (LegacyCompat)
+ (UIColor *)cardColor;           // -> surfaceColor
+ (UIColor *)secondaryCardColor;  // -> surfaceSubtleColor
+ (UIColor *)mutedTextColor;      // -> textSecondaryColor
+ (UIColor *)subtleBorderColor;   // -> separatorColor
+ (UIColor *)dividerColor;        // -> separatorColor
+ (UIFont  *)sectionFont;         // -> titleFont
@end
