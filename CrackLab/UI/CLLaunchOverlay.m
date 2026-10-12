//
//  CLLaunchOverlay.m
//
//  Full-screen transition shown while a game is being launched from Crack Lab:
//    · dark blur backdrop
//    · game icon (or Crack Lab glyph) with copper glow, pulsing
//    · dashed copper orbit ring, rotating endlessly
//    · brand + status labels
//  Lifecycle: dismisses itself on UIApplicationDidBecomeActiveNotification
//  (user returned to Crack Lab) or on a 4s foreground fallback.
//

#import "CLLaunchOverlay.h"
#import "CLTheme.h"

@interface CLLaunchOverlay ()
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *ringContainer;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) CAShapeLayer *ringLayer;
@property (nonatomic, strong) CAShapeLayer *glowLayer;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *gameLabel;
@property (nonatomic, strong) UILabel *brandLabel;
@property (nonatomic, strong) NSTimer *fallbackTimer;
@end

@implementation CLLaunchOverlay

static CLLaunchOverlay *_shared = nil;

#pragma mark - Presentation

+ (instancetype)presentWithGame:(CLGame *)game {
    if (_shared) [_shared dismissAnimated:NO];

    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (!window) {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (!w.hidden) { window = w; break; }
        }
    }
    if (!window) return nil;

    CLLaunchOverlay *ov = [[CLLaunchOverlay alloc] initWithFrame:window.bounds];
    [window addSubview:ov];
    _shared = ov;

    [ov buildWithGame:game];
    [ov animateIn];
    [ov startMotion];

    [[NSNotificationCenter defaultCenter] addObserver:ov
        selector:@selector(handleDidBecomeActive)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    ov.fallbackTimer = [NSTimer scheduledTimerWithTimeInterval:4.0
        target:ov selector:@selector(handleFallback) userInfo:nil repeats:NO];
    return ov;
}

#pragma mark - Build

- (UIImage *)glyphImageForGame:(CLGame *)game {
    if (game.icon) return game.icon;
    UIImage *appIcon = [UIImage imageNamed:@"AppIcon60x60"];
    if (appIcon) return appIcon;
    return [UIImage systemImageNamed:@"gamecontroller.fill"];
}

- (void)buildWithGame:(CLGame *)game {
    self.backgroundColor = UIColor.clearColor;

    self.blurView = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    self.blurView.translatesAutoresizingMaskIntoConstraints = NO;
    self.blurView.alpha = 0.97;
    [self addSubview:self.blurView];

    // Subtle copper vignette
    UIView *tint = [UIView new];
    tint.translatesAutoresizingMaskIntoConstraints = NO;
    tint.backgroundColor = [CLTheme accentColor];
    tint.alpha = 0.05;
    [self.blurView.contentView addSubview:tint];

    self.cardView = [UIView new];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.cardView];

    // ── Orbit ring + icon ──
    self.ringContainer = [UIView new];
    self.ringContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardView addSubview:self.ringContainer];

    CGFloat ringD = 128.0;
    UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:
        CGRectMake(0, 0, ringD, ringD)];
    self.ringLayer = [CAShapeLayer layer];
    self.ringLayer.path = circle.CGPath;
    self.ringLayer.frame = CGRectMake(0, 0, ringD, ringD);
    self.ringLayer.strokeColor = [CLTheme accentColor].CGColor;
    self.ringLayer.fillColor = UIColor.clearColor;
    self.ringLayer.lineWidth = 2.0;
    self.ringLayer.lineCap = kCALineCapRound;
    self.ringLayer.strokeDashPattern = @[@10, @7];
    [self.ringContainer.layer addSublayer:self.ringLayer];

    // soft glow disc behind the icon
    self.glowLayer = [CAShapeLayer layer];
    UIBezierPath *disc = [UIBezierPath bezierPathWithOvalInRect:
        CGRectMake(19, 19, ringD - 38, ringD - 38)];
    self.glowLayer.path = disc.CGPath;
    self.glowLayer.frame = self.ringLayer.frame;
    self.glowLayer.fillColor = [CLTheme accentColor].CGColor;
    self.glowLayer.opacity = 0.10;
    [self.ringContainer.layer addSublayer:self.glowLayer];

    self.iconView = [UIImageView new];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.image = [self glyphImageForGame:game];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.layer.cornerRadius = 22;
    self.iconView.clipsToBounds = YES;
    self.iconView.backgroundColor = [CLTheme surfaceColor];
    [self.ringContainer addSubview:self.iconView];

    // ── Labels ──
    self.statusLabel = [UILabel new];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = [CLTheme accentColor];
    self.statusLabel.text = @"جارٍ تشغيل اللعبة…";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.cardView addSubview:self.statusLabel];

    self.gameLabel = [UILabel new];
    self.gameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.gameLabel.font = [CLTheme titleFont];
    self.gameLabel.textColor = [CLTheme textPrimaryColor];
    self.gameLabel.text = game.name.length ? game.name : @"";
    self.gameLabel.textAlignment = NSTextAlignmentCenter;
    [self.cardView addSubview:self.gameLabel];

    self.brandLabel = [UILabel new];
    self.brandLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.brandLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.brandLabel.textColor = [CLTheme textQuaternaryColor];
    self.brandLabel.text = @"CRACK LAB";
    self.brandLabel.textAlignment = NSTextAlignmentCenter;
    [self.cardView addSubview:self.brandLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.blurView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.blurView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.blurView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.blurView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [tint.topAnchor constraintEqualToAnchor:self.blurView.contentView.topAnchor],
        [tint.leadingAnchor constraintEqualToAnchor:self.blurView.contentView.leadingAnchor],
        [tint.trailingAnchor constraintEqualToAnchor:self.blurView.contentView.trailingAnchor],
        [tint.bottomAnchor constraintEqualToAnchor:self.blurView.contentView.bottomAnchor],

        [self.cardView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.cardView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-20],

        [self.ringContainer.topAnchor constraintEqualToAnchor:self.cardView.topAnchor],
        [self.ringContainer.centerXAnchor constraintEqualToAnchor:self.cardView.centerXAnchor],
        [self.ringContainer.widthAnchor constraintEqualToConstant:ringD],
        [self.ringContainer.heightAnchor constraintEqualToConstant:ringD],

        [self.iconView.centerXAnchor constraintEqualToAnchor:self.ringContainer.centerXAnchor],
        [self.iconView.centerYAnchor constraintEqualToAnchor:self.ringContainer.centerYAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:88],
        [self.iconView.heightAnchor constraintEqualToConstant:88],

        [self.gameLabel.topAnchor constraintEqualToAnchor:self.ringContainer.bottomAnchor constant:26],
        [self.gameLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor],
        [self.gameLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.gameLabel.bottomAnchor constant:8],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor],

        [self.brandLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:22],
        [self.brandLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor],
        [self.brandLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor],
        [self.cardView.bottomAnchor constraintEqualToAnchor:self.brandLabel.bottomAnchor],
    ]];
}

#pragma mark - Motion

- (void)animateIn {
    self.alpha = 0;
    self.cardView.transform = CGAffineTransformMakeScale(0.82, 0.82);
    [UIView animateWithDuration:[CLTheme durationEmphasis] delay:0
        options:[CLTheme easing] animations:^{
        self.alpha = 1;
        self.cardView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)startMotion {
    // Endless orbit rotation
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @0;
    spin.toValue = @(M_PI * 2);
    spin.duration = 3.2;
    spin.repeatCount = HUGE_VALF;
    [self.ringContainer.layer addAnimation:spin forKey:@"orbit"];

    // Breathing pulse on the icon
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    pulse.fromValue = @1.0;
    pulse.toValue = @1.07;
    pulse.duration = 0.85;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.iconView.layer addAnimation:pulse forKey:@"pulse"];

    // Glow breathing
    CABasicAnimation *glow = [CABasicAnimation animationWithKeyPath:@"opacity"];
    glow.fromValue = @0.10;
    glow.toValue = @0.22;
    glow.duration = 0.85;
    glow.autoreverses = YES;
    glow.repeatCount = HUGE_VALF;
    [self.glowLayer addAnimation:glow forKey:@"glow"];

    // Status label shimmer
    [UIView animateWithDuration:1.1 delay:0
        options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat | UIViewAnimationOptionCurveEaseInOut
        animations:^{ self.statusLabel.alpha = 0.45; } completion:nil];
}

#pragma mark - Dismissal

- (void)handleDidBecomeActive { [self dismiss]; }

- (void)handleFallback {
    // Still foreground after 4s → the launch never took us away; close silently.
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
        [self dismiss];
    }
}

- (void)dismiss { [self dismissAnimated:YES]; }

- (void)dismissAnimated:(BOOL)animated {
    [_fallbackTimer invalidate];
    _fallbackTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:UIApplicationDidBecomeActiveNotification object:nil];
    if (!animated) {
        if (_shared == self) _shared = nil;
        [self removeFromSuperview];
        return;
    }
    [UIView animateWithDuration:[CLTheme durationFast] animations:^{
        self.alpha = 0;
        self.cardView.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        if (_shared == self) _shared = nil;
        [self removeFromSuperview];
    }];
}

@end
