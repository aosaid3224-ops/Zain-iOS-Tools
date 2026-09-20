//
//  CLLogViewController.m
//

#import "CLLogViewController.h"
#import "CLOperationLog.h"
#import "CLTheme.h"
#import "CLComponents.h"

@interface CLLogViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation CLLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"السجل";
    self.view.backgroundColor = [CLTheme backgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:@"CLOperationLogDidAdd" object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"CLOperationLogDidAdd" object:nil];
}

- (void)reload { [self.tableView reloadData]; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return [CLOperationLog sharedLog].allEntries.count;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"log"];
    if (!cell) { cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"log"];
        cell.backgroundColor = UIColor.clearColor; cell.selectionStyle = UITableViewCellSelectionStyleNone; }
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];
    CLOperationEntry *e = [CLOperationLog sharedLog].allEntries[ip.row];

    static NSDateFormatter *df = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ df = [NSDateFormatter new]; df.dateFormat = @"HH:mm:ss"; });

    UIColor *statusColor = [CLTheme successColor];
    if (e.status == CLOperationStatusFailed) statusColor = [CLTheme errorColor];
    else if (e.status == CLOperationStatusSkipped) statusColor = [CLTheme textQuaternaryColor];

    UIView *dot = [UIView new]; dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.backgroundColor = statusColor; dot.layer.cornerRadius = 3;
    [cell.contentView addSubview:dot];

    UILabel *time = [UILabel new]; time.translatesAutoresizingMaskIntoConstraints = NO;
    time.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    time.textColor = [CLTheme textQuaternaryColor]; time.text = [df stringFromDate:e.date];
    [cell.contentView addSubview:time];

    UILabel *title = [UILabel new]; title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [CLTheme captionFont]; title.textColor = [CLTheme textPrimaryColor];
    title.text = e.title; title.textAlignment = NSTextAlignmentRight;
    [cell.contentView addSubview:title];

    UILabel *detail = [UILabel new]; detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.font = [CLTheme monoFont]; detail.textColor = [CLTheme textTertiaryColor];
    detail.text = e.detail; detail.textAlignment = NSTextAlignmentRight; detail.numberOfLines = 0;
    [cell.contentView addSubview:detail];

    CLHairlineView *sep = [[CLHairlineView alloc] initWithMargins:UIEdgeInsetsMake(0, 24, 0, 0)];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:sep];

    [NSLayoutConstraint activateConstraints:@[
        [dot.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-[CLTheme pageMargin]],
        [dot.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:18],
        [dot.widthAnchor constraintEqualToConstant:6], [dot.heightAnchor constraintEqualToConstant:6],
        [time.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:[CLTheme pageMargin]],
        [time.centerYAnchor constraintEqualToAnchor:dot.centerYAnchor],
        [title.trailingAnchor constraintEqualToAnchor:dot.leadingAnchor constant:-10],
        [title.leadingAnchor constraintEqualToAnchor:time.trailingAnchor constant:12],
        [title.centerYAnchor constraintEqualToAnchor:dot.centerYAnchor],
        [detail.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [detail.leadingAnchor constraintEqualToAnchor:time.leadingAnchor],
        [detail.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [detail.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        [sep.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:[CLTheme pageMargin]],
        [sep.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-[CLTheme pageMargin]],
        [sep.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
    ]];
    return cell;
}

@end
