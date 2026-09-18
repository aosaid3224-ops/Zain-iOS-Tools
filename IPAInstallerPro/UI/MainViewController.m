#import "MainViewController.h"
#import "IPAFileBrowserViewController.h"
#import "IPAInstallViewController.h"
#import "Core/IPAExtractor.h"
#import "Core/Logger.h"
#import "GlassIPACell.h"
#import "RuntimeEnvironment.h"
#import "IPTheme.h"

@interface MainViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIView *toastView;
@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, strong) UIView *dashboardHeader;
@property (nonatomic, assign) BOOL hasShownAutoAbout;
@property (nonatomic, strong) UILabel *trustedCountLabel;
@property (nonatomic, strong) UILabel *installedCountLabel;
@property (nonatomic, strong) UIView *importOverlayView;
@property (nonatomic, strong) UIActivityIndicatorView *importSpinner;
@property (nonatomic, strong) UILabel *importLabel;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"";
    self.navigationItem.title = @"";
    self.view.backgroundColor = [IPTheme backgroundColor];
    self.ipaFiles = [NSMutableArray array];
    self.isLoading = NO;
    self.ipaMetadataCache = [NSMutableDictionary dictionary];
    self.ipaIconCache = [[NSCache alloc] init];
    self.ipaIconCache.countLimit = 100;
    self.ipaCacheQueue = dispatch_queue_create("com.aosaid.ipainstallerpro.ipa-metadata-cache", DISPATCH_QUEUE_SERIAL);

    [self setupNavigationBar];
    [self setupTableView];
    [self setupDashboardHeader];
    [self setupEmptyState];
    [self setupAddButton];
    [self setupToast];
    [self setupLoadingIndicator];
    [self setupImportOverlay];
    [self loadIPAFiles];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.hasShownAutoAbout) return;
    self.hasShownAutoAbout = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentAutomaticAboutIfNeeded];
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.navigationBarHidden = NO;
}

- (void)presentAutomaticAboutIfNeeded {
    NSString *message = @"هذه الأداة متاحة حاليًا كنسخة تجريبية وليست الإصدار النهائي.\n\nقد تواجه بعض الأخطاء أو المشاكل أثناء الاستخدام، ونهدف من خلال هذه المرحلة إلى اختبار الأداة وتحسين استقرارها وتطوير ميزاتها.\n\nإذا واجهت أي خلل، أو لديك ملاحظة أو اقتراح لتحسين الأداة، نرجو منك مشاركة تجربتك معنا. ملاحظاتك تساعدنا على اكتشاف المشاكل ومعالجتها قبل إطلاق الإصدار النهائي.\n\nللتواصل والإبلاغ عن المشاكل:\nX: @Zainqkvd";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"حول الأداة" message:message preferredStyle:UIAlertControllerStyleAlert];
    alert.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationController.navigationBarHidden = YES;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 4, 0);
    self.tableView.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, 20, 0);
    self.tableView.rowHeight = 72;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = [IPTheme textSecondaryColor];
    [self.refreshControl addTarget:self action:@selector(refreshPulled:) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;
}

- (void)setupDashboardHeader {
    CGFloat width = self.view.bounds.size.width;
    self.dashboardHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 220.0)];
    self.dashboardHeader.backgroundColor = UIColor.clearColor; self.dashboardHeader.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(8, 27, width - 16, 40)];
    NSMutableAttributedString *styledTitle = [[NSMutableAttributedString alloc] initWithString:@"ملفات IPA" attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:27 weight:UIFontWeightBold], NSForegroundColorAttributeName:UIColor.whiteColor}];
    [styledTitle addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithRed:1.0 green:0.22 blue:0.18 alpha:1.0] range:NSMakeRange(6, 3)]; title.attributedText = styledTitle; title.textAlignment = NSTextAlignmentCenter; title.autoresizingMask = UIViewAutoresizingFlexibleWidth; [self.dashboardHeader addSubview:title];
    UIButton *add = [UIButton buttonWithType:UIButtonTypeSystem]; add.frame = CGRectMake(width - 64, 34, 44, 44); add.layer.cornerRadius = 15; add.layer.borderWidth = 0.7; add.layer.borderColor = [IPTheme separatorStrongColor].CGColor; add.backgroundColor = [IPTheme selectionColor]; [add setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal]; add.tintColor = [UIColor colorWithRed:1 green:.20 blue:.16 alpha:1]; [add addTarget:self action:@selector(addIPATapped:) forControlEvents:UIControlEventTouchUpInside]; [self.dashboardHeader addSubview:add];
    UIButton *viewMode = [UIButton buttonWithType:UIButtonTypeSystem]; viewMode.frame = CGRectMake(24, 34, 48, 48); viewMode.layer.cornerRadius = 17; viewMode.layer.borderWidth = 1; viewMode.layer.borderColor = [IPTheme separatorStrongColor].CGColor; [viewMode setImage:[UIImage systemImageNamed:@"list.bullet"] forState:UIControlStateNormal]; viewMode.tintColor = [UIColor colorWithRed:1 green:.20 blue:.16 alpha:1]; [viewMode addTarget:self action:@selector(toggleViewMode:) forControlEvents:UIControlEventTouchUpInside]; [self.dashboardHeader addSubview:viewMode];
    UIView *stats = [[UIView alloc] initWithFrame:CGRectMake(8, 139, MAX(width - 16, 1), 74)]; stats.autoresizingMask = UIViewAutoresizingFlexibleWidth; stats.backgroundColor = [UIColor colorWithRed:.065 green:.066 blue:.075 alpha:1]; stats.layer.cornerRadius = 17; stats.layer.borderWidth = 1; stats.layer.borderColor = [UIColor colorWithRed:.42 green:.08 blue:.09 alpha:.65].CGColor; [self.dashboardHeader addSubview:stats];
    NSArray *icons = @[@"cube", @"chart.pie", @"shield", @"arrow.down.circle"]; NSArray *labels = @[@"التطبيقات", @"إجمالي الحجم", @"موثوقة", @"تم التثبيت"]; NSMutableArray *values = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) { CGFloat x = stats.bounds.size.width / 4.0 * i; if (i) { UIView *d = [[UIView alloc] initWithFrame:CGRectMake(x, 14, 1, 46)]; d.backgroundColor = [IPTheme separatorColor]; [stats addSubview:d]; } UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(x + (stats.bounds.size.width / 4.0 - 22) / 2.0, 7, 22, 22)]; iv.image = [UIImage systemImageNamed:icons[i]]; iv.tintColor = [UIColor colorWithRed:1 green:.22 blue:.18 alpha:1]; iv.contentMode = UIViewContentModeScaleAspectFit; [stats addSubview:iv]; UILabel *v = [[UILabel alloc] initWithFrame:CGRectMake(x + 3, 30, stats.bounds.size.width / 4.0 - 6, 22)]; v.textAlignment = NSTextAlignmentCenter; v.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold]; v.textColor = UIColor.whiteColor; [stats addSubview:v]; [values addObject:v]; UILabel *c = [[UILabel alloc] initWithFrame:CGRectMake(x + 1, 54, stats.bounds.size.width / 4.0 - 2, 16)]; c.text = labels[i]; c.textAlignment = NSTextAlignmentCenter; c.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium]; c.textColor = [IPTheme textSecondaryColor]; [stats addSubview:c]; }
    self.appsCountLabel = values[0]; self.totalSizeLabel = values[1]; self.trustedCountLabel = values[2]; self.installedCountLabel = values[3];
    self.totalSizeLabel.adjustsFontSizeToFitWidth = YES; self.totalSizeLabel.minimumScaleFactor = 0.45; self.totalSizeLabel.numberOfLines = 1;
    self.tableView.tableHeaderView = self.dashboardHeader;
}

- (void)updateDashboardStatistics {
    NSUInteger trusted = 0; unsigned long long total = 0; for (IPAExtractedInfo *info in self.ipaFiles) { total += info.fileSize.unsignedLongLongValue; if (info.teamIdentifier.length > 0 && ![info.teamIdentifier isEqualToString:@"غير معروف"]) trusted++; }
    NSUInteger installed = 0; NSFileManager *fm = [NSFileManager defaultManager]; RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment]; NSMutableArray *appRoots = [NSMutableArray arrayWithObject:@"/Applications"]; if (rt.bootstrapPath) { [appRoots addObject:[rt.bootstrapPath stringByAppendingPathComponent:@"Applications"]]; } else { [appRoots addObject:@"/var/jb/Applications"]; } for (NSString *root in appRoots) { for (NSString *item in [fm contentsOfDirectoryAtPath:root error:nil]) if ([item.pathExtension.lowercaseString isEqualToString:@"app"]) installed++; }
    self.appsCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.ipaFiles.count]; self.totalSizeLabel.text = [[IPAExtractor sharedExtractor] formatFileSize:(long long)total]; self.trustedCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)trusted]; self.installedCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)installed];
}

- (void)setupEmptyState {
    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.text = @"لا توجد ملفات IPA\nاضغط + لإضافة ملف";
    self.emptyLabel.textColor = [IPTheme textTertiaryColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
}

- (void)setupAddButton {
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                              target:self
                                                                              action:@selector(addIPATapped:)];
    addBtn.tintColor = [UIColor colorWithRed:0.82 green:0.12 blue:0.15 alpha:0.96];
    self.navigationItem.rightBarButtonItem = addBtn;
}

- (void)setupToast {
    self.toastView = [[UIView alloc] initWithFrame:CGRectMake(20, -60, self.view.bounds.size.width - 40, 50)];
    self.toastView.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:0.95];
    self.toastView.layer.cornerRadius = 12;
    self.toastView.layer.masksToBounds = YES;
    self.toastView.alpha = 0;
    [self.view addSubview:self.toastView];

    self.toastLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, self.toastView.bounds.size.width - 32, 50)];
    self.toastLabel.textColor = [IPTheme textPrimaryColor];
    self.toastLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.toastLabel.textAlignment = NSTextAlignmentCenter;
    [self.toastView addSubview:self.toastLabel];
}

- (void)setupLoadingIndicator {
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.color = [IPTheme textSecondaryColor];
    self.loadingIndicator.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2 - 40);
    self.loadingIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.loadingIndicator.hidden = YES;
    [self.view addSubview:self.loadingIndicator];
}

- (void)setupImportOverlay {
    self.importOverlayView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.importOverlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.importOverlayView.backgroundColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.55];
    self.importOverlayView.alpha = 0.0;
    self.importOverlayView.hidden = YES;
    [self.view addSubview:self.importOverlayView];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 120)];
    card.center = CGPointMake(self.importOverlayView.bounds.size.width / 2, self.importOverlayView.bounds.size.height / 2);
    card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    card.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1.0];
    card.layer.cornerRadius = 20;
    card.layer.borderWidth = 0.8;
    card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    [self.importOverlayView addSubview:card];

    self.importSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.importSpinner.center = CGPointMake(card.bounds.size.width / 2, 38);
    self.importSpinner.color = [UIColor colorWithRed:1 green:.22 blue:.18 alpha:1];
    [card addSubview:self.importSpinner];

    self.importLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 64, 200, 40)];
    self.importLabel.textAlignment = NSTextAlignmentCenter;
    self.importLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.importLabel.textColor = [IPTheme textPrimaryColor];
    self.importLabel.text = @"جارٍ استيراد الملفات...";
    [card addSubview:self.importLabel];
}

- (void)showImportOverlay:(BOOL)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (show) {
            self.importOverlayView.hidden = NO;
            [self.importSpinner startAnimating];
            [UIView animateWithDuration:0.25 animations:^{
                self.importOverlayView.alpha = 1.0;
            }];
        } else {
            [UIView animateWithDuration:0.25 animations:^{
                self.importOverlayView.alpha = 0.0;
            } completion:^(BOOL finished) {
                self.importOverlayView.hidden = YES;
                [self.importSpinner stopAnimating];
            }];
        }
    });
}

- (void)showToast:(NSString *)message isError:(BOOL)isError {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.toastLabel.text = message;
        self.toastView.backgroundColor = isError
            ? [UIColor colorWithRed:0.8 green:0.25 blue:0.2 alpha:0.95]
            : [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:0.95];

        [UIView animateWithDuration:0.3 animations:^{
            self.toastView.alpha = 1;
            self.toastView.frame = CGRectMake(20, 60, self.view.bounds.size.width - 40, 50);
        } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.3 animations:^{
                    self.toastView.alpha = 0;
                    self.toastView.frame = CGRectMake(20, -60, self.view.bounds.size.width - 40, 50);
                }];
            });
        }];
    });
}

#pragma mark - Cache Keys

- (NSString *)ipaCacheKeyForPath:(NSString *)path attributes:(NSDictionary *)attrs {
    if (path.length == 0 || !attrs) return nil;
    unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
    NSTimeInterval modified = [attrs[NSFileModificationDate] timeIntervalSince1970];
    unsigned long long fileNumber = [attrs[NSFileSystemFileNumber] unsignedLongLongValue];
    return [NSString stringWithFormat:@"%@|%llu|%.6f|%llu", path, size, modified, fileNumber];
}

- (NSString *)iconCacheKeyForPath:(NSString *)path key:(NSString *)cacheKey {
    return [NSString stringWithFormat:@"%@|%@", path, cacheKey];
}

#pragma mark - Persistent Cache (v3.0.35)

static NSString * const kPersistentCacheKey = @"IPAInstallerPro.PersistentMetadataCache.v1";

- (NSString *)persistentIconCacheDirectory {
    NSArray *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *dir = [[caches.firstObject stringByAppendingPathComponent:@"IPAInstallerPro"] stringByAppendingPathComponent:@"Icons"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSString *)persistentIconPathForIPAPath:(NSString *)path {
    NSString *safeName = [[path lastPathComponent] stringByDeletingPathExtension];
    safeName = [safeName stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    safeName = [safeName stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    return [[self persistentIconCacheDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", safeName]];
}

- (void)persistCacheForPath:(NSString *)path info:(IPAExtractedInfo *)info cacheKey:(NSString *)cacheKey {
    if (!path || !cacheKey || !info) return;
    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    record[@"key"] = cacheKey;
    record[@"bundleID"] = info.bundleID ?: @"";
    record[@"name"] = info.name ?: @"";
    record[@"displayName"] = info.displayName ?: @"";
    record[@"version"] = info.version ?: @"";
    record[@"buildVersion"] = info.buildVersion ?: @"";
    record[@"minOSVersion"] = info.minOSVersion ?: @"";
    record[@"bundleExecutable"] = info.bundleExecutable ?: @"";
    record[@"teamIdentifier"] = info.teamIdentifier ?: @"";
    record[@"fileSize"] = info.fileSize ?: @0;
    record[@"formattedSize"] = info.formattedSize ?: @"";
    record[@"filePath"] = info.filePath ?: path;
    record[@"supportedDevices"] = info.supportedDevices ?: @[];
    record[@"architectures"] = info.architectures ?: @[];
    record[@"appDirectoryPath"] = info.appDirectoryPath ?: @"";
    record[@"modifiedDate"] = info.modifiedDate ?: [NSDate date];

    NSMutableDictionary *allCaches = [[[NSUserDefaults standardUserDefaults] objectForKey:kPersistentCacheKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    allCaches[path] = record;
    [[NSUserDefaults standardUserDefaults] setObject:allCaches forKey:kPersistentCacheKey];

    if (info.icon) {
        NSString *iconPath = [self persistentIconPathForIPAPath:path];
        NSData *pngData = UIImagePNGRepresentation(info.icon);
        if (pngData) [pngData writeToFile:iconPath atomically:YES];
    }
}

- (IPAExtractedInfo *)loadPersistentCacheForPath:(NSString *)path cacheKey:(NSString *)cacheKey {
    if (!path || !cacheKey) return nil;
    NSDictionary *allCaches = [[NSUserDefaults standardUserDefaults] objectForKey:kPersistentCacheKey];
    NSDictionary *record = allCaches[path];
    if (![record[@"key"] isEqualToString:cacheKey]) return nil;

    IPAExtractedInfo *info = [[IPAExtractedInfo alloc] init];
    info.bundleID = record[@"bundleID"];
    info.name = record[@"name"];
    info.displayName = record[@"displayName"];
    info.version = record[@"version"];
    info.buildVersion = record[@"buildVersion"];
    info.minOSVersion = record[@"minOSVersion"];
    info.bundleExecutable = record[@"bundleExecutable"];
    info.teamIdentifier = record[@"teamIdentifier"];
    info.fileSize = record[@"fileSize"];
    info.formattedSize = record[@"formattedSize"];
    info.filePath = record[@"filePath"] ?: path;
    info.supportedDevices = record[@"supportedDevices"];
    info.architectures = record[@"architectures"];
    info.appDirectoryPath = record[@"appDirectoryPath"];
    info.modifiedDate = record[@"modifiedDate"];

    NSString *iconPath = [self persistentIconPathForIPAPath:path];
    if ([[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
        NSData *pngData = [NSData dataWithContentsOfFile:iconPath];
        if (pngData) info.icon = [UIImage imageWithData:pngData];
    }
    return info;
}

- (void)clearPersistentCacheForPath:(NSString *)path {
    if (!path) return;
    NSMutableDictionary *allCaches = [[[NSUserDefaults standardUserDefaults] objectForKey:kPersistentCacheKey] mutableCopy];
    [allCaches removeObjectForKey:path];
    [[NSUserDefaults standardUserDefaults] setObject:allCaches forKey:kPersistentCacheKey];
    NSString *iconPath = [self persistentIconPathForIPAPath:path];
    [[NSFileManager defaultManager] removeItemAtPath:iconPath error:nil];
}

- (IPAExtractedInfo *)placeholderInfoForIPAPath:(NSString *)path size:(NSNumber *)size {
    IPAExtractedInfo *info = [[IPAExtractedInfo alloc] init];
    info.filePath = path;
    info.fileSize = size ?: @0;
    info.formattedSize = [[IPAExtractor sharedExtractor] formatFileSize:info.fileSize.longLongValue];
    info.name = [[path.lastPathComponent stringByDeletingPathExtension] copy];
    info.displayName = info.name;
    info.version = @"جارٍ قراءة البيانات...";
    info.bundleID = @"جارٍ قراءة البيانات...";
    info.buildVersion = @"";
    info.minOSVersion = @"غير محدد";
    info.teamIdentifier = @"غير معروف";
    info.supportedDevices = @[];
    info.architectures = @[];
    return info;
}

- (void)loadIPAFiles {
    if (self.isLoading) return;
    self.isLoading = YES;
    self.ipaLoadGeneration += 1;
    NSUInteger loadGeneration = self.ipaLoadGeneration;

    dispatch_async(dispatch_get_main_queue(), ^{
        self.loadingIndicator.hidden = NO;
        [self.loadingIndicator startAnimating];
        self.emptyLabel.hidden = YES;
    });

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<IPAExtractedInfo *> *foundFiles = [NSMutableArray array];
        NSMutableArray<NSDictionary *> *pending = [NSMutableArray array];
        NSArray *directories = @[
            @"/var/mobile/Documents/IPAInstaller",
            @"/var/mobile/Documents",
            @"/var/mobile/Downloads",
            @"/var/mobile/Media/Downloads"
        ];

        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableSet<NSString *> *seenIPAPaths = [NSMutableSet set];
        for (NSString *dir in directories) {
            if (![fm fileExistsAtPath:dir]) {
                if ([dir isEqualToString:@"/var/mobile/Documents/IPAInstaller"]) {
                    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
                }
                continue;
            }

            NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:nil];
            for (NSString *file in contents) {
                if (![file.pathExtension.lowercaseString isEqualToString:@"ipa"]) continue;
                NSString *path = [dir stringByAppendingPathComponent:file];
                if ([seenIPAPaths containsObject:path]) continue;
                [seenIPAPaths addObject:path];

                NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
                NSString *cacheKey = [self ipaCacheKeyForPath:path attributes:attrs];

                // 1. Check memory cache first
                __block NSDictionary *cachedRecord = nil;
                dispatch_sync(self.ipaCacheQueue, ^{
                    cachedRecord = self.ipaMetadataCache[path];
                });
                IPAExtractedInfo *cachedInfo = cachedRecord[@"info"];
                if ([cachedRecord[@"key"] isEqualToString:cacheKey] && cachedInfo) {
                    [foundFiles addObject:cachedInfo];
                    continue;
                }

                // 2. Check persistent cache (disk)
                IPAExtractedInfo *persistentInfo = [self loadPersistentCacheForPath:path cacheKey:cacheKey];
                if (persistentInfo) {
                    [foundFiles addObject:persistentInfo];
                    // Warm memory cache
                    dispatch_sync(self.ipaCacheQueue, ^{
                        self.ipaMetadataCache[path] = @{@"key": cacheKey, @"info": persistentInfo};
                    });
                    if (persistentInfo.icon) {
                        NSString *iconCacheKey = [self iconCacheKeyForPath:path key:cacheKey];
                        [self.ipaIconCache setObject:persistentInfo.icon forKey:iconCacheKey];
                    }
                    continue;
                }

                // 3. No cache — use placeholder and queue for extraction
                IPAExtractedInfo *placeholder = [self placeholderInfoForIPAPath:path size:attrs[NSFileSize]];
                [foundFiles addObject:placeholder];
                [pending addObject:@{@"path": path, @"key": cacheKey ?: @"", @"index": @(foundFiles.count - 1)}];
            }
        }

        // Phase 1 UI commit: show cached data / placeholders immediately
        dispatch_async(dispatch_get_main_queue(), ^{
            if (loadGeneration != self.ipaLoadGeneration) return;
            [self.ipaFiles removeAllObjects];
            [self.ipaFiles addObjectsFromArray:foundFiles];
            [self.tableView reloadData];
            [self updateDashboardStatistics];
            self.emptyLabel.hidden = (self.ipaFiles.count > 0);
            self.emptyLabel.frame = CGRectMake(20, self.view.bounds.size.height / 2 - 40, self.view.bounds.size.width - 40, 80);
            [self.refreshControl endRefreshing];
            [self.loadingIndicator stopAnimating];
            self.loadingIndicator.hidden = YES;
            self.isLoading = NO;
        });

        if (pending.count == 0) return;

        // Phase 2: metadata enrichment (limited concurrency, no icons)
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            dispatch_semaphore_t metaSem = dispatch_semaphore_create(4);
            dispatch_group_t metaGroup = dispatch_group_create();
            NSMutableArray<NSIndexPath *> *batchPaths = [NSMutableArray array];
            NSLock *batchLock = [[NSLock alloc] init];

            for (NSDictionary *job in pending) {
                dispatch_semaphore_wait(metaSem, DISPATCH_TIME_FOREVER);
                dispatch_group_enter(metaGroup);

                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    @autoreleasepool {
                        NSString *path = job[@"path"];
                        NSString *originalKey = job[@"key"];
                        IPAExtractedInfo *parsed = [[IPAExtractor sharedExtractor] extractMetadataFromIPA:path];

                        if (parsed) {
                            NSDictionary *currentAttrs = [fm attributesOfItemAtPath:path error:nil];
                            NSString *currentKey = [self ipaCacheKeyForPath:path attributes:currentAttrs];
                            if ([currentKey isEqualToString:originalKey]) {
                                // Save to persistent cache
                                [self persistCacheForPath:path info:parsed cacheKey:originalKey];
                                // Save to memory cache
                                dispatch_sync(self.ipaCacheQueue, ^{
                                    self.ipaMetadataCache[path] = @{@"key": originalKey, @"info": parsed};
                                });
                            }

                            dispatch_async(dispatch_get_main_queue(), ^{
                                if (loadGeneration == self.ipaLoadGeneration) {
                                    NSUInteger index = [job[@"index"] unsignedIntegerValue];
                                    if (index < self.ipaFiles.count) {
                                        IPAExtractedInfo *existing = self.ipaFiles[index];
                                        if ([existing.filePath isEqualToString:path]) {
                                            self.ipaFiles[index] = parsed;
                                            [batchLock lock];
                                            [batchPaths addObject:[NSIndexPath indexPathForRow:index inSection:0]];
                                            if (batchPaths.count >= 5) {
                                                NSArray *toReload = [batchPaths copy];
                                                [batchPaths removeAllObjects];
                                                [batchLock unlock];
                                                [self.tableView reloadRowsAtIndexPaths:toReload withRowAnimation:UITableViewRowAnimationNone];
                                            } else {
                                                [batchLock unlock];
                                            }
                                        }
                                    }
                                }
                                dispatch_semaphore_signal(metaSem);
                                dispatch_group_leave(metaGroup);
                            });
                        } else {
                            dispatch_semaphore_signal(metaSem);
                            dispatch_group_leave(metaGroup);
                        }
                    }
                });
            }

            dispatch_group_wait(metaGroup, DISPATCH_TIME_FOREVER);

            dispatch_async(dispatch_get_main_queue(), ^{
                if (loadGeneration == self.ipaLoadGeneration && batchPaths.count > 0) {
                    [batchLock lock];
                    NSArray *toReload = [batchPaths copy];
                    [batchPaths removeAllObjects];
                    [batchLock unlock];
                    [self.tableView reloadRowsAtIndexPaths:toReload withRowAnimation:UITableViewRowAnimationNone];
                }
                [self updateDashboardStatistics];
            });

            // Phase 3: icon enrichment (background, limited concurrency)
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
                dispatch_semaphore_t iconSem = dispatch_semaphore_create(2);
                dispatch_group_t iconGroup = dispatch_group_create();

                for (NSDictionary *job in pending) {
                    dispatch_semaphore_wait(iconSem, DISPATCH_TIME_FOREVER);
                    dispatch_group_enter(iconGroup);

                    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
                        @autoreleasepool {
                            NSString *path = job[@"path"];
                            NSString *originalKey = job[@"key"];

                            NSString *iconCacheKey = [self iconCacheKeyForPath:path key:originalKey];
                            UIImage *icon = [self.ipaIconCache objectForKey:iconCacheKey];

                            // 1. Check persistent icon cache on disk
                            if (!icon) {
                                NSString *iconPath = [self persistentIconPathForIPAPath:path];
                                if ([[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
                                    NSData *pngData = [NSData dataWithContentsOfFile:iconPath];
                                    if (pngData) icon = [UIImage imageWithData:pngData];
                                }
                            }

                            // 2. Extract from IPA if not cached
                            if (!icon) {
                                icon = [[IPAExtractor sharedExtractor] extractIconFromIPA:path];
                                if (icon) {
                                    // Save to persistent cache
                                    NSString *iconPath = [self persistentIconPathForIPAPath:path];
                                    NSData *pngData = UIImagePNGRepresentation(icon);
                                    if (pngData) [pngData writeToFile:iconPath atomically:YES];
                                }
                            }

                            if (icon) {
                                [self.ipaIconCache setObject:icon forKey:iconCacheKey];
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    if (loadGeneration == self.ipaLoadGeneration) {
                                        NSUInteger index = [job[@"index"] unsignedIntegerValue];
                                        if (index < self.ipaFiles.count) {
                                            IPAExtractedInfo *info = self.ipaFiles[index];
                                            if ([info.filePath isEqualToString:path] && !info.icon) {
                                                info.icon = icon;
                                                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
                                                GlassIPACell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
                                                if ([cell isKindOfClass:[GlassIPACell class]]) {
                                                    [cell setIconImage:icon animated:YES];
                                                }
                                            }
                                        }
                                    }
                                    dispatch_semaphore_signal(iconSem);
                                    dispatch_group_leave(iconGroup);
                                });
                            } else {
                                dispatch_semaphore_signal(iconSem);
                                dispatch_group_leave(iconGroup);
                            }
                        }
                    });
                }

                dispatch_group_wait(iconGroup, DISPATCH_TIME_FOREVER);
            });
        });
    });
}

- (void)refreshPulled:(UIRefreshControl *)sender {
    [self loadIPAFiles];
}

- (void)addIPATapped:(id)sender {
    NSArray *docTypes = @[
        @"com.apple.itunes.ipa",
        @"public.data",
        @"public.item",
        @"public.archive",
        @"public.zip-archive"
    ];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:docTypes inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray *)urls {
    if (urls.count == 0) return;

    [self showImportOverlay:YES];
    self.ipaLoadGeneration += 1;
    NSUInteger importGeneration = self.ipaLoadGeneration;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *destDir = @"/var/mobile/Documents/IPAInstaller";

        if (![fm fileExistsAtPath:destDir]) {
            [fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:nil];
        }

        __block NSInteger successCount = 0;
        __block NSInteger failCount = 0;
        NSMutableArray<NSString *> *importedPaths = [NSMutableArray array];

        for (NSURL *url in urls) {
            BOOL accessGranted = [url startAccessingSecurityScopedResource];

            @try {
                NSString *fileName = url.lastPathComponent;
                if (!fileName || fileName.length == 0) {
                    fileName = @"imported.ipa";
                }
                if (![fileName.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
                    fileName = [fileName stringByAppendingPathExtension:@"ipa"];
                }

                NSString *destPath = [destDir stringByAppendingPathComponent:fileName];

                if ([fm fileExistsAtPath:destPath]) {
                    [fm removeItemAtPath:destPath error:nil];
                    dispatch_async(self.ipaCacheQueue, ^{
                        [self.ipaMetadataCache removeObjectForKey:destPath];
                    });
                    [self clearPersistentCacheForPath:destPath];
                }

                NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
                __block NSError *coordError = nil;
                [coordinator coordinateReadingItemAtURL:url
                                                options:NSFileCoordinatorReadingWithoutChanges
                                                  error:&coordError
                                             byAccessor:^(NSURL *newURL) {
                    NSError *copyError = nil;
                    BOOL copied = [fm copyItemAtPath:newURL.path toPath:destPath error:&copyError];
                    if (copied) {
                        successCount++;
                        [importedPaths addObject:destPath];
                        [[Logger sharedLogger] info:[NSString stringWithFormat:@"Imported %@ to %@", fileName, destPath]];
                    } else {
                        failCount++;
                        [[Logger sharedLogger] error:[NSString stringWithFormat:@"Failed to import %@: %@", fileName, copyError.localizedDescription]];
                    }
                }];

                if (coordError) {
                    failCount++;
                    [[Logger sharedLogger] error:[NSString stringWithFormat:@"Coordinator failed for %@: %@", fileName, coordError.localizedDescription]];
                }
            } @catch (NSException *exception) {
                failCount++;
                [[Logger sharedLogger] error:[NSString stringWithFormat:@"Exception importing %@: %@", url.lastPathComponent, exception.reason]];
            } @finally {
                if (accessGranted) {
                    [url stopAccessingSecurityScopedResource];
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self showImportOverlay:NO];
            if (importGeneration == self.ipaLoadGeneration) {
                [self loadIPAFiles];
            }
            if (successCount > 0 && failCount == 0) {
                [self showToast:[NSString stringWithFormat:@"تمت إضافة %ld ملف IPA", (long)successCount] isError:NO];
            } else if (successCount > 0 && failCount > 0) {
                [self showToast:[NSString stringWithFormat:@"%ld نجح، %ld فشل", (long)successCount, (long)failCount] isError:YES];
            } else if (failCount > 0) {
                [self showToast:@"فشل إضافة الملفات" isError:YES];
            }
        });
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self showImportOverlay:NO];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.ipaFiles.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"GlassIPACell";
    GlassIPACell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[GlassIPACell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
    }
    [cell configureWithIPAInfo:self.ipaFiles[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([cell isKindOfClass:[GlassIPACell class]]) {
        [(GlassIPACell *)cell playEntranceAnimationWithDelay:MIN(indexPath.row * 0.045, 0.24)];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IPAExtractedInfo *info = self.ipaFiles[indexPath.row];
    IPAInstallViewController *installVC = [[IPAInstallViewController alloc] initWithIPAInfo:info];
    [self.navigationController pushViewController:installVC animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"حذف"
                                                                             handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        IPAExtractedInfo *info = self.ipaFiles[indexPath.row];
        [[NSFileManager defaultManager] removeItemAtPath:info.filePath error:nil];
        dispatch_async(self.ipaCacheQueue, ^{
            [self.ipaMetadataCache removeObjectForKey:info.filePath];
        });
        [self clearPersistentCacheForPath:info.filePath];
        [self.ipaFiles removeObjectAtIndex:indexPath.row];
        [self updateDashboardStatistics];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        completionHandler(YES);
    }];
    deleteAction.backgroundColor = [UIColor colorWithRed:0.8 green:0.25 blue:0.2 alpha:1.0];

    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

- (void)toggleViewMode:(id)sender {
}

@end
