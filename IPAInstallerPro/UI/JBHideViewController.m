//
//  JBHideViewController.m
//
//  Lists only apps installed by Spider (registry). Each row has an
//  independent toggle. ON = real mechanism install + launch-verified.
//  Status is never assumed: Configured ≠ Applied ≠ Verified.
//

#import "JBHideViewController.h"
#import "IPTheme.h"
#import "../Core/JBHide/SpiderManagedAppsRegistry.h"
#import "../Core/JBHide/SpiderJBHideEngine.h"
#import "../Core/JBHide/SpiderJBHideStateStore.h"

@interface JBHideAppCell : UITableViewCell
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) SpiderManagedApp *app;
@end

@implementation JBHideAppCell
@end

@interface JBHideViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<SpiderManagedApp *> *apps;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UILabel *statusBar;
@end

@implementation JBHideViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"إخفاء الجلبريك";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.statusBar = [UILabel new];
    self.statusBar.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.statusBar.textColor = UIColor.secondaryLabelColor;
    self.statusBar.textAlignment = NSTextAlignmentCenter;
    self.statusBar.numberOfLines = 2;
    self.statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusBar];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.font = [UIFont systemFontOfSize:14];
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.statusBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.statusBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.tableView.topAnchor constraintEqualToAnchor:self.statusBar.bottomAnchor constant:4],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32]
    ]];

    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (void)refresh {
    [[SpiderManagedAppsRegistry sharedRegistry] refresh];
    self.apps = [SpiderManagedAppsRegistry sharedRegistry].managedApps;
    self.emptyLabel.hidden = self.apps.count > 0;
    self.emptyLabel.text = @"لا توجد تطبيقات مثبتة بواسطة Spider بعد.\nثبّت تطبيقًا أولًا ثم عد إلى هنا.";
    NSString *reason = nil;
    BOOL available = [[SpiderJBHideEngine sharedEngine] isMechanismAvailableWithReason:&reason];
    self.statusBar.text = available
        ? @"الآلية جاهزة. التفعيل يُطبَّق فعليًا على التطبيق ويُتحقق منه بإطلاقه."
        : [NSString stringWithFormat:@"الآلية غير متاحة: %@", reason ?: @"سبب غير معروف"];
    self.statusBar.textColor = available ? UIColor.secondaryLabelColor : UIColor.systemRedColor;
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.apps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"JBHideAppCell";
    JBHideAppCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[JBHideAppCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ident];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        cell.toggle = [UISwitch new];
        [cell.toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = cell.toggle;

        cell.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        cell.spinner.hidesWhenStopped = YES;
    }
    SpiderManagedApp *app = self.apps[indexPath.row];
    cell.app = app;
    cell.textLabel.text = app.name;
    NSString *presence = app.currentlyInstalled ? @"" : @"غير مثبت حاليًا على الجهاز — السجل محفوظ\n";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@\n%@", presence, app.bundleID, [self statusTextForBundleID:app.bundleID]];
    cell.detailTextLabel.numberOfLines = 3;
    cell.imageView.image = app.icon;
    cell.toggle.on = [[SpiderJBHideStateStore sharedStore] stateForBundleID:app.bundleID].enabled;
    cell.toggle.enabled = app.currentlyInstalled;
    cell.toggle.tag = indexPath.row;
    cell.tag = indexPath.row;
    [cell.spinner stopAnimating];
    return cell;
}

- (NSString *)statusTextForBundleID:(NSString *)bundleID {
    SpiderJBHideAppState *st = [[SpiderJBHideStateStore sharedStore] stateForBundleID:bundleID];
    switch (st.status) {
        case SpiderJBHideStatusVerified: return @"الحالة: مُفعّل — مُطبَّق — مُتحقَّق منه ✅";
        case SpiderJBHideStatusApplied: return st.lastError.length
            ? [NSString stringWithFormat:@"الحالة: مُفعّل — مُطبَّق — التحقق غير مكتمل ⚠️\n%@", st.lastError]
            : @"الحالة: مُفعّل — مُطبَّق — التحقق غير مكتمل ⚠️";
        case SpiderJBHideStatusConfigured:
            return st.lastError.length
                ? [NSString stringWithFormat:@"الحالة: مُفعّل — لم يُطبَّق بعد ⚠️\n%@", st.lastError]
                : @"الحالة: مُفعّل — لم يُطبَّق بعد ⚠️";
        case SpiderJBHideStatusFailed:
            return st.lastError.length
                ? [NSString stringWithFormat:@"الحالة: فشل ❌\n%@", st.lastError]
                : @"الحالة: فشل ❌";
        default: return @"الحالة: معطّل";
    }
}

#pragma mark - Toggle

- (void)toggleChanged:(UISwitch *)sender {
    NSInteger row = sender.tag;
    if (row < 0 || row >= (NSInteger)self.apps.count) return;
    SpiderManagedApp *app = self.apps[row];
    if (!app.currentlyInstalled) {
        [sender setOn:NO animated:YES];
        self.statusBar.text = @"هذا التطبيق غير مثبت حاليًا على الجهاز. السجل محفوظ — أعد تثبيته من Spider لتفعيل الإخفاء.";
        self.statusBar.textColor = UIColor.systemOrangeColor;
        return;
    }
    sender.enabled = NO;

    JBHideAppCell *cell = (JBHideAppCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
    cell.accessoryView = cell.spinner;
    [cell.spinner startAnimating];

    void (^finish)(SpiderJBHideResult *) = ^(SpiderJBHideResult *result) {
        [cell.spinner stopAnimating];
        cell.accessoryView = cell.toggle;
        cell.toggle.enabled = YES;
        sender.enabled = YES;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", app.bundleID, [self statusTextForBundleID:app.bundleID]];
        if (result.success) {
            self.statusBar.text = result.detailReport ?: @"تم التنفيذ بنجاح.";
            self.statusBar.textColor = UIColor.systemGreenColor;
        } else {
            self.statusBar.text = result.errorMessage ?: @"فشل التنفيذ.";
            self.statusBar.textColor = UIColor.systemRedColor;
            [sender setOn:!sender.on animated:YES]; // revert on failure
            [[SpiderJBHideStateStore sharedStore] setEnabled:sender.on forBundleID:app.bundleID];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تعذّر تفعيل إخفاء الجلبريك"
                                                                           message:result.errorMessage
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]]
                              withRowAnimation:UITableViewRowAnimationNone];
    };

    [[SpiderJBHideStateStore sharedStore] setEnabled:sender.on forBundleID:app.bundleID];
    if (sender.on) {
        [[SpiderJBHideEngine sharedEngine] applyHidingForBundleID:app.bundleID completion:finish];
    } else {
        [[SpiderJBHideEngine sharedEngine] removeHidingForBundleID:app.bundleID completion:finish];
    }
}

#pragma mark - Footer note (honest coverage)

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"تغطي الآلية الكشف عبر واجهات الملفات و dyld والبيئة. لا تغطي الاستدعاءات المباشرة للـ kernel أو الكشف الخادمي. عند فشل التحقق يُعلَم السبب بدل إظهار نجاح وهمي.";
}

@end
