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
    [super viewDidLoad]; [self addTitle:@"حارس ألعاب دلتا" subtitle:@"القناة الرسمية @yxbb2025"];
    UIView *statusCard=[self card]; UIStackView *ss=[[UIStackView alloc] init]; ss.axis=UILayoutConstraintAxisVertical; ss.spacing=8; ss.layoutMargins=UIEdgeInsetsMake(20,20,20,20); ss.layoutMarginsRelativeArrangement=YES;
    [ss addArrangedSubview:[self label:@"الحالة الحالية" size:13 color:DGMuted()]]; self.status=[self label:@"في وضع الاستعداد" size:18 color:DGText()]; self.status.font=[UIFont systemFontOfSize:18 weight:UIFontWeightBold]; [ss addArrangedSubview:self.status]; [ss addArrangedSubview:[self label:@"نمط الصلاحيات: تطبيق iOS" size:13 color:DGMuted()]]; [statusCard addSubview:ss]; ss.translatesAutoresizingMaskIntoConstraints=NO; [NSLayoutConstraint activateConstraints:@[[ss.topAnchor constraintEqualToAnchor:statusCard.topAnchor],[ss.bottomAnchor constraintEqualToAnchor:statusCard.bottomAnchor],[ss.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor],[ss.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor]]]; [self.stack addArrangedSubview:statusCard];
    UIButton *floating=[self button:@"تشغيل الأداة العائمة"]; [floating addTarget:self action:@selector(showFloating) forControlEvents:UIControlEventTouchUpInside]; [self.stack addArrangedSubview:floating];
    UIStackView *row=[[UIStackView alloc] init]; row.axis=UILayoutConstraintAxisHorizontal; row.spacing=10; UIButton *b1=[self button:@"تشغيل ميزة التصويب"]; UIButton *b2=[self button:@"وظيفة غير مهيأة"]; b1.titleLabel.font=b2.titleLabel.font=[UIFont systemFontOfSize:13]; [b1 addTarget:self action:@selector(unavailable) forControlEvents:UIControlEventTouchUpInside]; [b2 addTarget:self action:@selector(unavailable) forControlEvents:UIControlEventTouchUpInside]; [row addArrangedSubview:b1]; [row addArrangedSubview:b2]; [self.stack addArrangedSubview:row];
    UIView *logCard=[self card]; UIStackView *ls=[[UIStackView alloc] init]; ls.axis=UILayoutConstraintAxisVertical; ls.spacing=10; ls.layoutMargins=UIEdgeInsetsMake(16,16,16,16); ls.layoutMarginsRelativeArrangement=YES; UIStackView *lh=[[UIStackView alloc] init]; UILabel *lt=[self label:@"سجل التشغيل" size:14 color:DGText()]; lt.font=[UIFont boldSystemFontOfSize:14]; UIButton *copy=[UIButton buttonWithType:UIButtonTypeSystem]; [copy setTitle:@"نسخ" forState:UIControlStateNormal]; [copy setTitleColor:DGPrimary() forState:UIControlStateNormal]; [copy addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside]; [lh addArrangedSubview:lt]; [lh addArrangedSubview:copy]; [ls addArrangedSubview:lh]; self.log=[self label:@"واجهة iOS الأصلية جاهزة.\nمحرك Android لم تتم إعادة بنائه، ولن يتم عرض نجاح وهمي للحقن.\nيمكنك مراجعة الوظائف المرئية من صفحات الصلاحيات والخوادم والإعدادات." size:12 color:DGMuted()]; self.log.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]; [ls addArrangedSubview:self.log]; [logCard addSubview:ls]; ls.translatesAutoresizingMaskIntoConstraints=NO; [NSLayoutConstraint activateConstraints:@[[ls.topAnchor constraintEqualToAnchor:logCard.topAnchor],[ls.bottomAnchor constraintEqualToAnchor:logCard.bottomAnchor],[ls.leadingAnchor constraintEqualToAnchor:logCard.leadingAnchor],[ls.trailingAnchor constraintEqualToAnchor:logCard.trailingAnchor]]]; [self.stack addArrangedSubview:logCard];
}
- (void)unavailable { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"غير منقول" message:@"هذا الزر تابع لمحرك حقن Android، ولا يتم الادعاء بأنه يعمل داخل نسخة iOS الأصلية." preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)copyLog { [UIPasteboard generalPasteboard].string=self.log.text; }
- (void)showFloating { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"الأداة العائمة" message:@"جاهز\n\nهذه النسخة توفر واجهة أصلية فقط. حقن Android وShizuku وSAF والتحكم بعمليات الألعاب غير منقولة إلى iOS." preferredStyle:UIAlertControllerStyleActionSheet]; [a addAction:[UIAlertAction actionWithTitle:@"إغلاق" style:UIAlertActionStyleCancel handler:nil]]; [a addAction:[UIAlertAction actionWithTitle:@"حقن ملف (غير متاح في iOS)" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [self unavailable]; }]]; [self presentViewController:a animated:YES completion:nil]; }
@end

@interface DGPermissionViewController : DGBaseViewController
@property(nonatomic,strong) UILabel *state;
@end
@implementation DGPermissionViewController
- (void)viewDidLoad { [super viewDidLoad]; [self addTitle:@"إدارة الصلاحيات" subtitle:@"اختر نمط الصلاحيات الظاهر في التطبيق الأصلي. نسخة iOS لا تطلب صلاحيات Android."];
    UIView *card=[self card]; UIStackView *s=[[UIStackView alloc] init]; s.axis=UILayoutConstraintAxisVertical; s.spacing=10; s.layoutMargins=UIEdgeInsetsMake(18,18,18,18); s.layoutMarginsRelativeArrangement=YES; [s addArrangedSubview:[self label:@"نمط الصلاحيات" size:13 color:DGMuted()]]; NSArray *items=@[@"Shizuku\nخاص بـ Android ولا ينطبق على iOS",@"Root\nخاص بـ Android ولا ينطبق على iOS",@"الملفات\nصلاحية ملفات Android ولا تنطبق على iOS",@"صلاحية التعريف\nخاصة ببعض أجهزة Android فقط"]; for(NSString *t in items){ UIButton *b=[self button:t]; b.backgroundColor=[DGPrimary() colorWithAlphaComponent:.18]; [b setTitleColor:DGText() forState:UIControlStateNormal]; b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight; [b addTarget:self action:@selector(selectMode:) forControlEvents:UIControlEventTouchUpInside]; [s addArrangedSubview:b]; } [card addSubview:s]; s.translatesAutoresizingMaskIntoConstraints=NO; [NSLayoutConstraint activateConstraints:@[[s.topAnchor constraintEqualToAnchor:card.topAnchor],[s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],[s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],[s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor]]]; [self.stack addArrangedSubview:card]; self.state=[self label:@"حالة الصلاحيات: لا تحتاج هذه الواجهة إلى صلاحيات Android؛ وضع iOS جاهز" size:16 color:[UIColor systemGreenColor]]; self.state.font=[UIFont boldSystemFontOfSize:16]; [self.stack addArrangedSubview:self.state]; }
- (void)selectMode:(UIButton *)b { self.state.text=[NSString stringWithFormat:@"تم اختيار: %@\nهذا النمط خاص بـ Android ولم يتم تزوير تشغيله على iOS.", b.titleLabel.text]; self.state.textColor=[UIColor systemOrangeColor]; }
@end

@interface DGServerViewController : DGBaseViewController
@property(nonatomic,strong) UILabel *selected;
@end
@implementation DGServerViewController
- (void)viewDidLoad { [super viewDidLoad]; [self addTitle:@"اختيار الخادم" subtitle:@"اختر حزمة اللعبة كما ظهرت في التطبيق الأصلي"];
 UIView *card=[self card]; UIStackView *s=[[UIStackView alloc] init]; s.axis=UILayoutConstraintAxisVertical; s.layoutMargins=UIEdgeInsetsMake(8,0,8,0); s.layoutMarginsRelativeArrangement=YES; NSArray *items=@[@"الخادم الصيني\ncom.tencent.tmgp.dfm",@"الخادم الدولي\ncom.proxima.dfm",@"الخادم التايواني\ncom.garena.game.df"]; for(NSString *t in items){ UIButton *b=[self button:t]; b.backgroundColor=UIColor.clearColor; [b setTitleColor:DGText() forState:UIControlStateNormal]; b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight; b.contentEdgeInsets=UIEdgeInsetsMake(16,20,16,20); [b addTarget:self action:@selector(selectServer:) forControlEvents:UIControlEventTouchUpInside]; [s addArrangedSubview:b]; } [card addSubview:s]; s.translatesAutoresizingMaskIntoConstraints=NO; [NSLayoutConstraint activateConstraints:@[[s.topAnchor constraintEqualToAnchor:card.topAnchor],[s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],[s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],[s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor]]]; [self.stack addArrangedSubview:card]; self.selected=[self label:@"لم يتم تشغيل اللعبة أو التحكم في أي عملية. الاختيار محفوظ للعرض فقط." size:14 color:DGMuted()]; [self.stack addArrangedSubview:self.selected]; }
- (void)selectServer:(UIButton *)b { self.selected.text=[NSString stringWithFormat:@"تم اختيار: %@\nهذا الاختيار للواجهة فقط ولا يشغل حزمة Android على iOS.",b.titleLabel.text]; self.selected.textColor=DGPrimary(); }
@end

@interface DGSettingsViewController : DGBaseViewController
@property(nonatomic,strong) UISwitch *dark;
@end
@implementation DGSettingsViewController
- (void)viewDidLoad { [super viewDidLoad]; [self addTitle:@"الإعدادات" subtitle:nil]; UIView *card=[self card]; UIStackView *s=[[UIStackView alloc] init]; s.axis=UILayoutConstraintAxisVertical; s.spacing=1; s.layoutMargins=UIEdgeInsetsMake(8,20,8,20); s.layoutMarginsRelativeArrangement=YES; UIStackView *darkRow=[self row:@"الوضع الداكن"]; self.dark=[UISwitch new]; self.dark.on=YES; [darkRow addArrangedSubview:self.dark]; [s addArrangedSubview:darkRow]; for(NSString *t in @[@"مسح الكاش",@"مسح البيانات",@"التعليمات النصية",@"جميع الفيديوهات والبرامج",@"تحميل ألعاب الخادم الدولي والتايواني"]){ UIButton *b=[self button:t]; b.backgroundColor=UIColor.clearColor; [b setTitleColor:DGText() forState:UIControlStateNormal]; b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentRight; [b addTarget:self action:@selector(settingAction:) forControlEvents:UIControlEventTouchUpInside]; [s addArrangedSubview:b]; } UIStackView *v=[self row:@"الإصدار"]; [v addArrangedSubview:[self label:@"0.1.2 — واجهة iOS أصلية" size:14 color:DGMuted()]]; [s addArrangedSubview:v]; [card addSubview:s]; s.translatesAutoresizingMaskIntoConstraints=NO; [NSLayoutConstraint activateConstraints:@[[s.topAnchor constraintEqualToAnchor:card.topAnchor],[s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],[s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],[s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor]]]; [self.stack addArrangedSubview:card]; UIView *note=[self card]; UILabel *n=[self label:@"ملاحظة\nهذه نسخة iOS أصلية تعيد الوظائف المرئية فقط. لا تدّعي تشغيل Android أو تنفيذ حقن داخل الألعاب." size:14 color:DGMuted()]; n.translatesAutoresizingMaskIntoConstraints=NO; [note addSubview:n]; [NSLayoutConstraint activateConstraints:@[[n.topAnchor constraintEqualToAnchor:note.topAnchor constant:18],[n.bottomAnchor constraintEqualToAnchor:note.bottomAnchor constant:-18],[n.leadingAnchor constraintEqualToAnchor:note.leadingAnchor constant:18],[n.trailingAnchor constraintEqualToAnchor:note.trailingAnchor constant:-18]]]; [self.stack addArrangedSubview:note]; }
- (UIStackView *)row:(NSString *)title { UIStackView *r=[[UIStackView alloc] init]; r.axis=UILayoutConstraintAxisHorizontal; r.alignment=UIStackViewAlignmentCenter; r.spacing=8; [r addArrangedSubview:[self label:title size:16 color:DGText()]]; return r; }
- (void)settingAction:(UIButton *)b { UIAlertController *a=[UIAlertController alertControllerWithTitle:b.titleLabel.text message:@"هذه وظيفة واجهة تمت إعادة بنائها. لا توجد بيانات Android لحذفها في هذه النسخة." preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
@end

@implementation RootViewController
- (void)viewDidLoad { [super viewDidLoad]; self.view.semanticContentAttribute=UISemanticContentAttributeForceRightToLeft; self.tabBar.semanticContentAttribute=UISemanticContentAttributeForceRightToLeft; self.view.backgroundColor=DGBackground(); DGHomeViewController *home=[DGHomeViewController new]; DGPermissionViewController *perm=[DGPermissionViewController new]; DGServerViewController *server=[DGServerViewController new]; DGSettingsViewController *settings=[DGSettingsViewController new]; home.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"الرئيسية" image:[UIImage systemImageNamed:@"house"] tag:0]; perm.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"الصلاحيات" image:[UIImage systemImageNamed:@"lock.shield"] tag:1]; server.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"الخوادم" image:[UIImage systemImageNamed:@"network"] tag:2]; settings.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"الإعدادات" image:[UIImage systemImageNamed:@"gear"] tag:3]; self.viewControllers=@[home,perm,server,settings]; self.tabBar.tintColor=DGPrimary(); self.tabBar.barTintColor=DGSurface(); if(@available(iOS 13.0,*)){ UITabBarAppearance *a=[UITabBarAppearance new]; [a configureWithOpaqueBackground]; a.backgroundColor=DGSurface(); self.tabBar.standardAppearance=a; if(@available(iOS 15.0,*)) self.tabBar.scrollEdgeAppearance=a; } }
@end
