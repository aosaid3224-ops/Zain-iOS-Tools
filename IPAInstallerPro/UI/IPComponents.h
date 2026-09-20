//
//  IPComponents.h
//  IPAInstallerPro — Shared components of the "Quiet Precision" system.
//

#import <UIKit/UIKit.h>
#import "IPTheme.h"

NS_ASSUME_NONNULL_BEGIN

/// A hairline separator that respects page margins. The single separator style.
@interface IPHairlineView : UIView
- (instancetype)initWithMargins:(UIEdgeInsets)insets;
@end

/// Quiet press feedback: brief highlight, no scale gimmicks.
@interface IPPressableView : UIView
@property (nonatomic, copy, nullable) void (^pressedHandler)(void);
@end

/// Semantic status pill: Ready / Working / Warning / Failed / Unavailable.
@interface IPStatusPill : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIColor *statusColor;
- (instancetype)initWithText:(NSString *)text color:(UIColor *)color;
@end

/// Buttons — strict hierarchy. One style per role, everywhere.
@interface IPButton : UIButton
+ (instancetype)primaryWithTitle:(NSString *)title;
+ (instancetype)secondaryWithTitle:(NSString *)title;
+ (instancetype)destructiveWithTitle:(NSString *)title;
+ (instancetype)tertiaryWithTitle:(NSString *)title;
+ (instancetype)inlineWithTitle:(NSString *)title; // text-only, accent color
@end

/// Structured list row (NOT a card). Icon + title + subtitle + optional
/// trailing metadata + optional disclosure + optional custom accessory.
@interface IPListRow : UIView
@property (nonatomic, strong, readonly) UIImageView *iconView;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;
@property (nonatomic, strong, readonly) UILabel *metadataLabel;
@property (nonatomic, strong, readonly) UIImageView *disclosureView;
/// Assign any view (switch, pill, button) as the trailing accessory.
- (void)setAccessoryView:(nullable UIView *)accessory;
/// Separator visibility (default YES, last row hides it).
@property (nonatomic, assign) BOOL showsSeparator;
@end

/// Professional empty state: what is missing, why, and the single next action.
@interface IPEmptyStateView : UIView
- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
                  actionTitle:(nullable NSString *)actionTitle
                      handler:(nullable void (^)(void))handler;
@end

/// Inline notice — quiet error/info strip, never a wall of red.
@interface IPNoticeView : UIView
- (instancetype)initWithMessage:(NSString *)message
                           kind:(NSString *)kind; // @"error" | @"warning" | @"info" | @"success"
@end

/// Skeleton line for progressive loading.
@interface IPSkeletonView : UIView
@property (nonatomic, assign) CGFloat cornerRadius;
@end

NS_ASSUME_NONNULL_END
