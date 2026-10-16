#import <UIKit/UIKit.h>
#import <mach/mach.h>
#include <stdlib.h>

@interface DGFloatButton : UIButton @end

static UIWindow *DGWindow;
static UIView *DGPanel;
static UILabel *DGStatsLabel;
static NSDate *DGSessionStart;
static CADisplayLink *DGLink;
static NSUInteger DGFrameCount;
static NSUInteger DGFPS;
static NSTimer *DGStatsTimer;

static NSString *DGMemoryString(void){
    task_vm_info_data_t info; mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    if(task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count)==KERN_SUCCESS){
#if defined(TASK_VM_INFO_REV3)
        return [NSString stringWithFormat:@"%.1f MB",info.phys_footprint/1048576.0];
#else
        return [NSString stringWithFormat:@"%.1f MB",info.internal+info.compressed/2.0/1048576.0];
#endif
    }
    return @"غير متاح";
}

@implementation DGFloatButton
- (void)dgPan:(UIPanGestureRecognizer *)g{
    CGPoint t=[g translationInView:DGWindow];
    static CGPoint start;
    if(g.state==UIGestureRecognizerStateBegan) start=self.center;
    self.center=CGPointMake(start.x+t.x,start.y+t.y);
    [g setTranslation:CGPointZero inView:DGWindow];
}
@end

@interface DGMenu : NSObject
+ (void)install;
@end

@implementation DGMenu
+ (void)install{
    if(DGWindow) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [DGMenu build]; });
}
+ (void)build{
    if(DGWindow) return;
    DGSessionStart=[NSDate date];
    DGWindow=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    DGWindow.windowLevel=UIWindowLevelStatusBar+100;
    DGWindow.hidden=NO;
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
    [DGWindow addSubview:btn];
    DGPanel=[[UIView alloc] initWithFrame:CGRectMake(60,220,260,185)];
    DGPanel.backgroundColor=[UIColor colorWithWhite:0.08 alpha:0.92];
    DGPanel.layer.cornerRadius=14;
    DGPanel.layer.borderColor=[UIColor colorWithRed:0.2 green:0.85 blue:1 alpha:1].CGColor;
    DGPanel.layer.borderWidth=1.5;
    DGPanel.hidden=YES;
    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(0,10,260,24)];
    title.text=@"🛡 حارس دلتا — أداة العملية";
    title.textColor=[UIColor whiteColor]; title.textAlignment=NSTextAlignmentCenter; title.font=[UIFont boldSystemFontOfSize:14];
    [DGPanel addSubview:title];
    DGStatsLabel=[[UILabel alloc] initWithFrame:CGRectMake(10,40,240,60)];
    DGStatsLabel.textColor=[UIColor colorWithRed:0.4 green:1 blue:0.6 alpha:1];
    DGStatsLabel.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    DGStatsLabel.numberOfLines=3;
    [DGPanel addSubview:DGStatsLabel];
    UIButton *hide=[UIButton buttonWithType:UIButtonTypeSystem];
    hide.frame=CGRectMake(20,110,100,34);
    [hide setTitle:@"إخفاء اللوحة" forState:UIControlStateNormal];
    [hide addTarget:self action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];
    [DGPanel addSubview:hide];
    UIButton *quit=[UIButton buttonWithType:UIButtonTypeSystem];
    quit.frame=CGRectMake(140,110,100,34);
    [quit setTitle:@"إنهاء اللعبة" forState:UIControlStateNormal];
    quit.tintColor=[UIColor systemRedColor];
    [quit addTarget:self action:@selector(quitGame) forControlEvents:UIControlEventTouchUpInside];
    [DGPanel addSubview:quit];
    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(10,148,240,30)];
    hint.text=@"اسحب الأيقونة لتحريكها — اضغط عليها للفتح";
    hint.textColor=[UIColor lightGrayColor]; hint.textAlignment=NSTextAlignmentCenter; hint.font=[UIFont systemFontOfSize:10];
    [DGPanel addSubview:hint];
    [DGWindow addSubview:DGPanel];
    DGLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
    [DGLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    DGStatsTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateStats) userInfo:nil repeats:YES];
    [DGStatsLabel setText:[self statsText]];
}
+ (void)frame:(CADisplayLink *)l{ DGFrameCount++; }
+ (void)updateStats{ DGFPS=DGFrameCount; DGFrameCount=0; [DGStatsLabel setText:[self statsText]]; }
+ (NSString *)statsText{
    NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
    return [NSString stringWithFormat:@"FPS: %lu | الذاكرة: %@\nمدة التشغيل: %02d:%02d",(unsigned long)DGFPS,DGMemoryString(),(int)(up/60),((int)up)%60];
}
+ (void)togglePanel{ DGPanel.hidden=!DGPanel.isHidden; }
+ (void)hidePanel{ DGPanel.hidden=YES; }
+ (void)quitGame{
    DGStatsLabel.text=@"جاري إنهاء اللعبة…";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ exit(0); });
}
@end

__attribute__((constructor)) static void DGEntry(void){
    @autoreleasepool{ [DGMenu install]; }
}
