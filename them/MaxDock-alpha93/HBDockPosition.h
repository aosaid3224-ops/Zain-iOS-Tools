#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
CGFloat HBDockClampedOffset(CGFloat requested,CGRect content,CGRect screen,CGFloat topInset);
void HBUpdateDockPosition(UIView *dock,CGRect content,CGFloat requested,BOOL allowDrag,BOOL editing,void(^save)(CGFloat));
CGFloat HBDockAppliedOffset(UIView *dock);
void HBPositionSetNativeCenter(UIView*dock,CGPoint center,void(^original)(CGPoint));
void HBPositionSetNativeFrame(UIView*dock,CGRect frame,void(^original)(CGRect));
#ifdef HB_POSITION_TEST
void HBPositionTestPan(UIView*dock,UIGestureRecognizerState state,CGFloat y);
#endif
#ifdef __cplusplus
}
#endif
