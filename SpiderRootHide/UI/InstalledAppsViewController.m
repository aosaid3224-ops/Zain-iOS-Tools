#import "InstalledAppsViewController.h"
#import "ApplicationManager.h"
#import "AppDetailsViewController.h"
#import "IPTheme.h"

@interface InstalledAppsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray<AppInfo *> *apps;
@property (nonatomic, strong) NSArray<AppInfo *> *filteredApps;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIButton *retryButton;
@end

@implementation InstalledAppsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [IPTheme backgroundColor];
    self.title = @"\u0627\u0644\u062a\u0637\u0628\u064a\u0642\u0627\u062a";
    self.searchText = @"";

    [self setupSegmentControl];
    [self setupSearchBar];
    [self setupTableView];
    [self setupActivityIndicator];
    [self setupErrorUI];
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

- (void)setupSegmentControl {
    _segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"\u0627\u0644\u0643\u0644", @"\u0645\u0633\u062a\u062e\u062f\u0645", @"\u0646\u0638\u0627\u0645"]];
    _segmentControl.translatesAutoresizingMaskIntoConstraints = NO;
    _segmentControl.selectedSegmentIndex = 0;
    _segmentControl.backgroundColor = [IPTheme cardColor];
    _segmentControl.layer.cornerRadius = 12;
    _segmentControl.layer.masksToBounds = YES;
    _segmentControl.selectedSegmentTintColor = [IPTheme accentColor];
    [_segmentControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
    [_segmentControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_segmentControl];

    [NSLayoutConstraint activateConstraints:@[
        [_segmentControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [_segmentControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [_segmentControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [_segmentControl.heightAnchor constraintEqualToConstant:36]
    ]];
}

- (void)setupSearchBar {
    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _searchBar.placeholder = @"\u0627\u0644\u0628\u062d\u062b \u0641\u064a \u0627\u0644\u062a\u0637\u0628\u064a\u0642\u0627\u062a...";
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.tintColor = [IPTheme accentColor];
    _searchBar.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    _searchBar.delegate = self;
    _searchBar.showsCancelButton = NO;
    _searchBar.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_searchBar];

    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:_segmentControl.bottomAnchor constant:6],
        [_searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [_searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [_searchBar.heightAnchor constraintEqualToConstant:42]
    ]];
}

- (void)setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 72;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"AppCell"];
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:4],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupActivityIndicator {
    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _activityIndicator.color = [UIColor colorWithWhite:0.5 alpha:1.0];
    _activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:_activityIndicator];

    [NSLayoutConstraint activateConstraints:@[
        [_activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_activityIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

- (void)setupErrorUI {
    _errorLabel = [[UILabel alloc] init];
    _errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _errorLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _errorLabel.textColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.3 alpha:1.0];
    _errorLabel.textAlignment = NSTextAlignmentCenter;
    _errorLabel.numberOfLines = 0;
    _errorLabel.hidden = YES;
    [self.view addSubview:_errorLabel];

    _retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_retryButton setTitle:@"\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629" forState:UIControlStateNormal];
    _retryButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_retryButton setTitleColor:[IPTheme accentColor] forState:UIControlStateNormal];
    [_retryButton addTarget:self action:@selector(loadApps) forControlEvents:UIControlEventTouchUpInside];
    _retryButton.hidden = YES;
    [self.view addSubview:_retryButton];

    [NSLayoutConstraint activateConstraints:@[
        [_errorLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_errorLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30],
        [_errorLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [_errorLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],

        [_retryButton.topAnchor constraintEqualToAnchor:_errorLabel.bottomAnchor constant:16],
        [_retryButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];
}

- (void)loadApps {
    [self.activityIndicator startAnimating];
    self.tableView.hidden = YES;
    self.errorLabel.hidden = YES;
    self.retryButton.hidden = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<AppInfo *> *apps = nil;
        NSString *errorMsg = nil;

        @try {
            apps = [[ApplicationManager sharedManager] allInstalledApplications];
        } @catch (NSException *e) {
            errorMsg = [NSString stringWithFormat:@"\u062e\u0637\u0623: %@", e.reason ?: @"\u063a\u064a\u0631 \u0645\u0639\u0631\u0648\u0641"];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.activityIndicator stopAnimating];

            if (errorMsg) {
                self.errorLabel.text = errorMsg;
                self.errorLabel.hidden = NO;
                self.retryButton.hidden = NO;
                self.tableView.hidden = YES;
                return;
            }

            if (!apps || apps.count == 0) {
                self.errorLabel.text = @"\u0644\u0627 \u062a\u0648\u062c\u062f \u062a\u0637\u0628\u064a\u0642\u0627\u062a \u0645\u062b\u0628\u062a\u0629";
                self.errorLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
                self.errorLabel.hidden = NO;
                self.retryButton.hidden = NO;
                self.tableView.hidden = YES;
                return;
            }

            self.apps = apps;
            [self filterApps];
            self.tableView.hidden = NO;
            [self.tableView reloadData];
        });
    });
}

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
    if (query.length == 0) {
        self.filteredApps = segmented;
        return;
    }

    NSMutableArray<AppInfo *> *results = [NSMutableArray array];

    for (AppInfo *app in segmented) {
        NSString *name = app.name ?: @"";
        NSString *bundleID = app.bundleID ?: @"";
        if ([name hasPrefix:query] || [bundleID hasPrefix:query]) {
            [results addObject:app];
        }
    }

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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell" forIndexPath:indexPath];
    AppInfo *app = self.filteredApps[indexPath.row];

    cell.backgroundColor = [UIColor clearColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    cell.textLabel.text = app.name;
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ \u2022 %@", app.bundleID, app.version];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];

    if (app.icon) {
        cell.imageView.image = app.icon;
    } else {
        cell.imageView.image = [self placeholderIcon];
    }
    cell.imageView.layer.cornerRadius = 10;
    cell.imageView.clipsToBounds = YES;

    return cell;
}

- (UIImage *)placeholderIcon {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(44, 44), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.15 alpha:1.0].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, 44, 44));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    AppInfo *app = self.filteredApps[indexPath.row];
    AppDetailsViewController *detail = [[AppDetailsViewController alloc] initWithAppInfo:app];
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchText = searchText ?: @"";
    [self filterApps];
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = YES;
    UIButton *cancelButton = [searchBar valueForKey:@"cancelButton"];
    if ([cancelButton isKindOfClass:[UIButton class]]) {
        [cancelButton setTitle:@"\u0625\u0644\u063a\u0627\u0621" forState:UIControlStateNormal];
    }
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = NO;
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    self.searchText = @"";
    [searchBar resignFirstResponder];
    [self filterApps];
    [self.tableView reloadData];
}

@end
