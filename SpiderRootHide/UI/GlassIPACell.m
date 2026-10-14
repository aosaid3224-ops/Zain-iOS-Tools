#import "GlassIPACell.h"
#import "IPTheme.h"
#import "IPComponents.h"
#import "Core/IPAExtractor.h"

@interface GlassIPACell ()
@property (nonatomic, strong) UIImageView *ipaIconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metadataLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UIView *rowContainer;
@property (nonatomic, strong) IPHairlineView *separator;
@end

@implementation GlassIPACell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        [self buildLayout];
    }
    return self;
}

// Structured list row — the screen is the canvas; no card, no glass.
- (void)buildLayout {
    self.rowContainer = [[UIView alloc] init];
    self.rowContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.rowContainer.backgroundColor = UIColor.clearColor;
    [self.contentView addSubview:self.rowContainer];

    self.ipaIconView = [[UIImageView alloc] init];
    self.ipaIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.ipaIconView.contentMode = UIViewContentModeScaleAspectFill;
    self.ipaIconView.clipsToBounds = YES;
    self.ipaIconView.layer.cornerRadius = [IPTheme radiusIcon];
    self.ipaIconView.backgroundColor = [IPTheme surfaceSubtleColor];
    [self.rowContainer addSubview:self.ipaIconView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [IPTheme headlineFont];
    self.titleLabel.textColor = [IPTheme textPrimaryColor];
    self.titleLabel.textAlignment = NSTextAlignmentRight;
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.78;
    [self.rowContainer addSubview:self.titleLabel];

    self.metadataLabel = [[UILabel alloc] init];
    self.metadataLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.metadataLabel.font = [IPTheme monoFont];
    self.metadataLabel.textColor = [IPTheme textTertiaryColor];
    self.metadataLabel.textAlignment = NSTextAlignmentRight;
    self.metadataLabel.numberOfLines = 1;
    [self.rowContainer addSubview:self.metadataLabel];

    self.chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]];
    self.chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronView.tintColor = [IPTheme textQuaternaryColor];
    self.chevronView.contentMode = UIViewContentModeScaleAspectFit;
    [self.rowContainer addSubview:self.chevronView];

    self.separator = [[IPHairlineView alloc] initWithMargins:UIEdgeInsetsMake(0, 76, 0, 0)];
    self.separator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.rowContainer addSubview:self.separator];

    [NSLayoutConstraint activateConstraints:@[
        [self.rowContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.rowContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:[IPTheme pageMargin]],
        [self.rowContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-[IPTheme pageMargin]],
        [self.rowContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [self.ipaIconView.trailingAnchor constraintEqualToAnchor:self.rowContainer.trailingAnchor],
        [self.ipaIconView.centerYAnchor constraintEqualToAnchor:self.rowContainer.centerYAnchor],
        [self.ipaIconView.widthAnchor constraintEqualToConstant:52],
        [self.ipaIconView.heightAnchor constraintEqualToConstant:52],

        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.ipaIconView.leadingAnchor constant:-[IPTheme space16]],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.chevronView.trailingAnchor constant:[IPTheme space12]],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.rowContainer.topAnchor constant:14],

        [self.metadataLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.metadataLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.metadataLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:3],

        [self.chevronView.leadingAnchor constraintEqualToAnchor:self.rowContainer.leadingAnchor],
        [self.chevronView.centerYAnchor constraintEqualToAnchor:self.rowContainer.centerYAnchor],
        [self.chevronView.widthAnchor constraintEqualToConstant:14],
        [self.chevronView.heightAnchor constraintEqualToConstant:14],

        [self.separator.leadingAnchor constraintEqualToAnchor:self.rowContainer.leadingAnchor],
        [self.separator.trailingAnchor constraintEqualToAnchor:self.rowContainer.trailingAnchor],
        [self.separator.bottomAnchor constraintEqualToAnchor:self.rowContainer.bottomAnchor],

        [self.rowContainer.heightAnchor constraintEqualToConstant:76],
    ]];
}

- (void)configureWithIPAInfo:(IPAExtractedInfo *)info {
    self.titleLabel.text = info.displayName ?: info.name ?: [info.filePath lastPathComponent];

    NSString *date = @"";
    if (info.modifiedDate) {
        static NSDateFormatter *formatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"dd/MM/yyyy";
        });
        date = [formatter stringFromDate:info.modifiedDate];
    }

    // Single quiet metadata line: version · size · date (monospaced).
    NSMutableArray *parts = [NSMutableArray array];
    if (info.version) [parts addObject:info.version];
    if (info.formattedSize) [parts addObject:info.formattedSize];
    if (date.length) [parts addObject:date];
    self.metadataLabel.text = parts.count ? [parts componentsJoinedByString:@"  ·  "] : @"IPA";

    if (info.icon) {
        self.ipaIconView.image = info.icon;
        self.ipaIconView.alpha = 1;
    } else {
        self.ipaIconView.image = [[UIImage systemImageNamed:@"doc.zipper"] imageWithTintColor:[IPTheme textTertiaryColor]];
        self.ipaIconView.alpha = 1;
    }
}

- (void)setIconImage:(UIImage *)icon animated:(BOOL)animated {
    if (!icon) return;
    if (animated) {
        self.ipaIconView.alpha = 0;
        self.ipaIconView.image = icon;
        [UIView animateWithDuration:[IPTheme durationFast] animations:^{
            self.ipaIconView.alpha = 1;
        }];
    } else {
        self.ipaIconView.image = icon;
        self.ipaIconView.alpha = 1;
    }
}

// Quiet press feedback — a soft highlight, no scale gimmicks.
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    void (^changes)(void) = ^{
        self.rowContainer.backgroundColor = highlighted ? [IPTheme selectionColor] : UIColor.clearColor;
    };
    if (animated) {
        [UIView animateWithDuration:[IPTheme durationFast] delay:0 options:[IPTheme easing]|UIViewAnimationOptionAllowUserInteraction animations:changes completion:nil];
    } else {
        changes();
    }
}

// Entrance — short fade + small rise, part of the same motion system.
- (void)playEntranceAnimationWithDelay:(NSTimeInterval)delay {
    self.rowContainer.alpha = 0;
    self.rowContainer.transform = CGAffineTransformMakeTranslation(0, 10);
    [UIView animateWithDuration:[IPTheme durationEmphasis] delay:delay options:[IPTheme easing]|UIViewAnimationOptionAllowUserInteraction animations:^{
        self.rowContainer.alpha = 1;
        self.rowContainer.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end
