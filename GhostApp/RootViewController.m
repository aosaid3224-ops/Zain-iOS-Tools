#import "RootViewController.h"
#include <spawn.h>
#include <sys/wait.h>

@interface RootViewController ()
@property (strong, nonatomic) UITextView *statusView;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"👻 نظام الشبح";
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.09 blue:0.12 alpha:1.0];
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, self.view.bounds.size.width - 40, 40)];
    header.text = @"ZAIN GHOST — إدارة المراقب التلقائي";
    header.textColor = UIColor.whiteColor;
    header.textAlignment = NSTextAlignmentCenter;
    header.font = [UIFont boldSystemFontOfSize:18];
    [self.view addSubview:header];

    NSArray *btns = @[@"▶️ تفعيل المراقب", @"⏹ إيقاف المراقب", @"👻 لصق الآن", @"🔄 تحديث الحالة"];
    for (int i = 0; i < 4; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(20, 160 + i * 58, self.view.bounds.size.width - 40, 48);
        [b setTitle:btns[i] forState:UIControlStateNormal];
        b.tag = i;
        b.backgroundColor = [UIColor colorWithRed:0.12 green:0.55 blue:0.45 alpha:1.0];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        b.layer.cornerRadius = 10;
        [b addTarget:self action:@selector(btn:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:b];
    }

    self.statusView = [[UITextView alloc] initWithFrame:CGRectMake(20, 400, self.view.bounds.size.width - 40, self.view.bounds.size.height - 430)];
    self.statusView.editable = NO;
    self.statusView.backgroundColor = [UIColor colorWithRed:0.05 green:0.06 blue:0.08 alpha:1.0];
    self.statusView.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.6 alpha:1.0];
    self.statusView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.statusView.layer.cornerRadius = 10;
    [self.view addSubview:self.statusView];
    [self refresh];
}

- (void)btn:(UIButton *)b {
    const char *ops[] = {"start", "stop", "paste", "status"};
    [self runHelper:ops[b.tag]];
}

- (void)runHelper:(const char *)op {
    const char *path = "/var/jb/usr/local/bin/ghosthelper";
    pid_t pid;
    char *argv[] = {(char *)path, (char *)op, NULL};
    if (posix_spawn(&pid, path, NULL, NULL, argv, NULL) == 0) {
        waitpid(pid, NULL, 0);
    }
    [self refresh];
}

- (void)refresh {
    NSString *s = [[NSString alloc] initWithContentsOfFile:@"/var/mobile/Documents/ghost_status.txt"
        encoding:NSUTF8StringEncoding error:nil];
    NSString *l = [[NSString alloc] initWithContentsOfFile:@"/var/mobile/Documents/ghost_watcher.log"
        encoding:NSUTF8StringEncoding error:nil];
    NSMutableString *all = [NSMutableString stringWithString:@"═══ الحالة ═══\n"];
    if (s) [all appendString:s];
    [all appendString:@"\n═══ آخر اللوق ═══\n"];
    if (l) {
        NSArray *lines = [l componentsSeparatedByString:@"\n"];
        NSUInteger n = lines.count;
        NSUInteger start = n > 12 ? n - 12 : 0;
        [all appendString:[[lines subarrayWithRange:NSMakeRange(start, n - start)] componentsJoinedByString:@"\n"]];
    } else { [all appendString:@"لا يوجد لوق بعد"]; }
    dispatch_async(dispatch_get_main_queue(), ^{ self.statusView.text = all; });
}
@end
