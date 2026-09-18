//
//  AppDetailsViewController.m
//  IPAInstallerPro — Commit 2: Adaptive layout for all iOS versions
//
//  FIX: Replaced fixed-frame layout with scrollView + viewDidLayoutSubviews.
//  Cards and buttons now adapt to screen width, safe area, and Dynamic Island.
//

#import "AppDetailsViewController.h"
#import "Core/InstallationEngine.h"
#import "Core/IPAExportManager.h"
#import "Core/IPAExtractor.h"
#import "Core/ApplicationManager.h"
#import "Core/Logger.h"
#import "IPAInstallViewController.h"
#import "IPAExportProgressView.h"
#import "IPTheme.h"

@interface AppDetailsViewController ()
@property (nonatomic, strong) AppInfo *appInfo;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *bundleLabel;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) UIButton *exportButton;
@property (nonatomic, strong) UIButton *cloneButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) NSMutableArray<UILabel *> *cardValueLabels;
@property (nonatomic, strong) IPAExportProgressView *cloneProgressView;
@property (nonatomic, assign) NSUInteger cloneProgressGeneration;
@end

@implementation AppDetailsViewController

- (instancetype)initWithAppInfo:(AppInfo *)appInfo {
    self = [super init];
    if (self) { _appInfo = appInfo; _cardValueLabels = [NSMutableArray array]; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"معلومات التطبيق";
    self.view.backgroundColor = [IPTheme backgroundColor];
    [self setupViews];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutContent];
}

- (void)setupViews {
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] initWithFrame:self.scrollView.bounds];
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scrollView addSubview:self.contentView];

    self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.iconView.layer.cornerRadius = 18;
    self.iconView.layer.masksToBounds = YES;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.backgroundColor = [IPTheme cardColor];
    if (self.appInfo.icon) {
        self.iconView.image = self.appInfo.icon;
    } else {
        self.iconView.image = [[UIImage systemImageNamed:@"app"] imageWithTintColor:[IPTheme textTertiaryColor]];
    }
    [self.contentView addSubview:self.iconView];

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.text = self.appInfo.name;
    self.nameLabel.textColor = [IPTheme textPrimaryColor];
    self.nameLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.adjustsFontSizeToFitWidth = YES;
    self.nameLabel.minimumScaleFactor = 0.7;
    [self.contentView addSubview:self.nameLabel];

    self.card = [[UIView alloc] initWithFrame:CGRectZero];
    self.card.backgroundColor = [IPTheme cardColor];
    self.card.layer.borderWidth = 0.7;
    self.card.layer.borderColor = [IPTheme subtleBorderColor].CGColor;
    self.card.layer.cornerRadius = 18;
    [self.contentView addSubview:self.card];

    NSArray *details = @[
        @{@"title": @"معرّف الحزمة", @"value": self.appInfo.bundleID},
        @{@"title": @"الإصدار", @"value": self.appInfo.version},
        @{@"title": @"النوع", @"value": self.appInfo.isSystemApp ? @"نظام" : @"مستخدم"},
        @{@"title": @"الحماية", @"value": self.appInfo.isProtected ? @"محمي ✓" : @"غير معروف"},
    ];
    for (NSDictionary *d in details) {
        UILabel *tl = [[UILabel alloc] initWithFrame:CGRectZero];
        tl.text = d[@"title"];
        tl.textColor = [IPTheme textTertiaryColor];
        tl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [self.card addSubview:tl];

        UILabel *vl = [[UILabel alloc] initWithFrame:CGRectZero];
        vl.text = d[@"value"];
        vl.textColor = [IPTheme textPrimaryColor];
        vl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        vl.textAlignment = NSTextAlignmentRight;
        vl.adjustsFontSizeToFitWidth = YES;
        vl.minimumScaleFactor = 0.8;
        [self.card addSubview:vl];
        [self.cardValueLabels addObject:vl];
    }

    self.openButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.openButton setTitle:@"فتح التطبيق" forState:UIControlStateNormal];
    [self.openButton setTitleColor:[IPTheme textPrimaryColor] forState:UIControlStateNormal];
    self.openButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.openButton.backgroundColor = [IPTheme accentColor];
    self.openButton.layer.cornerRadius = 17;
    [self.openButton addTarget:self action:@selector(openTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.openButton];

    self.exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.exportButton setTitle:@"استخراج IPA" forState:UIControlStateNormal];
    [self.exportButton setTitleColor:[IPTheme textPrimaryColor] forState:UIControlStateNormal];
    self.exportButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.exportButton.backgroundColor = [IPTheme secondaryCardColor];
    self.exportButton.layer.borderWidth = 0.7;
    self.exportButton.layer.borderColor = [IPTheme subtleBorderColor].CGColor;
    self.exportButton.layer.cornerRadius = 17;
    [self.exportButton addTarget:self action:@selector(exportTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.exportButton];

    self.cloneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cloneButton setTitle:@"تكرار التطبيق" forState:UIControlStateNormal];
    [self.cloneButton setTitleColor:[IPTheme textPrimaryColor] forState:UIControlStateNormal];
    self.cloneButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.cloneButton.backgroundColor = [IPTheme secondaryCardColor];
    self.cloneButton.layer.borderWidth = 0.7;
    self.cloneButton.layer.borderColor = [IPTheme subtleBorderColor].CGColor;
    self.cloneButton.layer.cornerRadius = 17;
    [self.cloneButton addTarget:self action:@selector(cloneTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.cloneButton];

    if (!self.appInfo.isProtected) {
        self.deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.deleteButton setTitle:@"حذف التطبيق" forState:UIControlStateNormal];
        [self.deleteButton setTitleColor:[IPTheme textPrimaryColor] forState:UIControlStateNormal];
        self.deleteButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        self.deleteButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.25 blue:0.25 alpha:1.0];
        self.deleteButton.layer.cornerRadius = 17;
        [self.deleteButton addTarget:self action:@selector(deleteTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.deleteButton];
    }
}

- (void)layoutContent {
    CGFloat w = self.view.bounds.size.width;
    CGFloat margin = 20;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;
    CGFloat y = safeTop + 20;

    self.iconView.frame = CGRectMake((w - 80) / 2, y, 80, 80);
    y += 100;

    self.nameLabel.frame = CGRectMake(margin, y, w - margin * 2, 28);
    y += 36;

    CGFloat cardH = 14 + 4 * 34;
    self.card.frame = CGRectMake(margin, y, w - margin * 2, cardH);
    CGFloat dy = 14;
    NSArray *subviews = self.card.subviews;
    for (NSUInteger i = 0; i < subviews.count; i += 2) {
        UILabel *tl = (UILabel *)subviews[i];
        UILabel *vl = (UILabel *)subviews[i+1];
        tl.frame = CGRectMake(16, dy, 140, 22);
        vl.frame = CGRectMake(160, dy, self.card.bounds.size.width - 176, 22);
        dy += 34;
    }
    y += cardH + 20;

    self.openButton.frame = CGRectMake(margin, y, w - margin * 2, 52);
    y += 68;

    self.exportButton.frame = CGRectMake(margin, y, w - margin * 2, 52);
    y += 68;

    self.cloneButton.frame = CGRectMake(margin, y, w - margin * 2, 52);
    y += 68;

    if (self.deleteButton) {
        self.deleteButton.frame = CGRectMake(margin, y, w - margin * 2, 52);
        y += 68;
    }

    self.contentView.frame = CGRectMake(0, 0, w, y);
    self.scrollView.contentSize = CGSizeMake(w, y + safeBottom + 20);
}

- (void)openTapped:(UIButton *)sender {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", self.appInfo.bundleID]];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تعذر الفتح"
            message:@"لا يوجد رابط URL scheme لهذا التطبيق" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)exportTapped:(UIButton *)sender {
    if (self.appInfo.bundlePath.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تعذر استخراج IPA"
            message:@"مسار التطبيق غير متاح من النظام" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    sender.enabled = NO;
    [sender setTitle:@"جارٍ استخراج IPA…" forState:UIControlStateNormal];
    NSString *suggestedName = self.appInfo.name.length > 0 ? self.appInfo.name : self.appInfo.bundleID;
    [[IPAExportManager sharedManager] exportApplicationAtPath:self.appInfo.bundlePath
                                                suggestedName:suggestedName
                                                   completion:^(NSURL *ipaURL, NSError *error) {
        sender.enabled = YES;
        [sender setTitle:@"استخراج IPA" forState:UIControlStateNormal];
        if (!ipaURL || error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"فشل استخراج IPA"
                message:error.localizedDescription ?: @"تعذر إنشاء ملف IPA" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }

        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[ipaURL]
                                                                             applicationActivities:nil];
        share.excludedActivityTypes = @[UIActivityTypeAssignToContact, UIActivityTypeAddToReadingList];
        share.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
            [[NSFileManager defaultManager] removeItemAtURL:ipaURL error:nil];
        };
        if (share.popoverPresentationController) {
            share.popoverPresentationController.sourceView = sender;
            share.popoverPresentationController.sourceRect = sender.bounds;
        }
        [self presentViewController:share animated:YES completion:nil];
    }];
}

- (void)cloneTapped:(UIButton *)sender {
    if (self.appInfo.isSystemApp || self.appInfo.isProtected) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تعذر التكرار"
            message:@"لا يمكن تكرار تطبيق نظام أو تطبيق محمي." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (self.appInfo.bundlePath.length == 0 || self.appInfo.bundleID.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تعذر التكرار"
            message:@"مسار التطبيق أو معرّف الحزمة غير متاح." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSString *appName = self.appInfo.name.length > 0 ? self.appInfo.name : @"التطبيق";
    NSString *baseID = [self.appInfo.bundleID stringByAppendingString:@".clone"];
    NSString *candidateID = baseID;
    NSUInteger suffix = 2;
    while ([[ApplicationManager sharedManager] appInfoForBundleID:candidateID] != nil) {
        candidateID = [NSString stringWithFormat:@"%@%lu", baseID, (unsigned long)suffix++];
    }

    UIAlertController *form = [UIAlertController alertControllerWithTitle:@"تكرار التطبيق"
        message:@"سيتم إنشاء IPA مستقلة دون تعديل التطبيق الأصلي. قد لا تعمل بعض التطبيقات التي تعتمد على تسجيل الدخول أو App Groups أو الإضافات أو خدمات Apple كما هي بعد التكرار."
        preferredStyle:UIAlertControllerStyleAlert];
    [form addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"اسم النسخة";
        field.text = [NSString stringWithFormat:@"%@ نسخة", appName];
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.returnKeyType = UIReturnKeyNext;
    }];
    [form addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Bundle ID الجديد";
        field.text = candidateID;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.keyboardType = UIKeyboardTypeASCIICapable;
        field.returnKeyType = UIReturnKeyDone;
    }];
    [form addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakForm = form;
    [form addAction:[UIAlertAction actionWithTitle:@"إنشاء IPA" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        UIAlertController *strongForm = weakForm;
        NSString *requestedName = [strongForm.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *requestedID = [strongForm.textFields.lastObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSPredicate *validID = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$"];
        if (requestedName.length == 0 || ![validID evaluateWithObject:requestedID] || [requestedID isEqualToString:self.appInfo.bundleID] || [[ApplicationManager sharedManager] appInfoForBundleID:requestedID] != nil) {
            UIAlertController *invalid = [UIAlertController alertControllerWithTitle:@"بيانات غير صالحة"
                message:@"استخدم اسمًا غير فارغ وBundle ID بصيغة صحيحة ومختلفًا عن التطبيق الأصلي وغير مستخدم على الجهاز." preferredStyle:UIAlertControllerStyleAlert];
            [invalid addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:invalid animated:YES completion:nil];
            return;
        }

        sender.enabled = NO;
        [sender setTitle:@"جارٍ إنشاء النسخة…" forState:UIControlStateNormal];
        NSUInteger progressGeneration = ++self.cloneProgressGeneration;
        IPAExportProgressView *progressView = [[IPAExportProgressView alloc] initWithFrame:self.view.bounds];
        self.cloneProgressView = progressView;
        [progressView setAppIcon:self.appInfo.icon name:requestedName];
        [progressView showInView:self.view animated:YES];
        NSArray<NSDictionary *> *cloneStages = @[
            @{ @"p": @0.05, @"s": @"جارٍ التحضير...", @"d": @"تهيئة مساحة العمل للنسخ" },
            @{ @"p": @0.20, @"s": @"جارٍ نسخ التطبيق...", @"d": @"نسخ Bundle الأصلي" },
            @{ @"p": @0.40, @"s": @"جارٍ تعديل Info.plist...", @"d": @"تحديث Bundle ID واسم العرض" },
            @{ @"p": @0.55, @"s": @"جارٍ تعديل الملفات...", @"d": @"تحديث الروابط الداخلية" },
            @{ @"p": @0.75, @"s": @"جارٍ إعادة التوقيع...", @"d": @"توقيع النسخة بـ ldid" },
            @{ @"p": @0.90, @"s": @"جارٍ إنشاء IPA...", @"d": @"ضغط النسخة إلى ملف .ipa" },
            @{ @"p": @0.98, @"s": @"جارٍ التحقق...", @"d": @"التحقق من سلامة النسخة" }
        ];
        __weak typeof(self) weakSelf = self;
        [cloneStages enumerateObjectsUsingBlock:^(NSDictionary *stage, NSUInteger idx, BOOL *stop) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((idx + 1) * 0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf || strongSelf.cloneProgressGeneration != progressGeneration || !strongSelf.cloneProgressView) return;
                [strongSelf.cloneProgressView setStage:stage[@"s"] detail:stage[@"d"] progress:[stage[@"p"] doubleValue]];
            });
        }];
        [[IPAExportManager sharedManager] cloneApplicationAtPath:self.appInfo.bundlePath
                                                   suggestedName:requestedName
                                                 bundleIdentifier:requestedID
                                                       completion:^(NSURL *ipaURL, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                sender.enabled = YES;
                [sender setTitle:@"تكرار التطبيق" forState:UIControlStateNormal];
                __strong typeof(weakSelf) strongSelf = weakSelf;
                IPAExportProgressView *activeProgress = strongSelf.cloneProgressView;
                if (!ipaURL || error) {
                    [activeProgress markCompletedWithSuccess:NO message:error.localizedDescription ?: @"تعذر إنشاء النسخة المكررة"];
                    [activeProgress dismissWithCompletion:nil];
                    strongSelf.cloneProgressView = nil;
                    UIAlertController *failed = [UIAlertController alertControllerWithTitle:@"فشل تكرار التطبيق"
                        message:error.localizedDescription ?: @"تعذر إنشاء النسخة المكررة" preferredStyle:UIAlertControllerStyleAlert];
                    [failed addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:failed animated:YES completion:nil];
                    return;
                }

                NSString *libraryDirectory = @"/var/mobile/Documents/IPAInstaller";
                NSFileManager *fm = [NSFileManager defaultManager];
                NSError *directoryError = nil;
                [fm createDirectoryAtPath:libraryDirectory withIntermediateDirectories:YES attributes:nil error:&directoryError];
                NSString *destination = [libraryDirectory stringByAppendingPathComponent:ipaURL.lastPathComponent];
                NSUInteger collision = 2;
                while ([fm fileExistsAtPath:destination]) {
                    NSString *stem = [ipaURL.lastPathComponent stringByDeletingPathExtension];
                    destination = [libraryDirectory stringByAppendingPathComponent:[[NSString stringWithFormat:@"%@ (%lu)", stem, (unsigned long)collision++] stringByAppendingPathExtension:@"ipa"]];
                }
                NSError *copyError = nil;
                BOOL copied = !directoryError && [fm copyItemAtURL:ipaURL toURL:[NSURL fileURLWithPath:destination] error:&copyError];
                [fm removeItemAtURL:ipaURL error:nil];
                if (!copied) {
                    [activeProgress markCompletedWithSuccess:NO message:copyError.localizedDescription ?: @"تعذر حفظ IPA المكررة"];
                    [activeProgress dismissWithCompletion:nil];
                    strongSelf.cloneProgressView = nil;
                    UIAlertController *failed = [UIAlertController alertControllerWithTitle:@"فشل حفظ النسخة"
                        message:copyError.localizedDescription ?: @"تعذر حفظ IPA المكررة" preferredStyle:UIAlertControllerStyleAlert];
                    [failed addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:failed animated:YES completion:nil];
                    return;
                }

                IPAExtractedInfo *info = [[IPAExtractor sharedExtractor] extractInfoFromIPA:destination];
                if (!info) {
                    [activeProgress markCompletedWithSuccess:NO message:@"تم إنشاء IPA لكن تعذر تجهيزها للتثبيت."];
                    [activeProgress dismissWithCompletion:nil];
                    strongSelf.cloneProgressView = nil;
                    UIAlertController *failed = [UIAlertController alertControllerWithTitle:@"فشل قراءة النسخة"
                        message:@"تم إنشاء IPA لكن تعذر تجهيزها للتثبيت." preferredStyle:UIAlertControllerStyleAlert];
                    [failed addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:failed animated:YES completion:nil];
                    return;
                }
                IPAInstallViewController *installVC = [[IPAInstallViewController alloc] initWithIPAInfo:info];
                installVC.modalPresentationStyle = UIModalPresentationFullScreen;
                installVC.launchedFromDuplicate = YES;
                [activeProgress setStats:[NSString stringWithFormat:@"%@ • %@", destination.lastPathComponent, [info.formattedSize length] ? info.formattedSize : @"تم التحقق"]];
                [activeProgress markCompletedWithSuccess:YES message:@"تم إنشاء النسخة المكررة بنجاح"];
                strongSelf.cloneProgressView = nil;
                void (^presentInstall)(void) = ^{
                    [self presentViewController:installVC animated:YES completion:nil];
                };
                installVC.duplicateCompletionHandler = ^(BOOL success) {
                    if (!success) return;
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"IPAInstallerProDuplicateDidComplete"
                                                                        object:strongSelf
                                                                      userInfo:@{ @"success": @YES,
                                                                                  @"bundleID": requestedID ?: @"" }];
                };
                if (activeProgress) {
                    [activeProgress dismissWithCompletion:presentInstall];
                } else {
                    presentInstall();
                }
            });
        }];
    }]];
    [self presentViewController:form animated:YES completion:nil];
}

- (void)deleteTapped:(UIButton *)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تأكيد الحذف"
        message:[NSString stringWithFormat:@"هل أنت متأكد من حذف %@؟ لا يمكن التراجع.", self.appInfo.name]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"حذف" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        NSString *appPath = self.appInfo.bundlePath;
        void (^done)(BOOL, NSString *) = ^(BOOL success, NSString *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"تم الحذف"
                        message:[NSString stringWithFormat:@"تم حذف %@ بنجاح", self.appInfo.name]
                        preferredStyle:UIAlertControllerStyleAlert];
                    [ok addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                        [self.navigationController popViewControllerAnimated:YES];
                    }]];
                    [self presentViewController:ok animated:YES completion:nil];
                } else {
                    UIAlertController *err = [UIAlertController alertControllerWithTitle:@"فشل الحذف"
                        message:error preferredStyle:UIAlertControllerStyleAlert];
                    [err addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:err animated:YES completion:nil];
                }
            });
        };
        if (appPath && appPath.length > 0) {
            [[InstallationEngine sharedEngine] uninstallAppAtPath:appPath bundleID:self.appInfo.bundleID completion:done];
        } else {
            [[InstallationEngine sharedEngine] uninstallAppWithBundleID:self.appInfo.bundleID completion:done];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
