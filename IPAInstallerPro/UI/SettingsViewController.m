//
//  SettingsViewController.m
//  IPAInstallerPro — Edge-to-Edge Settings UI
//

#import "SettingsViewController.h"
#import "CapabilityManager.h"
#import "JBHideViewController.h"
#import "JailbreakEnvironment.h"
#import "IPTheme.h"
#import "RuntimeEnvironment.h"
#import <objc/runtime.h>

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
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.showsVerticalScrollIndicator = NO;
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
        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor]
    ]];
}

#pragma mark - Row Builders

- (UIView *)infoRowWithIcon:(NSString *)iconName label:(NSString *)label value:(NSString *)value {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [UIColor clearColor];

    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.image = [UIImage systemImageNamed:iconName];
    iconView.tintColor = [UIColor colorWithWhite:0.55 alpha:1];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [row addSubview:iconView];

    UILabel *labelLbl = [[UILabel alloc] init];
    labelLbl.translatesAutoresizingMaskIntoConstraints = NO;
    labelLbl.text = label;
    labelLbl.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    labelLbl.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    labelLbl.textAlignment = NSTextAlignmentRight;
    [row addSubview:labelLbl];

    UILabel *valueLbl = [[UILabel alloc] init];
    valueLbl.translatesAutoresizingMaskIntoConstraints = NO;
    valueLbl.text = value ?: @"—";
    valueLbl.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    valueLbl.textColor = [UIColor whiteColor];
    valueLbl.textAlignment = NSTextAlignmentLeft;
    valueLbl.numberOfLines = 1;
    valueLbl.adjustsFontSizeToFitWidth = YES;
    valueLbl.minimumScaleFactor = 0.75;
    [row addSubview:valueLbl];

    UIView *sep = [[UIView alloc] init];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.backgroundColor = [IPTheme dividerColor];
    [row addSubview:sep];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-20],
        [iconView.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:20],
        [iconView.heightAnchor constraintEqualToConstant:20],

        [labelLbl.trailingAnchor constraintEqualToAnchor:iconView.leadingAnchor constant:-10],
        [labelLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [valueLbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:20],
        [valueLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [valueLbl.trailingAnchor constraintLessThanOrEqualToAnchor:labelLbl.leadingAnchor constant:-10],

        [sep.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:20],
        [sep.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-20],
        [sep.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [sep.heightAnchor constraintEqualToConstant:0.5],

        [row.heightAnchor constraintEqualToConstant:48]
    ]];

    return row;
}

- (UIView *)toolRowWithName:(NSString *)name path:(NSString *)path available:(BOOL)available {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [UIColor clearColor];

    UIView *dot = [[UIView alloc] init];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.backgroundColor = available
        ? [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0]
        : [UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:1.0];
    dot.layer.cornerRadius = 5;
    [row addSubview:dot];

    UILabel *nameLbl = [[UILabel alloc] init];
    nameLbl.translatesAutoresizingMaskIntoConstraints = NO;
    nameLbl.text = name;
    nameLbl.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    nameLbl.textColor = [UIColor whiteColor];
    nameLbl.textAlignment = NSTextAlignmentRight;
    [row addSubview:nameLbl];

    UILabel *statusLbl = [[UILabel alloc] init];
    statusLbl.translatesAutoresizingMaskIntoConstraints = NO;
    statusLbl.text = available ? @"متوفر" : @"غير متوفر";
    statusLbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    statusLbl.textColor = available
        ? [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0]
        : [UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:1.0];
    statusLbl.textAlignment = NSTextAlignmentRight;
    [row addSubview:statusLbl];

    UILabel *pathLbl = [[UILabel alloc] init];
    pathLbl.translatesAutoresizingMaskIntoConstraints = NO;
    pathLbl.text = path ?: @"";
    pathLbl.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    pathLbl.textColor = [UIColor colorWithWhite:0.4 alpha:1];
    pathLbl.textAlignment = NSTextAlignmentLeft;
    pathLbl.numberOfLines = 1;
    pathLbl.adjustsFontSizeToFitWidth = YES;
    pathLbl.minimumScaleFactor = 0.7;
    [row addSubview:pathLbl];

    UIView *sep = [[UIView alloc] init];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.backgroundColor = [IPTheme dividerColor];
    [row addSubview:sep];

    [NSLayoutConstraint activateConstraints:@[
        [dot.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-20],
        [dot.topAnchor constraintEqualToAnchor:row.topAnchor constant:14],
        [dot.widthAnchor constraintEqualToConstant:10],
        [dot.heightAnchor constraintEqualToConstant:10],

        [nameLbl.trailingAnchor constraintEqualToAnchor:dot.leadingAnchor constant:-10],
        [nameLbl.topAnchor constraintEqualToAnchor:row.topAnchor constant:10],

        [statusLbl.trailingAnchor constraintEqualToAnchor:nameLbl.trailingAnchor],
        [statusLbl.topAnchor constraintEqualToAnchor:nameLbl.bottomAnchor constant:2],
        [statusLbl.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-10],

        [pathLbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:20],
        [pathLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [pathLbl.trailingAnchor constraintLessThanOrEqualToAnchor:nameLbl.leadingAnchor constant:-10],

        [sep.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:20],
        [sep.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-20],
        [sep.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [sep.heightAnchor constraintEqualToConstant:0.5],

        [row.heightAnchor constraintEqualToConstant:54]
    ]];

    return row;
}

- (UIView *)jbHideRow {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [UIColor clearColor];
    row.userInteractionEnabled = YES;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openJBHide)];
    [row addGestureRecognizer:tap];

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titleLbl.text = @"إخفاء الجلبريك";
    titleLbl.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    titleLbl.textColor = [UIColor whiteColor];
    titleLbl.textAlignment = NSTextAlignmentRight;
    [row addSubview:titleLbl];

    UIImageView *chevron = [[UIImageView alloc] init];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.image = [UIImage systemImageNamed:@"eye.slash"];
    chevron.tintColor = [UIColor whiteColor];
    [row addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [chevron.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [chevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:22],
        [chevron.heightAnchor constraintEqualToConstant:22],
        [titleLbl.leadingAnchor constraintEqualToAnchor:chevron.trailingAnchor constant:12],
        [titleLbl.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [titleLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintEqualToConstant:44]
    ]];
    return row;
}

- (void)openJBHide {
    [self.navigationController pushViewController:[JBHideViewController new] animated:YES];
}

- (UIView *)aboutRow {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [UIColor clearColor];
    row.userInteractionEnabled = YES;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showAbout)];
    [row addGestureRecognizer:tap];

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titleLbl.text = @"حول الأداة";
    titleLbl.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    titleLbl.textColor = [UIColor whiteColor];
    titleLbl.textAlignment = NSTextAlignmentRight;
    [row addSubview:titleLbl];

    UIImageView *chevron = [[UIImageView alloc] init];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.image = [UIImage systemImageNamed:@"chevron.left"];
    chevron.tintColor = [UIColor colorWithWhite:0.35 alpha:1];
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    [row addSubview:chevron];

    UIView *sep = [[UIView alloc] init];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.backgroundColor = [IPTheme dividerColor];
    [row addSubview:sep];

    [NSLayoutConstraint activateConstraints:@[
        [chevron.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-20],
        [chevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:14],
        [chevron.heightAnchor constraintEqualToConstant:14],

        [titleLbl.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-10],
        [titleLbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:20],
        [titleLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [sep.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:20],
        [sep.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-20],
        [sep.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [sep.heightAnchor constraintEqualToConstant:0.5],

        [row.heightAnchor constraintEqualToConstant:50]
    ]];

    return row;
}

- (UIView *)sectionDivider {
    UIView *v = [[UIView alloc] init];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.backgroundColor = [UIColor clearColor];

    UIView *line = [[UIView alloc] init];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.8];
    [v addSubview:line];

    [NSLayoutConstraint activateConstraints:@[
        [line.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:20],
        [line.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-20],
        [line.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
        [line.heightAnchor constraintEqualToConstant:1],
        [v.heightAnchor constraintEqualToConstant:24]
    ]];

    return v;
}

#pragma mark - Data Refresh

- (void)refreshData {
    JailbreakEnvironment *env = [JailbreakEnvironment sharedEnvironment];
    CapabilityManager *cap = [CapabilityManager sharedManager];

    [self clearStack:self.contentStack];

    // ─── Environment Rows ───
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

    for (NSString *key in envOrder) {
        NSArray *data = envItems[key];
        UIView *row = [self infoRowWithIcon:data[1] label:key value:data[0]];
        [self.contentStack addArrangedSubview:row];
    }

    // Divider
    [self.contentStack addArrangedSubview:[self sectionDivider]];

    // ─── Tool Rows ───
    for (Capability *c in [cap allCapabilities]) {
        UIView *row = [self toolRowWithName:c.name path:c.path available:c.isAvailable];
        [self.contentStack addArrangedSubview:row];
    }

    // ─── Jailbreak Hiding ───
    [self.contentStack addArrangedSubview:[self sectionDivider]];
    [self.contentStack addArrangedSubview:[self jbHideRow]];

    // ─── About ───
    [self.contentStack addArrangedSubview:[self sectionDivider]];
    [self.contentStack addArrangedSubview:[self aboutRow]];
}

- (void)clearStack:(UIStackView *)stack {
    NSArray *views = [stack.arrangedSubviews copy];
    for (UIView *v in views) {
        [stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
}

#pragma mark - Actions

- (void)showAbout {
    NSString *message = @"هذه الأداة متاحة حاليًا كنسخة تجريبية وليست الإصدار النهائي.\n\nقد تواجه بعض الأخطاء أو المشاكل أثناء الاستخدام، ونهدف من خلال هذه المرحلة إلى اختبار الأداة وتحسين استقرارها وتطوير ميزاتها.\n\nإذا واجهت أي خلل، أو لديك ملاحظة أو اقتراح لتحسين الأداة، نرجو منك مشاركة تجربتك معنا. ملاحظاتك تساعدنا على اكتشاف المشاكل ومعالجتها قبل إطلاق الإصدار النهائي.\n\nللتواصل والإبلاغ عن المشاكل:\nX: @Zainqkvd";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"حول الأداة" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
