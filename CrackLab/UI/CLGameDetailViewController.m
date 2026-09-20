//
//  CLGameDetailViewController.m
//

#import "CLGameDetailViewController.h"
#import "CLGameStateInspector.h"
#import "CLOperationLog.h"
#import "CLTheme.h"
#import "CLComponents.h"

@interface CLGameDetailViewController ()
@property (nonatomic, strong) CLGame *game;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) CLStatusPill *statePill;
@end

@implementation CLGameDetailViewController

- (instancetype)initWithGame:(CLGame *)game {
    self = [super initWithNibName:nil bundle:nil];
    self.game = game;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.game.name;
    self.view.backgroundColor = [CLTheme backgroundColor];
    [self setupLayout];
    [self renderHeader];
    [self renderInfoSection];
    [self renderStateSection];
    [self renderFutureNotice];
}

- (void)setupLayout {
    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.stack = [UIStackView new];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 0;
    [self.scrollView addSubview:self.stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:[CLTheme space16]],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:[CLTheme pageMargin]],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-[CLTheme pageMargin]],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-[CLTheme space24]],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-(2 * [CLTheme pageMargin])],
    ]];
}

- (UILabel *)sectionHeader:(NSString *)title {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    l.textColor = [CLTheme textTertiaryColor];
    l.textAlignment = NSTextAlignmentRight;
    l.text = title;
    [l.heightAnchor constraintEqualToConstant:34].active = YES;
    return l;
}

- (UIView *)infoRow:(NSString *)key value:(NSString *)value {
    UIView *row = [UIView new];
    UILabel *k = [UILabel new]; k.font = [CLTheme captionFont]; k.textColor = [CLTheme textSecondaryColor];
    k.text = key; k.textAlignment = NSTextAlignmentRight;
    UILabel *v = [UILabel new]; v.font = [CLTheme monoFont]; v.textColor = [CLTheme textPrimaryColor];
    v.text = value.length ? value : @"—"; v.textAlignment = NSTextAlignmentLeft;
    v.numberOfLines = 1; v.adjustsFontSizeToFitWidth = YES; v.minimumScaleFactor = 0.6;
    k.translatesAutoresizingMaskIntoConstraints = NO; v.translatesAutoresizingMaskIntoConstraints = NO;
    CLHairlineView *sep = [[CLHairlineView alloc] initWithMargins:UIEdgeInsetsZero];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:k]; [row addSubview:v]; [row addSubview:sep];
    [NSLayoutConstraint activateConstraints:@[
        [k.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [k.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [v.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [v.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [v.trailingAnchor constraintLessThanOrEqualToAnchor:k.leadingAnchor constant:-12],
        [sep.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [sep.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [row.heightAnchor constraintEqualToConstant:44],
    ]];
    return row;
}

- (void)renderHeader {
    UIView *header = [UIView new];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *icon = [UIImageView new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = self.game.icon;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.layer.cornerRadius = 16; icon.clipsToBounds = YES;
    icon.backgroundColor = [CLTheme surfaceSubtleColor];
    [header addSubview:icon];

    UILabel *name = [UILabel new];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    name.font = [CLTheme titleFont]; name.textColor = [CLTheme textPrimaryColor];
    name.text = self.game.name; name.textAlignment = NSTextAlignmentRight;
    [header addSubview:name];

    UILabel *ver = [UILabel new];
    ver.translatesAutoresizingMaskIntoConstraints = NO;
    ver.font = [CLTheme captionFont]; ver.textColor = [CLTheme textSecondaryColor];
    ver.text = [NSString stringWithFormat:@"%@ · %@", self.game.version, self.game.engineName];
    ver.textAlignment = NSTextAlignmentRight;
    [header addSubview:ver];

    self.statePill = [[CLStatusPill alloc] initWithText:@"جارٍ الفحص…" color:[CLTheme textQuaternaryColor]];
    self.statePill.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.statePill];

    [NSLayoutConstraint activateConstraints:@[
        [icon.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [icon.topAnchor constraintEqualToAnchor:header.topAnchor],
        [icon.widthAnchor constraintEqualToConstant:72],
        [icon.heightAnchor constraintEqualToConstant:72],
        [name.trailingAnchor constraintEqualToAnchor:icon.leadingAnchor constant:-16],
        [name.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [name.topAnchor constraintEqualToAnchor:header.topAnchor constant:4],
        [ver.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
        [ver.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [ver.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:4],
        [self.statePill.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
        [self.statePill.topAnchor constraintEqualToAnchor:ver.bottomAnchor constant:10],
        [header.bottomAnchor constraintEqualToAnchor:icon.bottomAnchor constant:8],
    ]];
    [self.stack addArrangedSubview:header];

    // Kick off inspection (updates statePill)
    [self inspectState];
}

- (void)inspectState {
    CLGameStateInspector *inspector = [CLGameStateInspector new];
    [inspector inspectGame:self.game completion:^(CLGame *g, NSString *error) {
        if (error.length) {
            self.statePill.text = @"تعذّر الفحص";
            self.statePill.statusColor = [CLTheme errorColor];
            [[CLOperationLog sharedLog] addEntryWithKind:CLOperationKindInspect
                status:CLOperationStatusFailed title:g.name detail:error];
            return;
        }
        NSString *label; UIColor *color;
        switch (g.modState) {
            case CLGameModStateOriginal: label = @"أصلية"; color = [CLTheme successColor]; break;
            case CLGameModStateModified: label = @"معدّلة"; color = [CLTheme warningColor]; break;
            case CLGameModStateNoBaseline: label = @"بلا خط أساس"; color = [CLTheme textQuaternaryColor]; break;
            default: label = @"غير معروف"; color = [CLTheme textQuaternaryColor]; break;
        }
        self.statePill.text = label;
        self.statePill.statusColor = color;
        [[CLOperationLog sharedLog] addEntryWithKind:CLOperationKindInspect
            status:CLOperationStatusSuccess title:g.name
            detail:[NSString stringWithFormat:@"الحالة: %@ · SHA256: %@…", label,
                    [g.executableSHA256 substringToIndex:MIN(12, g.executableSHA256.length)]]];
        [self renderStateValue:label color:color];
    }];
}

- (void)renderInfoSection {
    [self.stack addArrangedSubview:[self spacer:20]];
    [self.stack addArrangedSubview:[self sectionHeader:@"المعلومات"]];
    [self.stack addArrangedSubview:[self infoRow:@"معرف الحزمة" value:self.game.bundleID]];
    [self.stack addArrangedSubview:[self infoRow:@"الإصدار" value:self.game.version]];
    [self.stack addArrangedSubview:[self infoRow:@"المحرك" value:self.game.engineName]];
    [self.stack addArrangedSubview:[self infoRow:@"الحجم" value:[self formattedSize:self.game.bundleSize]]];
    [self.stack addArrangedSubview:[self infoRow:@"المسار" value:self.game.bundlePath]];
}

- (void)renderStateSection {
    [self.stack addArrangedSubview:[self spacer:8]];
    [self.stack addArrangedSubview:[self sectionHeader:@"الحالة"]];
}

- (void)renderStateValue:(NSString *)label color:(UIColor *)color {
    CLNoticeView *notice = [[CLNoticeView alloc] initWithMessage:
        [NSString stringWithFormat:@"بصمة الملف التنفيذي: %@",
         [self.game.executableSHA256 substringToIndex:MIN(16, self.game.executableSHA256.length)]]
        kind:@"info"];
    [self.stack addArrangedSubview:notice];
}

- (void)renderFutureNotice {
    [self.stack addArrangedSubview:[self spacer:20]];
    CLNoticeView *future = [[CLNoticeView alloc] initWithMessage:
        @"النسخ الاحتياطي، تطبيق التعديلات، وإدارة الـ Mods ستتوفر في المراحل القادمة."
        kind:@"warning"];
    [self.stack addArrangedSubview:future];
}

- (UIView *)spacer:(CGFloat)h {
    UIView *v = [UIView new]; [v.heightAnchor constraintEqualToConstant:h].active = YES; return v;
}

- (NSString *)formattedSize:(long long)bytes {
    if (bytes <= 0) return @"—";
    double b = bytes; NSArray *u = @[@"B", @"KB", @"MB", @"GB"]; NSInteger i = 0;
    while (b >= 1024 && i < u.count - 1) { b /= 1024; i++; }
    return [NSString stringWithFormat:@"%.1f %@", b, u[i]];
}

@end
