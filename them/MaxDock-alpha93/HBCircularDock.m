#import "HBCircularDock.h"
#import "HBIconColor.h"
#import <objc/runtime.h>
#import <math.h>
static char CircleKey;
static CGFloat Normalize(CGFloat p){return isfinite(p)?remainder(p,M_PI*2):0;}
// A shallow horizontal orbit, entirely inside the existing Dock footprint.
// The near side is larger; the far side recedes behind it, like a carousel.
NSArray<NSDictionary*> *HBCircularGeometry(NSUInteger count,CGFloat phase,CGSize bounds){return HBCircularGeometryScaled(count,phase,bounds,1);}
NSArray<NSDictionary*> *HBCircularGeometryScaled(NSUInteger count,CGFloat phase,CGSize bounds,CGFloat scale){
 if(!count||count>100||!isfinite(bounds.width)||!isfinite(bounds.height)||bounds.width<80||bounds.height<40)return @[];
 phase=Normalize(phase);CGFloat base=MIN(48*(isfinite(scale)?MAX(.6,MIN(1.3,scale)):1),bounds.height-16),radiusX=MAX(0,(bounds.width-base-16)/2),radiusY=MIN(4,MAX(0,(bounds.height-base-12)/2)),step=2*M_PI/count;
 NSInteger front=((NSInteger)llround(-phase/step)%(NSInteger)count+(NSInteger)count)%(NSInteger)count;
 NSMutableArray*result=[NSMutableArray new];
 for(NSUInteger i=0;i<count;i++){CGFloat angle=phase+i*step,depth=cos(angle),size=base*(.58+.42*(depth+1)/2);[result addObject:@{@"x":@(bounds.width/2+sin(angle)*radiusX),@"y":@(bounds.height/2+cos(angle)*radiusY),@"size":@(size),@"depth":@(depth),@"selected":@((BOOL)(i==(NSUInteger)front))}];}
 return result;
}
@interface HBCircularView:UIView<UIGestureRecognizerDelegate>
@property(nonatomic,copy) NSArray<NSDictionary*> *rows;
@property(nonatomic,strong) NSMutableArray<UIButton*> *buttons;
@property(nonatomic,strong) UIVisualEffectView *backdrop;
@property(nonatomic,copy) void(^tap)(NSString*),(^save)(CGFloat);
@property(nonatomic) CGFloat phase,startPhase,lastAngle,speed,iconScale;
@property(nonatomic,copy) void(^editRequest)(void);
@property(nonatomic) BOOL rotating;
- (void)drawIcons;
- (void)rotateBy:(CGFloat)delta;
- (void)finishRotation:(BOOL)cancel;
@end
@implementation HBCircularView
- (instancetype)initWithFrame:(CGRect)frame{
 if((self=[super initWithFrame:frame])){
 self.speed=2;self.iconScale=1;self.backgroundColor=UIColor.clearColor;self.clipsToBounds=YES;self.buttons=[NSMutableArray new];
 self.backdrop=[[UIVisualEffectView alloc]initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
 self.backdrop.userInteractionEnabled=NO;[self addSubview:self.backdrop];
 self.layer.borderColor=[UIColor colorWithWhite:1 alpha:.18].CGColor;self.layer.borderWidth=.5;
 UIPanGestureRecognizer*pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)];pan.maximumNumberOfTouches=1;pan.cancelsTouchesInView=YES;pan.delegate=self;[self addGestureRecognizer:pan];
 }return self;
}
- (BOOL)onTrack:(CGPoint)p{return CGRectContainsPoint(self.bounds,p);}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gesture{
 if(self.rows.count<2)return NO;
 CGPoint velocity=[(UIPanGestureRecognizer*)gesture velocityInView:self];return fabs(velocity.x)>fabs(velocity.y);
}
- (void)button:(UIButton*)button{if(self.tap)self.tap(button.accessibilityIdentifier);}
- (void)rotateBy:(CGFloat)delta{if(!isfinite(delta))return;self.phase=Normalize(self.phase+delta);[self drawIcons];}
- (void)finishRotation:(BOOL)cancel{if(!self.rotating)return;self.rotating=NO;if(cancel){self.phase=self.startPhase;[self drawIcons];return;}if(!self.rows.count)return;CGFloat step=2*M_PI/self.rows.count;self.phase=Normalize(round(self.phase/step)*step);[UIView animateWithDuration:.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:^{[self drawIcons];}completion:nil];if(self.save)self.save(self.phase);}
- (void)pan:(UIPanGestureRecognizer*)pan{
 CGFloat x=[pan translationInView:self].x;
 if(pan.state==UIGestureRecognizerStateBegan){self.rotating=YES;self.startPhase=self.phase;self.lastAngle=0;}
 if(pan.state==UIGestureRecognizerStateChanged||pan.state==UIGestureRecognizerStateEnded){CGFloat angle=x*self.speed/MAX(32,(self.bounds.size.width-72)/2);[self rotateBy:angle-self.lastAngle];self.lastAngle=angle;}
 if(pan.state==UIGestureRecognizerStateEnded)[self finishRotation:NO];
 if(pan.state==UIGestureRecognizerStateCancelled||pan.state==UIGestureRecognizerStateFailed)[self finishRotation:YES];
}
- (void)setRows:(NSArray<NSDictionary*>*)rows{_rows=[rows copy];while(self.buttons.count>rows.count){[self.buttons.lastObject removeFromSuperview];[self.buttons removeLastObject];}while(self.buttons.count<rows.count){UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom];UILongPressGestureRecognizer*hold=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(hold:)];hold.minimumPressDuration=.45;hold.cancelsTouchesInView=YES;[b addGestureRecognizer:hold];b.imageView.contentMode=UIViewContentModeScaleAspectFit;b.clipsToBounds=NO;[b addTarget:self action:@selector(button:)forControlEvents:UIControlEventTouchUpInside];UILabel*badge=[UILabel new];badge.tag=89;badge.font=[UIFont boldSystemFontOfSize:9];badge.textColor=UIColor.whiteColor;badge.backgroundColor=UIColor.systemRedColor;badge.textAlignment=NSTextAlignmentCenter;badge.layer.cornerRadius=7;badge.clipsToBounds=YES;[b addSubview:badge];[self addSubview:b];[self.buttons addObject:b];}for(NSUInteger i=0;i<rows.count;i++){NSDictionary*row=rows[i];UIButton*b=self.buttons[i];UIImage*image=row[@"image"];if(![image isKindOfClass:UIImage.class])image=[UIImage systemImageNamed:@"app.fill"];[b setImage:image forState:UIControlStateNormal];b.accessibilityIdentifier=row[@"key"];b.accessibilityLabel=row[@"title"];UILabel*badge=[b viewWithTag:89];badge.text=row[@"badge"];badge.hidden=!badge.text.length;}[self drawIcons];}
- (void)layoutSubviews{[super layoutSubviews];[self drawIcons];}
- (void)drawIcons{
 self.layer.cornerRadius=MIN(30,self.bounds.size.height/2);self.backdrop.frame=self.bounds;
 NSArray*layout=HBCircularGeometryScaled(self.rows.count,self.phase,self.bounds.size,self.iconScale);
 for(NSUInteger i=0;i<layout.count;i++){
 NSDictionary*g=layout[i];UIButton*b=self.buttons[i];CGFloat size=[g[@"size"]doubleValue],depth=[g[@"depth"]doubleValue];
 b.frame=CGRectMake([g[@"x"]doubleValue]-size/2,[g[@"y"]doubleValue]-size/2,size,size);b.alpha=.55+.45*(depth+1)/2;b.layer.zPosition=depth+2;
 b.imageView.layer.cornerRadius=size*.23;b.imageView.clipsToBounds=YES;
 UILabel*badge=[b viewWithTag:89];badge.frame=CGRectMake(MAX(0,size-15),0,18,14);
 b.accessibilityTraits=UIAccessibilityTraitButton|([g[@"selected"]boolValue]?UIAccessibilityTraitSelected:0);
 }
 // Match UIKit hit testing order to visual depth so a rear icon never steals a tap.
 NSArray*sorted=[self.buttons sortedArrayUsingComparator:^NSComparisonResult(UIButton*a,UIButton*b){return a.layer.zPosition<b.layer.zPosition?NSOrderedAscending:(a.layer.zPosition>b.layer.zPosition?NSOrderedDescending:NSOrderedSame);}];
 for(UIButton*b in sorted)[self bringSubviewToFront:b];
}

// Do not forward UIKit drag sessions to hidden SpringBoard interactions.
// Editing and actual drag/drop belong exclusively to the native Dock.
- (void)requestEditing {
 if(self.rotating||!self.editRequest)return;
 if(self.save)self.save(self.phase);
 void(^request)(void)=[self.editRequest copy];request();
}
- (void)hold:(UILongPressGestureRecognizer*)gesture {
 if(gesture.state==UIGestureRecognizerStateBegan)[self requestEditing];
}

@end
@interface HBCircularPresentation:NSObject
@property(nonatomic,weak) UIView*dock;
@property(nonatomic,strong) HBCircularView*ring;
@property(nonatomic) BOOL active,writingAlpha,oldInteraction,oldAccessibility;
@property(nonatomic) CGFloat iconScale;
@property(nonatomic) CGFloat nativeAlpha;
@end
@implementation HBCircularPresentation
- (void)dealloc{UIView*v=_ring;if(NSThread.isMainThread)[v removeFromSuperview];else dispatch_async(dispatch_get_main_queue(),^{[v removeFromSuperview];});}
@end
static void Restore(HBCircularPresentation*c){if(!c.active)return;UIView*dock=c.dock;c.active=NO;[c.ring removeFromSuperview];c.ring=nil;[UIView performWithoutAnimation:^{dock.alpha=c.nativeAlpha;dock.userInteractionEnabled=c.oldInteraction;dock.accessibilityElementsHidden=c.oldAccessibility;}];}
void HBCircularSetIconScale(UIView*dock,CGFloat scale){if(!NSThread.isMainThread||!dock)return;HBCircularPresentation*c=objc_getAssociatedObject(dock,&CircleKey);if(!c){c=[HBCircularPresentation new];c.dock=dock;objc_setAssociatedObject(dock,&CircleKey,c,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}c.iconScale=isfinite(scale)?MAX(.6,MIN(1.3,scale)):1;c.ring.iconScale=c.iconScale;[c.ring setNeedsLayout];}
void HBCircularSetEditRequest(UIView*dock,void(^request)(void)){if(!NSThread.isMainThread)return;HBCircularPresentation*c=objc_getAssociatedObject(dock,&CircleKey);c.ring.editRequest=request;}

void HBCircularSetSpeed(UIView*dock,CGFloat speed){if(!NSThread.isMainThread)return;HBCircularPresentation*c=objc_getAssociatedObject(dock,&CircleKey);c.ring.speed=isfinite(speed)?MAX(.5,MIN(4,speed)):2;}
BOOL HBCircularDockActive(UIView*dock){return ((HBCircularPresentation*)objc_getAssociatedObject(dock,&CircleKey)).active;}
CGFloat HBCircularNativeAlpha(UIView*dock){HBCircularPresentation*c=objc_getAssociatedObject(dock,&CircleKey);return c.active?c.nativeAlpha:dock.alpha;}
void HBCircularSetNativeAlpha(UIView*dock,CGFloat alpha,void(^original)(CGFloat)){HBCircularPresentation*c=NSThread.isMainThread?objc_getAssociatedObject(dock,&CircleKey):nil;if(c.active){if(!c.writingAlpha){c.nativeAlpha=alpha;c.ring.alpha=alpha;}original(0);}else original(alpha);}
void HBUpdateCircularDock(UIView*dock,UIView*surface,CGRect anchor,NSArray*rows,CGFloat phase,BOOL active,void(^tap)(NSString*),void(^save)(CGFloat)){
 if(!NSThread.isMainThread||!dock)return;HBCircularPresentation*c=objc_getAssociatedObject(dock,&CircleKey);
 BOOL attached=dock.window!=nil;
 if(!active||!surface||!attached||rows.count>100||CGRectIsNull(anchor)||CGRectIsEmpty(anchor)||!isfinite(anchor.origin.x)||!isfinite(anchor.origin.y)||!isfinite(anchor.size.width)||!isfinite(anchor.size.height)){Restore(c);return;}
 NSMutableArray*clean=[NSMutableArray new];for(id row in rows){if(![row isKindOfClass:NSDictionary.class]||![row[@"key"]isKindOfClass:NSString.class]||[row[@"key"]length]>256)continue;NSMutableDictionary*x=[row mutableCopy];if(![x[@"title"]isKindOfClass:NSString.class])x[@"title"]=@"";if(![x[@"badge"]isKindOfClass:NSString.class])x[@"badge"]=@"";if([x[@"badge"]length]>5)x[@"badge"]=@"99+";[clean addObject:x];}if(rows.count&&!clean.count){Restore(c);return;}
 if(!c){c=[HBCircularPresentation new];c.dock=dock;objc_setAssociatedObject(dock,&CircleKey,c,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
 [UIView performWithoutAnimation:^{
 if(!c.active){c.nativeAlpha=dock.alpha;c.oldInteraction=dock.userInteractionEnabled;c.oldAccessibility=dock.accessibilityElementsHidden;c.active=YES;c.ring=[[HBCircularView alloc]initWithFrame:CGRectZero];c.ring.phase=Normalize(phase);}
 CGFloat width=MIN(surface.bounds.size.width-16,MAX(anchor.size.width+16,surface.bounds.size.width-24));
 CGFloat scale=c.iconScale>0?c.iconScale:1;c.ring.iconScale=scale;
 CGFloat height=MIN(88,MAX(MAX(64,48*scale+16),anchor.size.height+16));
 if(width<80||surface.bounds.size.height<height){Restore(c);return;}
 CGFloat x=MAX(CGRectGetMinX(surface.bounds)+8,MIN(CGRectGetMaxX(surface.bounds)-width-8,CGRectGetMidX(anchor)-width/2));
 CGFloat bottom=MAX(CGRectGetMinY(surface.bounds)+height,MIN(CGRectGetMaxY(surface.bounds),CGRectGetMaxY(anchor)+8));
 c.ring.frame=CGRectMake(x,bottom-height,width,height);c.ring.tap=tap;c.ring.save=save;c.ring.rows=clean;c.ring.alpha=c.nativeAlpha;
 if(c.ring.superview!=surface){[c.ring removeFromSuperview];[surface addSubview:c.ring];}[surface bringSubviewToFront:c.ring];c.writingAlpha=YES;dock.alpha=0;c.writingAlpha=NO;dock.userInteractionEnabled=NO;dock.accessibilityElementsHidden=YES;
 }];
}
#ifdef HB_CIRCULAR_TEST
void HBCircularTestRequestEditing(UIView*dock){[((HBCircularPresentation*)objc_getAssociatedObject(dock,&CircleKey)).ring requestEditing];}
UIView*HBCircularTestView(UIView*dock){return ((HBCircularPresentation*)objc_getAssociatedObject(dock,&CircleKey)).ring;}
void HBCircularTestRotate(UIView*dock,CGFloat delta,BOOL finish,BOOL cancel){HBCircularView*v=(id)HBCircularTestView(dock);if(!v.rotating){v.startPhase=v.phase;v.rotating=YES;}[v rotateBy:delta];if(finish||cancel)[v finishRotation:cancel];}
#endif


