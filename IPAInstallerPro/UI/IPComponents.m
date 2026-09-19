//
//  IPComponents.m
//

#import "IPComponents.h"
#import "IPTheme.h"
#import <objc/runtime.h>

#pragma mark - Hairline

@implementation IPHairlineView {
    UIEdgeInsets _insets;
    UIView *_line;
}

- (instancetype)initWithMargins:(UIEdgeInsets)insets {
    self = [super initWithFrame:CGRectZero];
    _insets = insets;
    _line = [UIView new];
    _line.backgroundColor = [IPTheme separatorColor];
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

#pragma mark - Press feedback

@implementation IPPressableView {
    BOOL _highlighted;
}

- (void)setPressedHandler:(void (^)(void))pressedHandler {
    _pressedHandler = [pressedHandler copy];
    self.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTap:)];
    [self addGestureRecognizer:tap];
}

- (void)didTap:(UITapGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateEnded && self.pressedHandler) self.pressedHandler();
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [self setQuietHighlighted:YES];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [self setQuietHighlighted:NO];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [self setQuietHighlighted:NO];
}

- (void)setQuietHighlighted:(BOOL)on {
    [UIView animateWithDuration:[IPTheme durationFast] delay:0 options:[IPTheme easing] animations:^{
        self.backgroundColor = on ? [IPTheme selectionColor] : UIColor.clearColor;
    } completion:nil];
}

@end

#pragma mark - Status Pill

@implementation IPStatusPill {
    UILabel *_label;
}

- (instancetype)initWithText:(NSString *)text color:(UIColor *)color {
    self = [super initWithFrame:CGRectZero];
    self.statusColor = color;
    self.text = text;
    self.layer.cornerRadius = [IPTheme radiusSmall];
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
- (void)setStatusColor:(UIColor *)statusColor {
    _statusColor = statusColor;
    self.backgroundColor = [statusColor colorWithAlphaComponent:0.14];
    _label.textColor = statusColor;
}

@end

#pragma mark - Buttons

@implementation IPButton

+ (instancetype)baseWithTitle:(NSString *)title {
    IPButton *b = [IPButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    b.layer.cornerRadius = [IPTheme radiusMedium];
    b.clipsToBounds = YES;
    return b;
}

+ (instancetype)primaryWithTitle:(NSString *)title {
    IPButton *b = [self baseWithTitle:title];
    b.backgroundColor = [IPTheme accentColor];
    [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    b.contentEdgeInsets = UIEdgeInsetsMake(11, 20, 11, 20);
    return b;
}

+ (instancetype)secondaryWithTitle:(NSString *)title {
    IPButton *b = [self baseWithTitle:title];
    b.backgroundColor = [IPTheme surfaceSubtleColor];
    [b setTitleColor:[IPTheme textPrimaryColor] forState:UIControlStateNormal];
    b.contentEdgeInsets = UIEdgeInsetsMake(11, 20, 11, 20);
    return b;
}

+ (instancetype)destructiveWithTitle:(NSString *)title {
    IPButton *b = [self baseWithTitle:title];
    b.backgroundColor = [IPTheme errorColor];
    [b setTitleColor:[IPTheme textPrimaryColor] forState:UIControlStateNormal];
    b.contentEdgeInsets = UIEdgeInsetsMake(11, 20, 11, 20);
    return b;
}

+ (instancetype)tertiaryWithTitle:(NSString *)title {
    IPButton *b = [self baseWithTitle:title];
    b.backgroundColor = UIColor.clearColor;
    [b setTitleColor:[IPTheme textSecondaryColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    b.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
    return b;
}

+ (instancetype)inlineWithTitle:(NSString *)title {
    IPButton *b = [self baseWithTitle:title];
    b.backgroundColor = UIColor.clearColor;
    [b setTitleColor:[IPTheme accentColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    b.contentEdgeInsets = UIEdgeInsetsMake(6, 8, 6, 8);
    return b;
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1.0 : 0.45;
}

@end

#pragma mark - List Row

@implementation IPListRow {
    UIView *_accessory;
    IPHairlineView *_separator;
    NSLayoutConstraint *_metadataTrailingConstraint;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = UIColor.clearColor;

    _iconView = [UIImageView new];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.layer.cornerRadius = [IPTheme radiusIcon];
    _iconView.clipsToBounds = YES;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [UILabel new];
    _titleLabel.font = [IPTheme headlineFont];
    _titleLabel.textColor = [IPTheme textPrimaryColor];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _subtitleLabel = [UILabel new];
    _subtitleLabel.font = [IPTheme captionFont];
    _subtitleLabel.textColor = [IPTheme textSecondaryColor];
    _subtitleLabel.numberOfLines = 1;
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _metadataLabel = [UILabel new];
    _metadataLabel.font = [IPTheme monoFont];
    _metadataLabel.textColor = [IPTheme textQuaternaryColor];
    _metadataLabel.textAlignment = NSTextAlignmentRight;
    _metadataLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _disclosureView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]];
    _disclosureView.tintColor = [IPTheme textQuaternaryColor];
    _disclosureView.translatesAutoresizingMaskIntoConstraints = NO;

    _separator = [[IPHairlineView alloc] initWithMargins:UIEdgeInsetsMake(0, 68, 0, 0)];
    _separator.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:_iconView];
    [self addSubview:_titleLabel];
    [self addSubview:_subtitleLabel];
    [self addSubview:_metadataLabel];
    [self addSubview:_disclosureView];
    [self addSubview:_separator];

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:44],
        [_iconView.heightAnchor constraintEqualToConstant:44],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:16],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_metadataLabel.leadingAnchor constant:-8],

        (_metadataTrailingConstraint = [_metadataLabel.trailingAnchor constraintEqualToAnchor:_disclosureView.leadingAnchor constant:-8]),
        [_metadataLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_disclosureView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_disclosureView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_disclosureView.widthAnchor constraintEqualToConstant:14],
        [_disclosureView.heightAnchor constraintEqualToConstant:14],

        [_separator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_separator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_separator.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [self.heightAnchor constraintGreaterThanOrEqualToConstant:72],
    ]];

    _showsSeparator = YES;
    return self;
}

- (void)setAccessoryView:(UIView *)accessory {
    [_accessory removeFromSuperview];
    _accessory = accessory;
    if (!accessory) return;
    accessory.translatesAutoresizingMaskIntoConstraints = NO;
    _disclosureView.hidden = YES;
    [self addSubview:accessory];
    [NSLayoutConstraint activateConstraints:@[
        [accessory.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [accessory.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    [NSLayoutConstraint deactivateConstraints:@[_metadataTrailingConstraint]];
    [NSLayoutConstraint activateConstraints:@[
        [self.metadataLabel.trailingAnchor constraintEqualToAnchor:accessory.leadingAnchor constant:-8]
    ]];
}

- (void)setShowsSeparator:(BOOL)showsSeparator {
    _showsSeparator = showsSeparator;
    _separator.hidden = !showsSeparator;
}

@end

#pragma mark - Empty State

@implementation IPEmptyStateView {
    UILabel *_title;
    UILabel *_message;
    IPButton *_action;
}

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
                  actionTitle:(NSString *)actionTitle
                      handler:(void (^)(void))handler {
    self = [super initWithFrame:CGRectZero];
    self.backgroundColor = UIColor.clearColor;

    _title = [UILabel new];
    _title.font = [IPTheme titleFont];
    _title.textColor = [IPTheme textPrimaryColor];
    _title.text = title;
    _title.textAlignment = NSTextAlignmentCenter;
    _title.translatesAutoresizingMaskIntoConstraints = NO;

    _message = [UILabel new];
    _message.font = [IPTheme bodyFont];
    _message.textColor = [IPTheme textSecondaryColor];
    _message.text = message;
    _message.textAlignment = NSTextAlignmentCenter;
    _message.numberOfLines = 0;
    _message.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:_title];
    [self addSubview:_message];

    NSMutableArray *constraints = @[
        [_title.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_message.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32],
        [_title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32],
        [_message.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32],
        [_message.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32],
        [_message.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:10],
    ].mutableCopy;

    if (actionTitle.length) {
        _action = [IPButton primaryWithTitle:actionTitle];
        [_action addTarget:self action:@selector(runHandler:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(self, "handler", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
        _action.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_action];
        [constraints addObjectsFromArray:@[
            [_action.topAnchor constraintEqualToAnchor:_message.bottomAnchor constant:24],
            [_action.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        ]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    return self;
}

- (void)runHandler:(id)sender {
    void (^h)(void) = objc_getAssociatedObject(self, "handler");
    if (h) h();
}

@end

#pragma mark - Notice

@implementation IPNoticeView {
    UILabel *_label;
    UIView *_stripe;
}

- (instancetype)initWithMessage:(NSString *)message kind:(NSString *)kind {
    self = [super initWithFrame:CGRectZero];
    UIColor *color = [IPTheme infoColor];
    if ([kind isEqualToString:@"error"]) color = [IPTheme errorColor];
    else if ([kind isEqualToString:@"warning"]) color = [IPTheme warningColor];
    else if ([kind isEqualToString:@"success"]) color = [IPTheme successColor];

    self.backgroundColor = [color colorWithAlphaComponent:0.08];
    self.layer.cornerRadius = [IPTheme radiusMedium];

    _stripe = [UIView new];
    _stripe.backgroundColor = color;
    _stripe.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_stripe];

    _label = [UILabel new];
    _label.font = [IPTheme captionFont];
    _label.textColor = [IPTheme textPrimaryColor];
    _label.text = message;
    _label.numberOfLines = 0;
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_label];

    [NSLayoutConstraint activateConstraints:@[
        [_stripe.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_stripe.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [_stripe.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        [_stripe.widthAnchor constraintEqualToConstant:3],

        [_label.leadingAnchor constraintEqualToAnchor:_stripe.trailingAnchor constant:12],
        [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [_label.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
    ]];
    return self;
}

@end

#pragma mark - Skeleton

@implementation IPSkeletonView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [IPTheme surfaceSubtleColor];
    self.cornerRadius = [IPTheme radiusSmall];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self startShimmer];
}

- (void)startShimmer {
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
    a.fromValue = @1.0; a.toValue = @0.55;
    a.duration = 1.1; a.autoreverses = YES; a.repeatCount = HUGE_VALF;
    a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:a forKey:@"shimmer"];
}

@end
