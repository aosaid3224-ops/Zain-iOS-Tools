#import "PVDecoy2ViewController.h"
#import "PVPassword2ViewController.h"
#import "PVVaultViewController.h"

@interface PVDecoy2ViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, assign) BOOL openingAuthentication;
@end

@implementation PVDecoy2ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"النشاط";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.hidesBackButton = YES;

    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.backgroundColor = [UIColor clearColor];
    tableView.scrollEnabled = NO;
    tableView.delegate = self;
    tableView.dataSource = self;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.openingAuthentication = NO;
}

- (void)handleSevenTaps:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || self.openingAuthentication) return;
    self.openingAuthentication = YES;

    PVPassword2ViewController *password2 = [[PVPassword2ViewController alloc] init];
    __weak UINavigationController *weakNavigationController = self.navigationController;
    password2.authenticationSuccess = ^{
        UINavigationController *navigationController = weakNavigationController;
        if (!navigationController) return;
        PVVaultViewController *vault = [[PVVaultViewController alloc] init];
        [navigationController pushViewController:vault animated:YES];
    };
    password2.authenticationFailure = ^{
        UINavigationController *navigationController = weakNavigationController;
        if (!navigationController) return;
        [navigationController popViewControllerAnimated:YES];
    };
    [self.navigationController pushViewController:password2 animated:YES];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"ملخص النشاط";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *identifier = indexPath.row == 2 ? @"PVActivityDetailsCell" : @"PVActivityCell";
    UITableViewCellStyle style = indexPath.row == 2 ? UITableViewCellStyleDefault : UITableViewCellStyleValue1;
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:identifier];

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textAlignment = NSTextAlignmentRight;
    cell.detailTextLabel.textAlignment = NSTextAlignmentLeft;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.tintColor = [UIColor secondaryLabelColor];

    if (indexPath.row == 0) {
        cell.textLabel.text = @"حالة الاتصال";
        cell.detailTextLabel.text = @"يرجى التحقق من الاتصال";
        cell.imageView.image = [UIImage systemImageNamed:@"wifi"];
    } else if (indexPath.row == 1) {
        cell.textLabel.text = @"آخر مزامنة";
        cell.detailTextLabel.text = @"لم تتم المزامنة";
        cell.imageView.image = [UIImage systemImageNamed:@"arrow.clockwise"];
    } else {
        cell.textLabel.text = @"ملخص الحالة";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.imageView.image = nil;
        cell.userInteractionEnabled = YES;
        for (UIGestureRecognizer *existingGesture in [cell.gestureRecognizers copy]) {
            [cell removeGestureRecognizer:existingGesture];
        }
        UITapGestureRecognizer *sevenTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSevenTaps:)];
        sevenTap.numberOfTapsRequired = 7;
        sevenTap.numberOfTouchesRequired = 1;
        sevenTap.cancelsTouchesInView = NO;
        [cell addGestureRecognizer:sevenTap];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
}

@end
