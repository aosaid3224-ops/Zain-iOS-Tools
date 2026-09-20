//
//  CLSettingsViewController.m
//

#import "CLSettingsViewController.h"
#import "CLTheme.h"
#import "CLComponents.h"

@interface CLSettingsViewController ()
@property (nonatomic, strong) UIStackView *stack;
@end

@implementation CLSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"حول Crack Lab";
    self.view.backgroundColor = [CLTheme backgroundColor];

    UIScrollView *sv = [UIScrollView new];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.showsVerticalScrollIndicator = NO;
    [self.view addSubview:sv];
    self.stack = [UIStackView new];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisVertical;
    [sv addSubview:self.stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [sv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [sv.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:sv.topAnchor constant:24],
        [self.stack.leadingAnchor constraintEqualToAnchor:sv.leadingAnchor constant:[CLTheme pageMargin]],
        [self.stack.trailingAnchor constraintEqualToAnchor:sv.trailingAnchor constant:-[CLTheme pageMargin]],
        [self.stack.bottomAnchor constraintEqualToAnchor:sv.bottomAnchor constant:-24],
        [self.stack.widthAnchor constraintEqualToAnchor:sv.widthAnchor constant:-(2 * [CLTheme pageMargin])],
    ]];

    // Logo mark
    UIView *mark = [UIView new];
    mark.translatesAutoresizingMaskIntoConstraints = NO;
    mark.backgroundColor = [CLTheme accentColor];
    mark.layer.cornerRadius = 18;
    [mark.heightAnchor constraintEqualToConstant:72].active = YES;
    [mark.widthAnchor constraintEqualToConstant:72].active = YES;
    UIImageView *flask = [UIImageView new];
    flask.translatesAutoresizingMaskIntoConstraints = NO;
    flask.image = [UIImage systemImageNamed:@"flask"];
    flask.tintColor = UIColor.blackColor;
    flask.contentMode = UIViewContentModeScaleAspectFit;
    [mark addSubview:flask];
    [NSLayoutConstraint activateConstraints:@[
        [flask.centerXAnchor constraintEqualToAnchor:mark.centerXAnchor],
        [flask.centerYAnchor constraintEqualToAnchor:mark.centerYAnchor],
        [flask.widthAnchor constraintEqualToConstant:36],
        [flask.heightAnchor constraintEqualToConstant:36],
    ]];
    UIView *markWrap = [UIView new];
    [markWrap addSubview:mark];
    [mark.centerXAnchor constraintEqualToAnchor:markWrap.centerXAnchor].active = YES;
    [mark.topAnchor constraintEqualToAnchor:markWrap.topAnchor].active = YES;
    [mark.bottomAnchor constraintEqualToAnchor:markWrap.bottomAnchor].active = YES;
    [self.stack addArrangedSubview:markWrap];

    UILabel *title = [UILabel new];
    title.font = [CLTheme titleFont]; title.textColor = [CLTheme textPrimaryColor];
    title.text = @"Crack Lab"; title.textAlignment = NSTextAlignmentCenter;
    [self.stack addArrangedSubview:title];

    UILabel *sub = [UILabel new];
    sub.font = [CLTheme captionFont]; sub.textColor = [CLTheme textSecondaryColor];
    sub.text = @"مختبر تعديل الألعاب — إصدار 1.0 (المرحلة الأولى)";
    sub.textAlignment = NSTextAlignmentCenter; sub.numberOfLines = 0;
    [self.stack addArrangedSubview:sub];

    [self.stack addArrangedSubview:({
        UIView *s = [UIView new]; [s.heightAnchor constraintEqualToConstant:24].active = YES; s;
    })];

    [self.stack addArrangedSubview:({
        CLNoticeView *n = [[CLNoticeView alloc] initWithMessage:
            @"اكتشاف الألعاب وتصنيفها وكشف محركها والتحقق من حالتها جاهزة الآن. النسخ الاحتياطي وتطبيق التعديلات في المراحل القادمة." kind:@"info"];
        n;
    })];
}

@end
