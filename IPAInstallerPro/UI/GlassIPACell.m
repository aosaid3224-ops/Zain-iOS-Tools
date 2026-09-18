#import "GlassIPACell.h"
#import "IPTheme.h"
#import "Core/IPAExtractor.h"

@interface GlassIPACell ()
@property (nonatomic, strong) UIView *glassView;
@property (nonatomic, strong) UIView *accentView;
@property (nonatomic, strong) UIImageView *ipaIconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metadataLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UIImageView *moreView;
@end

@implementation GlassIPACell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) { self.backgroundColor = UIColor.clearColor; self.selectionStyle = UITableViewCellSelectionStyleNone; self.contentView.backgroundColor = UIColor.clearColor; [self buildGlassLayout]; }
    return self;
}

- (void)buildGlassLayout {
    self.glassView = [[UIView alloc] init]; self.glassView.translatesAutoresizingMaskIntoConstraints = NO; self.glassView.backgroundColor = [IPTheme surfaceColor]; self.glassView.layer.cornerRadius = 18; self.glassView.layer.borderWidth = 0.7; self.glassView.layer.borderColor = [[IPTheme textTertiaryColor] colorWithAlphaComponent:0.58].CGColor; self.glassView.layer.masksToBounds = YES; [self.contentView addSubview:self.glassView];
    self.accentView = [[UIView alloc] init]; self.accentView.translatesAutoresizingMaskIntoConstraints = NO; self.accentView.backgroundColor = [IPTheme errorColor]; [self.glassView addSubview:self.accentView];
    self.ipaIconView = [[UIImageView alloc] init]; self.ipaIconView.translatesAutoresizingMaskIntoConstraints = NO; self.ipaIconView.contentMode = UIViewContentModeScaleAspectFill; self.ipaIconView.clipsToBounds = YES; self.ipaIconView.layer.cornerRadius = 12; self.ipaIconView.backgroundColor = [IPTheme separatorColor]; [self.glassView addSubview:self.ipaIconView];
    self.titleLabel = [[UILabel alloc] init]; self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO; self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]; self.titleLabel.textColor = UIColor.whiteColor; self.titleLabel.textAlignment = NSTextAlignmentRight; self.titleLabel.adjustsFontSizeToFitWidth = YES; self.titleLabel.minimumScaleFactor = .78; [self.glassView addSubview:self.titleLabel];
    self.metadataLabel = [[UILabel alloc] init]; self.metadataLabel.translatesAutoresizingMaskIntoConstraints = NO; self.metadataLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium]; self.metadataLabel.textColor = [UIColor colorWithWhite:.70 alpha:1]; self.metadataLabel.textAlignment = NSTextAlignmentRight; self.metadataLabel.numberOfLines = 2; [self.glassView addSubview:self.metadataLabel];
    self.chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]]; self.chevronView.translatesAutoresizingMaskIntoConstraints = NO; self.chevronView.tintColor = [IPTheme errorColor]; self.chevronView.contentMode = UIViewContentModeScaleAspectFit; [self.glassView addSubview:self.chevronView];
    self.moreView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.vertical"]]; self.moreView.translatesAutoresizingMaskIntoConstraints = NO; self.moreView.tintColor = [IPTheme errorColor]; self.moreView.contentMode = UIViewContentModeScaleAspectFit; [self.glassView addSubview:self.moreView];
    [NSLayoutConstraint activateConstraints:@[
        [self.glassView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:2], [self.glassView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:0], [self.glassView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:0], [self.glassView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-2],
        [self.accentView.trailingAnchor constraintEqualToAnchor:self.glassView.trailingAnchor], [self.accentView.topAnchor constraintEqualToAnchor:self.glassView.topAnchor constant:16], [self.accentView.bottomAnchor constraintEqualToAnchor:self.glassView.bottomAnchor constant:-16], [self.accentView.widthAnchor constraintEqualToConstant:1.5],
        [self.ipaIconView.trailingAnchor constraintEqualToAnchor:self.glassView.trailingAnchor constant:-18], [self.ipaIconView.centerYAnchor constraintEqualToAnchor:self.glassView.centerYAnchor], [self.ipaIconView.widthAnchor constraintEqualToConstant:48], [self.ipaIconView.heightAnchor constraintEqualToConstant:48],
        [self.moreView.trailingAnchor constraintEqualToAnchor:self.ipaIconView.leadingAnchor constant:-10], [self.moreView.centerYAnchor constraintEqualToAnchor:self.glassView.centerYAnchor], [self.moreView.widthAnchor constraintEqualToConstant:16], [self.moreView.heightAnchor constraintEqualToConstant:28],
        [self.chevronView.leadingAnchor constraintEqualToAnchor:self.glassView.leadingAnchor constant:28], [self.chevronView.centerYAnchor constraintEqualToAnchor:self.glassView.centerYAnchor], [self.chevronView.widthAnchor constraintEqualToConstant:14], [self.chevronView.heightAnchor constraintEqualToConstant:20],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.moreView.leadingAnchor constant:-12], [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.chevronView.trailingAnchor constant:14], [self.titleLabel.topAnchor constraintEqualToAnchor:self.glassView.topAnchor constant:8], [self.titleLabel.heightAnchor constraintEqualToConstant:25],
        [self.metadataLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor], [self.metadataLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor], [self.metadataLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:1], [self.metadataLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.glassView.bottomAnchor constant:-8]
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

    NSString *first = [NSString stringWithFormat:@"%@  •  %@", info.version ?: @"غير معروف", info.formattedSize ?: @"غير معروف"];
    self.metadataLabel.text = date.length ? [NSString stringWithFormat:@"%@\n%@  •", first, date] : first;

    if (info.icon) {
        self.ipaIconView.image = info.icon;
        self.ipaIconView.alpha = 1;
    } else {
        self.ipaIconView.image = [[UIImage systemImageNamed:@"doc.zipper"] imageWithTintColor:[[IPTheme textPrimaryColor] colorWithAlphaComponent:0.7]];
        self.ipaIconView.alpha = 1;
    }
}

- (void)setIconImage:(UIImage *)icon animated:(BOOL)animated {
    if (!icon) return;
    if (animated) {
        self.ipaIconView.alpha = 0;
        self.ipaIconView.image = icon;
        [UIView animateWithDuration:0.25 animations:^{
            self.ipaIconView.alpha = 1;
        }];
    } else {
        self.ipaIconView.image = icon;
        self.ipaIconView.alpha = 1;
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated { [super setHighlighted:highlighted animated:animated]; void (^changes)(void) = ^{ self.glassView.transform = highlighted ? CGAffineTransformMakeScale(.975, .975) : CGAffineTransformIdentity; self.glassView.alpha = highlighted ? .72 : 1.0; }; if (animated) [UIView animateWithDuration:.26 delay:0 usingSpringWithDamping:.72 initialSpringVelocity:.2 options:UIViewAnimationOptionAllowUserInteraction animations:changes completion:nil]; else changes(); }
- (void)playEntranceAnimationWithDelay:(NSTimeInterval)delay { self.glassView.alpha = 0; self.glassView.transform = CGAffineTransformMakeTranslation(0, 18); [UIView animateWithDuration:.58 delay:delay usingSpringWithDamping:.82 initialSpringVelocity:.25 options:UIViewAnimationOptionAllowUserInteraction animations:^{ self.glassView.alpha = 1; self.glassView.transform = CGAffineTransformIdentity; } completion:nil]; }
@end
