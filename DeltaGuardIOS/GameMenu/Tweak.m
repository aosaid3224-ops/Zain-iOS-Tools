#import <UIKit/UIKit.h>
#import <mach/mach.h>
#include <stdlib.h>
#import <objc/runtime.h>

/* نفس تخطيط CAFrameRateRange (iOS 15+) */
typedef struct { float minimum; float maximum; float preferred; } DGFrameRateRange;

@class DGMenu;

@interface DGFloatButton : UIButton
@property(nonatomic,getter=isDGMinimized) BOOL dgMinimized;
@end

static UIWindow *DGWindow;
static DGFloatButton *DGButton;
static UIView *DGPanel;
static UILabel *DGStatsLabel;
static UIButton *DG90Button;
static NSDate *DGSessionStart;
static CADisplayLink *DGLink;
static NSUInteger DGFrameCount;
static NSUInteger DGFPS;
static NSTimer *DGStatsTimer;
static BOOL DG90Enabled=NO;
static NSInteger DGRealMaxFPS=60; /* قدرة الشاشة الحقيقية (تُلتقط قبل السوازل) */
static NSString *const DG90Key=@"DG90Enabled";
static NSString *const DGFloatPosKey=@"DGFloatPos";
static NSString *const DGPanelPosKey=@"DGPanelPos";
static BOOL DGStarted=NO;
static dispatch_block_t DGIdleBlock;

static NSString *DGMemoryString(void){
    task_vm_info_data_t info; mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    if(task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count)==KERN_SUCCESS){
#if defined(TASK_VM_INFO_REV3)
        return [NSString stringWithFormat:@"%.1f MB",info.phys_footprint/1048576.0];
#else
        return [NSString stringWithFormat:@"%.1f MB",(info.internal+info.compressed/2)/1048576.0]; /* إصلاح: القسمة على البايت كامل */
#endif
    }
    return @"غير متاح";
}

/* هل الشاشة تقدر تعرض أكثر من 60 فعلياً؟ */
static BOOL DGCanUnlock(void){ return DGRealMaxFPS>=90; }

// ===== 90 FPS: السوازل — تشتغل فقط إذا العتاد يقدر يعرض =====

static void DGSwizzle(Class c, SEL a, SEL b){
    if(!c) return;
    Method m1=class_getInstanceMethod(c,a), m2=class_getInstanceMethod(c,b);
    if(m1 && m2) method_exchangeImplementations(m1,m2);
}

@interface UIScreen (DG90)
@end
@implementation UIScreen (DG90)
- (NSInteger)dg_maximumFramesPerSecond{
    if(DG90Enabled && DGCanUnlock()){
        NSInteger real=[self dg_maximumFramesPerSecond];
        return real<120?120:real;
    }
    return [self dg_maximumFramesPerSecond];
}
@end

@interface CADisplayLink (DG90)
@end
@implementation CADisplayLink (DG90)
- (void)dg_setPreferredFramesPerSecond:(NSInteger)fps{
    if(DG90Enabled && DGCanUnlock() && fps<90) fps=90;
    [self dg_setPreferredFramesPerSecond:fps];
}
- (NSInteger)dg_preferredFramesPerSecond{
    NSInteger fps=[self dg_preferredFramesPerSecond];
    if(DG90Enabled && DGCanUnlock() && fps<90) return 90;
    return fps;
}
- (void)dg_setPreferredFrameRateRange:(DGFrameRateRange)r{
    if(DG90Enabled && DGCanUnlock()){
        if(r.maximum<90) r.maximum=90;
        if(r.preferred<90) r.preferred=90;
        if(r.minimum>r.maximum) r.minimum=r.maximum;
    }
    [self dg_setPreferredFrameRateRange:r];
}
- (DGFrameRateRange)dg_preferredFrameRateRange{
    DGFrameRateRange r=[self dg_preferredFrameRateRange];
    if(DG90Enabled && DGCanUnlock()){
        if(r.maximum<90) r.maximum=90;
        if(r.preferred<90) r.preferred=90;
    }
    return r;
}
@end

static void DGSwizzleFPS(void){
    static dispatch_once_t once;
    dispatch_once(&once,^{
        DGSwizzle(NSClassFromString(@"UIScreen"), @selector(maximumFramesPerSecond), @selector(dg_maximumFramesPerSecond));
        Class link=NSClassFromString(@"CADisplayLink");
        DGSwizzle(link, @selector(setPreferredFramesPerSecond:), @selector(dg_setPreferredFramesPerSecond:));
        DGSwizzle(link, @selector(preferredFramesPerSecond), @selector(dg_preferredFramesPerSecond));
        DGSwizzle(link, @selector(setPreferredFrameRateRange:), @selector(dg_setPreferredFrameRateRange:));
        DGSwizzle(link, @selector(preferredFrameRateRange), @selector(dg_preferredFrameRateRange));
    });
}

// ===== نافذة Pass-Through: اللمس يمر للعبة إلا على عناصرنا =====

@interface DGPassThroughWindow : UIWindow @end
@implementation DGPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event{
    UIView *hit=[super hitTest:point withEvent:event];
    if(!hit || hit==self || hit==self.rootViewController.view) return nil;
    return hit;
}
@end

// ===== سلوك الزر العائم: شفافية خمول، التصاق بالحواف، حفظ الموضع =====

static void DGCancelIdle(void){
    if(DGIdleBlock){ dispatch_block_cancel(DGIdleBlock); DGIdleBlock=nil; }
}

static void DGScheduleIdle(void){
    DGCancelIdle();
    DGIdleBlock=dispatch_block_create(0,^{
        DGFloatButton *b=DGButton;
        if(b && !b.isHighlighted && !b.isDGMinimized){
            [UIView animateWithDuration:0.4 animations:^{ b.alpha=0.55; }];
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),dispatch_get_main_queue(),DGIdleBlock);
}

static void DGSnapButton(DGFloatButton *btn){
    if(!btn) return;
    CGRect sb=[UIScreen mainScreen].bounds;
    CGFloat half=btn.bounds.size.width/2;
    CGFloat x=(btn.center.x<sb.size.width/2)?(10+half):(sb.size.width-10-half);
    CGFloat y=MIN(MAX(btn.center.y,70),sb.size.height-90);
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.4 options:UIViewAnimationOptionCurveEaseOut animations:^{
        btn.center=CGPointMake(x,y);
    } completion:nil];
}

static void DGSaveButtonPos(void){
    if(!DGButton) return;
    [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGPoint(DGButton.frame.origin) forKey:DGFloatPosKey];
}

static void DGRestoreButtonPos(CGRect *frame){
    NSString *s=[[NSUserDefaults standardUserDefaults] stringForKey:DGFloatPosKey];
    if(s){
        CGPoint o=CGPointFromString(s);
        if(o.x>=0 && o.y>=0) *frame=(CGRect){o,frame->size};
    }
}

@implementation DGFloatButton

/* سحب بالضغط المطوّل: الضغط العادي يبقى للفتح، والسحب ما يتعارض مع النقرة */
- (void)dgLongPress:(UILongPressGestureRecognizer *)g{
    CGPoint p=[g locationInView:DGWindow];
    if(g.state==UIGestureRecognizerStateBegan){
        DGCancelIdle();
        [UIView animateWithDuration:0.1 animations:^{ self.alpha=1.0; self.transform=CGAffineTransformMakeScale(1.08,1.08); }];
    } else if(g.state==UIGestureRecognizerStateChanged){
        self.center=CGPointMake(p.x,p.y-32); /* يطفو فوق الإصبع */
    } else if(g.state==UIGestureRecognizerStateEnded || g.state==UIGestureRecognizerStateCancelled){
        [UIView animateWithDuration:0.15 animations:^{ self.transform=CGAffineTransformIdentity; }];
        DGSnapButton(self);
        DGSaveButtonPos();
        DGScheduleIdle();
    }
}

/* نقرة مزدوجة: تصغير إلى نقطة صغيرة حتى لا تعيق التجارب */
- (void)dgDoubleTap:(UITapGestureRecognizer *)g{
    (void)g;
    self.dgMinimized=!self.dgMinimized;
    CGFloat size=self.dgMinimized?30:52;
    DGCancelIdle();
    [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.4 options:0 animations:^{
        self.frame=CGRectMake(self.center.x-size/2,self.center.y-size/2,size,size);
        self.layer.cornerRadius=size/2;
        self.titleLabel.font=[UIFont systemFontOfSize:self.dgMinimized?13:22];
        self.alpha=1.0;
    } completion:^(BOOL f){ (void)f; DGScheduleIdle(); }];
    if(self.dgMinimized && DGPanel && !DGPanel.isHidden) [DGMenu hidePanel];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [super touchesBegan:touches withEvent:event];
    DGCancelIdle();
    self.alpha=1.0;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [super touchesEnded:touches withEvent:event];
    DGScheduleIdle();
}
@end

@interface DGMenu : NSObject
+ (void)install;
+ (void)start;
@end

@implementation DGMenu

+ (void)start{
    if(DGStarted) return;
    DGStarted=YES;
    DGRealMaxFPS=[UIScreen mainScreen].maximumFramesPerSecond;
    DG90Enabled=[[NSUserDefaults standardUserDefaults] boolForKey:DG90Key];
    DGSwizzleFPS();
    [self install];
}

+ (void)install{
    if(DGWindow) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [DGMenu build]; });
}

+ (void)build{
    if(DGWindow) return;
    DGSessionStart=[NSDate date];
    DGWindow=[[DGPassThroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    DGWindow.windowLevel=UIWindowLevelStatusBar+100;
    DGWindow.rootViewController=[UIViewController new];
    DGWindow.rootViewController.view.backgroundColor=[UIColor clearColor];
    DGWindow.hidden=NO;
    UIView *root=DGWindow.rootViewController.view;

    CGRect btnFrame=CGRectMake(20,140,52,52);
    DGRestoreButtonPos(&btnFrame);
    DGButton=[DGFloatButton buttonWithType:UIButtonTypeCustom];
    DGButton.frame=btnFrame;
    DGButton.layer.cornerRadius=26;
    DGButton.backgroundColor=[UIColor colorWithWhite:0.05 alpha:0.9];
    DGButton.layer.borderColor=[UIColor colorWithRed:0.2 green:0.85 blue:1 alpha:1].CGColor;
    DGButton.layer.borderWidth=2;
    [DGButton setTitle:@"🛡" forState:UIControlStateNormal];
    DGButton.titleLabel.font=[UIFont systemFontOfSize:22];
    [DGButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:DGButton action:@selector(dgLongPress:)];
    hold.minimumPressDuration=0.3;
    [DGButton addGestureRecognizer:hold];
    UITapGestureRecognizer *dt=[[UITapGestureRecognizer alloc] initWithTarget:DGButton action:@selector(dgDoubleTap:)];
    dt.numberOfTapsRequired=2;
    [DGButton addGestureRecognizer:dt];
    [root addSubview:DGButton];
    DGScheduleIdle();

    CGRect panelFrame=CGRectMake(60,200,260,222);
    NSString *ps=[[NSUserDefaults standardUserDefaults] stringForKey:DGPanelPosKey];
    if(ps){
        CGPoint o=CGPointFromString(ps);
        if(o.x>=0 && o.y>=0) panelFrame=(CGRect){o,panelFrame.size};
    }
    DGPanel=[[UIView alloc] initWithFrame:panelFrame];
    DGPanel.backgroundColor=[UIColor colorWithWhite:0.08 alpha:0.92];
    DGPanel.layer.cornerRadius=14;
    DGPanel.layer.borderColor=[UIColor colorWithRed:0.2 green:0.85 blue:1 alpha:1].CGColor;
    DGPanel.layer.borderWidth=1.5;
    DGPanel.hidden=YES;

    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(30,10,200,24)];
    title.text=@"🛡 حارس دلتا — أداة العملية";
    title.textColor=[UIColor whiteColor]; title.textAlignment=NSTextAlignmentCenter; title.font=[UIFont boldSystemFontOfSize:14];
    title.userInteractionEnabled=YES;
    UIPanGestureRecognizer *panelPan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dgPanelPan:)];
    [title addGestureRecognizer:panelPan];
    [DGPanel addSubview:title];

    UIButton *closeB=[UIButton buttonWithType:UIButtonTypeSystem];
    closeB.frame=CGRectMake(228,6,26,28);
    [closeB setTitle:@"✕" forState:UIControlStateNormal];
    closeB.titleLabel.font=[UIFont boldSystemFontOfSize:14];
    closeB.tintColor=[UIColor lightGrayColor];
    [closeB addTarget:self action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];
    [DGPanel addSubview:closeB];

    DGStatsLabel=[[UILabel alloc] initWithFrame:CGRectMake(10,40,240,60)];
    DGStatsLabel.textColor=[UIColor colorWithRed:0.4 green:1 blue:0.6 alpha:1];
    DGStatsLabel.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    DGStatsLabel.numberOfLines=3;
    DGStatsLabel.textAlignment=NSTextAlignmentCenter;
    [DGPanel addSubview:DGStatsLabel];

    UIButton *hide=[UIButton buttonWithType:UIButtonTypeSystem];
    hide.frame=CGRectMake(20,104,100,34);
    [hide setTitle:@"إخفاء اللوحة" forState:UIControlStateNormal];
    [hide addTarget:self action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];
    [DGPanel addSubview:hide];

    UIButton *quit=[UIButton buttonWithType:UIButtonTypeSystem];
    quit.frame=CGRectMake(140,104,100,34);
    [quit setTitle:@"إنهاء اللعبة" forState:UIControlStateNormal];
    quit.tintColor=[UIColor systemRedColor];
    [quit addTarget:self action:@selector(quitGame) forControlEvents:UIControlEventTouchUpInside];
    [DGPanel addSubview:quit];

    DG90Button=[UIButton buttonWithType:UIButtonTypeSystem];
    DG90Button.frame=CGRectMake(20,144,220,34);
    [DG90Button addTarget:self action:@selector(toggle90) forControlEvents:UIControlEventTouchUpInside];
    [self update90Button];
    [DGPanel addSubview:DG90Button];

    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(10,186,240,30)];
    hint.text=@"اضغط مطولاً للسحب • نقرة للفتح • نقرتان للتصغير";
    hint.textColor=[UIColor lightGrayColor]; hint.textAlignment=NSTextAlignmentCenter; hint.font=[UIFont systemFontOfSize:10];
    [DGPanel addSubview:hint];

    UILabel *ver=[[UILabel alloc] initWithFrame:CGRectMake(196,200,54,16)];
    ver.text=@"v0.4.0";
    ver.textColor=[UIColor lightGrayColor]; ver.textAlignment=NSTextAlignmentRight; ver.font=[UIFont systemFontOfSize:9]; ver.alpha=0.6;
    [DGPanel addSubview:ver];

    [root addSubview:DGPanel];
    DGLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
    [DGLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    DGStatsTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateStats) userInfo:nil repeats:YES];
    [DGStatsLabel setText:[self statsText]];
}

/* سحب اللوحة من شريط العنوان مع التثبيت داخل الشاشة والحفظ */
+ (void)dgPanelPan:(UIPanGestureRecognizer *)g{
    CGPoint t=[g translationInView:DGWindow];
    static CGPoint start;
    if(g.state==UIGestureRecognizerStateBegan) start=DGPanel.center;
    DGPanel.center=CGPointMake(start.x+t.x,start.y+t.y);
    [g setTranslation:CGPointZero inView:DGWindow];
    if(g.state==UIGestureRecognizerStateEnded || g.state==UIGestureRecognizerStateCancelled){
        CGRect b=[UIScreen mainScreen].bounds;
        CGFloat pw=DGPanel.bounds.size.width, ph=DGPanel.bounds.size.height;
        CGFloat cx=MIN(MAX(DGPanel.center.x,pw/2),b.size.width-pw/2);
        CGFloat cy=MIN(MAX(DGPanel.center.y,ph/2+40),b.size.height-ph/2-40);
        [UIView animateWithDuration:0.25 animations:^{ DGPanel.center=CGPointMake(cx,cy); }];
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGPoint(DGPanel.frame.origin) forKey:DGPanelPosKey];
    }
}

+ (void)toggle90{
    DG90Enabled=!DG90Enabled;
    [[NSUserDefaults standardUserDefaults] setBool:DG90Enabled forKey:DG90Key];
    [self update90Button];
    [DGStatsLabel setText:[self statsText]];
}

+ (void)update90Button{
    NSString *title;
    UIColor *color=[UIColor labelColor];
    if(!DG90Enabled) title=@"⚡ تفعيل 90 FPS";
    else if(DGCanUnlock()){ title=@"⚡ 90 FPS: مفعّل ✅"; color=[UIColor systemGreenColor]; }
    else { title=@"⚡ 90 FPS: غير متاح — شاشتك 60Hz"; color=[UIColor systemYellowColor]; }
    [DG90Button setTitle:title forState:UIControlStateNormal];
    DG90Button.tintColor=color;
}

+ (void)frame:(CADisplayLink *)l{ DGFrameCount++; }
+ (void)updateStats{ DGFPS=DGFrameCount; DGFrameCount=0; [DGStatsLabel setText:[self statsText]]; }

+ (NSString *)statsText{
    NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
    NSString *mode;
    if(!DG90Enabled) mode=@"متوقف";
    else if(DGCanUnlock()) mode=@"مفعّل ✅";
    else mode=@"مفعّل — بلا فائدة (60Hz)";
    return [NSString stringWithFormat:@"إطارات الشاشة: %ld Hz | الذاكرة: %@\nمدة التشغيل: %02d:%02d | 90FPS: %@",
        (long)DGRealMaxFPS,DGMemoryString(),(int)(up/60),((int)up)%60,mode];
}

+ (void)togglePanel{
    if(DGPanel.isHidden){
        DGPanel.hidden=NO;
        DGPanel.alpha=0;
        DGPanel.transform=CGAffineTransformMakeScale(0.85,0.85);
        [UIView animateWithDuration:0.2 animations:^{ DGPanel.alpha=1; DGPanel.transform=CGAffineTransformIdentity; }];
    } else {
        [UIView animateWithDuration:0.15 animations:^{ DGPanel.alpha=0; DGPanel.transform=CGAffineTransformMakeScale(0.9,0.9); }
                         completion:^(BOOL f){ DGPanel.hidden=YES; DGPanel.transform=CGAffineTransformIdentity; DGPanel.alpha=1; }];
    }
}
+ (void)hidePanel{ DGPanel.hidden=YES; }
+ (void)quitGame{
    DGStatsLabel.text=@"جاري إنهاء اللعبة…";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ exit(0); });
}
@end

__attribute__((constructor)) static void DGEntry(void){
    @autoreleasepool{
        /* لا نستدعي UIKit من constructor: UIScreen غير مهيأ بعد وقد يسبب deadlock في iOS 18. */
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                               object:nil
                                                                queue:[NSOperationQueue mainQueue]
                                                           usingBlock:^(NSNotification *note){
                (void)note;
                [DGMenu start];
            }];
            UIApplication *app=[UIApplication sharedApplication];
            if(app.applicationState==UIApplicationStateActive || app.applicationState==UIApplicationStateInactive){
                [DGMenu start];
            }
        });
    }
}
