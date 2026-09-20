//
//  CLGameCell.h
//

#import <UIKit/UIKit.h>
#import "CLGame.h"
#import "CLComponents.h"

@interface CLGameCell : UITableViewCell
@property (nonatomic, strong, readonly) CLListRow *rowView;
- (void)configureWithGame:(CLGame *)game;
@end
