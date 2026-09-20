//
//  CLGameCell.m
//

#import "CLGameCell.h"
#import "CLTheme.h"

@implementation CLGameCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _rowView = [CLListRow new];
    _rowView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_rowView];
    [NSLayoutConstraint activateConstraints:@[
        [_rowView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [_rowView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:[CLTheme pageMargin]],
        [_rowView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-[CLTheme pageMargin]],
        [_rowView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    ]];
    return self;
}

- (void)configureWithGame:(CLGame *)game {
    self.rowView.titleLabel.text = game.name;
    self.rowView.subtitleLabel.text = [NSString stringWithFormat:@"%@ · %@", game.version, game.engineName];
    self.rowView.metadataLabel.text = [self formattedSize:game.bundleSize];
    self.rowView.iconView.image = game.icon ?: [self placeholderIcon];
}

- (NSString *)formattedSize:(long long)bytes {
    if (bytes <= 0) return @"—";
    double b = bytes;
    NSArray *units = @[@"B", @"KB", @"MB", @"GB"];
    NSInteger u = 0;
    while (b >= 1024 && u < units.count - 1) { b /= 1024; u++; }
    return [NSString stringWithFormat:@"%.1f %@", b, units[u]];
}

- (UIImage *)placeholderIcon {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(44, 44)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [[CLTheme surfaceSubtleColor] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 44, 44) cornerRadius:9] fill];
        UIImage *sym = [[UIImage systemImageNamed:@"gamecontroller"] imageWithTintColor:[CLTheme textQuaternaryColor]];
        [sym drawInRect:CGRectMake(10, 10, 24, 24)];
    }];
}

@end
