#import "IPAUnpackViewController.h"
#import "Core/IPAArchiveExtractor.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "IPAArchiveBrowserViewController.h"
#import "IPAFileCardCell.h"
#import "IPTheme.h"

@interface IPAUnpackViewController () <UIDocumentPickerDelegate, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *items;
@property (nonatomic, strong) IPAArchiveExtractionTask *activeTask;
@property (nonatomic, assign) BOOL sortByDate;
@property (nonatomic, assign) BOOL restoringItems;
@property (nonatomic, assign) BOOL hasLoadedPersistedItems;

// New UI v3.0.35
@property (nonatomic, strong) UIView *customHeader;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIView *sectionHeaderView;
@property (nonatomic, strong) UILabel *sectionTitleLabel;
@property (nonatomic, strong) UILabel *sectionCountLabel;
@property (nonatomic, strong) UIButton *fabButton;
@property (nonatomic, copy) NSString *searchText;
@end

static NSString * const kIPAExtractorPersistedItemsKey = @"IPAExtractor.PersistedItems.v1";

@implementation IPAUnpackViewController

- (void)dealloc {
    for (NSDictionary *item in self.items) {
        NSURL *url = [self urlForItem:item];
        if ([item[@"securityScopeActive"] boolValue] && url) {
            [url stopAccessingSecurityScopedResource];
        }
    }
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [IPTheme backgroundColor];
    self.title = @"";
    self.navigationItem.title = @"";
    self.searchText = @"";
    self.items = [NSMutableArray array];
    [self restorePersistedItems];
    [self setupNavigationBar];
    [self setupCustomHeader];
    [self setupSearchBar];
    [self setupSectionHeader];
    [self setupTableView];
    [self setupEmptyState];
    [self setupFAB];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
    if (!self.hasLoadedPersistedItems) {
        [self restorePersistedItems];
        self.hasLoadedPersistedItems = YES;
    }
    self.emptyLabel.hidden = self.items.count != 0;
    [self updateSectionHeader];
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.navigationBarHidden = NO;
    [self persistItems];
}

#pragma mark - Helpers

- (NSURL *)urlForItem:(NSDictionary *)item {
    id value = item[@"url"];
    return [value isKindOfClass:NSURL.class] ? value : nil;
}

- (NSString *)sourcePathForItem:(NSDictionary *)item {
    return item[@"originalPath"] ?: [self urlForItem:item].path;
}

- (void)persistItems {
    NSMutableArray *records = [NSMutableArray arrayWithCapacity:self.items.count];
    for (NSDictionary *item in self.items) {
        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        NSString *originalPath = [self sourcePathForItem:item];
        if (originalPath.length > 0) record[@"originalPath"] = originalPath;
        NSData *bookmark = item[@"bookmarkData"];
        if (bookmark.length > 0) record[@"bookmarkData"] = bookmark;
        for (NSString *key in @[@"displayName", @"name", @"status", @"outputPath", @"state", @"addedAt", @"updatedAt"]) {
            id value = item[key];
            if (value) record[key] = value;
        }
        record[@"unavailable"] = @([item[@"unavailable"] boolValue]);
        [records addObject:record];
    }
    [[NSUserDefaults standardUserDefaults] setObject:records forKey:kIPAExtractorPersistedItemsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSURL *)resolvePersistedURLForRecord:(NSDictionary *)record {
    NSData *bookmark = record[@"bookmarkData"];
    BOOL stale = NO;
    NSError *bookmarkError = nil;
    NSURL *url = bookmark.length > 0 ? [NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&bookmarkError] : nil;
    NSString *path = record[@"originalPath"];
    if (!url && path.length > 0) url = [NSURL fileURLWithPath:path];
    if (url && ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return nil;
    if (url && ![url.path.pathExtension.lowercaseString isEqualToString:@"ipa"]) return nil;
    return url;
}

- (void)restorePersistedItems {
    self.restoringItems = YES;
    NSArray<NSDictionary *> *records = [[NSUserDefaults standardUserDefaults] arrayForKey:kIPAExtractorPersistedItemsKey];
    for (NSDictionary *record in records) {
        if (![record isKindOfClass:NSDictionary.class]) continue;
        NSURL *url = [self resolvePersistedURLForRecord:record];
        NSString *originalPath = record[@"originalPath"] ?: url.path;
        if (originalPath.length == 0) continue;
        NSMutableDictionary *item = [@{
            @"url": url ?: [NSNull null],
            @"originalPath": originalPath,
            @"name": record[@"name"] ?: [originalPath lastPathComponent],
            @"displayName": record[@"displayName"] ?: [[originalPath lastPathComponent] stringByDeletingPathExtension],
            @"status": record[@"status"] ?: (url ? @"جاهز" : @"غير متاح"),
            @"state": record[@"state"] ?: (url ? @"ready" : @"unavailable"),
            @"progress": @0.0,
            @"extracting": @NO,
            @"unavailable": @(!url),
            @"outputPath": record[@"outputPath"] ?: @"",
            @"addedAt": record[@"addedAt"] ?: [NSDate date],
            @"updatedAt": record[@"updatedAt"] ?: [NSDate date]
        } mutableCopy];
        if (record[@"bookmarkData"]) item[@"bookmarkData"] = record[@"bookmarkData"];
        if (url) item[@"securityScopeActive"] = @([url startAccessingSecurityScopedResource]);
        [self.items addObject:item];
    }
    self.restoringItems = NO;
    self.hasLoadedPersistedItems = YES;
}

- (NSString *)rtlText:(NSString *)text {
    return [NSString stringWithFormat:@"\u2067%@\u2069", text ?: @""];
}

- (NSString *)ltrText:(NSString *)text {
    return [NSString stringWithFormat:@"\u2066%@\u2069", text ?: @""];
}

#pragma mark - UI Setup v3.0.35 (Auto Layout + Safe Area)

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationController.navigationBarHidden = YES;
}

- (void)setupCustomHeader {
    self.customHeader = [[UIView alloc] init];
    self.customHeader.translatesAutoresizingMaskIntoConstraints = NO;
    self.customHeader.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.customHeader];

    // Settings button
    UIButton *settingsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    settingsBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [settingsBtn setImage:[UIImage systemImageNamed:@"gear"] forState:UIControlStateNormal];
    settingsBtn.tintColor = [IPTheme textSecondaryColor];
    [settingsBtn addTarget:self action:@selector(settingsTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.customHeader addSubview:settingsBtn];

    // Title
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"فك حزمة IPA";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;
    [self.customHeader addSubview:title];

    [NSLayoutConstraint activateConstraints:@[
        [self.customHeader.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.customHeader.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.customHeader.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.customHeader.heightAnchor constraintEqualToConstant:48],

        [settingsBtn.leadingAnchor constraintEqualToAnchor:self.customHeader.leadingAnchor constant:12],
        [settingsBtn.centerYAnchor constraintEqualToAnchor:self.customHeader.centerYAnchor],
        [settingsBtn.widthAnchor constraintEqualToConstant:40],
        [settingsBtn.heightAnchor constraintEqualToConstant:40],

        [title.centerXAnchor constraintEqualToAnchor:self.customHeader.centerXAnchor],
        [title.centerYAnchor constraintEqualToAnchor:self.customHeader.centerYAnchor],
        [title.leadingAnchor constraintGreaterThanOrEqualToAnchor:settingsBtn.trailingAnchor constant:8]
    ]];
}

- (void)setupSearchBar {
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.placeholder = @"ابحث في حزم IPA...";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.tintColor = [IPTheme errorColor];
    self.searchBar.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.searchBar.delegate = self;
    self.searchBar.showsCancelButton = NO;
    self.searchBar.backgroundColor = [IPTheme textQuaternaryColor];
    self.searchBar.layer.cornerRadius = 14;
    self.searchBar.layer.masksToBounds = YES;
    [self.view addSubview:self.searchBar];

    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:self.customHeader.bottomAnchor constant:8],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.searchBar.heightAnchor constraintEqualToConstant:44]
    ]];
}

- (void)setupSectionHeader {
    self.sectionHeaderView = [[UIView alloc] init];
    self.sectionHeaderView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sectionHeaderView.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.sectionHeaderView];

    self.sectionTitleLabel = [[UILabel alloc] init];
    self.sectionTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.sectionTitleLabel.text = @"ملفاتي";
    self.sectionTitleLabel.textColor = [IPTheme textPrimaryColor];
    self.sectionTitleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.sectionTitleLabel.textAlignment = NSTextAlignmentRight;
    [self.sectionHeaderView addSubview:self.sectionTitleLabel];

    self.sectionCountLabel = [[UILabel alloc] init];
    self.sectionCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.sectionCountLabel.textColor = [IPTheme textSecondaryColor];
    self.sectionCountLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.sectionCountLabel.textAlignment = NSTextAlignmentLeft;
    [self.sectionHeaderView addSubview:self.sectionCountLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.sectionHeaderView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:8],
        [self.sectionHeaderView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.sectionHeaderView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.sectionHeaderView.heightAnchor constraintEqualToConstant:32],

        [self.sectionTitleLabel.leadingAnchor constraintEqualToAnchor:self.sectionHeaderView.leadingAnchor],
        [self.sectionTitleLabel.centerYAnchor constraintEqualToAnchor:self.sectionHeaderView.centerYAnchor],

        [self.sectionCountLabel.trailingAnchor constraintEqualToAnchor:self.sectionHeaderView.trailingAnchor],
        [self.sectionCountLabel.centerYAnchor constraintEqualToAnchor:self.sectionHeaderView.centerYAnchor]
    ]];
}

- (void)updateSectionHeader {
    NSInteger count = [self displayRows].count;
    self.sectionCountLabel.text = [NSString stringWithFormat:@"%ld عنصر", (long)count];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 80, 0);
    self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    self.tableView.estimatedRowHeight = 82.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.alwaysBounceVertical = YES;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.tableView registerClass:IPAFileCardCell.class forCellReuseIdentifier:@"IPAUnpackCell"];
    [self.view insertSubview:self.tableView atIndex:0];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.sectionHeaderView.bottomAnchor constant:4],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupEmptyState {
    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"لا توجد حزم IPA مضافة\nاضغط + لاختيار ملف خارجي";
    self.emptyLabel.textColor = [IPTheme textTertiaryColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = self.items.count != 0;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24.0],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24.0]
    ]];
    [self.view bringSubviewToFront:self.emptyLabel];
}

- (void)setupFAB {
    CGFloat size = 56;
    self.fabButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.fabButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.fabButton.backgroundColor = [IPTheme accentColor];
    self.fabButton.tintColor = UIColor.whiteColor;
    self.fabButton.layer.cornerRadius = size / 2.0;
    self.fabButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.fabButton.layer.shadowOffset = CGSizeMake(0, 4);
    self.fabButton.layer.shadowRadius = 8;
    self.fabButton.layer.shadowOpacity = 0.35;
    [self.fabButton setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    self.fabButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.fabButton addTarget:self action:@selector(addIPATapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.fabButton];
    [self.view bringSubviewToFront:self.fabButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.fabButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.fabButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [self.fabButton.widthAnchor constraintEqualToConstant:size],
        [self.fabButton.heightAnchor constraintEqualToConstant:size]
    ]];
}

#pragma mark - Actions

- (void)settingsTapped:(id)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"إعدادات فك الحزمة" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [sheet addAction:[UIAlertAction actionWithTitle:self.sortByDate ? @"الترتيب: الاسم" : @"الترتيب: التاريخ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.sortByDate = !self.sortByDate;
        [self.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)addIPATapped:(id)sender {
    void (^presentPicker)(void) = ^{
        UTType *appleIPAType = [UTType typeWithIdentifier:@"com.apple.itunes.ipa"];
        UTType *localIPAType = [UTType typeWithIdentifier:@"com.aosaid.ipainstallerpro.ipa"];
        UTType *extensionIPAType = [UTType typeWithFilenameExtension:@"ipa"];
        NSMutableArray<UTType *> *ipaTypes = [NSMutableArray array];
        for (UTType *type in @[appleIPAType ?: [NSNull null], localIPAType ?: [NSNull null], extensionIPAType ?: [NSNull null]]) {
            if (![type isKindOfClass:UTType.class] || [ipaTypes containsObject:type]) continue;
            [ipaTypes addObject:type];
        }
        if (ipaTypes.count == 0) {
            [self showMessage:@"تعذر تسجيل نوع IPA على هذا النظام."];
            return;
        }
        UIViewController *presenter = self;
        if (self.navigationController.visibleViewController == self) presenter = self.navigationController;
        if (!presenter.viewIfLoaded.window) presenter = self;
        if (presenter.presentedViewController) {
            NSLog(@"[IPAExtractor] picker presentation deferred: %@ is already presenting %@", presenter, presenter.presentedViewController);
            return;
        }
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:ipaTypes asCopy:NO];
        picker.delegate = self;
        picker.allowsMultipleSelection = YES;
        picker.modalPresentationStyle = UIModalPresentationPageSheet;
        NSLog(@"[IPAExtractor] presenting IPA picker from %@ with %lu allowed types", presenter, (unsigned long)ipaTypes.count);
        [presenter presentViewController:picker animated:YES completion:nil];
    };
    if ([NSThread isMainThread]) presentPicker();
    else dispatch_async(dispatch_get_main_queue(), presentPicker);
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSArray<NSURL *> *pickedURLs = [urls copy] ?: @[];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray<NSString *> *supportPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        NSString *workspace = [[(supportPaths.firstObject ?: NSTemporaryDirectory()) stringByAppendingPathComponent:@"IPAInstallerPro"] stringByAppendingPathComponent:@"IPAExtractor"];
        NSString *importDirectory = [workspace stringByAppendingPathComponent:@"Imported"];
        [fm createDirectoryAtPath:importDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        NSMutableArray<NSDictionary *> *imported = [NSMutableArray array];
        NSUInteger rejected = 0;
        for (NSURL *url in pickedURLs) {
            if (![url isKindOfClass:NSURL.class]) { rejected++; continue; }
            BOOL accessed = [url startAccessingSecurityScopedResource];
            __block NSString *fileName = url.lastPathComponent;
            if (fileName.length == 0) {
                [url getResourceValue:&fileName forKey:NSURLNameKey error:nil];
            }
            NSString *extension = fileName.pathExtension.lowercaseString ?: @"";
            if (![extension isEqualToString:@"ipa"]) {
                NSLog(@"[IPAExtractor] post-selection rejected non-IPA filename=%@ url=%@", fileName, url);
                rejected++;
                if (accessed) [url stopAccessingSecurityScopedResource];
                continue;
            }
            NSString *safeName = fileName.length > 0 ? fileName : @"Imported.ipa";
            NSString *temporary = [importDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@".importing-%@.ipa", NSUUID.UUID.UUIDString]];
            __block NSError *coordinationError = nil;
            __block BOOL copied = NO;
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            [coordinator coordinateReadingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL *coordinatedURL) {
                NSError *copyError = nil;
                copied = [fm copyItemAtPath:coordinatedURL.path toPath:temporary error:&copyError];
                if (!copied) coordinationError = copyError;
            }];
            if (accessed) [url stopAccessingSecurityScopedResource];
            if (!copied) {
                NSLog(@"[IPAExtractor] import failed filename=%@ error=%@", safeName, coordinationError);
                [fm removeItemAtPath:temporary error:nil];
                continue;
            }
            NSString *destination = [importDirectory stringByAppendingPathComponent:safeName];
            if ([fm fileExistsAtPath:destination]) {
                NSString *base = [safeName stringByDeletingPathExtension];
                NSUInteger suffix = 2;
                do { destination = [importDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ (%lu).ipa", base, (unsigned long)suffix++]]; } while ([fm fileExistsAtPath:destination]);
            }
            NSError *moveError = nil;
            if (![fm moveItemAtPath:temporary toPath:destination error:&moveError]) {
                NSLog(@"[IPAExtractor] import promote failed filename=%@ error=%@", safeName, moveError);
                [fm removeItemAtPath:temporary error:nil];
                continue;
            }
            NSURL *internalURL = [NSURL fileURLWithPath:destination];
            NSData *bookmark = [internalURL bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
            [imported addObject:@{ @"url": internalURL, @"path": destination, @"name": destination.lastPathComponent ?: safeName, @"bookmark": bookmark ?: [NSData data] }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUInteger added = 0;
            for (NSDictionary *record in imported) {
                NSString *path = record[@"path"];
                BOOL duplicate = NO;
                for (NSDictionary *existing in self.items) {
                    if ([[self sourcePathForItem:existing] isEqualToString:path]) { duplicate = YES; break; }
                }
                if (duplicate) continue;
                NSString *name = record[@"name"] ?: [path lastPathComponent];
                NSMutableDictionary *item = [@{
                    @"url": record[@"url"], @"name": name,
                    @"displayName": [name stringByDeletingPathExtension], @"status": @"جاهز",
                    @"progress": @0.0, @"extracting": @NO, @"securityScopeActive": @NO,
                    @"bookmarkData": record[@"bookmark"] ?: [NSData data], @"originalPath": path,
                    @"state": @"ready", @"unavailable": @NO, @"addedAt": [NSDate date], @"updatedAt": [NSDate date]
                } mutableCopy];
                [self.items addObject:item];
                added++;
            }
            if (added > 0) [self persistItems];
            self.emptyLabel.hidden = self.items.count > 0;
            [self updateSectionHeader];
            [self.tableView reloadData];
            NSLog(@"[IPAExtractor] post-selection import complete accepted=%lu rejected=%lu", (unsigned long)added, (unsigned long)rejected);
            if (added == 0 && pickedURLs.count > 0) [self showMessage:@"لم يتم قبول أي ملف؛ يجب أن يكون الامتداد .ipa."];
        });
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
}

#pragma mark - Display & Filtering

- (NSArray<NSDictionary *> *)displayRows {
    NSString *query = self.searchText.lowercaseString ?: @"";
    NSArray *visibleItems = [self.items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        if (query.length == 0) return YES;
        NSString *name = [item[@"displayName"] ?: item[@"name"] ?: @"" lowercaseString];
        return [name containsString:query];
    }]];
    visibleItems = [visibleItems sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if (self.sortByDate) {
            NSDate *aDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:[self sourcePathForItem:a] error:nil] objectForKey:NSFileModificationDate];
            NSDate *bDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:[self sourcePathForItem:b] error:nil] objectForKey:NSFileModificationDate];
            return [bDate compare:aDate];
        }
        return [[a[@"displayName"] ?: a[@"name"] ?: @"" description] localizedCaseInsensitiveCompare:[b[@"displayName"] ?: b[@"name"] ?: @"" description]];
    }];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSMutableDictionary *item in visibleItems) {
        [rows addObject:@{ @"kind": @"source", @"item": item }];
        NSString *output = item[@"outputPath"];
        if (output.length > 0) {
            [rows addObject:@{ @"kind": @"output", @"item": item }];
        }
    }
    return rows;
}

- (void)toggleSort:(id)sender {
    self.sortByDate = !self.sortByDate;
    [self updateSectionHeader];
    [self.tableView reloadData];
}

- (NSDictionary *)rowDescriptorAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *rows = [self displayRows];
    return indexPath.row < rows.count ? rows[indexPath.row] : nil;
}

#pragma mark - Extraction Logic

- (void)confirmExtractionForItem:(NSMutableDictionary *)item indexPath:(NSIndexPath *)indexPath {
    if ([item[@"extracting"] boolValue] || self.activeTask) return;
    NSURL *url = item[@"url"];
    NSString *name = item[@"displayName"] ?: item[@"name"] ?: @"IPA";
    BOOL hasPreviousOutput = [item[@"outputPath"] length] > 0;
    NSString *message = hasPreviousOutput
        ? [NSString stringWithFormat:@"سيتم إنشاء ناتج جديد داخل مساحة العمل الخاصة بالأداة، مع إبقاء الناتج السابق دون تغيير.\n\n%@", name]
        : [NSString stringWithFormat:@"سيتم إنشاء مجلد الناتج داخل مساحة العمل الخاصة بالأداة دون تعديل أو حذف ملف IPA الأصلي.\n\n%@", name];
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:hasPreviousOutput ? @"إعادة استخراج IPA" : @"فك حزمة IPA" message:message preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"نعم، استخراج" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *outputPath = [[IPAArchiveExtractor sharedExtractor] uniqueOutputDirectoryForIPAPath:url.path];
        item[@"extracting"] = @YES;
        item[@"state"] = @"extracting";
        item[@"status"] = @"جارٍ التحقق والاستخراج...";
        item[@"progress"] = @0.0;
        [self reloadItem:item];
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"إلغاء" style:UIBarButtonItemStylePlain target:self action:@selector(cancelActiveExtraction:)];
        __weak typeof(self) weakSelf = self;
        self.activeTask = [[IPAArchiveExtractor sharedExtractor] extractIPAAtPath:url.path outputPath:outputPath progress:^(double progress, NSString *status) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            item[@"progress"] = @(progress);
            item[@"status"] = status ?: @"جارٍ العمل...";
            [strongSelf reloadItem:item];
        } completion:^(IPAArchiveExtractionResult *result) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            item[@"extracting"] = @NO;
            strongSelf.activeTask = nil;
            strongSelf.navigationItem.leftBarButtonItem = nil;
            item[@"progress"] = result.success ? @1.0 : @0.0;
            item[@"state"] = result.success ? @"success" : (result.cancelled ? @"cancelled" : @"failed");
            item[@"status"] = result.success ? @"نجح الاستخراج" : (result.cancelled ? @"أُلغي" : (result.errorMessage.length ? result.errorMessage : @"فشل فك الحزمة"));
            if (result.success) item[@"outputPath"] = result.outputPath ?: @"";
            [strongSelf reloadItem:item];
            if (result.success) {
                UIAlertController *done = [UIAlertController alertControllerWithTitle:@"تم فك الحزمة" message:[NSString stringWithFormat:@"تم استخراج كامل المحتوى إلى:\n%@\n\nعدد العناصر: %lu", [strongSelf ltrText:result.outputPath], (unsigned long)result.extractedEntryCount] preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleCancel handler:nil]];
                [done addAction:[UIAlertAction actionWithTitle:@"فتح المجلد" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [strongSelf openOutputPath:result.outputPath]; }]];
                [strongSelf presentViewController:done animated:YES completion:nil];
            } else if (result.cancelled) {
                UIAlertController *cancelled = [UIAlertController alertControllerWithTitle:@"تم إلغاء الاستخراج" message:@"تم تنظيف الحالة المؤقتة ولم يتم اعتماد مجلد ناقص كناتج." preferredStyle:UIAlertControllerStyleAlert];
                [cancelled addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:cancelled animated:YES completion:nil];
            } else {
                UIAlertController *failed = [UIAlertController alertControllerWithTitle:@"فشل فك الحزمة" message:result.errorMessage ?: @"تعذر استخراج الملف" preferredStyle:UIAlertControllerStyleAlert];
                [failed addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:failed animated:YES completion:nil];
            }
        }];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)cancelActiveExtraction:(id)sender {
    if (!self.activeTask) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إلغاء الاستخراج" message:@"هل تريد إلغاء العملية؟ سيتم تنظيف الملفات المؤقتة ولن يتغير ملف IPA الأصلي." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"متابعة" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء العملية" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self.activeTask cancel]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)reloadItem:(NSMutableDictionary *)item {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadItem:item]; });
        return;
    }
    item[@"updatedAt"] = [NSDate date];
    [self persistItems];
    self.emptyLabel.hidden = self.items.count != 0;
    [self updateSectionHeader];
    [self.tableView reloadData];
}

- (void)openOutputPath:(NSString *)path {
    if (path.length == 0) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self showMessage:@"الناتج غير متاح؛ قد يكون المجلد قد نُقل أو حُذف خارج Spider."];
        return;
    }
    IPAArchiveBrowserViewController *browser = [[IPAArchiveBrowserViewController alloc] initWithRootPath:path];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:browser];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)sharePath:(NSString *)path {
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self showMessage:@"الملف أو المجلد غير متاح للمشاركة."];
        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)savePathToFiles:(NSString *)path {
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self showMessage:@"الناتج غير متاح للحفظ في الملفات."];
        return;
    }
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[[NSURL fileURLWithPath:path]] asCopy:YES];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)showInfoForPath:(NSString *)path title:(NSString *)title {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    BOOL isDirectory = [attrs[NSFileType] isEqualToString:NSFileTypeDirectory];
    NSString *message = [NSString stringWithFormat:@"المسار:\n%@\n\nالنوع: %@\nالحجم: %@\nالتاريخ: %@", [self ltrText:path], isDirectory ? @"مجلد" : @"ملف", [self formattedSize:[attrs[NSFileSize] unsignedLongLongValue]], [self formattedDate:attrs[NSFileModificationDate]]];
    [self showAlertWithTitle:title ?: @"معلومات الملف" message:message];
}

- (void)renameDisplayNameForItem:(NSMutableDictionary *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إعادة تسمية العرض" message:@"سيتم تغيير الاسم الظاهر داخل Spider فقط، ولن يتغير اسم الملف الحقيقي." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = item[@"displayName"] ?: item[@"name"]; field.clearButtonMode = UITextFieldViewModeWhileEditing; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (value.length > 0) { item[@"displayName"] = value; [self reloadItem:item]; } }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)renameOutputForItem:(NSMutableDictionary *)item {
    NSString *oldPath = item[@"outputPath"];
    if (oldPath.length == 0) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إعادة تسمية الناتج" message:@"سيتم تغيير اسم مجلد الاستخراج الحقيقي فقط، ولن يتغير ملف IPA الأصلي." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = oldPath.lastPathComponent;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length == 0 || [name containsString:@"/"] || [name containsString:@"\\"] || [name isEqualToString:@"."] || [name isEqualToString:@".."] || [name containsString:@":"]) {
            [self showMessage:@"اسم المجلد غير صالح."];
            return;
        }
        NSString *newPath = [[oldPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:newPath]) {
            [self showMessage:@"يوجد مجلد بهذا الاسم؛ اختر اسمًا آخر."];
            return;
        }
        NSError *error = nil;
        if (![[NSFileManager defaultManager] moveItemAtPath:oldPath toPath:newPath error:&error]) {
            [self showMessage:error.localizedDescription ?: @"تعذر إعادة تسمية الناتج."];
            return;
        }
        item[@"outputPath"] = newPath;
        item[@"state"] = @"success";
        [self reloadItem:item];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)removeSourceFromList:(NSMutableDictionary *)item {
    NSURL *url = [self urlForItem:item];
    if ([item[@"securityScopeActive"] boolValue] && url) [url stopAccessingSecurityScopedResource];
    [self.items removeObjectIdenticalTo:item];
    [self persistItems];
    self.emptyLabel.hidden = self.items.count > 0;
    [self updateSectionHeader];
    [self.tableView reloadData];
}

- (void)deleteOutputForItem:(NSMutableDictionary *)item {
    NSString *path = item[@"outputPath"];
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"حذف الناتج" message:@"سيُحذف مجلد الاستخراج فقط، ولن يُحذف ملف IPA الأصلي ولن يُزال المصدر من القائمة." preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"حذف الناتج" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { NSError *error = nil; if ([[NSFileManager defaultManager] fileExistsAtPath:path] && ![[NSFileManager defaultManager] removeItemAtPath:path error:&error]) { [self showMessage:error.localizedDescription ?: @"تعذر حذف الناتج"]; return; }         [item removeObjectForKey:@"outputPath"]; item[@"state"] = @"ready"; item[@"status"] = @"جاهز لإعادة الاستخراج"; [self reloadItem:item]; }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (UIImage *)ipaFileIcon {
    CGSize size = CGSizeMake(52, 52);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        // Background rounded rect
        CGRect bgRect = CGRectMake(2, 2, 48, 48);
        UIBezierPath *bgPath = [UIBezierPath bezierPathWithRoundedRect:bgRect cornerRadius:10];
        [[UIColor colorWithRed:0.15 green:0.25 blue:0.40 alpha:1.0] setFill];
        [bgPath fill];
        // White page icon
        CGRect pageRect = CGRectMake(16, 10, 20, 26);
        UIBezierPath *pagePath = [UIBezierPath bezierPathWithRoundedRect:pageRect cornerRadius:3];
        [[IPTheme textPrimaryColor] setFill];
        [pagePath fill];
        // Green badge
        CGRect badgeRect = CGRectMake(10, 32, 32, 14);
        UIBezierPath *badgePath = [UIBezierPath bezierPathWithRoundedRect:badgeRect cornerRadius:4];
        [[IPTheme successColor] setFill];
        [badgePath fill];
        // IPA text
        NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:8 weight:UIFontWeightBold], NSForegroundColorAttributeName: UIColor.whiteColor };
        [@"IPA" drawInRect:CGRectMake(10, 34, 32, 10) withAttributes:attrs];
    }];
}

- (NSString *)formattedSize:(unsigned long long)bytes {
    if (bytes < 1024) return [NSString stringWithFormat:@"%llu B", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    if (bytes < 1024ULL * 1024ULL * 1024ULL) return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}

- (NSString *)formattedDate:(NSDate *)date {
    if (!date) return @"غير معروف";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ar"];
    return [formatter stringFromDate:date];
}

- (void)showMessage:(NSString *)message { [self showAlertWithTitle:@"فك حزمة IPA" message:message]; }

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    alert.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentActionsForDescriptor:(NSDictionary *)descriptor fromButton:(UIButton *)button {
    if (!descriptor) return;
    BOOL isOutput = [descriptor[@"kind"] isEqualToString:@"output"];
    NSMutableDictionary *item = descriptor[@"item"];
    NSString *title = isOutput ? @"إجراءات المجلد المستخرج" : @"إجراءات ملف IPA";
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    __weak typeof(self) weakSelf = self;
    void (^add)(NSString *, UIAlertActionStyle, dispatch_block_t) = ^(NSString *name, UIAlertActionStyle style, dispatch_block_t block) {
        [sheet addAction:[UIAlertAction actionWithTitle:name style:style handler:^(UIAlertAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (self && block) block();
        }]];
    };
    if (isOutput) {
        add(@"فتح", UIAlertActionStyleDefault, ^{ [weakSelf openOutputPath:item[@"outputPath"]]; });
        add(@"حفظ في الملفات", UIAlertActionStyleDefault, ^{ [weakSelf savePathToFiles:item[@"outputPath"]]; });
        add(@"مشاركة", UIAlertActionStyleDefault, ^{ [weakSelf sharePath:item[@"outputPath"]]; });
        add(@"إعادة تسمية", UIAlertActionStyleDefault, ^{ [weakSelf renameOutputForItem:item]; });
        add(@"نسخ المسار", UIAlertActionStyleDefault, ^{ [UIPasteboard generalPasteboard].string = item[@"outputPath"]; [weakSelf showMessage:@"تم نسخ المسار."]; });
        add(@"معلومات الملف", UIAlertActionStyleDefault, ^{ [weakSelf showInfoForPath:item[@"outputPath"] title:@"معلومات الناتج"]; });
        add(@"حذف الناتج", UIAlertActionStyleDestructive, ^{ [weakSelf deleteOutputForItem:item]; });
    } else {
        BOOL available = ![item[@"unavailable"] boolValue] && [self urlForItem:item] != nil;
        NSString *extractTitle = [item[@"outputPath"] length] > 0 ? @"إعادة استخراج" : @"استخراج";
        UIAlertAction *extract = [UIAlertAction actionWithTitle:extractTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [weakSelf confirmExtractionForItem:item indexPath:nil]; }];
        extract.enabled = available && !self.activeTask;
        [sheet addAction:extract];
        add(@"مشاركة", UIAlertActionStyleDefault, ^{ [weakSelf sharePath:[weakSelf sourcePathForItem:item]]; });
        add(@"فتح في الملفات", UIAlertActionStyleDefault, ^{ [weakSelf sharePath:[weakSelf sourcePathForItem:item]]; });
        add(@"إعادة تسمية العرض", UIAlertActionStyleDefault, ^{ [weakSelf renameDisplayNameForItem:item]; });
        add(@"معلومات الملف", UIAlertActionStyleDefault, ^{ [weakSelf showInfoForPath:[weakSelf sourcePathForItem:item] title:@"معلومات IPA"]; });
        add(@"إزالة من القائمة", UIAlertActionStyleDestructive, ^{ [weakSelf removeSourceFromList:item]; });
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = button ?: self.view;
        sheet.popoverPresentationController.sourceRect = button ? button.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)moreTapped:(UIButton *)button {
    NSDictionary *descriptor = [self rowDescriptorAtIndexPath:[NSIndexPath indexPathForRow:button.tag inSection:0]];
    [self presentActionsForDescriptor:descriptor fromButton:button];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    NSDictionary *descriptor = [self rowDescriptorAtIndexPath:indexPath];
    if (!descriptor) return nil;
    NSString *kind = descriptor[@"kind"];
    NSMutableDictionary *item = descriptor[@"item"];
    BOOL isOutput = [kind isEqualToString:@"output"];
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return nil;
        NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
        if (isOutput) {
            [actions addObject:[UIAction actionWithTitle:@"فتح" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(__kindof UIAction *action) { [self openOutputPath:item[@"outputPath"]]; }]];
            [actions addObject:[UIAction actionWithTitle:@"حفظ في الملفات" image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(__kindof UIAction *action) { [self savePathToFiles:item[@"outputPath"]]; }]];
            [actions addObject:[UIAction actionWithTitle:@"مشاركة" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(__kindof UIAction *action) { [self sharePath:item[@"outputPath"]]; }]];
            [actions addObject:[UIAction actionWithTitle:@"إعادة تسمية" image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(__kindof UIAction *action) { [self renameOutputForItem:item]; }]];
            [actions addObject:[UIAction actionWithTitle:@"نسخ المسار" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(__kindof UIAction *action) { [UIPasteboard generalPasteboard].string = item[@"outputPath"]; [self showMessage:@"تم نسخ المسار."]; }]];
            [actions addObject:[UIAction actionWithTitle:@"معلومات الملف" image:[UIImage systemImageNamed:@"info.circle"] identifier:nil handler:^(__kindof UIAction *action) { [self showInfoForPath:item[@"outputPath"] title:@"معلومات الناتج"]; }]];
            [actions addObject:[UIAction actionWithTitle:@"حذف الناتج" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__kindof UIAction *action) { [self deleteOutputForItem:item]; }]];
        } else {
            NSString *extractTitle = [item[@"outputPath"] length] > 0 ? @"إعادة استخراج" : @"استخراج";
            [actions addObject:[UIAction actionWithTitle:extractTitle image:[UIImage systemImageNamed:@"archivebox"] identifier:nil handler:^(__kindof UIAction *action) { [self confirmExtractionForItem:item indexPath:indexPath]; }]];
            [actions addObject:[UIAction actionWithTitle:@"مشاركة" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(__kindof UIAction *action) { [self sharePath:[self sourcePathForItem:item]]; }]];
            [actions addObject:[UIAction actionWithTitle:@"فتح في الملفات" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(__kindof UIAction *action) { [self sharePath:[self sourcePathForItem:item]]; }]];
            [actions addObject:[UIAction actionWithTitle:@"إعادة تسمية العرض" image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(__kindof UIAction *action) { [self renameDisplayNameForItem:item]; }]];
            [actions addObject:[UIAction actionWithTitle:@"معلومات الملف" image:[UIImage systemImageNamed:@"info.circle"] identifier:nil handler:^(__kindof UIAction *action) { [self showInfoForPath:[self sourcePathForItem:item] title:@"معلومات IPA"]; }]];
            [actions addObject:[UIAction actionWithTitle:@"إزالة من القائمة" image:[UIImage systemImageNamed:@"minus.circle"] identifier:nil handler:^(__kindof UIAction *action) { [self removeSourceFromList:item]; }]];
        }
        return [UIMenu menuWithTitle:@"إجراءات" children:actions];
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self displayRows].count;
}

- (IPAFileCardCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IPAFileCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"IPAUnpackCell" forIndexPath:indexPath];
    NSDictionary *descriptor = [self rowDescriptorAtIndexPath:indexPath];
    NSString *kind = descriptor[@"kind"];
    NSMutableDictionary *item = descriptor[@"item"];
    BOOL output = [kind isEqualToString:@"output"];
    NSString *sourceTitle = item[@"displayName"] ?: item[@"name"] ?: @"IPA";
    NSString *sourceName = item[@"name"] ?: [NSString stringWithFormat:@"%@.ipa", sourceTitle];
    NSString *sourcePath = [self sourcePathForItem:item];
    NSDictionary *sourceAttrs = sourcePath.length ? [[NSFileManager defaultManager] attributesOfItemAtPath:sourcePath error:nil] : @{};
    unsigned long long sourceBytes = [sourceAttrs[NSFileSize] unsignedLongLongValue];
    NSString *sizeText = sourceBytes > 0 ? [self formattedSize:sourceBytes] : @"الحجم غير متاح";
    UIImage *icon = nil;
    NSString *title = nil;
    NSString *subtitle = nil;
    NSString *meta = nil;
    UIColor *statusColor = nil;
    if (output) {
        BOOL outputAvailable = [[NSFileManager defaultManager] fileExistsAtPath:item[@"outputPath"]];
        NSDictionary *attrs = outputAvailable ? [[NSFileManager defaultManager] attributesOfItemAtPath:item[@"outputPath"] error:nil] : @{};
        NSString *outputSize = outputAvailable ? [self formattedSize:[attrs[NSFileSize] unsignedLongLongValue]] : @"غير متاح";
        title = @"المجلد المستخرج";
        subtitle = [NSString stringWithFormat:@"↳ %@ — Extracted", sourceTitle];
        meta = outputAvailable ? [NSString stringWithFormat:@"%@ • %@", outputSize, [self formattedDate:attrs[NSFileModificationDate]]] : @"الناتج غير متاح";
        icon = [[UIImage systemImageNamed:@"folder.fill"] imageWithTintColor:[IPTheme accentColor]];
        statusColor = outputAvailable ? [IPTheme successColor] : [UIColor colorWithRed:0.95 green:0.63 blue:0.25 alpha:1.0];
    } else {
        BOOL extracting = [item[@"extracting"] boolValue];
        BOOL unavailable = [item[@"unavailable"] boolValue];
        double progress = [item[@"progress"] doubleValue];
        NSString *status = item[@"status"] ?: @"جاهز";
        title = sourceTitle;
        subtitle = sourceName;
        if (extracting) meta = [NSString stringWithFormat:@"%@ • %.0f%% • %@", status, progress * 100.0, sizeText];
        else if (unavailable) meta = [NSString stringWithFormat:@"غير متاح • %@", sizeText];
        else meta = [NSString stringWithFormat:@"%@ • %@ • IPA", sizeText, status];
        icon = [self ipaFileIcon];
        statusColor = extracting ? [IPTheme accentColor] : (unavailable ? [UIColor colorWithRed:0.95 green:0.63 blue:0.25 alpha:1.0] : [IPTheme successColor]);
    }
    [cell configureWithTitle:title subtitle:subtitle meta:meta icon:icon statusColor:statusColor isChild:output];
    cell.moreButton.tag = indexPath.row;
    [cell.moreButton removeTarget:nil action:@selector(moreTapped:) forControlEvents:UIControlEventTouchUpInside];
    [cell.moreButton addTarget:self action:@selector(moreTapped:) forControlEvents:UIControlEventTouchUpInside];
    cell.selectionStyle = (!output && [item[@"extracting"] boolValue]) ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *descriptor = [self rowDescriptorAtIndexPath:indexPath];
    if (!descriptor) return;
    NSMutableDictionary *item = descriptor[@"item"];
    if ([descriptor[@"kind"] isEqualToString:@"output"]) {
        [self openOutputPath:item[@"outputPath"]];
    } else if (![item[@"extracting"] boolValue] && !self.activeTask) {
        [self confirmExtractionForItem:item indexPath:indexPath];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *descriptor = [self rowDescriptorAtIndexPath:indexPath];
    if (!descriptor) return nil;
    NSMutableDictionary *item = descriptor[@"item"];
    BOOL output = [descriptor[@"kind"] isEqualToString:@"output"];
    NSString *title = output ? @"حذف الناتج" : @"إزالة من القائمة";
    UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:title handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        if (output) [self deleteOutputForItem:item]; else [self removeSourceFromList:item];
        completionHandler(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[action]];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchText = searchText ?: @"";
    [self updateSectionHeader];
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = YES;
    UIButton *cancelButton = [searchBar valueForKey:@"cancelButton"];
    if ([cancelButton isKindOfClass:[UIButton class]]) {
        [cancelButton setTitle:@"إلغاء" forState:UIControlStateNormal];
    }
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = NO;
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    self.searchText = @"";
    [searchBar resignFirstResponder];
    [self updateSectionHeader];
    [self.tableView reloadData];
}

@end
