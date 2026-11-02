#import <UIKit/UIKit.h>
#import "HBCircularDock.h"
#import <math.h>
static int checks=0;
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"Failed line %d\n",__LINE__);return 1;}}while(0)
@interface HandoffDock:UIView @end
@implementation HandoffDock
-(void)setAlpha:(CGFloat)a{HBCircularSetNativeAlpha(self,a,^(CGFloat v){[super setAlpha:v];});}
@end
int main(){@autoreleasepool{
 UIWindow*w=[[UIWindow alloc]initWithFrame:CGRectMake(0,0,375,812)];UIView*root=[[UIView alloc]initWithFrame:w.bounds];[w addSubview:root];HandoffDock*d=[[HandoffDock alloc]initWithFrame:CGRectMake(0,712,375,100)];[root addSubview:d];UIView*nativeChild=[[UIView alloc]initWithFrame:CGRectMake(0,0,40,40)];[d addSubview:nativeChild];
 UIGraphicsBeginImageContextWithOptions(CGSizeMake(32,32),NO,1);[UIColor.redColor setFill];UIRectFill(CGRectMake(0,0,32,32));UIImage*image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();NSArray*rows=@[@{@"key":@"demo",@"title":@"Demo",@"image":image,@"badge":@""}];CGRect anchor=CGRectMake(12,740,351,48);
 __block int edits=0,taps=0,saves=0;__block CGFloat savedPhase=.5;
 for(int cycle=0;cycle<100;cycle++){
 d.alpha=.8;d.userInteractionEnabled=YES;d.accessibilityElementsHidden=NO;
 CGFloat scale=cycle%2?.6:1.3;HBCircularSetIconScale(d,scale);
 HBUpdateCircularDock(d,root,anchor,rows,savedPhase,YES,^(NSString*key){taps++;},^(CGFloat p){saves++;savedPhase=p;});
 UIView*ring=HBCircularTestView(d);CHECK(HBCircularDockActive(d));CHECK(d.alpha==0);CHECK(!d.userInteractionEnabled);CHECK(d.accessibilityElementsHidden);CHECK(root.subviews.count==2);[ring layoutIfNeeded];
 CHECK(ring.interactions.count==0);
 int holds=0;for(UIView*v in ring.subviews)if([v isKindOfClass:UIButton.class]){for(id interaction in v.interactions){CHECK(![interaction isKindOfClass:UIDragInteraction.class]);CHECK(![interaction isKindOfClass:UIDropInteraction.class]);}CHECK(CGRectContainsRect(ring.bounds,v.frame));CGFloat expected=48*scale;CHECK(v.bounds.size.width<=expected+.01&&v.bounds.size.width>=expected*.58-.01);for(UIGestureRecognizer*g in v.gestureRecognizers)if([g isKindOfClass:UILongPressGestureRecognizer.class]){CHECK(g.cancelsTouchesInView);holds++;}}
 CHECK(holds==1);
 HBCircularSetEditRequest(d,^{edits++;HBUpdateCircularDock(d,nil,CGRectZero,@[],0,NO,nil,nil);});
 HBCircularTestRequestEditing(d);
 CHECK(edits==cycle+1);CHECK(saves==cycle+1);CHECK(taps==0);CHECK(!HBCircularDockActive(d));CHECK(!ring.superview);CHECK(root.subviews.count==1);CHECK(fabs(d.alpha-.8)<.001);CHECK(d.userInteractionEnabled);CHECK(!d.accessibilityElementsHidden);CHECK(nativeChild.superview==d);CHECK(CGRectEqualToRect(nativeChild.frame,CGRectMake(0,0,40,40)));
 // Repeated native editing/drag refreshes do not attach a circular input surface.
 HBUpdateCircularDock(d,nil,CGRectZero,@[],0,NO,nil,nil);CHECK(d.userInteractionEnabled);CHECK(root.subviews.count==1);
 // Native Done/drag cancellation returns to circular without modifying mode or phase.
 HBUpdateCircularDock(d,root,anchor,rows,savedPhase,YES,nil,nil);CHECK(HBCircularDockActive(d));CHECK(HBCircularTestView(d)!=ring);CHECK(root.subviews.count==2);
 HBUpdateCircularDock(d,nil,CGRectZero,@[],0,NO,nil,nil);CHECK(root.subviews.count==1);CHECK(d.userInteractionEnabled);
 }
 printf("{\"checks\":%d,\"handoffCycles\":100,\"proxyDragInteractions\":0,\"realAppsMoved\":false,\"windowShown\":false}\n",checks);return 0;
}}
