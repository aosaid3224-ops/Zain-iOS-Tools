//
//  CLComponents.m
//

#import "CLComponents.h"
#import <objc/runtime.h>

@implementation CLHairlineView {
    UIView *_line;
}
- (instancetype)initWithMargins:(UIEdgeInsets)insets {
    self = [super initWithFrame:CGRectZero];
    _line = [UIView new];
    _line.backgroundColor = [CLTheme separatorColor];
    _line.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_line];
    self.backgroundColor = UIColor.clearColor;
    [NSLayoutConstraint activateConstraints:@[
        [_line.heightAnchor constraintEqualToConstant:0.5],
        [_line.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_line.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_line.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:insets.left],
        [_line.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-insets.right],
    ]];
    return self;
}
@end

@implementation CLStatusPill {
    UILabel *_label;
}
- (instancetype)initWithText:(NSString *)text color:(UIColor *)color {
    self = [super initWithFrame:CGRectZero];
    _statusColor = color;
    self.layer.cornerRadius = [CLTheme radiusSmall];
    self.backgroundColor = [color colorWithAlphaComponent:0.14];
    _label = [UILabel new];
    _label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _label.textColor = color;
    _label.text = text;
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_label];
    [NSLayoutConstraint activateConstraints:@[
        [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_label.topAnchor constraintEqualToAnchor:self.topAnchor constant:3],
        [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-3],
    ]];
    return self;
}
- (void)setText:(NSString *)text { _text = [text copy]; _label.text = text; }
- (void)setStatusColor:(UIColor *)c { _statusColor = c; self.backgroundColor = [c colorWithAlphaComponent:0.14]; _label.textColor = c; }
@end

@implementation CLButton
+ (instancetype)base:(NSString *)title {
    CLButton *b = [CLButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    b.layer.cornerRadius = [CLTheme radiusMedium];
    b.clipsToBounds = YES;
    return b;
}
+ (instancetype)primaryWithTitle:(NSString *)title {
    CLButton *b = [self base:title];
    b.backgroundColor = [CLTheme accentColor];
    [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    b.contentEdgeInsets = UIEdgeInsetsMake(11, 20, 11, 20);
    return b;
}
+ (instancetype)secondaryWithTitle:(NSString *)title {
    CLButton *b = [self base:title];
    b.backgroundColor = [CLTheme surfaceSubtleColor];
    [b setTitleColor:[CLTheme textPrimaryColor] forState:UIControlStateNormal];
    b.contentEdgeInsets = UIEdgeInsetsMake(11, 20, 11, 20);
    return b;
}
+ (instancetype)destructiveWithTitle:(NSString *)title {
    CLButton *b = [self base:title];
    b.backgroundColor = [CLTheme errorColor];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.contentEdgeInsets = UIEdgeInsetsMake(11, 20, 11, 20);
    return b;
}
+ (instancetype)tertiaryWithTitle:(NSString *)title {
    CLButton *b = [self base:title];
    b.backgroundColor = UIColor.clearColor;
    [b setTitleColor:[CLTheme textSecondaryColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    b.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
    return b;
}
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; self.alpha = enabled ? 1.0 : 0.45; }
@end

@implementation CLListRow {
    UIView *_accessory;
    CLHairlineView *_separator;
    UIImageView *_disclosure;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = UIColor.clearColor;

    _iconView = [UIImageView new];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.layer.cornerRadius = [CLTheme radiusIcon];
    _iconView.clipsToBounds = YES;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [UILabel new];
    _titleLabel.font = [CLTheme headlineFont];
    _titleLabel.textColor = [CLTheme textPrimaryColor];
    _titleLabel.textAlignment = NSTextAlignmentRight;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _subtitleLabel = [UILabel new];
    _subtitleLabel.font = [CLTheme captionFont];
    _subtitleLabel.textColor = [CLTheme textSecondaryColor];
    _subtitleLabel.numberOfLines = 1;
    _subtitleLabel.textAlignment = NSTextAlignmentRight;
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _metadataLabel = [UILabel new];
    _metadataLabel.font = [CLTheme monoFont];
    _metadataLabel.textColor = [CLTheme textQuaternaryColor];
    _metadataLabel.textAlignment = NSTextAlignmentLeft;
    _metadataLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _disclosure = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]];
    _disclosure.tintColor = [CLTheme textQuaternaryColor];
    _disclosure.translatesAutoresizingMaskIntoConstraints = NO;

    _separator = [[CLHairlineView alloc] initWithMargins:UIEdgeInsetsMake(0, 68, 0, 0)];
    _separator.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:_iconView]; [self addSubview:_titleLabel];
    [self addSubview:_subtitleLabel]; [self addSubview:_metadataLabel];
    [self addSubview:_disclosure]; [self addSubview:_separator];

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:44],
        [_iconView.heightAnchor constraintEqualToConstant:44],

        [_titleLabel.trailingAnchor constraintEqualToAnchor:_iconView.leadingAnchor constant:-16],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_metadataLabel.trailingAnchor constant:8],

        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3],

        [_metadataLabel.leadingAnchor constraintEqualToAnchor:_disclosure.trailingAnchor constant:8],
        [_metadataLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_disclosure.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_disclosure.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_disclosure.widthAnchor constraintEqualToConstant:14],
        [_disclosure.heightAnchor constraintEqualToConstant:14],

        [_separator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_separator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_separator.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:72],
    ]];
    _showsSeparator = YES;
    return self;
}
- (void)setAccessoryView:(UIView *)accessory {
    [_accessory removeFromSuperview]; _accessory = accessory;
    if (!accessory) return;
    accessory.translatesAutoresizingMaskIntoConstraints = NO;
    _disclosure.hidden = YES;
    [self addSubview:accessory];
    [NSLayoutConstraint activateConstraints:@[
        [accessory.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [accessory.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
}
- (void)setShowsSeparator:(BOOL)s { _showsSeparator = s; _separator.hidden = !s; }
@end

@implementation CLEmptyStateView
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message
                  actionTitle:(NSString *)actionTitle handler:(void (^)(void))handler {
    self = [super initWithFrame:CGRectZero];
    self.backgroundColor = UIColor.clearColor;
    UILabel *t = [UILabel new];
    t.font = [CLTheme titleFont]; t.textColor = [CLTheme textPrimaryColor];
    t.text = title; t.textAlignment = NSTextAlignmentCenter; t.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *m = [UILabel new];
    m.font = [CLTheme bodyFont]; m.textColor = [CLTheme textSecondaryColor];
    m.text = message; m.textAlignment = NSTextAlignmentCenter; m.numberOfLines = 0;
    m.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:t]; [self addSubview:m];
    NSMutableArray *c = @[
        [t.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [m.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [t.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32],
        [t.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32],
        [m.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32],
        [m.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32],
        [m.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:10],
    ].mutableCopy;
    if (actionTitle.length) {
        CLButton *a = [CLButton primaryWithTitle:actionTitle];
        objc_setAssociatedObject(a, "h", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [a addTarget:self action:@selector(run:) forControlEvents:UIControlEventTouchUpInside];
        a.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:a];
        [c addObjectsFromArray:@[
            [a.topAnchor constraintEqualToAnchor:m.bottomAnchor constant:24],
            [a.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        ]];
    }
    [NSLayoutConstraint activateConstraints:c];
    return self;
}
- (void)run:(id)sender {
    void (^h)(void) = objc_getAssociatedObject(sender, "h");
    if (h) h();
}
@end

@implementation CLNoticeView
- (instancetype)initWithMessage:(NSString *)message kind:(NSString *)kind {
    self = [super initWithFrame:CGRectZero];
    UIColor *color = [CLTheme infoColor];
    if ([kind isEqualToString:@"error"]) color = [CLTheme errorColor];
    else if ([kind isEqualToString:@"warning"]) color = [CLTheme warningColor];
    else if ([kind isEqualToString:@"success"]) color = [CLTheme successColor];
    self.backgroundColor = [color colorWithAlphaComponent:0.08];
    self.layer.cornerRadius = [CLTheme radiusMedium];
    UIView *stripe = [UIView new];
    stripe.backgroundColor = color; stripe.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *l = [UILabel new];
    l.font = [CLTheme captionFont]; l.textColor = [CLTheme textPrimaryColor];
    l.text = message; l.numberOfLines = 0; l.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stripe]; [self addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [stripe.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stripe.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [stripe.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        [stripe.widthAnchor constraintEqualToConstant:3],
        [l.leadingAnchor constraintEqualToAnchor:stripe.trailingAnchor constant:12],
        [l.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [l.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [l.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
    ]];
    return self;
}
@end

@implementation CLSkeletonView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [CLTheme surfaceSubtleColor];
    self.layer.cornerRadius = [CLTheme radiusSmall];
    return self;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
        a.fromValue = @1.0; a.toValue = @0.55; a.duration = 1.1;
        a.autoreverses = YES; a.repeatCount = HUGE_VALF;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.layer addAnimation:a forKey:@"shimmer"];
    }
}
@end
