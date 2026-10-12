#import "RootViewController.h"

static UIColor *DGBackground(void) { return [UIColor colorWithRed:0.055 green:0.055 blue:0.075 alpha:1]; }
static UIColor *DGSurface(void) { return [UIColor colorWithRed:0.11 green:0.11 blue:0.14 alpha:1]; }
static UIColor *DGText(void) { return [UIColor colorWithWhite:0.94 alpha:1]; }
static UIColor *DGMuted(void) { return [UIColor colorWithWhite:0.62 alpha:1]; }
static UIColor *DGPrimary(void) { return [UIColor colorWithRed:0.36 green:0.55 blue:1 alpha:1]; }

@interface DGBaseViewController : UIViewController
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIStackView *stack;
- (void)addTitle:(NSString *)title subtitle:(NSString *)subtitle;
- (UIView *)card;
- (UILabel *)label:(NSString *)text size:(CGFloat)size color:(UIColor *)color;
- (UIButton *)button:(NSString *)title;
@end

@implementation DGBaseViewController
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = DGBackground(); }
- (void)addTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self.scroll = [UIScrollView new]; self.scroll.alwaysBounceVertical = YES; self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scroll];
    [NSLayoutConstraint activateConstraints:@[[self.scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    self.stack = [[UIStackView alloc] init]; self.stack.axis = UILayoutConstraintAxisVertical; self.stack.spacing = 16; self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[[self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor constant:20], [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.leadingAnchor constant:20], [self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.trailingAnchor constant:-20], [self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:-28]]];
    UILabel *heading = [self label:title size:28 color:DGText()]; heading.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    [self.stack addArrangedSubview:heading];
    if (subtitle.length) { UILabel *sub = [self label:subtitle size:13 color:DGMuted()]; [self.stack addArrangedSubview:sub]; }
}
- (UIView *)card { UIView *v=[UIView new]; v.backgroundColor=DGSurface(); v.layer.cornerRadius=16; v.translatesAutoresizingMaskIntoConstraints=NO; return v; }
- (UILabel *)label:(NSString *)text size:(CGFloat)size color:(UIColor *)color { UILabel *l=[UILabel new]; l.text=text; l.textColor=color; l.font=[UIFont systemFontOfSize:size]; l.numberOfLines=0; l.textAlignment=NSTextAlignmentRight; l.adjustsFontForContentSizeCategory=YES; return l; }
- (UIButton *)button:(NSString *)title { UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; [b setTitle:title forState:UIControlStateNormal]; [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; b.backgroundColor=DGPrimary(); b.layer.cornerRadius=14; b.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]; b.contentEdgeInsets=UIEdgeInsetsMake(15,16,15,16); return b; }
@end

@interface DGHomeViewController : DGBaseViewController
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UILabel *log;
@end
@implementation DGHomeViewController
- (void)viewDidLoad {
    [super viewDidLoad]; [self addTitle:@"三角洲游戏保镖" subtitle:@"官方频道@yxbb2025"];
    UIView *statusCard=[self card]; UIStackView *ss=[[UIStackView alloc] init]; ss.axis=UILayoutConstraintAxisVertical; ss.spacing=8; ss.layoutMargins=UIEdgeInsetsMake(20,20,20,20); ss.layoutMarginsRelativeArrangement=YES;
    [ss addArrangedSubview:[self label:@"当前状态" size:13 color:DGMuted()]]; self.status=[self label:@"待命中" size:18 color:DGText()]; self.status.font=[UIFont systemFontOfSize:18 weight:UIFontWeightBold]; [ss addArrangedSubview:self.status]; [ss addArrangedSubview:[self label:@"授权模式：iOS 应用模式" size:13 color:DGMuted()]]; [statusCard addSubview:ss]; ss.translatesAutoresizingMaskIntoConstraints=NO; [NSLayoutConstraint activateConstraints:@[[ss.topAnchor constraintEqualToAnchor:statusCard.topAnchor],[ss.bottomAnchor constraintEqualToAnchor:statusCard.bottomAnchor],[ss.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor],[ss.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor]]]; [self.stack addArrangedSubview:statusCard];
    UIButton *floating=[self button:@"启动悬浮工具"]; [floating addTarget:self action:@selector(showFloating) forControlEvents:UIControlEventTouchUpInside]; [self.stack addArrangedSubview:floating];
    UIStackView *row=[[UIStackView alloc] init]; row.axis=UILayoutConstraintAxisHorizontal; row.spacing=10; UIButton *b1=[self button:@"注入漏打自瞄"]; UIButton *b2=[self button:@"未配置功能"]; b1.titleLabel.font=b2.titleLabel.font=[UIFont systemFontOfSize:13]; [b1 addTarget:self action:@selector(unavailable) forControlEvents:UIControlEventTouchUpInside]; [b2 addTarget:self action:@selector(unavailable) forControlEvents:UIControlEventTouchUpInside]; [row addArrangedSubview:b1]; [row addArrangedSubview:b2]; [self.stack addArrangedSubview:row];
    UIView *logCard=[self card]; UIStackView *ls=[[UIStackView alloc] init]; ls.axis=UILayoutConstraintAxisVertical; ls.spacing=10; ls.layoutMargins=UIEdgeInsetsMake(16,16,16,16); ls.layoutMarginsRelativeArrangement=YES; UIStackView *lh=[[UIStackView alloc] init]; UILabel *lt=[self label:@"运行日志" size:14 color:DGText()]; lt.font=[UIFont boldSystemFontOfSize:14]; UIButton *copy=[UIButton buttonWithType:UIButtonTypeSystem]; [copy setTitle:@"复制" forState:UIControlStateNormal]; [copy setTitleColor:DGPrimary() forState:UIControlStateNormal]; [copy addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside]; [lh addArrangedSubview:lt]; [lh addArrangedSubview:copy]; [ls addArrangedSubview:lh]; self.log=[self label:@"原生 iOS 界面已就绪。\nAndroid 注入引擎未移植，当前不会伪装成已注入。\n可在权限、服务器和设置页面查看可见功能。" size:12 color:DGMuted()]; self.log.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]; [ls addArrangedSubview:self.log]; [logCard addSubview:ls]; ls.translatesAutoresizingMaskIntoConstraints=NO; [NSLayoutConstraint activateConstraints:@[[ls.topAnchor constraintEqualToAnchor:logCard.topAnchor],[ls.bottomAnchor constraintEqualToAnchor:logCard.bottomAnchor],[ls.leadingAnchor constraintEqualToAnchor:logCard.leadingAnchor],[ls.trailingAnchor constraintEqualToAnchor:logCard.trailingAnchor]]]; [self.stack addArrangedSubview:logCard];
}
- (void)unavailable { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"未移植" message:@"该按钮属于 Android 注入引擎功能，当前 iOS 原生重建不会宣称它可用。" preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)copyLog { [UIPasteboard generalPasteboard].string=self.log.text; }
- (void)showFloating { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"注入工具2" message:@"就绪\n\n此版本仅提供原生界面。实际 Android 注入、Shizuku、SAF 和游戏进程控制尚未移植到 iOS。" preferredStyle:UIAlertControllerStyleActionSheet]; [a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStylecancel handler:nil]]; [a addAction:[UIAlertAction actionWithTitle:@"注入文件（未移植）" style:UIAlertActionStyledefault handler:^(__unused UIAlertAction *x){ [self unavailable]; }]]; [self presentViewController:a animated:YES completion:nil]; }
@end

@interface DGPermissionViewController : DGBaseViewController
@property(nonatomic,strong) UILabel *state;
@end
@implementation DGPermissionViewController
- (void)viewDidLoad { [super viewDidLoad]; [self addTitle:@"权限管理" subtitle:@"选择原应用中可见的授权模式；iOS 版本不申请 Android 权限。"];
    UIView *card=[self card]; UIStackView *s=[[UIStackView alloc] init]; s.axis=UILayoutConstraintAxisVertical; s.spacing=10; s.layoutMargins=UIEdgeInsetsMake(18,18,18,18); s.layoutMarginsRelativeArrangement=YES; [s addArrangedSubview:[self label:@"授权模式" size:13 color:DGMuted()]]; NSArray *items=@[@"Shizuku\nAndroid 专用，iOS 不适用",@"Root\nAndroid 专用，iOS 不适用",@"Data\nAndroid 文件访问权限，iOS 不适用",@"驱动授权\n仅支持部分 Android 设备"]; for(NSString *t in items){ UIButton *b=[self button:t]; b.backgroundColor=[DGPrimary() colorWithAlphaComponent:.18]; [b setTitleColor:DGText() forState:UIControlStateNormal]; b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight; [b addTarget:self action:@selector(selectMode:) forControlEvents:UIControlEventTouchUpInside]; [s addArrangedSubview:b]; } [card addSubview:s]; s.translatesAutoresizingMaskIntoConstraints=NO; [NSLayoutConstraint activateConstraints:@[[s.topAnchor constraintEqualToAnchor:card.topAnchor],[s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],[s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],[s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor]]]; [self.stack addArrangedSubview:card]; self.state=[self label:@"权限状态：不需要 Android 权限；iOS UI 模式已就绪" size:16 color:[UIColor systemGreenColor]]; self.state.font=[UIFont boldSystemFontOfSize:16]; [self.stack addArrangedSubview:self.state]; }
- (void)selectMode:(UIButton *)b { self.state.text=[NSString stringWithFormat:@"已选择：%@\n该模式为 Android 专用，未在 iOS 中伪装执行。", b.titleLabel.text]; self.state.textColor=[UIColor systemOrangeColor]; }
@end

@interface DGServerViewController : DGBaseViewController
@property(nonatomic,strong) UILabel *selected;
@end
@implementation DGServerViewController
- (void)viewDidLoad { [super viewDidLoad]; [self addTitle:@"选择服务器" subtitle:@"选择目标游戏包 الظاهر في النسخة الأصلية"];
 UIView *card=[self card]; UIStackView *s=[[UIStackView alloc] init]; s.axis=UILayoutConstraintAxisVertical; s.layoutMargins=UIEdgeInsetsMake(8,0,8,0); s.layoutMarginsRelativeArrangement=YES; NSArray *items=@[@"国服\ncom.tencent.tmgp.dfm",@"国际服\ncom.proxima.dfm",@"台服\ncom.garena.game.df"]; for(NSString *t in items){ UIButton *b=[self button:t]; b.backgroundColor=UIColor.clearColor; [b setTitleColor:DGText() forState:UIControlStateNormal]; b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight; b.contentEdgeInsets=UIEdgeInsetsMake(16,20,16,20); [b addTarget:self action:@selector(selectServer:) forControlEvents:UIControlEventTouchUpInside]; [s addArrangedSubview:b]; } [card addSubview:s]; s.translatesAutoresizingMaskIntoConstraints=NO; [NSLayoutConstraint activateConstraints:@[[s.topAnchor constraintEqualToAnchor:card.topAnchor],[s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],[s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],[s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor]]]; [self.stack addArrangedSubview:card]; self.selected=[self label:@"لم يتم تشغيل اللعبة أو التحكم في أي عملية. الاختيار محفوظ للعرض فقط." size:14 color:DGMuted()]; [self.stack addArrangedSubview:self.selected]; }
- (void)selectServer:(UIButton *)b { self.selected.text=[NSString stringWithFormat:@"تم اختيار: %@\nهذا الاختيار واجهة فقط ولا يشغل حزمة Android على iOS.",b.titleLabel.text]; self.selected.textColor=DGPrimary(); }
@end

@interface DGSettingsViewController : DGBaseViewController
@property(nonatomic,strong) UISwitch *dark;
@end
@implementation DGSettingsViewController
- (void)viewDidLoad { [super viewDidLoad]; [self addTitle:@"设置" subtitle:nil]; UIView *card=[self card]; UIStackView *s=[[UIStackView alloc] init]; s.axis=UILayoutConstraintAxisVertical; s.spacing=1; s.layoutMargins=UIEdgeInsetsMake(8,20,8,20); s.layoutMarginsRelativeArrangement=YES; UIStackView *darkRow=[self row:@"深色模式"]; self.dark=[UISwitch new]; self.dark.on=YES; [darkRow addArrangedSubview:self.dark]; [s addArrangedSubview:darkRow]; for(NSString *t in @[@"清空缓存",@"清空数据",@"文字教程",@"所有视频教程及软件",@"下载台服国际服游戏"]){ UIButton *b=[self button:t]; b.backgroundColor=UIColor.clearColor; [b setTitleColor:DGText() forState:UIControlStateNormal]; b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight; [b addTarget:self action:@selector(settingAction:) forControlEvents:UIControlEventTouchUpInside]; [s addArrangedSubview:b]; } UIStackView *v=[self row:@"版本"]; [v addArrangedSubview:[self label:@"0.1.0 — Native iOS UI" size:14 color:DGMuted()]]; [s addArrangedSubview:v]; [card addSubview:s]; s.translatesAutoresizingMaskIntoConstraints=NO; [NSLayoutConstraint activateConstraints:@[[s.topAnchor constraintEqualToAnchor:card.topAnchor],[s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],[s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],[s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor]]]; [self.stack addArrangedSubview:card]; UIView *note=[self card]; UILabel *n=[self label:@"说明\nهذه نسخة iOS أصلية تعيد الوظائف المرئية فقط. لا تدّعي تشغيل Android أو تنفيذ حقن داخل الألعاب.",14,DGMuted()]; n.translatesAutoresizingMaskIntoConstraints=NO; [note addSubview:n]; [NSLayoutConstraint activateConstraints:@[[n.topAnchor constraintEqualToAnchor:note.topAnchor constant:18],[n.bottomAnchor constraintEqualToAnchor:note.bottomAnchor constant:-18],[n.leadingAnchor constraintEqualToAnchor:note.leadingAnchor constant:18],[n.trailingAnchor constraintEqualToAnchor:note.trailingAnchor constant:-18]]]; [self.stack addArrangedSubview:note]; }
- (UIStackView *)row:(NSString *)title { UIStackView *r=[[UIStackView alloc] init]; r.axis=UILayoutConstraintAxisHorizontal; r.alignment=UIStackViewAlignmentCenter; r.spacing=8; [r addArrangedSubview:[self label:title size:16 color:DGText()]]; return r; }
- (void)settingAction:(UIButton *)b { UIAlertController *a=[UIAlertController alertControllerWithTitle:b.titleLabel.text message:@"هذه وظيفة واجهة تمت إعادة بنائها. لا يوجد Android cache أو بيانات Android ليتم حذفها في هذه النسخة."] preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
@end

@implementation RootViewController
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor=DGBackground(); DGHomeViewController *home=[DGHomeViewController new]; DGPermissionViewController *perm=[DGPermissionViewController new]; DGServerViewController *server=[DGServerViewController new]; DGSettingsViewController *settings=[DGSettingsViewController new]; home.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"主页" image:[UIImage systemImageNamed:@"house"] tag:0]; perm.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"权限" image:[UIImage systemImageNamed:@"lock.shield"] tag:1]; server.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"服务器" image:[UIImage systemImageNamed:@"network"] tag:2]; settings.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"设置" image:[UIImage systemImageNamed:@"gear"] tag:3]; self.viewControllers=@[home,perm,server,settings]; self.tabBar.tintColor=DGPrimary(); self.tabBar.barTintColor=DGSurface(); if(@available(iOS 13.0,*)){ UITabBarAppearance *a=[UITabBarAppearance new]; [a configureWithOpaqueBackground]; a.backgroundColor=DGSurface(); self.tabBar.standardAppearance=a; if(@available(iOS 15.0,*)) self.tabBar.scrollEdgeAppearance=a; } }
@end
