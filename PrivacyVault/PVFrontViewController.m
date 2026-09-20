#import "PVFrontViewController.h"
#import "PVSettingsViewController.h"
#import "PVEntryViewController.h"

@interface PVFrontViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *lastCheckLabel;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@end

@implementation PVFrontViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"الجهاز";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIBarButtonItem *settingsItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"] style:UIBarButtonItemStylePlain target:self action:@selector(settingsTapped:)];
    settingsItem.accessibilityLabel = @"الإعدادات";
    self.navigationItem.rightBarButtonItem = settingsItem;

    [self buildInterface];
    [self installEntryGesture];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refreshFrontStateAnimated:NO];
}

- (void)buildInterface {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 16.0;
    self.contentStack.alignment = UIStackViewAlignmentFill;
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:16.0],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:20.0],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-20.0],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-28.0]
    ]];

    [self.contentStack addArrangedSubview:[self makeWelcomeView]];
    [self.contentStack addArrangedSubview:[self makeStatusCard]];
    [self.contentStack addArrangedSubview:[self makeUpdatesCard]];
    [self.contentStack addArrangedSubview:[self makeSupportCard]];
}

- (UIView *)makeWelcomeView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [self labelWithText:@"اخر التحديثات" font:[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2] color:[UIColor labelColor]];
    title.textAlignment = NSTextAlignmentRight;
    UILabel *subtitle = [self labelWithText:@"حاله التحديث الحالي" font:[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline] color:[UIColor secondaryLabelColor]];
    subtitle.textAlignment = NSTextAlignmentRight;
    [container addSubview:title];
    [container addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [container.heightAnchor constraintGreaterThanOrEqualToConstant:66.0],
        [title.topAnchor constraintEqualToAnchor:container.topAnchor],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:5.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [subtitle.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
    ]];
    return container;
}

- (UIView *)makeStatusCard {
    UIView *card = [self cardView];
    UILabel *title = [self labelWithText:@"iphone xs" font:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] color:[UIColor labelColor]];
    title.textAlignment = NSTextAlignmentRight;

    UIView *statusDot = [[UIView alloc] init];
    statusDot.backgroundColor = [UIColor systemGreenColor];
    statusDot.layer.cornerRadius = 5.0;
    statusDot.translatesAutoresizingMaskIntoConstraints = NO;

    self.statusLabel = [self labelWithText:@"يعمل بشكل طبيعي" font:[UIFont preferredFontForTextStyle:UIFontTextStyleBody] color:[UIColor secondaryLabelColor]];
    self.statusLabel.textAlignment = NSTextAlignmentRight;
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.hidesWhenStopped = YES;
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusLabel, statusDot, self.activityIndicator]];
    line.axis = UILayoutConstraintAxisHorizontal;
    line.alignment = UIStackViewAlignmentCenter;
    line.spacing = 8.0;
    line.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    line.translatesAutoresizingMaskIntoConstraints = NO;

    [card addSubview:title];
    [card addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:18.0],
        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18.0],
        [line.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10.0],
        [line.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0],
        [line.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18.0],
        [line.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18.0],
        [statusDot.widthAnchor constraintEqualToConstant:10.0],
        [statusDot.heightAnchor constraintEqualToConstant:10.0]
    ]];
    return card;
}

- (UIView *)makeUpdatesCard {
    UIView *card = [self cardView];
    UILabel *title = [self labelWithText:@"آخر المستجدات"  font:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] color:[UIColor labelColor]];
    title.textAlignment = NSTextAlignmentRight;

    UIImageView *checkmark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
    checkmark.tintColor = [UIColor systemGreenColor];
    checkmark.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *message = [self labelWithText:@"اخر تحديث متاح  18.7.1" font:[UIFont preferredFontForTextStyle:UIFontTextStyleBody] color:[UIColor secondaryLabelColor]];
    message.textAlignment = NSTextAlignmentRight;
    message.numberOfLines = 0;

    self.lastCheckLabel = [self labelWithText:@"آخر فحص: تم" font:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote] color:[UIColor tertiaryLabelColor]];
    self.lastCheckLabel.textAlignment = NSTextAlignmentRight;
    self.lastCheckLabel.userInteractionEnabled = YES;

    [card addSubview:title];
    [card addSubview:checkmark];
    [card addSubview:message];
    [card addSubview:self.lastCheckLabel];
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:18.0],
        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18.0],
        [checkmark.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0],
        [checkmark.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [checkmark.widthAnchor constraintEqualToConstant:22.0],
        [checkmark.heightAnchor constraintEqualToConstant:22.0],
        [message.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12.0],
        [message.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0],
        [message.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18.0],
        [self.lastCheckLabel.topAnchor constraintEqualToAnchor:message.bottomAnchor constant:9.0],
        [self.lastCheckLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0],
        [self.lastCheckLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18.0],
        [self.lastCheckLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18.0]
    ]];
    return card;
}

- (UIView *)makeSupportCard {
    UIView *card = [self cardView];
    UILabel *title = [self labelWithText:@"الوصول السريع" font:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] color:[UIColor labelColor]];
    title.textAlignment = NSTextAlignmentRight;
    UIButton *settingsButton = [self actionButtonWithTitle:@"الإعدادات" imageName:@"gearshape" action:@selector(settingsTapped:)];
    UIButton *helpButton = [self actionButtonWithTitle:@"المساعدة" imageName:@"questionmark.circle" action:@selector(helpTapped:)];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[settingsButton, helpButton]];
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.distribution = UIStackViewDistributionFillEqually;
    actions.spacing = 12.0;
    actions.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    actions.translatesAutoresizingMaskIntoConstraints = NO;

    [card addSubview:title];
    [card addSubview:actions];
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:18.0],
        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18.0],
        [actions.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14.0],
        [actions.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0],
        [actions.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18.0],
        [actions.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18.0],
        [actions.heightAnchor constraintEqualToConstant:46.0]
    ]];
    return card;
}

- (UIView *)cardView {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 18.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    return card;
}

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (UIButton *)actionButtonWithTitle:(NSString *)title imageName:(NSString *)imageName action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:imageName] forState:UIControlStateNormal];
    button.imageEdgeInsets = UIEdgeInsetsMake(0.0, 0.0, 0.0, 7.0);
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)installEntryGesture {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleEntryGesture:)];
    longPress.minimumPressDuration = 5.0;
    longPress.allowableMovement = 12.0;
    [self.lastCheckLabel addGestureRecognizer:longPress];
}

- (void)handleEntryGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
    }
    PVEntryViewController *entry = [[PVEntryViewController alloc] init];
    [entry beginAuthenticationFromNavigationController:self.navigationController];
}

- (void)settingsTapped:(id)sender {
    PVSettingsViewController *settings = [[PVSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [self.navigationController pushViewController:settings animated:YES];
}

- (void)helpTapped:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"المساعدة" message:@"الادة مخصصة لاجهزة ios يمكنك متابعة التحديثات الجديده في اي وقت." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshFrontStateAnimated:(BOOL)animated {
    void (^update)(void) = ^{
        [self.activityIndicator stopAnimating];
        self.statusLabel.text = @"يعمل بشكل طبيعي";
        self.lastCheckLabel.text = @"آخر فحص: تم";
    };
    [self.activityIndicator startAnimating];
    if (animated) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), update);
    } else {
        update();
    }
}

@end
