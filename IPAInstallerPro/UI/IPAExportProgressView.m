#import "IPAExportProgressView.h"
#import "IPTheme.h"

@interface IPAExportProgressView ()
@property (nonatomic, strong, readwrite) UILabel *stageLabel;
@property (nonatomic, strong, readwrite) UILabel *detailLabel;
@property (nonatomic, strong, readwrite) UILabel *statsLabel;
@property (nonatomic, strong, readwrite) UIProgressView *progressBar;
@property (nonatomic, strong, readwrite) UIImageView *appIconView;
@property (nonatomic, strong, readwrite) UILabel *appNameLabel;
@property (nonatomic, strong, readwrite) UIButton *closeButton;
@property (nonatomic, strong, readwrite) UIView *cardView;
@property (nonatomic, strong) UIView *backdropView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSDate *startTime;
@property (nonatomic, strong) NSTimer *statsTimer;
@end

@implementation IPAExportProgressView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
        self.startTime = [NSDate date];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = UIColor.clearColor;

    // Backdrop
    self.backdropView = [[UIView alloc] init];
    self.backdropView.translatesAutoresizingMaskIntoConstraints = NO;
    self.backdropView.backgroundColor = [IPTheme backgroundColor];
    self.backdropView.alpha = 0;
    [self addSubview:self.backdropView];

    // Card
    self.cardView = [[UIView alloc] init];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.backgroundColor = [IPTheme surfaceColor];
    self.cardView.layer.cornerRadius = 24;
    self.cardView.layer.borderWidth = 1;
    self.cardView.layer.borderColor = [[IPTheme textPrimaryColor] colorWithAlphaComponent:0.08].CGColor;
    self.cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 12);
    self.cardView.layer.shadowRadius = 24;
    self.cardView.layer.shadowOpacity = 0.5;
    self.cardView.alpha = 0;
    self.cardView.transform = CGAffineTransformMakeScale(0.85, 0.85);
    [self addSubview:self.cardView];

    // App Icon
    self.appIconView = [[UIImageView alloc] init];
    self.appIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.appIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.appIconView.layer.cornerRadius = 16;
    self.appIconView.clipsToBounds = YES;
    self.appIconView.backgroundColor = [IPTheme textPrimaryColor];
    [self.cardView addSubview:self.appIconView];

    // App Name
    self.appNameLabel = [[UILabel alloc] init];
    self.appNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.appNameLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.appNameLabel.textColor = UIColor.whiteColor;
    self.appNameLabel.textAlignment = NSTextAlignmentCenter;
    self.appNameLabel.numberOfLines = 1;
    [self.cardView addSubview:self.appNameLabel];

    // Stage Label
    self.stageLabel = [[UILabel alloc] init];
    self.stageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stageLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    self.stageLabel.textColor = [IPTheme errorColor];
    self.stageLabel.textAlignment = NSTextAlignmentCenter;
    self.stageLabel.text = @"جارٍ التحضير...";
    [self.cardView addSubview:self.stageLabel];

    // Detail Label
    self.detailLabel = [[UILabel alloc] init];
    self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.detailLabel.textColor = [IPTheme textSecondaryColor];
    self.detailLabel.textAlignment = NSTextAlignmentCenter;
    self.detailLabel.numberOfLines = 2;
    [self.cardView addSubview:self.detailLabel];

    // Progress Bar
    self.progressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressBar.progressTintColor = [IPTheme errorColor];
    self.progressBar.trackTintColor = [IPTheme textPrimaryColor];
    self.progressBar.layer.cornerRadius = 3;
    self.progressBar.clipsToBounds = YES;
    self.progressBar.progress = 0.0;
    [self.cardView addSubview:self.progressBar];

    // Stats Label
    self.statsLabel = [[UILabel alloc] init];
    self.statsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statsLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.statsLabel.textColor = [IPTheme textTertiaryColor];
    self.statsLabel.textAlignment = NSTextAlignmentCenter;
    self.statsLabel.text = @"";
    [self.cardView addSubview:self.statsLabel];

    // Spinner
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = [IPTheme errorColor];
    self.spinner.hidesWhenStopped = YES;
    [self.cardView addSubview:self.spinner];
    [self.spinner startAnimating];

    // Close Button (hidden by default, shown on completion)
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.closeButton.backgroundColor = [IPTheme errorColor];
    self.closeButton.tintColor = UIColor.whiteColor;
    self.closeButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    [self.closeButton setTitle:@"إغلاق" forState:UIControlStateNormal];
    self.closeButton.layer.cornerRadius = 14;
    self.closeButton.hidden = YES;
    [self.closeButton addTarget:self action:@selector(dismissTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.closeButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.backdropView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.backdropView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.backdropView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.backdropView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [self.cardView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.cardView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.cardView.widthAnchor constraintEqualToConstant:300],
        [self.cardView.heightAnchor constraintGreaterThanOrEqualToConstant:340],

        [self.appIconView.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:28],
        [self.appIconView.centerXAnchor constraintEqualToAnchor:self.cardView.centerXAnchor],
        [self.appIconView.widthAnchor constraintEqualToConstant:64],
        [self.appIconView.heightAnchor constraintEqualToConstant:64],

        [self.appNameLabel.topAnchor constraintEqualToAnchor:self.appIconView.bottomAnchor constant:12],
        [self.appNameLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.appNameLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],

        [self.stageLabel.topAnchor constraintEqualToAnchor:self.appNameLabel.bottomAnchor constant:20],
        [self.stageLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.stageLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],

        [self.detailLabel.topAnchor constraintEqualToAnchor:self.stageLabel.bottomAnchor constant:6],
        [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],

        [self.progressBar.topAnchor constraintEqualToAnchor:self.detailLabel.bottomAnchor constant:18],
        [self.progressBar.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:24],
        [self.progressBar.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-24],
        [self.progressBar.heightAnchor constraintEqualToConstant:6],

        [self.statsLabel.topAnchor constraintEqualToAnchor:self.progressBar.bottomAnchor constant:10],
        [self.statsLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.statsLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],

        [self.spinner.topAnchor constraintEqualToAnchor:self.statsLabel.bottomAnchor constant:14],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.cardView.centerXAnchor],

        [self.closeButton.topAnchor constraintEqualToAnchor:self.spinner.bottomAnchor constant:16],
        [self.closeButton.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:24],
        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-24],
        [self.closeButton.heightAnchor constraintEqualToConstant:46],
        [self.closeButton.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-24]
    ]];
}

- (void)showInView:(UIView *)view animated:(BOOL)animated {
    self.frame = view.bounds;
    [view addSubview:self];

    if (animated) {
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.backdropView.alpha = 1.0;
            self.cardView.alpha = 1.0;
            self.cardView.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        self.backdropView.alpha = 1.0;
        self.cardView.alpha = 1.0;
        self.cardView.transform = CGAffineTransformIdentity;
    }

    // Start stats timer
    self.statsTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateElapsedTime) userInfo:nil repeats:YES];
}

- (void)dismissWithCompletion:(void (^)(void))completion {
    [self.statsTimer invalidate];
    self.statsTimer = nil;

    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.backdropView.alpha = 0.0;
        self.cardView.alpha = 0.0;
        self.cardView.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (completion) completion();
    }];
}

- (void)dismissTapped:(id)sender {
    [self dismissWithCompletion:nil];
}

- (void)setStage:(NSString *)stage detail:(NSString *)detail progress:(CGFloat)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.stageLabel.text = stage ?: @"";
        self.detailLabel.text = detail ?: @"";
        [self.progressBar setProgress:MAX(0.0, MIN(1.0, progress)) animated:YES];
    });
}

- (void)setStats:(NSString *)stats {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statsLabel.text = stats ?: @"";
    });
}

- (void)setAppIcon:(UIImage *)icon name:(NSString *)name {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.appIconView.image = icon;
        self.appNameLabel.text = name ?: @"";
    });
}

- (void)updateElapsedTime {
    NSTimeInterval elapsed = -[self.startTime timeIntervalSinceNow];
    NSString *timeStr = [NSString stringWithFormat:@"%.1f ث", elapsed];
    NSString *currentStats = self.statsLabel.text ?: @"";
    if ([currentStats containsString:@"•"]) {
        NSArray *parts = [currentStats componentsSeparatedByString:@"•"];
        if (parts.count >= 2) {
            self.statsLabel.text = [NSString stringWithFormat:@"%@ • %@", [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]], timeStr];
            return;
        }
    }
    self.statsLabel.text = [NSString stringWithFormat:@"الوقت: %@", timeStr];
}

- (void)markCompletedWithSuccess:(BOOL)success message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.statsTimer invalidate];
        self.statsTimer = nil;
        [self.spinner stopAnimating];
        self.stageLabel.text = success ? @"تم الاستخراج بنجاح" : @"فشل الاستخراج";
        self.stageLabel.textColor = success ? [IPTheme successColor] : [IPTheme errorColor];
        self.detailLabel.text = message ?: @"";
        self.progressBar.progressTintColor = success ? [IPTheme successColor] : [IPTheme errorColor];
        [self.progressBar setProgress:1.0 animated:YES];
        self.closeButton.hidden = NO;
    });
}

@end
