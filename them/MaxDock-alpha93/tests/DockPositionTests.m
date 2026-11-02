#import "../HBDockPosition.h"
#import <math.h>
@interface HBPositionNativeDock85:UIView
@property(nonatomic) CGPoint lastDeliveredCenter;
@property(nonatomic) CGRect lastDeliveredFrame;
@property(nonatomic) BOOL animationsEnabledAtCenterWrite;
@end
@implementation HBPositionNativeDock85
- (void)setCenter:(CGPoint)center{HBPositionSetNativeCenter(self,center,^(CGPoint adjusted){self.lastDeliveredCenter=adjusted;self.animationsEnabledAtCenterWrite=UIView.areAnimationsEnabled;[super setCenter:adjusted];});}
- (void)setFrame:(CGRect)frame{HBPositionSetNativeFrame(self,frame,^(CGRect adjusted){self.lastDeliveredFrame=adjusted;[super setFrame:adjusted];});}
@end
static int checks=0;
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"failed line %d: %s\n",__LINE__,#x);return 2;}}while(0)
int main(void){@autoreleasepool{
 CGRect screen=CGRectMake(0,0,390,844),content=CGRectMake(25,690,340,60);
 CHECK(HBDockClampedOffset(120,content,screen,52)==94);CHECK(fabs(CGRectGetMaxY(content)+HBDockClampedOffset(120,content,screen,52)-CGRectGetMaxY(screen))<.01);CHECK(HBDockClampedOffset(30,content,screen,52)==30);CHECK(HBDockClampedOffset(-200,content,screen,52)==-100);
 CHECK(HBDockClampedOffset(NAN,content,screen,52)==0);CHECK(HBDockClampedOffset(40,CGRectNull,screen,52)==0);CHECK(HBDockClampedOffset(40,CGRectZero,screen,52)==0);
 CHECK(HBDockClampedOffset(0,CGRectMake(0,830,50,30),screen,52)==0);CHECK(HBDockClampedOffset(40,CGRectMake(0,830,50,30),screen,52)==0);
 UIWindow*w=[[UIWindow alloc]initWithFrame:screen];UIView*root=[[UIView alloc]initWithFrame:screen];[w addSubview:root];HBPositionNativeDock85*dock=[[HBPositionNativeDock85 alloc]initWithFrame:CGRectMake(20,650,350,140)];[root addSubview:dock];
 UIButton*icon=[[UIButton alloc]initWithFrame:CGRectMake(40,50,35,35)];[dock addSubview:icon];CGPoint oldPoint=[icon convertPoint:CGPointMake(15,15)toView:root];
 CGRect local=CGRectMake(5,40,340,60);HBUpdateDockPosition(dock,local,40,NO,NO,nil);CHECK(fabs(dock.center.y-760)<.01);CHECK(HBDockAppliedOffset(dock)==40);
 for(int i=0;i<100;i++){HBUpdateDockPosition(dock,local,40,NO,NO,nil);CHECK(fabs(dock.center.y-760)<.01);}
 // A native layout reset must never deliver an unshifted target to UIView.
 for(int i=0;i<50;i++){
  dock.center=CGPointMake(195,720);CHECK(fabs(dock.center.y-760)<.01);CHECK(fabs(dock.lastDeliveredCenter.y-760)<.01);
  dock.frame=CGRectMake(20,650,350,140);CHECK(fabs(dock.center.y-760)<.01);CHECK(fabs(dock.lastDeliveredFrame.origin.y-690)<.01);
  HBUpdateDockPosition(dock,local,40,NO,NO,nil);CHECK(fabs(dock.center.y-760)<.01);
 }
 __block BOOL ownUpdateAnimated=YES;
 [UIView animateWithDuration:.3 animations:^{HBUpdateDockPosition(dock,local,50,NO,NO,nil);ownUpdateAnimated=dock.animationsEnabledAtCenterWrite;}];
 CHECK(!ownUpdateAnimated);CHECK(fabs(dock.center.y-770)<.01);
 HBUpdateDockPosition(dock,local,40,NO,NO,nil);
 [UIView animateWithDuration:.3 animations:^{dock.center=CGPointMake(195,700);}];CHECK(fabs(dock.center.y-740)<.01);CHECK(dock.animationsEnabledAtCenterWrite);
 dock.center=CGPointMake(195,720);CHECK(fabs(dock.center.y-760)<.01);
 CGPoint moved=[icon convertPoint:CGPointMake(15,15)toView:root];CHECK(fabs(moved.y-oldPoint.y-40)<.01);CHECK([root hitTest:moved withEvent:nil]==icon);CHECK([root hitTest:oldPoint withEvent:nil]!=icon);
 HBUpdateDockPosition(dock,local,120,NO,NO,nil);CHECK(HBDockAppliedOffset(dock)==94);CHECK(fabs(dock.center.y-814)<.01);
 dock.center=CGPointMake(195,720);HBUpdateDockPosition(dock,local,40,NO,NO,nil);CHECK(fabs(dock.center.y-760)<.01);
 CGAffineTransform hidden=CGAffineTransformMakeTranslation(0,100);dock.transform=hidden;HBUpdateDockPosition(dock,local,40,NO,NO,nil);CHECK(CGAffineTransformEqualToTransform(dock.transform,hidden));CHECK(fabs(dock.center.y-760)<.01);dock.transform=CGAffineTransformIdentity;
 HBUpdateDockPosition(dock,local,0,NO,NO,nil);CHECK(fabs(dock.center.y-720)<.01);
 __block int saves=0;__block CGFloat saved=0;void(^save)(CGFloat)=^(CGFloat y){saves++;saved=y;};HBUpdateDockPosition(dock,local,0,YES,YES,save);
 NSUInteger handles=0;for(UIView*v in dock.subviews)if([v isKindOfClass:UIButton.class]&&v!=icon&&!v.hidden)handles++;CHECK(handles==1);
 HBPositionTestPan(dock,UIGestureRecognizerStateBegan,0);HBPositionTestPan(dock,UIGestureRecognizerStateChanged,45);CHECK(saves==0);CHECK(HBDockAppliedOffset(dock)==45);
 HBUpdateDockPosition(dock,local,0,YES,YES,save);CHECK(HBDockAppliedOffset(dock)==45);
 HBPositionTestPan(dock,UIGestureRecognizerStateEnded,45);CHECK(saves==1&&saved==45);CHECK(fabs(dock.center.y-765)<.01);
 HBUpdateDockPosition(dock,local,45,YES,YES,save);HBPositionTestPan(dock,UIGestureRecognizerStateBegan,0);HBPositionTestPan(dock,UIGestureRecognizerStateChanged,-20);CHECK(HBDockAppliedOffset(dock)==25);HBPositionTestPan(dock,UIGestureRecognizerStateCancelled,-20);CHECK(HBDockAppliedOffset(dock)==45);CHECK(saves==1);
 HBUpdateDockPosition(dock,local,0,NO,NO,nil);CHECK(HBDockAppliedOffset(dock)==0);CHECK(fabs(dock.center.y-720)<.01);for(UIView*v in dock.subviews)if(v!=icon)CHECK(v.hidden);
 w.frame=CGRectMake(0,0,844,390);root.frame=w.bounds;dock.center=CGPointMake(422,300);HBUpdateDockPosition(dock,local,40,YES,YES,save);CHECK(HBDockAppliedOffset(dock)==0);for(UIView*v in dock.subviews)if(v!=icon)CHECK(v.hidden);
 // Reproduce the observed Home Screen shrink behind Settings (scale .88).
 w.frame=screen;root.frame=screen;dock.center=CGPointMake(195,720);
 HBUpdateDockPosition(dock,local,120,NO,NO,nil);CHECK(HBDockAppliedOffset(dock)==94);
 for(int i=0;i<60;i++){
  CGFloat scale=(i%3==0)?.88:(i%3==1)?.94:1;
  root.transform=CGAffineTransformMakeScale(scale,scale);root.hidden=(i%2)==0;
  HBUpdateDockPosition(dock,local,120,NO,NO,nil);
  CHECK(fabs(HBDockAppliedOffset(dock)-94)<.01);CHECK(fabs(dock.center.y-814)<.01);
  dock.center=CGPointMake(195,720);CHECK(fabs(dock.center.y-814)<.01);
 }
 root.hidden=NO;root.transform=CGAffineTransformIdentity;
 HBUpdateDockPosition(dock,local,120,NO,NO,nil);CHECK(fabs(dock.center.y-814)<.01);
 HBUpdateDockPosition(dock,local,0,NO,NO,nil);CHECK(fabs(dock.center.y-720)<.01);
 CHECK(w.hidden);printf("{\"checks\":%d,\"appTransitionZoomRegressionVerified\":true,\"nativeResetsMediated\":true,\"ownCorrectionAnimationsDisabled\":true,\"repeatUpdatesStable\":true,\"hitTestingVerified\":true,\"dragSaveAndCancelVerified\":true,\"realDockModified\":false,\"realPreferencesWritten\":false,\"windowShown\":false}\n",checks);return 0;
}}
