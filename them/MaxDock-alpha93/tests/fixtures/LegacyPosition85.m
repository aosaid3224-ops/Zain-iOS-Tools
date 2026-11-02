#import "HBDockPosition.h"
#import <objc/runtime.h>
#import <math.h>
static char PositionKey;
CGFloat HBDockClampedOffset(CGFloat requested,CGRect content,CGRect screen,CGFloat topInset){
 if(!isfinite(requested)||!isfinite(topInset)||!isfinite(content.origin.x)||!isfinite(content.origin.y)||!isfinite(content.size.width)||!isfinite(content.size.height)||CGRectIsEmpty(content)||CGRectIsNull(content)||CGRectIsInfinite(content)||!isfinite(screen.size.height)||!isfinite(screen.origin.y)||screen.size.height<=0)return 0;
 if(requested>0)return MAX(0,MIN(MIN(requested,120),CGRectGetMaxY(screen)-24-CGRectGetMaxY(content)));
 if(requested<0)return MIN(0,MAX(MAX(requested,-100),CGRectGetMinY(screen)+MAX(0,topInset)-CGRectGetMinY(content)));
 return 0;
}
@interface HBDockPositionController:NSObject<UIGestureRecognizerDelegate>
@property(nonatomic,weak) UIView *dock;
@property(nonatomic,weak) UIButton *handle;
@property(nonatomic) CGPoint nativeCenter,lastCenter;
@property(nonatomic) NSUInteger nativeWriteDepth;
@property(nonatomic) BOOL positioned,applying,dragging,allowDrag,editing;
@property(nonatomic) CGFloat requested,applied,startOffset,startRequested;
@property(nonatomic) CGRect content;
@property(nonatomic,copy) void(^save)(CGFloat);
- (void)apply;
- (CGFloat)offsetForNativeCenter:(CGPoint)center;
@end
@implementation HBDockPositionController
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)recognizer{if(!self.editing||!self.allowDrag)return NO;CGPoint v=[(UIPanGestureRecognizer*)recognizer velocityInView:self.dock.superview];return fabs(v.y)>fabs(v.x);}
- (void)pan:(UIPanGestureRecognizer*)pan{
 UIView*dock=self.dock;if(!dock)return;
 if(pan.state==UIGestureRecognizerStateBegan){self.dragging=YES;self.startOffset=self.applied;self.startRequested=self.requested;}
 if(pan.state==UIGestureRecognizerStateBegan||pan.state==UIGestureRecognizerStateChanged||pan.state==UIGestureRecognizerStateEnded){self.requested=self.startOffset+[pan translationInView:dock.superview].y;[self apply];}
 if(pan.state==UIGestureRecognizerStateEnded){self.dragging=NO;self.requested=round(self.applied);if(self.save)self.save(self.requested);}
 if(pan.state==UIGestureRecognizerStateCancelled||pan.state==UIGestureRecognizerStateFailed){self.dragging=NO;self.requested=self.startRequested;[self apply];}
}
- (CGFloat)offsetForNativeCenter:(CGPoint)center{
 UIView*dock=self.dock;UIWindow*window=dock.window;
 BOOL portrait=window&&CGRectGetHeight(window.bounds)>=CGRectGetWidth(window.bounds);
 CGRect base=self.content;base.origin.x+=center.x-CGRectGetMidX(dock.bounds);base.origin.y+=center.y-CGRectGetMidY(dock.bounds);
 CGRect onScreen=(window&&!CGRectIsNull(base)&&!CGRectIsEmpty(base))?[dock.superview convertRect:base toView:window]:CGRectNull;
 return portrait?HBDockClampedOffset(self.requested,onScreen,window.bounds,window.safeAreaInsets.top+8):0;
}
- (void)apply{
 if(!NSThread.isMainThread||self.applying||self.nativeWriteDepth)return;UIView*dock=self.dock;if(!dock||!dock.superview)return;self.applying=YES;
 CGPoint center=dock.center;
 if(!self.positioned||fabs(center.x-self.lastCenter.x)>.01||fabs(center.y-self.lastCenter.y)>.01)self.nativeCenter=center;
 UIWindow*window=dock.window;BOOL portrait=window&&CGRectGetHeight(window.bounds)>=CGRectGetWidth(window.bounds);
 self.applied=[self offsetForNativeCenter:self.nativeCenter];
 [UIView performWithoutAnimation:^{
 [CATransaction begin];[CATransaction setDisableActions:YES];
 self.lastCenter=CGPointMake(self.nativeCenter.x,self.nativeCenter.y+self.applied);self.positioned=YES;
 if(!CGPointEqualToPoint(dock.center,self.lastCenter))dock.center=self.lastCenter;
 BOOL show=self.allowDrag&&self.editing&&portrait&&!CGRectIsEmpty(self.content)&&!CGRectIsNull(self.content);
 UIButton*handle=self.handle;
 if(show&&!handle){handle=[UIButton buttonWithType:UIButtonTypeSystem];handle.backgroundColor=[UIColor.systemBlueColor colorWithAlphaComponent:.9];handle.tintColor=UIColor.whiteColor;handle.layer.cornerRadius=10;[handle setImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"]forState:UIControlStateNormal];handle.accessibilityLabel=[NSLocale.preferredLanguages.firstObject hasPrefix:@"ar"]?@"اسحب لتغيير ارتفاع الدوك":@"Drag to move Dock vertically";UIPanGestureRecognizer*pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)];pan.maximumNumberOfTouches=1;pan.delegate=self;[handle addGestureRecognizer:pan];[dock addSubview:handle];self.handle=handle;}
 handle.hidden=!show;handle.userInteractionEnabled=show;
 if(show){handle.frame=CGRectMake(CGRectGetMidX(self.content)-22,MAX(CGRectGetMinY(dock.bounds),CGRectGetMinY(self.content)-20),44,20);[dock bringSubviewToFront:handle];}
 [CATransaction commit];
 }];
 self.applying=NO;
}
@end
void HBUpdateDockPosition(UIView*dock,CGRect content,CGFloat requested,BOOL allowDrag,BOOL editing,void(^save)(CGFloat)){
 if(!NSThread.isMainThread||!dock)return;
 HBDockPositionController*c=objc_getAssociatedObject(dock,&PositionKey);if(!c){c=[HBDockPositionController new];c.dock=dock;objc_setAssociatedObject(dock,&PositionKey,c,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
 c.content=content;if(!c.dragging)c.requested=requested;c.allowDrag=allowDrag;c.editing=editing;c.save=save;[c apply];
}
CGFloat HBDockAppliedOffset(UIView*dock){return ((HBDockPositionController*)objc_getAssociatedObject(dock,&PositionKey)).applied;}

// Native layout writes are adjusted before UIView sees the target. This avoids
// briefly animating to the unshifted frame and repairing it on the next poll.
void HBPositionSetNativeCenter(UIView*dock,CGPoint center,void(^original)(CGPoint)){
 if(!original)return;
 HBDockPositionController*c=NSThread.isMainThread?objc_getAssociatedObject(dock,&PositionKey):nil;
 if(!c||c.applying||c.nativeWriteDepth||CGPointEqualToPoint(center,dock.center)){original(center);return;}
 c.nativeCenter=center;c.applied=[c offsetForNativeCenter:center];c.lastCenter=CGPointMake(center.x,center.y+c.applied);c.positioned=YES;
 c.nativeWriteDepth++;@try{original(c.lastCenter);}@finally{c.nativeWriteDepth--;}[c apply];
}
void HBPositionSetNativeFrame(UIView*dock,CGRect frame,void(^original)(CGRect)){
 if(!original)return;
 HBDockPositionController*c=NSThread.isMainThread?objc_getAssociatedObject(dock,&PositionKey):nil;
 if(!c||c.applying||c.nativeWriteDepth||CGRectEqualToRect(frame,dock.frame)){original(frame);return;}
 CGPoint center=CGPointMake(CGRectGetMidX(frame)-dock.transform.tx,CGRectGetMidY(frame)-dock.transform.ty);
 c.nativeCenter=center;c.applied=[c offsetForNativeCenter:center];c.lastCenter=CGPointMake(center.x,center.y+c.applied);c.positioned=YES;
 frame.origin.y+=c.applied;c.nativeWriteDepth++;@try{original(frame);}@finally{c.nativeWriteDepth--;}[c apply];
}

#ifdef HB_POSITION_TEST
@interface HBPositionFakePan84:UIPanGestureRecognizer
@property(nonatomic) UIGestureRecognizerState simulatedState;
@property(nonatomic) CGFloat simulatedY;
@end
@implementation HBPositionFakePan84
- (UIGestureRecognizerState)state{return self.simulatedState;}
- (CGPoint)translationInView:(UIView*)view{(void)view;return CGPointMake(0,self.simulatedY);}
@end
void HBPositionTestPan(UIView*dock,UIGestureRecognizerState state,CGFloat y){HBDockPositionController*c=objc_getAssociatedObject(dock,&PositionKey);HBPositionFakePan84*p=[HBPositionFakePan84 new];p.simulatedState=state;p.simulatedY=y;[c pan:p];}
#endif
