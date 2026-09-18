//
//  IPAInstallViewController.m
//  IPAInstallerPro — Commit 2: Adaptive layout for all iOS versions
//
//  FIXES:
//  1. Replaced fixed-frame layout in viewDidLoad with layoutSubviews recalculation.
//     On iOS 16+ view bounds are not final in viewDidLoad (Dynamic Island, rotation, multitasking).
//  2. Wrapped content in UIScrollView to prevent clipping on small screens (iPhone SE, iOS 16).
//  3. All labels now use autoresizingMask for width flexibility.
//  4. Safe-area insets respected for notched devices.
//

#import "IPAInstallViewController.h"
#import "InstallationProgressViewController.h"
#import "Core/InstallationEngine.h"
#import "Core/CapabilityManager.h"
#import "Core/Logger.h"
#import "Core/IPAValidator.h"
#import "Core/IPAMultiInstancePreparer.h"
#import "IPTheme.h"

@interface IPAInstallViewController ()
@property (nonatomic, strong) IPAExtractedInfo *ipaInfo;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIView *detailsContainer;
@property (nonatomic, strong) UIButton *installButton;
@property (nonatomic, strong) UILabel *validationLabel;
@property (nonatomic, strong) UIActivityIndicatorView *validationSpinner;
@property (nonatomic, assign) BOOL isValidated;
@property (nonatomic, assign) BOOL isValid;
@property (nonatomic, strong) UISwitch *multiInstanceSwitch;
@property (nonatomic, strong) UILabel *multiInstanceLabel;
@property (nonatomic, strong) NSMutableArray<UILabel *> *detailValueLabels;
@end

@implementation IPAInstallViewController

- (instancetype)initWithIPAInfo:(IPAExtractedInfo *)info {
    self = [super init];
    if (self) {
        _ipaInfo = info;
        _detailValueLabels = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"تثبيت IPA";
    self.view.backgroundColor = [IPTheme backgroundColor];
    [self setupViews];
    [self validateIPA];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutContent];
}

- (void)setupViews {
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.showsVerticalScrollIndicator = YES;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] initWithFrame:self.scrollView.bounds];
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scrollView addSubview:self.contentView];

    self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.iconView.layer.cornerRadius = 20;
    self.iconView.layer.masksToBounds = YES;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.backgroundColor = [IPTheme cardColor];
    UIImage *icon = self.ipaInfo.icon;
    if (icon) {
        self.iconView.image = icon;
    } else {
        self.iconView.image = [[UIImage systemImageNamed:@"doc.zipper"] imageWithTintColor:[IPTheme textTertiaryColor]];
    }
    [self.contentView addSubview:self.iconView];

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.text = self.ipaInfo.displayName ?: self.ipaInfo.name;
    self.nameLabel.textColor = [IPTheme textPrimaryColor];
    self.nameLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.adjustsFontSizeToFitWidth = YES;
    self.nameLabel.minimumScaleFactor = 0.7;
    [self.contentView addSubview:self.nameLabel];

    self.validationSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.validationSpinner.color = [IPTheme textSecondaryColor];
    [self.validationSpinner startAnimating];
    [self.contentView addSubview:self.validationSpinner];

    self.validationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.validationLabel.text = @"جاري التحقق...";
    self.validationLabel.textColor = [IPTheme textSecondaryColor];
    self.validationLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.validationLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.validationLabel];

    self.detailsContainer = [[UIView alloc] initWithFrame:CGRectZero];
    self.detailsContainer.backgroundColor = [IPTheme cardColor];
    self.detailsContainer.layer.borderWidth = 0.7;
    self.detailsContainer.layer.borderColor = [IPTheme subtleBorderColor].CGColor;
    self.detailsContainer.layer.cornerRadius = 18;
    [self.contentView addSubview:self.detailsContainer];

    NSArray *details = @[
        @{@"title": @"معرّف الحزمة", @"value": self.ipaInfo.bundleID ?: @"غير معروف"},
        @{@"title": @"الإصدار", @"value": self.ipaInfo.version ?: @"غير معروف"},
        @{@"title": @"الحجم", @"value": self.ipaInfo.formattedSize ?: @"غير معروف"},
        @{@"title": @"الحد الأدنى لنظام iOS", @"value": self.ipaInfo.minOSVersion ?: @"غير محدد"},
        @{@"title": @"الفريق", @"value": self.ipaInfo.teamIdentifier ?: @"غير موقّع"},
    ];

    for (NSDictionary *detail in details) {
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        titleLabel.text = detail[@"title"];
        titleLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
        titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [self.detailsContainer addSubview:titleLabel];

        UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        valueLabel.text = detail[@"value"];
        valueLabel.textColor = [IPTheme textPrimaryColor];
        valueLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        valueLabel.textAlignment = NSTextAlignmentRight;
        valueLabel.adjustsFontSizeToFitWidth = YES;
        valueLabel.minimumScaleFactor = 0.8;
        [self.detailsContainer addSubview:valueLabel];
        [self.detailValueLabels addObject:valueLabel];
    }

    UIView *multiRow = [[UIView alloc] initWithFrame:CGRectZero];
    multiRow.backgroundColor = [IPTheme cardColor];
    multiRow.layer.borderWidth = 0.7;
    multiRow.layer.borderColor = [IPTheme subtleBorderColor].CGColor;
    multiRow.layer.cornerRadius = 16.0;
    multiRow.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [self.contentView addSubview:multiRow];

    self.multiInstanceLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.multiInstanceLabel.text = @"نسخ متعددة";
    self.multiInstanceLabel.textColor = UIColor.whiteColor;
    self.multiInstanceLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.multiInstanceLabel.textAlignment = NSTextAlignmentRight;
    self.multiInstanceLabel.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [multiRow addSubview:self.multiInstanceLabel];

    self.multiInstanceSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.multiInstanceSwitch.on = NO;
    self.multiInstanceSwitch.onTintColor = [IPTheme accentColor];
    self.multiInstanceSwitch.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.multiInstanceSwitch.accessibilityLabel = @"نسخ متعددة";
    self.multiInstanceSwitch.accessibilityHint = @"عند التفعيل سيتم تجهيز نسخة مستقلة بمعرّف حزمة مختلف";
    [multiRow addSubview:self.multiInstanceSwitch];

    self.installButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.installButton setTitle:@"تثبيت التطبيق" forState:UIControlStateNormal];
    [self.installButton setTitleColor:[IPTheme textPrimaryColor] forState:UIControlStateNormal];
    self.installButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.installButton.backgroundColor = [IPTheme accentColor];
    self.installButton.layer.cornerRadius = 17;
    self.installButton.enabled = NO;
    self.installButton.alpha = 0.5;
    [self.installButton addTarget:self action:@selector(installTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.installButton];
}

- (void)layoutContent {
    CGFloat margin = 20;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;
    CGFloat w = self.view.bounds.size.width;
    CGFloat y = safeTop + 20;

    self.iconView.frame = CGRectMake((w - 90) / 2, y, 90, 90);
    y += 110;

    self.nameLabel.frame = CGRectMake(margin, y, w - margin * 2, 30);
    y += 38;

    self.validationSpinner.center = CGPointMake(w / 2, y + 10);
    self.validationLabel.frame = CGRectMake(margin, y, w - margin * 2, 22);
    y += 50;

    CGFloat containerH = 14 + 5 * 34;
    self.detailsContainer.frame = CGRectMake(margin, y, w - margin * 2, containerH);

    NSArray *subviews = self.detailsContainer.subviews;
    CGFloat detailY = 14;
    for (NSUInteger i = 0; i < subviews.count; i += 2) {
        UILabel *titleLabel = (UILabel *)subviews[i];
        UILabel *valueLabel = (UILabel *)subviews[i+1];
        titleLabel.frame = CGRectMake(16, detailY, 140, 22);
        valueLabel.frame = CGRectMake(160, detailY, self.detailsContainer.bounds.size.width - 176, 22);
        detailY += 34;
    }
    y += containerH + 20;

    UIView *multiRow = self.multiInstanceSwitch.superview;
    multiRow.frame = CGRectMake(margin, y, w - margin * 2, 54);
    self.multiInstanceLabel.frame = CGRectMake(16, 8, multiRow.bounds.size.width - 92, 38);
    self.multiInstanceSwitch.center = CGPointMake(multiRow.bounds.size.width - 48.0, multiRow.bounds.size.height / 2.0);
    y += 70;

    self.installButton.frame = CGRectMake(margin, y, w - margin * 2, 54);
    y += 70;

    self.contentView.frame = CGRectMake(0, 0, w, y);
    self.scrollView.contentSize = CGSizeMake(w, y + safeBottom + 20);
}

- (void)validateIPA {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        IPAValidationResult *result = [[IPAValidator sharedValidator] validateIPAAtPath:self.ipaInfo.filePath];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.validationSpinner stopAnimating];
            self.isValidated = YES;
            self.isValid = result.isReadyForInstall;

            if (result.isReadyForInstall) {
                NSArray<NSString *> *missingLibs = [[IPAValidator sharedValidator] checkDependenciesAtAppPath:self.ipaInfo.appDirectoryPath];
                if (missingLibs.count > 0) {
                    NSString *libsList = [missingLibs componentsJoinedByString:@", "];
                    self.validationLabel.text = [NSString stringWithFormat:@"⚠️ جاهز لكن ينقص: %@", libsList];
                    self.validationLabel.textColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:1.0];
                    self.installButton.enabled = YES;
                    self.installButton.alpha = 1.0;
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"مكتبات مفقودة"
                                                                                 message:[NSString stringWithFormat:@"التطبيق يحتاج هذه المكتبات:\n%@\n\nقد لا يعمل التطبيق بدونها. هل تريد الاستمرار؟", libsList]
                                                                          preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"تثبيت" style:UIAlertActionStyleDefault handler:nil]];
                    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                        self.installButton.enabled = NO;
                        self.installButton.alpha = 0.5;
                    }]];
                    [self presentViewController:alert animated:YES completion:nil];
                } else {
                    self.validationLabel.text = @"جاهز للتثبيت ✓";
                    self.validationLabel.textColor = [UIColor colorWithRed:0.3 green:0.7 blue:0.5 alpha:1.0];
                    self.installButton.enabled = YES;
                    self.installButton.alpha = 1.0;
                }
            } else {
                self.validationLabel.text = result.statusMessage;
                self.validationLabel.textColor = [UIColor colorWithRed:0.9 green:0.4 blue:0.3 alpha:1.0];
                self.installButton.enabled = NO;
                self.installButton.alpha = 0.5;
                [self.installButton setTitle:@"لا يمكن التثبيت" forState:UIControlStateNormal];
                self.installButton.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
            }
        });
    });
}

- (void)installTapped:(UIButton *)sender {
    if (!self.isValid) return;
    CapabilityManager *capMgr = [CapabilityManager sharedManager];
    [capMgr scanCapabilities];
    if (!capMgr.canInstallIPA) {
        [self showReadinessAlert:capMgr];
        return;
    }
    if (self.multiInstanceSwitch.isOn) {
        sender.enabled = NO;
        [sender setTitle:@"جاري تجهيز النسخة..." forState:UIControlStateNormal];
        NSString *displayName = self.ipaInfo.displayName ?: self.ipaInfo.name ?: @"التطبيق";
        [[IPAMultiInstancePreparer sharedPreparer] prepareIPAAtPath:self.ipaInfo.filePath displayName:displayName completion:^(NSString *preparedIPAPath, NSString *instanceBundleID, NSString *instanceName, NSError *error) {
            sender.enabled = YES;
            [sender setTitle:@"تثبيت التطبيق" forState:UIControlStateNormal];
            if (error || preparedIPAPath.length == 0) {
                [self showReadinessAlertWithMessage:error.localizedDescription ?: @"تعذر إنشاء نسخة مستقلة؛ لم يتم تسجيل أي تطبيق ولم تتأثر النسخة الأصلية."];
                return;
            }
            NSLog(@"[IPAInstallerPro] multi-instance prepared bundleID=%@ path=%@", instanceBundleID, preparedIPAPath);
            [self presentProgressForIPAPath:preparedIPAPath name:[NSString stringWithFormat:@"%@ نسخة", instanceName ?: displayName]];
        }];
        return;
    }
    [self presentProgressForIPAPath:self.ipaInfo.filePath name:self.ipaInfo.displayName ?: self.ipaInfo.name];
}

- (void)presentProgressForIPAPath:(NSString *)ipaPath name:(NSString *)name {
    InstallationProgressViewController *progressVC = [[InstallationProgressViewController alloc] init];
    progressVC.ipaName = name;
    progressVC.ipaPath = ipaPath;
    progressVC.modalPresentationStyle = UIModalPresentationFullScreen;
    if (self.launchedFromDuplicate) {
        progressVC.dismissOnDuplicateSuccess = YES;
        __weak typeof(self) weakSelf = self;
        __weak InstallationProgressViewController *weakProgressVC = progressVC;
        progressVC.duplicateCompletionHandler = ^(BOOL success, InstallationResult *result) {
            if (!success) return;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            __strong InstallationProgressViewController *strongProgressVC = weakProgressVC;
            if (!strongSelf || !strongProgressVC) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongProgressVC dismissViewControllerAnimated:YES completion:^{
                    [strongSelf dismissViewControllerAnimated:YES completion:^{
                        if (strongSelf.duplicateCompletionHandler) strongSelf.duplicateCompletionHandler(YES);
                    }];
                }];
            });
        };
    }
    [self presentViewController:progressVC animated:YES completion:nil];
}

- (void)showReadinessAlertWithMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تعذر تجهيز النسخة" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showReadinessAlert:(CapabilityManager *)capMgr {
    NSString *status = [capMgr installationReadinessStatus];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"جاهزية التثبيت"
        message:status
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
