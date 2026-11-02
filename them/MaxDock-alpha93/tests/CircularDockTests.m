#import <UIKit/UIKit.h>
#import "HBCircularDock.h"
#import <math.h>
static int checks=0;
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"Failed line %d\n",__LINE__);return 1;}}while(0)
@interface FakeDock:UIView @end
@implementation FakeDock
-(void)setAlpha:(CGFloat)a{HBCircularSetNativeAlpha(self,a,^(CGFloat v){[super setAlpha:v];});}
@end
int main(){@autoreleasepool{
 for(NSValue*value in @[[NSValue valueWithCGSize:CGSizeMake(351,64)],[NSValue valueWithCGSize:CGSizeMake(796,88)]]){
 CGSize bounds=value.CGSizeValue;
 for(NSNumber*n in @[@1,@4,@12,@18,@100])for(NSNumber*phase in @[@0,@.4,@-2.2,@(2*M_PI)]){
 NSArray*a=HBCircularGeometry(n.unsignedIntegerValue,phase.doubleValue,bounds);CHECK(a.count==n.unsignedIntegerValue);int selected=0;
 for(NSDictionary*g in a){double x=[g[@"x"]doubleValue],y=[g[@"y"]doubleValue],size=[g[@"size"]doubleValue];CHECK(isfinite(x)&&isfinite(y)&&size>0&&x-size/2>=0&&y-size/2>=0&&x+size/2<=bounds.width&&y+size/2<=bounds.height);selected+=[g[@"selected"]boolValue];}CHECK(selected==1);
 }
 }
 CHECK(HBCircularGeometry(0,0,CGSizeMake(351,64)).count==0);CHECK(HBCircularGeometry(101,0,CGSizeMake(351,64)).count==0);CHECK(HBCircularGeometry(4,0,CGSizeMake(NAN,64)).count==0);CHECK(HBCircularGeometry(4,0,CGSizeMake(351,30)).count==0);
 NSArray*zero=HBCircularGeometry(12,0,CGSizeMake(351,64)),*wrap=HBCircularGeometry(12,2*M_PI,CGSizeMake(351,64));for(int i=0;i<12;i++){CHECK(fabs([zero[i][@"x"]doubleValue]-[wrap[i][@"x"]doubleValue])<.0001);CHECK(fabs([zero[i][@"y"]doubleValue]-[wrap[i][@"y"]doubleValue])<.0001);}
 UIWindow*w=[[UIWindow alloc]initWithFrame:CGRectMake(0,0,375,812)];UIView*root=[[UIView alloc]initWithFrame:w.bounds];[w addSubview:root];FakeDock*d=[[FakeDock alloc]initWithFrame:CGRectMake(0,712,375,100)];[root addSubview:d];d.alpha=.8;
 UIGraphicsBeginImageContextWithOptions(CGSizeMake(32,32),NO,1);[UIColor.redColor setFill];UIRectFill(CGRectMake(0,0,32,32));UIImage*image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();
 NSMutableArray*rows=[NSMutableArray new];for(int i=0;i<4;i++)[rows addObject:@{@"key":[NSString stringWithFormat:@"demo%d",i],@"title":@"Demo",@"image":image,@"badge":@"4"}];__block int taps=0,saves=0;
 HBUpdateCircularDock(d,root,d.frame,rows,0,YES,^(NSString*k){taps++;},^(CGFloat phase){saves++;});CHECK(HBCircularDockActive(d));CHECK(d.alpha==0);CHECK(!d.userInteractionEnabled);UIView*ring=HBCircularTestView(d);CHECK(ring.superview==root);CHECK(CGRectContainsRect(root.bounds,ring.frame));CHECK(ring.bounds.size.height<=88);CHECK(ring.bounds.size.width>300);CHECK(CGRectGetMinY(ring.frame)>=CGRectGetMinY(d.frame)-8);CHECK(ring.clipsToBounds);[ring layoutIfNeeded];for(UIView*v in ring.subviews)if([v isKindOfClass:UIButton.class])CHECK(CGRectContainsRect(ring.bounds,v.frame));
 UIView*front=nil;for(UIView*v in ring.subviews)if([v isKindOfClass:UIButton.class]&&(!front||v.layer.zPosition>front.layer.zPosition))front=v;CHECK(front!=nil);CHECK([ring hitTest:front.center withEvent:nil]==front);
 d.alpha=.4;CHECK(d.alpha==0);CHECK(fabs(ring.alpha-.4)<.001);CHECK(fabs(HBCircularNativeAlpha(d)-.4)<.001);
 for(UIView*v in ring.subviews)if([v isKindOfClass:UIButton.class]){UIButton*b=(id)v;for(id target in b.allTargets)for(NSString*action in [b actionsForTarget:target forControlEvent:UIControlEventTouchUpInside]){[target performSelector:NSSelectorFromString(action) withObject:b];}break;}CHECK(taps==1);
 HBCircularTestRotate(d,.7,YES,NO);CHECK(saves==1);CHECK(taps==1);HBCircularTestRotate(d,.3,NO,YES);CHECK(saves==1);
 HBUpdateCircularDock(d,nil,CGRectZero,@[],0,NO,nil,nil);CHECK(!HBCircularDockActive(d));CHECK(!ring.superview);CHECK(fabs(d.alpha-.4)<.001);CHECK(d.userInteractionEnabled);CHECK(!d.accessibilityElementsHidden);
 // A wide/landscape Dock uses the same shallow orbit, not a tall ring.
 w.frame=CGRectMake(0,0,812,375);root.frame=w.bounds;d.frame=CGRectMake(0,287,812,88);
 HBUpdateCircularDock(d,root,d.frame,rows,0,YES,nil,nil);CHECK(HBCircularDockActive(d));UIView*wide=HBCircularTestView(d);CHECK(wide.bounds.size.width>700);CHECK(wide.bounds.size.height<=88);CHECK(CGRectContainsRect(root.bounds,wide.frame));
 HBUpdateCircularDock(d,nil,CGRectZero,@[],0,NO,nil,nil);CHECK(!HBCircularDockActive(d));
 printf("{\"checks\":%d,\"windowShown\":false,\"appsLaunched\":false}\n",checks);return 0;
}}
