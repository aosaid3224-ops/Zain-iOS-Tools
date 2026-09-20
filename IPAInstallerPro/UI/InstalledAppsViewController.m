//
//  InstalledAppsViewController.m
//  IPAInstallerPro — Design System "Quiet Precision" v2.0
//
//  Structured list, quiet filters, professional empty states.
//

#import "InstalledAppsViewController.h"
#import "ApplicationManager.h"
#import "AppDetailsViewController.h"
#import "IPTheme.h"
#import "IPComponents.h"

@interface InstalledAppsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray<AppInfo *> *apps;
@property (nonatomic, strong) NSArray<AppInfo *> *filteredApps;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) IPEmptyStateView *emptyView;
@property (nonatomic, strong) IPNoticeView *errorView;
@property (nonatomic, strong) UIView *loadingState;
@property (nonatomic, strong) UIStackView *skeletonStack;
@end

@implementation InstalledAppsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [IPTheme backgroundColor];
    // navigationItem.title يظهر في شريط التنقل فقط؛ أما self.title فينسخه UIKit إلى tabBarItem
    // ويحوّل عنوان التبويب من "التطبيقات المثبتة" إلى "التطبيقات"
    self.navigationItem.title = @"التطبيقات";
    self.searchText = @"";

    [self setupSegmentControl];
    [self setupSearchBar];
    [self setupTableView];
    [self setupLoadingAndEmpty];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(duplicateDidComplete:) name:@"IPAInstallerProDuplicateDidComplete" object:nil];
    [self loadApps];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"IPAInstallerProDuplicateDidComplete" object:nil];
}

- (void)duplicateDidComplete:(NSNotification *)note {
    if (![note.userInfo[@"success"] boolValue]) return;
    [self loadApps];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadApps];
}

#pragma mark - UI Setup

- (void)setupSegmentControl {
    _segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"الكل", @"مستخدم", @"نظام"]];
    _segmentControl.translatesAutoresizingMaskIntoConstraints = NO;
    _segmentControl.selectedSegmentIndex = 0;
    _segmentControl.backgroundColor = [IPTheme surfaceSubtleColor];
    _segmentControl.selectedSegmentTintColor = [IPTheme surfaceColor];
    _segmentControl.layer.cornerRadius = 8;
    [_segmentControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [IPTheme textTertiaryColor]} forState:UIControlStateNormal];
    [_segmentControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [IPTheme textPrimaryColor]} forState:UIControlStateSelected];
    [_segmentControl setTitleTextAttributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium]
    } forState:UIControlStateNormal];
    [_segmentControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_segmentControl];

    [NSLayoutConstraint activateConstraints:@[
        [_segmentControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:[IPTheme space12]],
        [_segmentControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:[IPTheme pageMargin]],
        [_segmentControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-[IPTheme pageMargin]],
        [_segmentControl.heightAnchor constraintEqualToConstant:34]
    ]];
}

- (void)setupSearchBar {
    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _searchBar.placeholder = @"البحث في التطبيقات…";
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.tintColor = [IPTheme accentColor];
    _searchBar.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    _searchBar.delegate = self;
    _searchBar.showsCancelButton = NO;
    _searchBar.backgroundColor = UIColor.clearColor;
    [self.view addSubview:_searchBar];

    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:_segmentControl.bottomAnchor],
        [_searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:4],
        [_searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-4],
        [_searchBar.heightAnchor constraintEqualToConstant:40]
    ]];
}

- (void)setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 72;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"AppCell"];
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupLoadingAndEmpty {
    // Skeleton rows — progressive, never a bare spinner.
    _skeletonStack = [[UIStackView alloc] init];
    _skeletonStack.translatesAutoresizingMaskIntoConstraints = NO;
    _skeletonStack.axis = UILayoutConstraintAxisVertical;
    _skeletonStack.spacing = 0;
    [self.view addSubview:_skeletonStack];
    for (NSInteger i = 0; i < 7; i++) {
        IPSkeletonView *sk = [[IPSkeletonView alloc] initWithFrame:CGRectZero];
        sk.translatesAutoresizingMaskIntoConstraints = NO;
        [_skeletonStack addArrangedSubview:sk];
        [sk.heightAnchor constraintEqualToConstant:64].active = YES;
    }
    _skeletonStack.hidden = YES;
    [NSLayoutConstraint activateConstraints:@[
        [_skeletonStack.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:8],
        [_skeletonStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:[IPTheme pageMargin]],
        [_skeletonStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-[IPTheme pageMargin]],
    ]];

    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _activityIndicator.color = [IPTheme textTertiaryColor];
    _activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:_activityIndicator];
    [NSLayoutConstraint activateConstraints:@[
        [_activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_activityIndicator.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:120]
    ]];
}

#pragma mark - Data Loading

- (void)loadApps {
    [self.activityIndicator stopAnimating];
    self.skeletonStack.hidden = NO;
    self.tableView.hidden = YES;
    [self.errorView removeFromSuperview];
    [self.emptyView removeFromSuperview];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<AppInfo *> *apps = nil;
        NSString *errorMsg = nil;
        @try {
            apps = [[ApplicationManager sharedManager] allInstalledApplications];
        } @catch (NSException *e) {
            errorMsg = [NSString stringWithFormat:@"تعذّر قراءة قائمة التطبيقات: %@", e.reason ?: @"خطأ غير معروف"];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.skeletonStack.hidden = YES;

            if (errorMsg) {
                self.errorView = [[IPNoticeView alloc] initWithMessage:errorMsg kind:@"error"];
                [self showCenteredState:self.errorView];
                return;
            }

            if (!apps || apps.count == 0) {
                self.emptyView = [[IPEmptyStateView alloc] initWithTitle:@"لا توجد تطبيقات"
                                                                message:@"لم يتم العثور على تطبيقات مثبتة على هذا الجهاز."
                                                            actionTitle:@"إعادة التحميل"
                                                                handler:^{ [self loadApps]; }];
                [self showCenteredState:self.emptyView];
                return;
            }

            self.apps = apps;
            [self filterApps];

            if (self.filteredApps.count == 0) {
                self.emptyView = [[IPEmptyStateView alloc] initWithTitle:@"لا نتائج"
                                                                message:@"جرّب تعديل كلمات البحث أو تغيير عامل التصفية."
                                                            actionTitle:nil handler:nil];
                [self showCenteredState:self.emptyView];
                return;
            }

            self.tableView.hidden = NO;
            [self.tableView reloadData];
        });
    });
}

- (void)showCenteredState:(UIView *)state {
    state.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:state];
    [NSLayoutConstraint activateConstraints:@[
        [state.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [state.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-20],
        [state.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:48],
        [state.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-48],
    ]];
}

#pragma mark - Filtering

- (void)segmentChanged:(UISegmentedControl *)sender {
    [self filterApps];
    [self.tableView reloadData];
}

- (void)filterApps {
    NSArray<AppInfo *> *segmented = self.apps;
    if (self.segmentControl.selectedSegmentIndex == 1) {
        segmented = [segmented filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isSystemApp == NO"]];
    } else if (self.segmentControl.selectedSegmentIndex == 2) {
        segmented = [segmented filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isSystemApp == YES"]];
    }

    NSString *query = [self.searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (query.length == 0) { self.filteredApps = segmented; return; }

    NSMutableArray<AppInfo *> *results = [NSMutableArray array];
    // Prefix match first
    for (AppInfo *app in segmented) {
        NSString *name = app.name ?: @"";
        NSString *bundleID = app.bundleID ?: @"";
        if ([name hasPrefix:query] || [bundleID hasPrefix:query]) [results addObject:app];
    }
    // Contains match
    for (AppInfo *app in segmented) {
        if ([results containsObject:app]) continue;
        NSString *name = app.name ?: @"";
        NSString *bundleID = app.bundleID ?: @"";
        NSString *version = app.version ?: @"";
        if ([name localizedStandardContainsString:query] ||
            [bundleID localizedStandardContainsString:query] ||
            [version localizedStandardContainsString:query]) {
            [results addObject:app];
        }
    }
    self.filteredApps = results;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell" forIndexPath:indexPath];
    AppInfo *app = self.filteredApps[indexPath.row];

    cell.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];

    IPListRow *row = [[IPListRow alloc] initWithFrame:CGRectZero];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.titleLabel.text = app.name;
    row.subtitleLabel.text = app.bundleID;
    row.metadataLabel.text = app.version;
    row.iconView.image = app.icon ?: [self placeholderIcon];
    [cell.contentView addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:[IPTheme pageMargin]],
        [row.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-[IPTheme pageMargin]],
        [row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
    ]];
    if (indexPath.row == self.filteredApps.count - 1) row.showsSeparator = NO;
    return cell;
}

- (UIImage *)placeholderIcon {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(44, 44), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [IPTheme surfaceSubtleColor].CGColor);
    CGContextFillRect(ctx, CGRectMake(0, 0, 44, 44));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    AppInfo *app = self.filteredApps[indexPath.row];
    AppDetailsViewController *detail = [[AppDetailsViewController alloc] initWithAppInfo:app];
    [self.navigationController pushViewController:detail animated:YES];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchText = searchText ?: @"";
    [self filterApps];
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = YES;
    UIButton *cancelButton = [searchBar valueForKey:@"cancelButton"];
    if ([cancelButton isKindOfClass:[UIButton class]]) [cancelButton setTitle:@"إلغاء" forState:UIControlStateNormal];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar { searchBar.showsCancelButton = NO; }

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    self.searchText = @"";
    [searchBar resignFirstResponder];
    [self filterApps];
    [self.tableView reloadData];
}

@end
