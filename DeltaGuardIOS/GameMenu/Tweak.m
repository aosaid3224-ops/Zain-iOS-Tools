#import <UIKit/UIKit.h>
#import <mach/mach.h>
#include <stdlib.h>
#import <objc/runtime.h>

/* نفس تخطيط CAFrameRateRange (iOS 15+) */
typedef struct { float minimum; float maximum; float preferred; } DGFrameRateRange;

@interface DGFloatButton : UIButton @end
@interface DGMockESPView : UIView @end

static UIWindow *DGWindow;
static UIView *DGPanel;
static UILabel *DGStatsLabel;
static UIButton *DG90Button;
static UIButton *DGMockButton;
static DGMockESPView *DGMockOverlay;
static NSDate *DGSessionStart;
static CADisplayLink *DGLink;
static NSUInteger DGFrameCount;
static NSUInteger DGFPS;
static NSTimer *DGStatsTimer;
static BOOL DG90Enabled=NO;
static BOOL DGMockEnabled=NO; /* معاينة تخطيط اصطناعية فقط، لا تتصل ببيانات اللعبة */
static NSInteger DGRealMaxFPS=60; /* قدرة الشاشة الحقيقية (تُلتقط قبل السوازل) */
static NSString *const DG90Key=@"DG90Enabled";
static BOOL DGStarted=NO;

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

@implementation DGFloatButton
- (void)dgPan:(UIPanGestureRecognizer *)g{
    CGPoint t=[g translationInView:DGWindow];
    static CGPoint start;
    if(g.state==UIGestureRecognizerStateBegan) start=self.center;
    self.center=CGPointMake(start.x+t.x,start.y+t.y);
    [g setTranslation:CGPointZero inView:DGWindow];
}
@end

/* طبقة اختبار مستقلة: كل المواقع والأسماء والمسافات أدناه بيانات ثابتة اصطناعية. */
@implementation DGMockESPView
- (instancetype)initWithFrame:(CGRect)frame{
    self=[super initWithFrame:frame];
    if(self){
        self.backgroundColor=[UIColor clearColor];
        self.opaque=NO;
        self.userInteractionEnabled=NO;
        self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        self.contentMode=UIViewContentModeRedraw;
    }
    return self;
}
- (void)drawRect:(CGRect)rect{
    CGFloat w=CGRectGetWidth(self.bounds), h=CGRectGetHeight(self.bounds);
    if(w<100 || h<100) return;

    NSDictionary *watermark=@{NSFontAttributeName:[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightBold],
                              NSForegroundColorAttributeName:[UIColor colorWithWhite:1 alpha:.92]};
    [@"معاينة اصطناعية — لا تقرأ بيانات اللعبة" drawInRect:CGRectMake(8,34,MAX(80,w-16),18) withAttributes:watermark];

    NSArray *samples=@[
        @{ @"name":@"SIM-01", @"meters":@"18", @"x":@0.29, @"y":@0.36, @"hp":@0.86 },
        @{ @"name":@"SIM-02", @"meters":@"37", @"x":@0.50, @"y":@0.43, @"hp":@0.54 },
        @{ @"name":@"SIM-03", @"meters":@"52", @"x":@0.70, @"y":@0.34, @"hp":@0.28 }
    ];
    NSArray *colors=@[[UIColor colorWithRed:.15 green:.92 blue:1 alpha:.96],
                      [UIColor colorWithRed:.45 green:1 blue:.52 alpha:.96],
                      [UIColor colorWithRed:1 green:.76 blue:.22 alpha:.96]];
    CGFloat boxW=MIN(w*.18,MAX(46.0,h*.12));
    CGFloat boxH=MIN(h*.30,MAX(90.0,h*.18));
    for(NSUInteger i=0;i<samples.count;i++){
        NSDictionary *sample=samples[i];
        CGFloat cx=[sample[@"x"] floatValue]*w, cy=[sample[@"y"] floatValue]*h;
        CGRect box=CGRectMake(cx-boxW*.5,cy-boxH*.5,boxW,boxH);
        box.origin.x=MIN(MAX(8.0,box.origin.x),MAX(8.0,w-boxW-8.0));
        box.origin.y=MIN(MAX(32.0,box.origin.y),MAX(32.0,h-boxH-8.0));
        UIColor *color=colors[i];
        UIBezierPath *outline=[UIBezierPath bezierPathWithRect:box];
        outline.lineWidth=2.0;
        [color setStroke];
        [outline stroke];

        NSString *caption=[NSString stringWithFormat:@"%@ · %@ m",sample[@"name"],sample[@"meters"]];
        NSDictionary *captionStyle=@{NSFontAttributeName:[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightBold],
                                     NSForegroundColorAttributeName:[UIColor whiteColor]};
        CGRect captionRect=CGRectMake(MAX(4.0,CGRectGetMinX(box)-15.0),CGRectGetMinY(box)-20.0,boxW+30.0,17.0);
        UIBezierPath *captionBG=[UIBezierPath bezierPathWithRoundedRect:captionRect cornerRadius:4.0];
        [[UIColor colorWithWhite:0 alpha:.78] setFill];
        [captionBG fill];
        [caption drawInRect:CGRectInset(captionRect,3,1) withAttributes:captionStyle];

        CGFloat health=[sample[@"hp"] floatValue];
        CGRect healthBG=CGRectMake(CGRectGetMaxX(box)+4.0,CGRectGetMinY(box),4.0,CGRectGetHeight(box));
        [[UIColor colorWithWhite:1 alpha:.30] setFill];
        [[UIBezierPath bezierPathWithRect:healthBG] fill];
        CGRect healthFG=CGRectMake(healthBG.origin.x,CGRectGetMaxY(healthBG)-healthBG.size.height*health,
                                   healthBG.size.width,healthBG.size.height*health);
        UIColor *healthColor=health>.5?[UIColor colorWithRed:.25 green:1 blue:.48 alpha:.96]:[UIColor colorWithRed:1 green:.36 blue:.24 alpha:.96];
        [healthColor setFill];
        [[UIBezierPath bezierPathWithRect:healthFG] fill];
    }

    CGFloat radarSize=MIN(112.0,MIN(w,h)*.30);
    CGRect radar=CGRectMake(MAX(8.0,w-radarSize-14.0),MAX(8.0,h-radarSize-14.0),radarSize,radarSize);
    UIBezierPath *radarBG=[UIBezierPath bezierPathWithRoundedRect:radar cornerRadius:9.0];
    [[UIColor colorWithWhite:0 alpha:.68] setFill];
    [radarBG fill];
    [[UIColor colorWithRed:.20 green:.88 blue:1 alpha:.90] setStroke];
    radarBG.lineWidth=1.3;
    [radarBG stroke];
    CGFloat cx=CGRectGetMidX(radar), cy=CGRectGetMidY(radar);
    UIBezierPath *axes=[UIBezierPath bezierPath];
    [axes moveToPoint:CGPointMake(cx,CGRectGetMinY(radar)+17)];
    [axes addLineToPoint:CGPointMake(cx,CGRectGetMaxY(radar)-7)];
    [axes moveToPoint:CGPointMake(CGRectGetMinX(radar)+7,cy+5)];
    [axes addLineToPoint:CGPointMake(CGRectGetMaxX(radar)-7,cy+5)];
    axes.lineWidth=.7;
    [[UIColor colorWithWhite:1 alpha:.42] setStroke];
    [axes stroke];
    NSDictionary *radarTitle=@{NSFontAttributeName:[UIFont monospacedSystemFontOfSize:8 weight:UIFontWeightBold],
                               NSForegroundColorAttributeName:[UIColor whiteColor]};
    [@"RADAR · SIM" drawInRect:CGRectMake(CGRectGetMinX(radar)+5,CGRectGetMinY(radar)+4,radarSize-10,12) withAttributes:radarTitle];
    NSArray *dots=@[@[@.34,@.38],@[@.68,@.47],@[@.58,@.72]];
    for(NSUInteger i=0;i<dots.count;i++){
        CGFloat dx=[dots[i][0] floatValue], dy=[dots[i][1] floatValue];
        CGPoint point=CGPointMake(CGRectGetMinX(radar)+dx*radarSize,CGRectGetMinY(radar)+dy*radarSize);
        UIBezierPath *dot=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(point.x-3.0,point.y-3.0,6.0,6.0)];
        [colors[i] setFill];
        [dot fill];
    }
    UIBezierPath *selfDot=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx-4.0,cy+1.0,8.0,8.0)];
    [[UIColor whiteColor] setFill];
    [selfDot fill];
}
@end

@interface DGMenu : NSObject
+ (void)install;
+ (void)start;
+ (void)toggleMock;
+ (void)updateMockButton;
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
    DGMockOverlay=[[DGMockESPView alloc] initWithFrame:root.bounds];
    DGMockOverlay.hidden=YES;
    [root addSubview:DGMockOverlay];
    DGFloatButton *btn=[DGFloatButton buttonWithType:UIButtonTypeCustom];
    btn.frame=CGRectMake(20,140,52,52);
    btn.layer.cornerRadius=26;
    btn.backgroundColor=[UIColor colorWithWhite:0.05 alpha:0.9];
    btn.layer.borderColor=[UIColor colorWithRed:0.2 green:0.85 blue:1 alpha:1].CGColor;
    btn.layer.borderWidth=2;
    [btn setTitle:@"🛡" forState:UIControlStateNormal];
    btn.titleLabel.font=[UIFont systemFontOfSize:22];
    [btn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:btn action:@selector(dgPan:)];
    [btn addGestureRecognizer:pan];
    [root addSubview:btn];

    CGFloat panelX=MIN(60.0,MAX(12.0,root.bounds.size.width-272.0));
    CGFloat panelY=MIN(200.0,MAX(12.0,root.bounds.size.height-282.0));
    DGPanel=[[UIView alloc] initWithFrame:CGRectMake(panelX,panelY,260,270)];
    DGPanel.backgroundColor=[UIColor colorWithWhite:0.08 alpha:0.92];
    DGPanel.layer.cornerRadius=14;
    DGPanel.layer.borderColor=[UIColor colorWithRed:0.2 green:0.85 blue:1 alpha:1].CGColor;
    DGPanel.layer.borderWidth=1.5;
    DGPanel.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleTopMargin;
    DGPanel.hidden=YES;

    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(0,10,260,24)];
    title.text=@"🛡 حارس دلتا — أداة العملية";
    title.textColor=[UIColor whiteColor]; title.textAlignment=NSTextAlignmentCenter; title.font=[UIFont boldSystemFontOfSize:14];
    [DGPanel addSubview:title];

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

    DGMockButton=[UIButton buttonWithType:UIButtonTypeSystem];
    DGMockButton.frame=CGRectMake(20,184,220,34);
    [DGMockButton addTarget:self action:@selector(toggleMock) forControlEvents:UIControlEventTouchUpInside];
    [self updateMockButton];
    [DGPanel addSubview:DGMockButton];

    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(10,224,240,30)];
    hint.text=@"المعاينة اصطناعية فقط — لا تقرأ بيانات اللعبة";
    hint.textColor=[UIColor lightGrayColor]; hint.textAlignment=NSTextAlignmentCenter; hint.font=[UIFont systemFontOfSize:10];
    [DGPanel addSubview:hint];

    [root addSubview:DGPanel];
    DGLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
    [DGLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    DGStatsTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateStats) userInfo:nil repeats:YES];
    [DGStatsLabel setText:[self statsText]];
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

+ (void)toggleMock{
    DGMockEnabled=!DGMockEnabled;
    DGMockOverlay.hidden=!DGMockEnabled;
    [DGMockOverlay setNeedsDisplay];
    [self updateMockButton];
}

+ (void)updateMockButton{
    if(!DGMockButton) return;
    NSString *title=DGMockEnabled?@"معاينة اصطناعية: تشغيل":@"معاينة اصطناعية: إيقاف";
    [DGMockButton setTitle:title forState:UIControlStateNormal];
    DGMockButton.tintColor=DGMockEnabled?[UIColor systemGreenColor]:[UIColor systemCyanColor];
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

+ (void)togglePanel{ DGPanel.hidden=!DGPanel.isHidden; }
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
