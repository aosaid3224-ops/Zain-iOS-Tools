#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
NSArray<NSDictionary*> *HBCircularGeometry(NSUInteger count,CGFloat phase,CGSize bounds);
void HBUpdateCircularDock(UIView*dock,UIView*surface,CGRect anchor,NSArray*rows,CGFloat phase,BOOL active,void(^tap)(NSString*),void(^save)(CGFloat));
NSArray<NSDictionary*> *HBCircularGeometryScaled(NSUInteger count,CGFloat phase,CGSize bounds,CGFloat scale);
void HBCircularSetIconScale(UIView*dock,CGFloat scale);
void HBCircularSetEditRequest(UIView*dock,void(^request)(void));
void HBCircularSetSpeed(UIView*dock,CGFloat speed);
BOOL HBCircularDockActive(UIView*dock);
CGFloat HBCircularNativeAlpha(UIView*dock);
void HBCircularSetNativeAlpha(UIView*dock,CGFloat alpha,void(^original)(CGFloat));
#ifdef HB_CIRCULAR_TEST
void HBCircularTestRequestEditing(UIView*dock);
UIView *HBCircularTestView(UIView*dock);
void HBCircularTestRotate(UIView*dock,CGFloat delta,BOOL finish,BOOL cancel);
#endif
#ifdef __cplusplus
}
#endif
