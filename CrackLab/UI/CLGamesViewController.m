//
//  CLGamesViewController.m
//

#import "CLGamesViewController.h"
#import "CLGameDetailViewController.h"
#import "CLGameDiscovery.h"
#import "CLGameCell.h"
#import "CLOperationLog.h"
#import "CLTheme.h"
#import "CLComponents.h"

@interface CLGamesViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<CLGame *> *games;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIStackView *skeletonStack;
@property (nonatomic, strong) CLEmptyStateView *emptyView;
@property (nonatomic, strong) CLNoticeView *errorView;
@property (nonatomic, assign) BOOL isScanning;
@end

@implementation CLGamesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Crack Lab";
    self.view.backgroundColor = [CLTheme backgroundColor];
    [self setupTable];
    [self discover];
}

- (void)setupTable {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 76;
    [self.tableView registerClass:[CLGameCell class] forCellReuseIdentifier:@"CLGameCell"];
    [self.view addSubview:self.tableView];

    self.refreshControl = [UIRefreshControl new];
    self.refreshControl.tintColor = [CLTheme accentColor];
    [self.refreshControl addTarget:self action:@selector(refresh:) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

#pragma mark - Discovery

- (void)refresh:(UIRefreshControl *)rc { [self discover]; }

- (void)discover {
    if (self.isScanning) return;                 // no overlapping scans
    self.isScanning = YES;

    __weak typeof(self) weakSelf = self;
    [self.emptyView removeFromSuperview];
    [self.errorView removeFromSuperview];
    self.games = nil;                            // drop stale list
    [self.tableView reloadData];                 // clear rows immediately
    self.tableView.hidden = YES;
    [self showSkeleton:YES];

    CLGameDiscovery *discovery = [CLGameDiscovery new];
    [discovery discoverGamesWithCompletion:^(NSArray<CLGame *> *games, NSString *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.isScanning = NO;                    // always reset, every path
        [self.refreshControl endRefreshing];

        if (error.length) {
            [[CLOperationLog sharedLog] addEntryWithKind:CLOperationKindDiscovery
                status:CLOperationStatusFailed title:@"اكتشاف الألعاب" detail:error];
            [self showSkeleton:NO];
            [self showError:error];
            return;
        }
        self.games = games;

        if (games.count == 0) {
            [self showSkeleton:NO];
            [self showEmpty];
            return;
        }
        [self showSkeleton:NO];
        self.tableView.hidden = NO;
        [self.tableView reloadData];
    }];
}

- (void)showSkeleton:(BOOL)on {
    if (on && !self.skeletonStack) {
        self.skeletonStack = [UIStackView new];
        self.skeletonStack.translatesAutoresizingMaskIntoConstraints = NO;
        self.skeletonStack.axis = UILayoutConstraintAxisVertical;
        [self.view addSubview:self.skeletonStack];
        for (NSInteger i = 0; i < 7; i++) {
            CLSkeletonView *sk = [CLSkeletonView new];
            sk.translatesAutoresizingMaskIntoConstraints = NO;
            [self.skeletonStack addArrangedSubview:sk];
            [sk.heightAnchor constraintEqualToConstant:68].active = YES;
        }
        [NSLayoutConstraint activateConstraints:@[
            [self.skeletonStack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
            [self.skeletonStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:[CLTheme pageMargin]],
            [self.skeletonStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-[CLTheme pageMargin]],
        ]];
    }
    self.skeletonStack.hidden = !on;
}

- (void)showEmpty {
    self.emptyView = [[CLEmptyStateView alloc] initWithTitle:@"لا توجد ألعاب"
        message:@"لم يتم العثور على ألعاب مثبتة على هذا الجهاز."
        actionTitle:@"إعادة الفحص" handler:^{ [self discover]; }];
    [self centerState:self.emptyView];
}

- (void)showError:(NSString *)msg {
    self.errorView = [[CLNoticeView alloc] initWithMessage:msg kind:@"error"];
    [self centerState:self.errorView];
}

- (void)centerState:(UIView *)v {
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [v.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [v.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30],
        [v.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:48],
        [v.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-48],
    ]];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.games.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CLGameCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CLGameCell" forIndexPath:indexPath];
    [cell configureWithGame:self.games[indexPath.row]];
    if (indexPath.row == self.games.count - 1) cell.rowView.showsSeparator = NO;
    else cell.rowView.showsSeparator = YES;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    CLGame *game = self.games[indexPath.row];
    CLGameDetailViewController *detail = [[CLGameDetailViewController alloc] initWithGame:game];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
