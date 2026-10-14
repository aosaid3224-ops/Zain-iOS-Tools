#import "IPAFileCardCell.h"
#import "IPTheme.h"
#import "IPComponents.h"

@interface IPAFileCardCell ()
@property (nonatomic, strong, readwrite) UIImageView *ipaIconView;
@property (nonatomic, strong, readwrite) UILabel *titleLabel;
@property (nonatomic, strong, readwrite) UILabel *subtitleLabel;
@property (nonatomic, strong, readwrite) UILabel *metaLabel;
@property (nonatomic, strong, readwrite) UIButton *moreButton;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UIView *childRail;
@end

@implementation IPAFileCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone; // بلا غطاء افتراضي — التمييز عبر setHighlighted فقط
    self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.contentView.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.contentView.layoutMargins = UIEdgeInsetsMake(3.0, 4.0, 3.0, 4.0);

    _cardView = [[UIView alloc] init];
    _cardView.translatesAutoresizingMaskIntoConstraints = NO;
    _cardView.backgroundColor = UIColor.clearColor;
    [self.contentView addSubview:_cardView];

    _childRail = [[UIView alloc] init];
    _childRail.translatesAutoresizingMaskIntoConstraints = NO;
    _childRail.layer.cornerRadius = 2.0;
    [_cardView addSubview:_childRail];

    IPHairlineView *sep = [[IPHairlineView alloc] initWithMargins:UIEdgeInsetsMake(0, 76, 0, 0)];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:sep];
    [NSLayoutConstraint activateConstraints:@[
        [sep.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor],
        [sep.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor],
    ]];

    _ipaIconView = [[UIImageView alloc] init];
    _ipaIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _ipaIconView.contentMode = UIViewContentModeScaleAspectFit;
    _ipaIconView.clipsToBounds = NO;
    [_cardView addSubview:_ipaIconView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [IPTheme textPrimaryColor];
    _titleLabel.textAlignment = NSTextAlignmentNatural;
    _titleLabel.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    _titleLabel.numberOfLines = 1;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_cardView addSubview:_titleLabel];

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    _subtitleLabel.textColor = [IPTheme textSecondaryColor];
    _subtitleLabel.textAlignment = NSTextAlignmentNatural;
    _subtitleLabel.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    _subtitleLabel.numberOfLines = 1;
    _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_cardView addSubview:_subtitleLabel];

    _metaLabel = [[UILabel alloc] init];
    _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _metaLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    _metaLabel.textColor = [IPTheme textSecondaryColor];
    _metaLabel.textAlignment = NSTextAlignmentNatural;
    _metaLabel.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    _metaLabel.numberOfLines = 1;
    _metaLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_cardView addSubview:_metaLabel];

    _statusDot = [[UIView alloc] init];
    _statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    _statusDot.layer.cornerRadius = 4.0;
    [_cardView addSubview:_statusDot];

    _moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_moreButton setTitle:@"•••" forState:UIControlStateNormal];
    _moreButton.titleLabel.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightBold];
    _moreButton.tintColor = [IPTheme textPrimaryColor];
    _moreButton.accessibilityLabel = @"إجراءات العنصر";
    _moreButton.accessibilityHint = @"فتح قائمة الإجراءات";
    _moreButton.accessibilityTraits = UIAccessibilityTraitButton;
    [_cardView addSubview:_moreButton];

    [NSLayoutConstraint activateConstraints:@[
        [_cardView.topAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.topAnchor],
        [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.bottomAnchor],
        [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        [_cardView.heightAnchor constraintGreaterThanOrEqualToConstant:82.0],
        [_childRail.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor],
        [_childRail.topAnchor constraintEqualToAnchor:_cardView.topAnchor],
        [_childRail.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor],
        [_childRail.widthAnchor constraintEqualToConstant:4.0],
        [_ipaIconView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-16.0],
        [_ipaIconView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        [_ipaIconView.widthAnchor constraintEqualToConstant:52.0],
        [_ipaIconView.heightAnchor constraintEqualToConstant:52.0],
        [_moreButton.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:8.0],
        [_moreButton.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        [_moreButton.widthAnchor constraintEqualToConstant:48.0],
        [_moreButton.heightAnchor constraintEqualToConstant:48.0],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_ipaIconView.leadingAnchor constant:-12.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_statusDot.trailingAnchor constant:8.0],
        [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:14.0],
        [_titleLabel.heightAnchor constraintEqualToConstant:22.0],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:1.0],
        [_subtitleLabel.heightAnchor constraintEqualToConstant:18.0],
        [_metaLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_metaLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_metaLabel.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:1.0],
        [_metaLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_cardView.bottomAnchor constant:-12.0],
        [_metaLabel.heightAnchor constraintEqualToConstant:17.0],
        [_statusDot.leadingAnchor constraintEqualToAnchor:_moreButton.trailingAnchor constant:8.0],
        [_statusDot.centerYAnchor constraintEqualToAnchor:_metaLabel.centerYAnchor],
        [_statusDot.widthAnchor constraintEqualToConstant:8.0],
        [_statusDot.heightAnchor constraintEqualToConstant:8.0]
    ]];
    return self;
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle meta:(NSString *)meta icon:(UIImage *)icon statusColor:(UIColor *)statusColor isChild:(BOOL)isChild {
    self.titleLabel.text = title ?: @"";
    self.subtitleLabel.text = subtitle ?: @"";
    self.metaLabel.text = meta ?: @"";
    self.ipaIconView.image = icon;
    self.statusDot.backgroundColor = statusColor ?: [IPTheme accentColor];
    self.showsChildIndent = isChild;
    self.childRail.hidden = !isChild;
    self.cardView.backgroundColor = isChild ? [IPTheme secondaryCardColor] : [IPTheme cardColor];
    self.titleLabel.font = [UIFont systemFontOfSize:isChild ? 15.0 : 17.0 weight:isChild ? UIFontWeightMedium : UIFontWeightSemibold];
    self.ipaIconView.alpha = isChild ? 0.9 : 1.0;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    [UIView animateWithDuration:0.12 animations:^{
        self.cardView.backgroundColor = selected ? [IPTheme selectionColor] : (self.showsChildIndent ? [IPTheme secondaryCardColor] : [IPTheme cardColor]);
    }];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    // تغذية راجعة لمس فقط — النصوص تبقى ظاهرة دائماً
    [UIView animateWithDuration:0.1 animations:^{
        self.cardView.backgroundColor = highlighted ? [IPTheme selectionColor] : (self.showsChildIndent ? [IPTheme secondaryCardColor] : [IPTheme cardColor]);
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = @"";
    self.subtitleLabel.text = @"";
    self.metaLabel.text = @"";
    self.ipaIconView.image = nil;
    self.moreButton.tag = 0;
    self.showsChildIndent = NO;
    self.childRail.hidden = YES;
    self.cardView.alpha = 1.0;
}

@end
