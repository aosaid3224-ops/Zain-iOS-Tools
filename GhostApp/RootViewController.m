#import "RootViewController.h"
#include <spawn.h>
#include <sys/wait.h>

@interface RootViewController ()
@property (strong, nonatomic) UITextView *statusView;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"👻 الشبح";
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.09 blue:0.12 alpha:1.0];
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(20, 110, self.view.bounds.size.width - 40, 34)];
    header.text = @"ZAIN GHOST — فعّل والعب";
    header.textColor = UIColor.whiteColor;
    header.textAlignment = NSTextAlignmentCenter;
    header.font = [UIFont boldSystemFontOfSize:20];
    [self.view addSubview:header];

    UIButton *act = [UIButton buttonWithType:UIButtonTypeSystem];
    act.frame = CGRectMake(20, 165, self.view.bounds.size.width - 40, 60);
    [act setTitle:@"⚡ تفعيل الشبح الكامل" forState:UIControlStateNormal];
    act.tag = 0;
    act.backgroundColor = [UIColor colorWithRed:0.10 green:0.65 blue:0.50 alpha:1.0];
    [act setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    act.titleLabel.font = [UIFont boldSystemFontOfSize:19];
    act.layer.cornerRadius = 14;
    [act addTarget:self action:@selector(btn:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:act];

    NSArray *btns = @[@"⏹ إيقاف", @"🔄 تحديث الحالة"];
    for (int i = 0; i < 2; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(20, 245 + i * 56, self.view.bounds.size.width - 40, 46);
        [b setTitle:btns[i] forState:UIControlStateNormal];
        b.tag = i + 1;
        b.backgroundColor = [UIColor colorWithRed:0.16 green:0.20 blue:0.26 alpha:1.0];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        b.layer.cornerRadius = 10;
        [b addTarget:self action:@selector(btn:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:b];
    }

    self.statusView = [[UITextView alloc] initWithFrame:CGRectMake(20, 370, self.view.bounds.size.width - 40, self.view.bounds.size.height - 400)];
    self.statusView.editable = NO;
    self.statusView.backgroundColor = [UIColor colorWithRed:0.05 green:0.06 blue:0.08 alpha:1.0];
    self.statusView.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.6 alpha:1.0];
    self.statusView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.statusView.layer.cornerRadius = 10;
    [self.view addSubview:self.statusView];
    [self refresh];
}

- (void)btn:(UIButton *)b {
    const char *ops[] = {"activate", "stop", "status"};
    const char *path = "/var/jb/usr/bin/ghosthelper";
    pid_t pid;
    char *argv[] = {(char *)path, (char *)ops[b.tag], NULL};
    if (posix_spawn(&pid, path, NULL, NULL, argv, NULL) == 0) waitpid(pid, NULL, 0);
    [self refresh];
}

- (void)refresh {
    NSString *s = [[NSString alloc] initWithContentsOfFile:@"/var/mobile/Documents/ghost_status.txt"
        encoding:NSUTF8StringEncoding error:nil];
    NSString *l = [[NSString alloc] initWithContentsOfFile:@"/var/mobile/Documents/ghost_watcher.log"
        encoding:NSUTF8StringEncoding error:nil];
    NSMutableString *all = [NSMutableString stringWithString:s ?: @""];
    [all appendString:@"\n═══ آخر اللوق ═══\n"];
    if (l) {
        NSArray *lines = [l componentsSeparatedByString:@"\n"];
        NSUInteger n = lines.count, start = n > 8 ? n - 8 : 0;
        [all appendString:[[lines subarrayWithRange:NSMakeRange(start, n - start)] componentsJoinedByString:@"\n"]];
    } else { [all appendString:@"لا يوجد بعد"]; }
    dispatch_async(dispatch_get_main_queue(), ^{ self.statusView.text = all; });
}
@end
