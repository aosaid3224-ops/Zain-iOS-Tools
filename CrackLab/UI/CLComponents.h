//
//  CLComponents.h
//  Crack Lab — shared components (Copper Precision).
//

#import <UIKit/UIKit.h>
#import "CLTheme.h"

NS_ASSUME_NONNULL_BEGIN

@interface CLHairlineView : UIView
- (instancetype)initWithMargins:(UIEdgeInsets)insets;
@end

@interface CLStatusPill : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIColor *statusColor;
- (instancetype)initWithText:(NSString *)text color:(UIColor *)color;
@end

@interface CLButton : UIButton
+ (instancetype)primaryWithTitle:(NSString *)title;
+ (instancetype)secondaryWithTitle:(NSString *)title;
+ (instancetype)destructiveWithTitle:(NSString *)title;
+ (instancetype)tertiaryWithTitle:(NSString *)title;
@end

@interface CLListRow : UIView
@property (nonatomic, strong, readonly) UIImageView *iconView;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;
@property (nonatomic, strong, readonly) UILabel *metadataLabel;
- (void)setAccessoryView:(nullable UIView *)accessory;
@property (nonatomic, assign) BOOL showsSeparator;
@end

@interface CLEmptyStateView : UIView
- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
                  actionTitle:(nullable NSString *)actionTitle
                      handler:(nullable void (^)(void))handler;
@end

@interface CLNoticeView : UIView
- (instancetype)initWithMessage:(NSString *)message kind:(NSString *)kind;
@end

@interface CLSkeletonView : UIView
@end

NS_ASSUME_NONNULL_END
