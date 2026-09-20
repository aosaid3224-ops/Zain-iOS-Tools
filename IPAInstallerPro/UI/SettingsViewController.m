//
//  SettingsViewController.m
//  IPAInstallerPro — Design System "Quiet Precision" v2.0
//
//  Structured, grouped, calm. One system, every row.
//

#import "SettingsViewController.h"
#import "CapabilityManager.h"
#import "JBHideViewController.h"
#import "JailbreakEnvironment.h"
#import "IPTheme.h"
#import "IPComponents.h"
#import "RuntimeEnvironment.h"

@interface SettingsViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@end

@implementation SettingsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"الإعدادات";
    self.view.backgroundColor = [IPTheme backgroundColor];
    [self setupUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshData];
}

#pragma mark - UI Setup

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.backgroundColor = UIColor.clearColor;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]
    ]];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 0;
    self.contentStack.alignment = UIStackViewAlignmentFill;
    [self.scrollView addSubview:self.contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:[IPTheme space8]],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:[IPTheme pageMargin]],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-[IPTheme pageMargin]],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-[IPTheme space24]],
        [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor
                                                      constant:-(2 * [IPTheme pageMargin])]
    ]];
}

#pragma mark - Section & Row Builders (Design System)

- (UILabel *)sectionHeaderWithTitle:(NSString *)title {
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.text = title;
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    l.textColor = [IPTheme textTertiaryColor];
    l.textAlignment = NSTextAlignmentRight;
    [l.heightAnchor constraintEqualToConstant:34].active = YES;
    return l;
}

/// Environment info row — quiet key/value, no card.
- (UIView *)infoRowWithIcon:(NSString *)iconName label:(NSString *)label value:(NSString *)value {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = UIColor.clearColor;

    UIImageView *iconView = [UIImageView new];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.image = [UIImage systemImageNamed:iconName];
    iconView.tintColor = [IPTheme textQuaternaryColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [row addSubview:iconView];

    UILabel *labelLbl = [UILabel new];
    labelLbl.translatesAutoresizingMaskIntoConstraints = NO;
    labelLbl.text = label;
    labelLbl.font = [IPTheme captionFont];
    labelLbl.textColor = [IPTheme textSecondaryColor];
    labelLbl.textAlignment = NSTextAlignmentRight;
    [row addSubview:labelLbl];

    UILabel *valueLbl = [UILabel new];
    valueLbl.translatesAutoresizingMaskIntoConstraints = NO;
    valueLbl.text = value.length ? value : @"—";
    valueLbl.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    valueLbl.textColor = [IPTheme textPrimaryColor];
    valueLbl.textAlignment = NSTextAlignmentLeft;
    valueLbl.numberOfLines = 1;
    valueLbl.adjustsFontSizeToFitWidth = YES;
    valueLbl.minimumScaleFactor = 0.7;
    [row addSubview:valueLbl];

    IPHairlineView *sep = [[IPHairlineView alloc] initWithMargins:UIEdgeInsetsZero];

    [row addSubview:sep];
    [NSLayoutConstraint activateConstraints:@[
        [iconView.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:18],
        [iconView.heightAnchor constraintEqualToConstant:18],

        [labelLbl.trailingAnchor constraintEqualToAnchor:iconView.leadingAnchor constant:-[IPTheme space12]],
        [labelLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [valueLbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [valueLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [valueLbl.trailingAnchor constraintLessThanOrEqualToAnchor:labelLbl.leadingAnchor constant:-[IPTheme space12]],

        [sep.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [sep.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],

        [row.heightAnchor constraintEqualToConstant:44]
    ]];
    return row;
}

/// Tool row — status pill (Ready/Unavailable), monospaced path, no dot gimmicks.
- (UIView *)toolRowWithName:(NSString *)name path:(NSString *)path available:(BOOL)available {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = UIColor.clearColor;

    UILabel *nameLbl = [UILabel new];
    nameLbl.translatesAutoresizingMaskIntoConstraints = NO;
    nameLbl.text = name;
    nameLbl.font = [IPTheme headlineFont];
    nameLbl.textColor = [IPTheme textPrimaryColor];
    nameLbl.textAlignment = NSTextAlignmentRight;
    [row addSubview:nameLbl];

    IPStatusPill *pill = [[IPStatusPill alloc] initWithText:(available ? @"جاهز" : @"غير متوفر")
                                                       color:(available ? [IPTheme successColor] : [IPTheme errorColor])];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:pill];

    UILabel *pathLbl = [UILabel new];
    pathLbl.translatesAutoresizingMaskIntoConstraints = NO;
    pathLbl.text = path.length ? path : @"";
    pathLbl.font = [IPTheme monoFont];
    pathLbl.textColor = [IPTheme textQuaternaryColor];
    pathLbl.textAlignment = NSTextAlignmentLeft;
    pathLbl.numberOfLines = 1;
    pathLbl.adjustsFontSizeToFitWidth = YES;
    pathLbl.minimumScaleFactor = 0.7;
    [row addSubview:pathLbl];

    IPHairlineView *sep = [[IPHairlineView alloc] initWithMargins:UIEdgeInsetsZero];
    [row addSubview:sep];

    [NSLayoutConstraint activateConstraints:@[
        [pill.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [pill.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [nameLbl.trailingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:-[IPTheme space12]],
        [nameLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [pathLbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [pathLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [pathLbl.trailingAnchor constraintLessThanOrEqualToAnchor:nameLbl.leadingAnchor constant:-[IPTheme space12]],

        [sep.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [sep.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],

        [row.heightAnchor constraintEqualToConstant:50]
    ]];
    return row;
}

/// Navigation row — chevron, quiet, no card.
- (UIView *)navRowWithIcon:(NSString *)iconName title:(NSString *)title action:(SEL)action {
    IPPressableView *row = [IPPressableView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.pressedHandler = nil;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:action];
    [row addGestureRecognizer:tap];

    UIImageView *iconView = [UIImageView new];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.image = [UIImage systemImageNamed:iconName];
    iconView.tintColor = [IPTheme textSecondaryColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [row addSubview:iconView];

    UILabel *titleLbl = [UILabel new];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titleLbl.text = title;
    titleLbl.font = [IPTheme headlineFont];
    titleLbl.textColor = [IPTheme textPrimaryColor];
    titleLbl.textAlignment = NSTextAlignmentRight;
    [row addSubview:titleLbl];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = [IPTheme textQuaternaryColor];
    [row addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:20],
        [iconView.heightAnchor constraintEqualToConstant:20],

        [titleLbl.trailingAnchor constraintEqualToAnchor:iconView.leadingAnchor constant:-[IPTheme space12]],
        [titleLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [chevron.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [chevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:14],
        [chevron.heightAnchor constraintEqualToConstant:14],

        [row.heightAnchor constraintEqualToConstant:48]
    ]];
    return row;
}

#pragma mark - Data Refresh

- (void)refreshData {
    JailbreakEnvironment *env = [JailbreakEnvironment sharedEnvironment];
    CapabilityManager *cap = [CapabilityManager sharedManager];

    [self clearStack:self.contentStack];

    // ─── البيئة ───
    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"البيئة"]];
    NSDictionary *envItems = @{
        @"حالة الجلبريك": @[env.jailbreakType ?: @"غير معروف", @"checkmark.circle.fill"],
        @"الجهاز": @[env.deviceModel ?: @"غير معروف", @"iphone"],
        @"إصدار iOS": @[env.iosVersion ?: @"غير معروف", @"number.circle.fill"],
        @"المعمارية": @[env.architecture ?: @"غير محدد", @"cpu"],
        @"مسار التطبيقات": @[env.applicationsPath ?: @"غير موقع", @"folder.fill"],
        @"مسار المستندات": @[env.mobileDocumentsPath ?: @"غير موقع", @"doc.fill"],
        @"مسار الروت": @[env.rootPath ?: @"غير موجود", @"number.sign"]
    };
    NSArray *envOrder = @[@"حالة الجلبريك", @"الجهاز", @"إصدار iOS", @"المعمارية",
                          @"مسار التطبيقات", @"مسار المستندات", @"مسار الروت"];
    NSUInteger idx = 0, total = envOrder.count;
    for (NSString *key in envOrder) {
        NSArray *data = envItems[key];
        UIView *row = [self infoRowWithIcon:data[1] label:key value:data[0]];
        if (++idx == total) [self hideSeparatorInRow:row];
        [self.contentStack addArrangedSubview:row];
    }

    // ─── الأدوات ───
    [self.contentStack addArrangedSubview:[self spacerWithHeight:16]];
    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"الأدوات"]];
    NSArray *caps = [cap allCapabilities];
    NSUInteger cIdx = 0, cTotal = caps.count;
    for (Capability *c in caps) {
        UIView *row = [self toolRowWithName:c.name path:c.path available:c.isAvailable];
        if (++cIdx == cTotal) [self hideSeparatorInRow:row];
        [self.contentStack addArrangedSubview:row];
    }

    // ─── الحماية ───
    [self.contentStack addArrangedSubview:[self spacerWithHeight:16]];
    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"الحماية"]];
    [self.contentStack addArrangedSubview:[self navRowWithIcon:@"eye.slash" title:@"إخفاء الجلبريك" action:@selector(openJBHide)]];

    // ─── حول ───
    [self.contentStack addArrangedSubview:[self spacerWithHeight:16]];
    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"حول"]];
    [self.contentStack addArrangedSubview:[self navRowWithIcon:@"info.circle" title:@"حول الأداة" action:@selector(showAbout)]];
}

- (void)hideSeparatorInRow:(UIView *)row {
    for (UIView *sub in row.subviews) {
        if ([sub isKindOfClass:[IPHairlineView class]]) sub.hidden = YES;
    }
}

- (UIView *)spacerWithHeight:(CGFloat)h {
    UIView *v = [UIView new];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [v.heightAnchor constraintEqualToConstant:h].active = YES;
    return v;
}

- (void)clearStack:(UIStackView *)stack {
    for (UIView *v in [stack.arrangedSubviews copy]) {
        [stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
}

#pragma mark - Actions

- (void)openJBHide {
    [self.navigationController pushViewController:[JBHideViewController new] animated:YES];
}

- (void)showAbout {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"حول الأداة"
                         message:@"هذه الأداة متاحة حاليًا كنسخة تجريبية وليست الإصدار النهائي.\n\nإذا واجهت أي خلل أو لديك ملاحظة، نرجو مشاركتها معنا — ملاحظاتك تساعدنا على تحسين الاستقرار قبل الإصدار النهائي.\n\nX: @Zainqkvd"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
