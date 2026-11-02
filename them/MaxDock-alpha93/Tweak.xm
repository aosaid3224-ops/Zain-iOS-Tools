#import "HBCircularDock.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>
#import <math.h>
#import <stdlib.h>
#import "HBIconColor.h"
#import "HBCompatibility.h"
#import "HBHookCompatibility.h"
#import "HBDockCapacity.h"
#import "HBDockPosition.h"

typedef struct SBIconCoordinate {
    NSInteger row;
    NSInteger col;
} SBIconCoordinate;

@interface SBDockView : UIView
- (void)setBackgroundAlpha:(double)alpha;
@end

@interface SBRootFolderView : UIView
@end

@interface SBHRootFolderView : UIView
@end

@interface SBDockIconListView : UIView
@end

@interface SBIconView : UIView
- (void)_updateIconImageViewAnimated:(BOOL)animated;
- (void)_handleTap;
- (void)_delegateTouchEnded:(BOOL)ended;
- (void)longPressTimerFired;
- (void)tapGestureDidChange:(UITapGestureRecognizer *)recognizer;
- (NSString *)applicationBundleIdentifier;
- (id)delegate;
@end

@interface SBIconListGridLayoutConfiguration : NSObject
- (void)setNumberOfPortraitColumns:(NSUInteger)value;
- (void)setNumberOfPortraitRows:(NSUInteger)value;
- (void)setNumberOfLandscapeColumns:(NSUInteger)value;
- (void)setNumberOfLandscapeRows:(NSUInteger)value;
@end

@interface SBIconListFlowExtendedLayout : NSObject
- (instancetype)initWithLayoutConfiguration:(SBIconListGridLayoutConfiguration *)configuration;
- (SBIconListGridLayoutConfiguration *)layoutConfiguration;
@end

@interface SBIconListView : UIView
- (SBIconListFlowExtendedLayout *)layout;
- (NSString *)iconLocation;
- (NSArray *)icons;
- (CGSize)iconSpacing;
- (UIEdgeInsets)additionalLayoutInsets;
- (BOOL)automaticallyAdjustsLayoutMetricsToFit;
- (CGPoint)centerForIcon:(id)icon;
- (CGPoint)centerForIcon:(id)icon metrics:(id)metrics;
- (CGPoint)centerForIconAtIndex:(NSUInteger)index;
- (CGPoint)centerForIconAtIndex:(NSUInteger)index metrics:(id)metrics;
- (NSUInteger)indexOfIcon:(id)icon;
- (CGPoint)originForIconAtCoordinate:(SBIconCoordinate)coordinate
                             metrics:(id)metrics;
- (CGPoint)originForIconAtCoordinate:(SBIconCoordinate)coordinate
                             metrics:(id)metrics
                             options:(NSUInteger)options;
- (NSUInteger)iconIndexForCoordinate:(SBIconCoordinate)coordinate
                              metrics:(id)metrics;
- (CGSize)alignmentIconViewSize;
@end

@interface SBHDefaultIconListLayoutProvider : NSObject
- (SBIconListFlowExtendedLayout *)layoutForIconLocation:(NSString *)iconLocation;
@end

@interface SBIconController : NSObject
+ (instancetype)sharedInstance;
- (id)iconManager;
- (void)iconHandleLongPress:(id)iconView;
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
+ (instancetype)sharedInstanceIfExists;
- (id)applicationWithBundleIdentifier:(NSString *)bundleIdentifier;
- (id)applicationForBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface SBApplication : NSObject
- (void)setRunning:(BOOL)running;
- (void)_setActivationState:(int)state;
- (void)_setInternalProcessState:(id)state;
- (int)activationState;
- (id)processState;
@end

typedef struct {
    CGSize size;
    CGFloat scale;
    CGFloat continuousCornerRadius;
} HBModernIconImageInfo;

static const void *HBPanGestureKey = &HBPanGestureKey;
static const void *HBMagnificationActiveKey = &HBMagnificationActiveKey;
static const void *HBIconSizeAppliedKey = &HBIconSizeAppliedKey;
static const void *HBIconSizeOriginalTransformKey =
    &HBIconSizeOriginalTransformKey;
static const void *HBIconSizeLastTransformKey = &HBIconSizeLastTransformKey;
static const void *HBIconSizeEffectiveScaleKey =
    &HBIconSizeEffectiveScaleKey;

static const void *HBVisualDockColumnsKey = &HBVisualDockColumnsKey;
static const void *HBVisualDockLayoutKey = &HBVisualDockLayoutKey;
static const void *HBVisualDockOriginalLayoutKey =
    &HBVisualDockOriginalLayoutKey;
static const void *HBLastDockSizeSignatureKey =
    &HBLastDockSizeSignatureKey;
static const void *HBDockLateDistributionScheduledKey =
    &HBDockLateDistributionScheduledKey;
static const void *HBLastDockBackgroundSignatureKey =
    &HBLastDockBackgroundSignatureKey;
static const void *HBLastNativeMaterialHiddenKey =
    &HBLastNativeMaterialHiddenKey;
static const void *HBLastNativeMaterialSubviewCountKey =
    &HBLastNativeMaterialSubviewCountKey;
static const void *HBOriginalDockBackgroundAlphaKey =
    &HBOriginalDockBackgroundAlphaKey;
static const void *HBSlimDockBackgroundViewKey =
    &HBSlimDockBackgroundViewKey;
static const void *HBSlimDockRestingFrameKey =
    &HBSlimDockRestingFrameKey;
static const void *HBNativeMaterialOriginalAlphaKey =
    &HBNativeMaterialOriginalAlphaKey;
static const void *HBNativeMaterialOriginalHiddenKey =
    &HBNativeMaterialOriginalHiddenKey;
static const void *HBNativeMaterialOriginalLayerOpacityKey =
    &HBNativeMaterialOriginalLayerOpacityKey;
static const void *HBDockOriginalBackgroundColorKey =
    &HBDockOriginalBackgroundColorKey;
static const void *HBSearchOriginalAlphaKey =
    &HBSearchOriginalAlphaKey;
static const void *HBSearchOriginalInteractionKey =
    &HBSearchOriginalInteractionKey;
static const void *HBRunningIndicatorKey = &HBRunningIndicatorKey;
static const void *HBAutoHideEdgeGestureKey = &HBAutoHideEdgeGestureKey;
static const void *HBAutoHideOriginalTransformKey = &HBAutoHideOriginalTransformKey;
static const void *HBAutoHideOriginalAlphaKey = &HBAutoHideOriginalAlphaKey;
static const void *HBDynamicRunningViewsKey = &HBDynamicRunningViewsKey;
static NSUInteger HBApplicationStateGeneration = 1;
static NSUInteger HBCachedRunningIconsGeneration = 0;
static NSArray *HBCachedRunningModelIcons = nil;
static NSUInteger HBDynamicRunningSequence = 0;
static NSUInteger HBApplicationRefreshScheduleGeneration = 0;
static NSUInteger HBDockCountRefreshScheduleGeneration = 0;
static NSMutableSet<NSString *> *HBUserPresentedApplicationIdentifiers = nil;

static NSArray<UIView *> *HBVisibleDockIconViews(UIView *dockView);
static UIView *HBOuterDockViewForView(UIView *view);
static NSHashTable<UIView *> *HBKnownDockHosts(void);
static void HBRefreshAllDockHosts(void);
static void HBScheduleDockCountRefresh(void);
static void HBUpdateDynamicRunningAppsForDock(UIView *dockView);
static void HBLaunchApplicationBundleIdentifier(NSString *bundleIdentifier);
static void HBUpdateSlimDockBackground(UIView *dockView, BOOL animated);
static CGFloat HBEffectiveDockIconScale(UIView *iconView);

static NSUserDefaults *HBPreferences(void) {
    static NSUserDefaults *preferences = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        preferences = [[NSUserDefaults alloc] initWithSuiteName:@"com.eswick.harbor16"];
    });
    return preferences;
}

static id HBPreferenceValue(NSString *key) {
    return [HBPreferences() objectForKey:key];
}

static BOOL HBBoolPreference(NSString *key, BOOL defaultValue) {
    id value = HBPreferenceValue(key);
    return value == nil ? defaultValue : [value boolValue];
}

static CGFloat HBFloatPreference(NSString *key, CGFloat defaultValue,
                                 CGFloat minimum, CGFloat maximum) {
    id value = HBPreferenceValue(key);
    CGFloat result = value == nil ? defaultValue : [value doubleValue];
    return MAX(minimum, MIN(result, maximum));
}

static BOOL HBEnabled(void) {
    long major=NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    return HBEngineEnabledForOS(major,HBBoolPreference(@"Enabled",HBDefaultEnabledForOS(major)),[HBPreferenceValue(@"RuntimeOptInMajor")integerValue]);
}

static BOOL HBCircularModeChosen(void){return [HBPreferenceValue(@"DockMode") isEqual:@"circular"];}
static BOOL HBExtraDockAppsEnabled(void) {
    return HBEnabled() && HBBoolPreference(@"ExtraDockApps", YES);
}

static BOOL HBLaunchOnReleaseEnabled(void) {
    return HBBoolPreference(@"LaunchOnRelease", YES);
}

static BOOL HBShowAppNameEnabled(void) {
    return HBBoolPreference(@"ShowAppName", YES);
}

static BOOL HBHapticFeedbackEnabled(void) {
    return HBBoolPreference(@"HapticFeedback", YES);
}

static BOOL HBSelectionGlowEnabled(void) {
    return HBBoolPreference(@"SelectionGlow", YES);
}

static BOOL HBHideDockBackgroundEnabled(void) {
    return HBEnabled() && HBBoolPreference(@"HideDockBackground", NO);
}

static BOOL HBSlimAdaptiveBackgroundEnabled(void) {
    return HBEnabled() && HBBoolPreference(@"SlimAdaptiveBackground", YES);
}

static BOOL HBHideHomeSearchEnabled(void) {
    return HBEnabled() && HBBoolPreference(@"HideHomeSearch", NO);
}

static BOOL HBRunningIndicatorsEnabled(void) {
    // MaxDock no longer exposes or renders the legacy green running dot.
    return NO;
}

static BOOL HBAutoHideDockEnabled(void) {
    return HBEnabled() && !HBCircularModeChosen() && HBBoolPreference(@"AutoHideDock", NO);
}

static BOOL HBLaunchBounceEnabled(void) {
    return HBEnabled() && HBBoolPreference(@"LaunchBounce", YES);
}

static BOOL HBBadgeBounceEnabled(void) {
    return HBEnabled() && HBBoolPreference(@"BadgeBounce", YES);
}

static BOOL HBDynamicRunningAppsEnabled(void) {
    // Temporary process-backed Dock icons were retired in alpha 67.
    return NO;
}

static NSUInteger HBDockCapacity(void) {
    id value = HBPreferenceValue(@"DockCapacity");
    NSInteger capacity = value == nil ? 12 : [value integerValue];
    return (NSUInteger)MAX(5, MIN(capacity, 100));
}

static CGFloat HBMaximumScale(void) {
    return HBFloatPreference(@"MaximumScale", 1.55, 1.1, 2.0);
}

static CGFloat HBIconSizeScale(void) {
    return HBFloatPreference(@"IconSizeScale", 1.0, 0.55, 1.25);
}

static void HBMigrateIconSizePreference(void) {
    NSUserDefaults *preferences = HBPreferences();
    NSInteger layoutVersion = [preferences integerForKey:@"LayoutEngineVersion"];
    if (layoutVersion >= 77) return;

    if (layoutVersion < 38) {
        // Alpha 38 establishes predictable first-install layout defaults.
        [preferences setDouble:1.0 forKey:@"IconSizeScale"];
        [preferences setInteger:12 forKey:@"DockCapacity"];
    }
    if (layoutVersion < 50) {
        // Alpha 49 permanently removes the live running-app folder and its
        // recent history after it caused SpringBoard stalls on A11 devices.
        [preferences removeObjectForKey:@"RecentBundleIDs"];
        [preferences setBool:NO forKey:@"RecentDockApps"];
    }
    if (layoutVersion < 52) {
        // Alpha 52 ships with a clean transparent Dock and live temporary
        // running icons enabled. Both remain user-configurable afterwards.
        [preferences setBool:YES forKey:@"HideDockBackground"];
        [preferences setBool:YES forKey:@"DynamicRunningApps"];
    }
    if (layoutVersion < 54) {
        // Alpha 54 replaces Apple's full-width Dock material with a thin pill
        // that follows the live icon envelope and macOS magnification wave.
        [preferences setBool:YES forKey:@"SlimAdaptiveBackground"];
        [preferences setBool:NO forKey:@"HideDockBackground"];
    }
    if (layoutVersion < 58) {
        // Earlier transparent/profile choices can leave the native Hide switch
        // enabled and prevent Harbor's replacement frost from being created at
        // all. Re-enable the requested adaptive background once for alpha 58;
        // subsequent user changes remain untouched at layout version 58.
        [preferences setBool:YES forKey:@"SlimAdaptiveBackground"];
        [preferences setBool:NO forKey:@"HideDockBackground"];
    }
    if (layoutVersion < 62) {
        // Alpha 62 replaces the private blur with an independent Harbor frost.
        // Select that material once and clear the all-backgrounds Hide switch;
        // native Apple materials are suppressed separately by the renderer.
        [preferences setBool:YES forKey:@"SlimAdaptiveBackground"];
        [preferences setBool:NO forKey:@"HideDockBackground"];
    }
    if (layoutVersion < 67) {
        // Remove the two retired features even when an older installation had
        // explicitly enabled them.
        [preferences setBool:NO forKey:@"DynamicRunningApps"];
        [preferences setBool:NO forKey:@"RunningIndicators"];
    }
    [preferences setInteger:77 forKey:@"LayoutEngineVersion"];
    [preferences synchronize];
}

static CGFloat HBIconInset(void) {
    return HBFloatPreference(@"IconInset", 15.0, 0.0, 80.0);
}

static CGFloat HBIconPaddingMultiplier(void) {
    return HBFloatPreference(@"IconPaddingMultiplier", 0.25, 0.0, 1.0);
}

static CGFloat HBInfluenceRadius(void) {
    return HBFloatPreference(@"EffectiveRange", 115.0, 30.0, 240.0);
}

static CGFloat HBLiftDistance(void) {
    return HBFloatPreference(@"EvasionDistance", 28.0, 0.0, 120.0);
}

static NSTimeInterval HBAnimationDuration(void) {
    return HBFloatPreference(@"AnimationDuration", 0.32, 0.1, 1.0);
}

static BOOL HBIsSpringBoardProcess(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}

static BOOL HBIconManagerIsEditingOrDragging(void) {
    Class controllerClass = NSClassFromString(@"SBIconController");
    if (controllerClass == Nil ||
        ![controllerClass respondsToSelector:@selector(sharedInstance)]) {
        return NO;
    }

    SBIconController *controller = [(id)controllerClass sharedInstance];
    if (controller == nil ||
        ![controller respondsToSelector:@selector(iconManager)]) {
        return NO;
    }

    id manager = [controller iconManager];
    if (manager == nil) return NO;
    @try {
        id editing = [manager valueForKey:@"editing"];
        if ([editing boolValue]) return YES;
    } @catch (__unused NSException *exception) {
    }
    @try {
        id grabbedIcon = [manager valueForKey:@"grabbedIcon"];
        if (grabbedIcon != nil) return YES;
    } @catch (__unused NSException *exception) {
    }
    return NO;
}

static BOOL HBIconManagerIsDraggingIcon(void) {
    Class controllerClass = NSClassFromString(@"SBIconController");
    if (controllerClass == Nil ||
        ![controllerClass respondsToSelector:@selector(sharedInstance)]) {
        return NO;
    }
    SBIconController *controller = [(id)controllerClass sharedInstance];
    if (controller == nil ||
        ![controller respondsToSelector:@selector(iconManager)]) {
        return NO;
    }
    id manager = [controller iconManager];
    if (manager == nil) return NO;
    @try {
        return [manager valueForKey:@"grabbedIcon"] != nil;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static BOOL HBIsDockLocation(id location) {
    if (![location isKindOfClass:NSString.class]) return NO;
    NSString *string = (NSString *)location;
    return [string isEqualToString:@"SBIconLocationDock"] ||
           [string isEqualToString:@"SBIconLocationFloatingDock"];
}

static BOOL HBIconViewIsInDock(UIView *iconView) {
    @try {
        id location = [iconView valueForKey:@"location"];
        if (HBIsDockLocation(location)) return YES;
        if ([location isKindOfClass:NSString.class] &&
            [(NSString *)location hasPrefix:@"SBIconLocationFloatingDock"]) {
            return YES;
        }
    } @catch (__unused NSException *exception) {
    }

    Class dockViewClass = NSClassFromString(@"SBDockView");
    Class dockListClass = NSClassFromString(@"SBDockIconListView");
    for (UIView *ancestor = iconView.superview;
         ancestor != nil;
         ancestor = ancestor.superview) {
        if ((dockViewClass != Nil && [ancestor isKindOfClass:dockViewClass]) ||
            (dockListClass != Nil && [ancestor isKindOfClass:dockListClass])) {
            return YES;
        }
    }
    return NO;
}

static NSValue *HBValueWithTransform3D(CATransform3D transform) {
    return [NSValue valueWithBytes:&transform objCType:@encode(CATransform3D)];
}

static BOOL HBGetAssociatedTransform3D(UIView *iconView, const void *key,
                                       CATransform3D *transform) {
    NSValue *value = objc_getAssociatedObject(iconView, key);
    if (![value isKindOfClass:NSValue.class]) return NO;
    [value getValue:transform size:sizeof(*transform)];
    return YES;
}

static BOOL HBTransform3DEqual(CATransform3D left, CATransform3D right) {
    const CGFloat *leftValues = (const CGFloat *)&left;
    const CGFloat *rightValues = (const CGFloat *)&right;
    for (NSUInteger index = 0; index < 16; index++) {
        if (fabs(leftValues[index] - rightValues[index]) > 0.0001) return NO;
    }
    return YES;
}

static UIView *HBIconImageView(UIView *iconView) {
    for (NSString *key in @[@"iconImageView", @"_iconImageView"]) {
        @try {
            id candidate = [iconView valueForKey:key];
            if ([candidate isKindOfClass:UIView.class]) return candidate;
        } @catch (__unused NSException *exception) {
        }
    }

    UIView *bestImageView = nil;
    CGFloat bestArea = 0.0;
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithArray:iconView.subviews];
    while (pending.count > 0) {
        UIView *candidate = pending.lastObject;
        [pending removeLastObject];
        if ([candidate isKindOfClass:UIImageView.class] &&
            !candidate.hidden && candidate.alpha > 0.01) {
            CGFloat area = CGRectGetWidth(candidate.bounds) *
                           CGRectGetHeight(candidate.bounds);
            if (area > bestArea) {
                bestArea = area;
                bestImageView = candidate;
            }
        }
        [pending addObjectsFromArray:candidate.subviews];
    }
    return bestImageView;
}

static CGFloat HBTargetIconExtent(UIView *dockView, NSUInteger count,
                                  BOOL horizontal) {
    if (dockView == nil || count == 0) return 0.0;
    CGFloat dockExtent = horizontal ? CGRectGetWidth(dockView.bounds)
                                    : CGRectGetHeight(dockView.bounds);
    CGFloat available = MAX(1.0, dockExtent - (2.0 * HBIconInset()));
    // 60 points is the normal phone icon size. For crowded Docks, reserve
    // eight percent of every slot as a guaranteed gap.
    return MIN(60.0, (available / (CGFloat)count) * 0.92);
}

static void HBClearDockIconSizeState(UIView *iconView) {
    objc_setAssociatedObject(iconView, HBIconSizeAppliedKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(iconView, HBIconSizeOriginalTransformKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(iconView, HBIconSizeLastTransformKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(iconView, HBIconSizeEffectiveScaleKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void HBSetSublayerTransformWithoutAnimation(UIView *iconView,
                                                   CATransform3D transform) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [iconView.layer removeAnimationForKey:@"sublayerTransform"];
    iconView.layer.sublayerTransform = transform;
    [CATransaction commit];
}

static void HBApplyDockIconSize(UIView *iconView) {
    if (iconView == nil) return;

    BOOL wasApplied =
        [objc_getAssociatedObject(iconView, HBIconSizeAppliedKey) boolValue];
    CATransform3D current = iconView.layer.sublayerTransform;
    CATransform3D original = CATransform3DIdentity;
    CATransform3D lastApplied = CATransform3DIdentity;
    BOOL hasOriginal = HBGetAssociatedTransform3D(
        iconView, HBIconSizeOriginalTransformKey, &original);
    BOOL hasLastApplied = HBGetAssociatedTransform3D(
        iconView, HBIconSizeLastTransformKey, &lastApplied);
    BOOL currentIsHarborTransform = wasApplied && hasLastApplied &&
        HBTransform3DEqual(current, lastApplied);

    BOOL shouldApply = HBEnabled() && HBIconViewIsInDock(iconView);
    // Every phone icon uses the same 60-point resting reference. Measuring an
    // icon image while SpringBoard reparents or animates it can return a
    // transient size and made individual icons alternate between large and
    // small. A deterministic reference gives every icon exactly one scale.
    CGFloat scale = HBIconSizeScale();
    if (shouldApply && HBExtraDockAppsEnabled()) {
        UIView *dockView = HBOuterDockViewForView(iconView);
        NSArray<UIView *> *visibleIcons = HBVisibleDockIconViews(dockView);
        NSUInteger targetCount = visibleIcons.count;
        BOOL horizontal = CGRectGetWidth(dockView.bounds) >=
                          CGRectGetHeight(dockView.bounds);
        CGFloat targetExtent = HBTargetIconExtent(
            dockView, MAX((NSUInteger)1, targetCount), horizontal);
        if (targetExtent > 0.0) {
            CGFloat geometryScale = targetExtent / 60.0;
            scale *= MAX(0.25, MIN(geometryScale, 4.0));
        }
    }
    BOOL wantsCustomSize = shouldApply && fabs(scale - 1.0) >= 0.001;
    if (!wantsCustomSize) {
        if (currentIsHarborTransform && hasOriginal) {
            HBSetSublayerTransformWithoutAnimation(iconView, original);
        }
        if (wasApplied) HBClearDockIconSizeState(iconView);
        if (shouldApply) {
            objc_setAssociatedObject(iconView, HBIconSizeEffectiveScaleKey,
                                     @1.0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    // Capture the native base only once. Temporary SpringBoard transforms must
    // never replace it, otherwise the requested scale compounds and flickers.
    if (!hasOriginal) {
        original = current;
        objc_setAssociatedObject(iconView, HBIconSizeOriginalTransformKey,
                                 HBValueWithTransform3D(original),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CATransform3D desired = CATransform3DScale(original, scale, scale, 1.0);
    if (!HBTransform3DEqual(current, desired)) {
        HBSetSublayerTransformWithoutAnimation(iconView, desired);
    }
    objc_setAssociatedObject(iconView, HBIconSizeAppliedKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(iconView, HBIconSizeLastTransformKey,
                             HBValueWithTransform3D(desired),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(iconView, HBIconSizeEffectiveScaleKey, @(scale),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSString *HBIconLocationForListView(id listView) {
    @try {
        id location = [listView valueForKey:@"iconLocation"];
        return [location isKindOfClass:NSString.class] ? location : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL HBListViewIsInDock(UIView *listView) {
    if (listView == nil) return NO;
    if (HBIsDockLocation(HBIconLocationForListView(listView))) return YES;

    // iconLocation is temporarily nil on iOS 16.7 while the list is recycled.
    // The view hierarchy remains authoritative throughout that transition.
    Class dockViewClass = NSClassFromString(@"SBDockView");
    Class dockListClass = NSClassFromString(@"SBDockIconListView");
    for (UIView *ancestor = listView;
         ancestor != nil;
         ancestor = ancestor.superview) {
        if ((dockViewClass != Nil && [ancestor isKindOfClass:dockViewClass]) ||
            (dockListClass != Nil && [ancestor isKindOfClass:dockListClass])) {
            return YES;
        }
    }
    return NO;
}

static NSUInteger HBIconCountForListView(id listView) {
    // On iOS 16 the authoritative icons collection belongs to the model. Keep
    // every private-key probe isolated so one missing key cannot skip the next.
    @try {
        id model = [listView valueForKey:@"model"];
        id icons = [model valueForKey:@"icons"];
        if ([icons respondsToSelector:@selector(count)]) return [icons count];
    } @catch (__unused NSException *exception) {
    }
    @try {
        id model = [listView valueForKey:@"_model"];
        id icons = [model valueForKey:@"_icons"];
        if ([icons respondsToSelector:@selector(count)]) return [icons count];
    } @catch (__unused NSException *exception) {
    }
    @try {
        id icons = [listView valueForKey:@"icons"];
        if ([icons respondsToSelector:@selector(count)]) return [icons count];
    } @catch (__unused NSException *exception) {
    }
    return 0;
}

static NSUInteger HBVisualColumnsForListView(id listView) {
    NSUInteger capacity = HBDockCapacity();
    NSUInteger count = HBIconCountForListView(listView);
    NSUInteger normalDockColumns = MIN((NSUInteger)5, capacity);

    // The provider gives the model the full acceptance ceiling. The live view
    // retains iOS's safe minimum grid while expanding to the real count.
    // MaxDock centers the visible icon views after native layout completes.
    NSUInteger columns = MAX(normalDockColumns, MIN(count, capacity));
    return MAX((NSUInteger)1, MIN(columns, capacity));
}

static CGPoint HBCorrectedDockCenterForIndex(UIView *listView,
                                              NSUInteger index,
                                              CGPoint nativeCenter) {
    if (!HBEnabled() || !HBExtraDockAppsEnabled() ||
        !HBListViewIsInDock(listView)) return nativeCenter;

    UIView *dockView = HBOuterDockViewForView(listView);
    NSUInteger count = HBIconCountForListView(listView);
    if (count == 0) count = HBVisibleDockIconViews(dockView).count;
    if (count == 0 || index == NSNotFound || index >= count) {
        return nativeCenter;
    }

    BOOL horizontal = CGRectGetWidth(dockView.bounds) >=
                      CGRectGetHeight(dockView.bounds);
    CGFloat dockMinimum = horizontal ? CGRectGetMinX(dockView.bounds)
                                     : CGRectGetMinY(dockView.bounds);
    CGFloat dockExtent = horizontal ? CGRectGetWidth(dockView.bounds)
                                    : CGRectGetHeight(dockView.bounds);
    CGFloat targetExtent = HBTargetIconExtent(dockView, count, horizontal) *
                           HBIconSizeScale();
    CGFloat gap = MAX(1.5, targetExtent * 0.05 *
                            HBIconPaddingMultiplier());
    CGFloat desiredCenterSpan = count > 1
        ? (targetExtent + gap) * (CGFloat)(count - 1) : 0.0;
    CGFloat safeEdge = (targetExtent * 0.5) + 18.0;
    CGFloat maximumCenterSpan = MAX(0.0,
        dockExtent - (2.0 * safeEdge));
    CGFloat centerSpan = MIN(desiredCenterSpan, maximumCenterSpan);
    CGFloat step = count > 1
        ? centerSpan / (CGFloat)(count - 1) : 0.0;

    BOOL reversed = NO;
    SEL reversedSelector = NSSelectorFromString(@"isLayoutReversed");
    if ([listView respondsToSelector:reversedSelector]) {
        reversed = ((BOOL (*)(id, SEL))objc_msgSend)(listView,
                                                     reversedSelector);
    }
    NSUInteger visualIndex = reversed ? (count - 1 - index) : index;
    CGFloat position = dockMinimum + (dockExtent * 0.5) -
                       (centerSpan * 0.5) +
                       (step * (CGFloat)visualIndex);

    CGPoint dockCenter = [listView convertPoint:nativeCenter toView:dockView];
    if (horizontal) dockCenter.x = position;
    else dockCenter.y = position;
    return [dockView convertPoint:dockCenter toView:listView];
}

static CGPoint HBCorrectedDockOriginForCoordinate(
    SBIconListView *listView,
    SBIconCoordinate coordinate,
    id metrics,
    CGPoint nativeOrigin) {
    if (!HBEnabled() || !HBExtraDockAppsEnabled() ||
        !HBListViewIsInDock((UIView *)listView)) return nativeOrigin;

    if (![listView respondsToSelector:
            @selector(iconIndexForCoordinate:metrics:)]) return nativeOrigin;
    NSUInteger index = [listView iconIndexForCoordinate:coordinate
                                                 metrics:metrics];
    CGSize iconViewSize = CGSizeZero;
    if ([listView respondsToSelector:@selector(alignmentIconViewSize)]) {
        iconViewSize = [listView alignmentIconViewSize];
    }
    if (iconViewSize.width <= 0.0 || iconViewSize.height <= 0.0) {
        iconViewSize = CGSizeMake(60.0, 60.0);
    }
    CGPoint nativeCenter = CGPointMake(
        nativeOrigin.x + iconViewSize.width * 0.5,
        nativeOrigin.y + iconViewSize.height * 0.5);
    CGPoint correctedCenter = HBCorrectedDockCenterForIndex(
        (UIView *)listView, index, nativeCenter);
    nativeOrigin.x += correctedCenter.x - nativeCenter.x;
    nativeOrigin.y += correctedCenter.y - nativeCenter.y;
    return nativeOrigin;
}

static BOOL HBConfigureDockGrid(id configuration, NSUInteger columns) {
    return HBApplyDockGridConfiguration(configuration, columns);
}

static void HBConfigureDockLayout(id layout, NSUInteger columns) {
    if (layout == nil || columns == 0) return;

    @try {
        HBConfigureDockGrid([layout valueForKey:@"layoutConfiguration"], columns);
    } @catch (NSException *exception) {
        os_log_error(OS_LOG_DEFAULT, "[Harbor] dock grid update failed: %{public}@",
                     exception.reason);
    }
}

static SBIconListFlowExtendedLayout *HBVisualDockLayoutForListView(
    UIView *listView,
    SBIconListFlowExtendedLayout *originalLayout,
    NSUInteger columns) {
    if (listView == nil || originalLayout == nil || columns == 0) {
        return originalLayout;
    }

    SBIconListFlowExtendedLayout *cachedLayout =
        objc_getAssociatedObject(listView, HBVisualDockLayoutKey);
    id cachedOriginal =
        objc_getAssociatedObject(listView, HBVisualDockOriginalLayoutKey);
    NSNumber *cachedColumns =
        objc_getAssociatedObject(listView, HBVisualDockColumnsKey);
    if (cachedLayout != nil && cachedOriginal == originalLayout &&
        cachedColumns.unsignedIntegerValue == columns) {
        return cachedLayout;
    }

    @try {
        id originalConfiguration = [originalLayout layoutConfiguration];
        id configurationCopy = [(id<NSCopying>)originalConfiguration copyWithZone:nil];
        Class layoutClass = NSClassFromString(@"SBIconListFlowExtendedLayout");
        if (!HBConfigureDockGrid(configurationCopy, columns) ||
            layoutClass == Nil ||
            ![layoutClass instancesRespondToSelector:
                @selector(initWithLayoutConfiguration:)]) {
            // Never mutate the provider's shared capacity layout from this
            // fallback. Reducing it to the live count can make the next Dock
            // application fail admission. Keep the ceiling and fail safely.
            os_log_error(OS_LOG_DEFAULT,
                         "[Harbor] separate visual dock layout unavailable");
            return originalLayout;
        }

        SBIconListFlowExtendedLayout *visualLayout =
            [(SBIconListFlowExtendedLayout *)[layoutClass alloc]
                initWithLayoutConfiguration:configurationCopy];
        if (visualLayout == nil) {
            os_log_error(OS_LOG_DEFAULT,
                         "[Harbor] visual dock layout creation returned nil");
            return originalLayout;
        }

        objc_setAssociatedObject(listView, HBVisualDockLayoutKey, visualLayout,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(listView, HBVisualDockOriginalLayoutKey,
                                 originalLayout,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(listView, HBVisualDockColumnsKey, @(columns),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return visualLayout;
    } @catch (NSException *exception) {
        os_log_error(OS_LOG_DEFAULT,
                     "[Harbor] visual dock layout copy failed: %{public}@",
                     exception.reason);
        return originalLayout;
    }
}

@interface HBDynamicRunningIconView : UIView
@property(nonatomic, copy) NSString *bundleIdentifier;
@property(nonatomic, strong) id modelIcon;
@property(nonatomic, strong) UIView *iconImageView;
@property(nonatomic) NSUInteger sequence;
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                                modelIcon:(id)modelIcon
                                    image:(UIImage *)image;
- (NSString *)applicationBundleIdentifier;
- (NSString *)location;
- (id)icon;
- (void)_handleTap;
@end

@implementation HBDynamicRunningIconView

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                                modelIcon:(id)modelIcon
                                    image:(UIImage *)image {
    self = [super initWithFrame:CGRectMake(0.0, 0.0, 60.0, 60.0)];
    if (self) {
        _bundleIdentifier = [bundleIdentifier copy];
        _modelIcon = modelIcon;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.userInteractionEnabled = YES;

        UIImageView *imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                     UIViewAutoresizingFlexibleHeight;
        imageView.image = image;
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        imageView.layer.cornerRadius = 13.5;
        imageView.userInteractionEnabled = NO;
        _iconImageView = imageView;
        [self addSubview:imageView];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(_handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (NSString *)applicationBundleIdentifier {
    return self.bundleIdentifier;
}

- (NSString *)location {
    return @"SBIconLocationDock";
}

- (id)icon {
    return self.modelIcon;
}

- (void)_handleTap {
    HBLaunchApplicationBundleIdentifier(self.bundleIdentifier);
}

@end

// A standalone frost avoids the private A11 visual-effect hierarchy entirely.
// Harbor owns both its geometry and its shape, so native Dock material updates
// cannot stretch or hide it.
@interface HBManagedFrostedDockView : UIView
@property(nonatomic) CGRect harborTargetFrame;
@property(nonatomic) BOOL hasHarborTargetFrame;
@property(nonatomic) CGFloat harborCornerRadius;
@property(nonatomic, strong) CAGradientLayer *harborFrostLayer;
@property(nonatomic, strong) CAShapeLayer *harborMaskLayer;
@property(nonatomic, strong) CAShapeLayer *harborBorderLayer;
- (void)hb_updateShapeLayers;
- (void)hb_applyTargetFrame:(CGRect)frame cornerRadius:(CGFloat)cornerRadius;
@end

@implementation HBManagedFrostedDockView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        self.autoresizingMask = UIViewAutoresizingNone;
        self.backgroundColor = UIColor.clearColor;

        _harborFrostLayer = [CAGradientLayer layer];
        _harborFrostLayer.colors = @[
            (id)[UIColor colorWithWhite:0.98 alpha:0.34].CGColor,
            (id)[UIColor colorWithWhite:0.72 alpha:0.24].CGColor
        ];
        _harborFrostLayer.locations = @[@0.0, @1.0];
        _harborFrostLayer.startPoint = CGPointMake(0.5, 0.0);
        _harborFrostLayer.endPoint = CGPointMake(0.5, 1.0);
        [self.layer addSublayer:_harborFrostLayer];
    }
    return self;
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:self.hasHarborTargetFrame ? self.harborTargetFrame : frame];
    [self hb_updateShapeLayers];
}

- (void)setBounds:(CGRect)bounds {
    if (self.hasHarborTargetFrame) {
        bounds.origin = CGPointZero;
        bounds.size = self.harborTargetFrame.size;
    }
    [super setBounds:bounds];
    [self hb_updateShapeLayers];
}

- (void)setCenter:(CGPoint)center {
    if (self.hasHarborTargetFrame) {
        center = CGPointMake(CGRectGetMidX(self.harborTargetFrame),
                             CGRectGetMidY(self.harborTargetFrame));
    }
    [super setCenter:center];
    [self hb_updateShapeLayers];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self hb_updateShapeLayers];
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    [self hb_updateShapeLayers];
}

- (void)hb_updateShapeLayers {
    if (!self.hasHarborTargetFrame || self.superview == nil ||
        CGRectIsEmpty(self.bounds)) return;
    self.harborFrostLayer.frame = self.bounds;
    CGRect localTarget = [self.superview convertRect:self.harborTargetFrame
                                              toView:self];
    if (CGRectIsEmpty(localTarget) ||
        !isfinite(CGRectGetMinX(localTarget)) ||
        !isfinite(CGRectGetMinY(localTarget)) ||
        !isfinite(CGRectGetWidth(localTarget)) ||
        !isfinite(CGRectGetHeight(localTarget))) return;

    UIBezierPath *path = [UIBezierPath
        bezierPathWithRoundedRect:localTarget
                     cornerRadius:self.harborCornerRadius];
    if (self.harborMaskLayer == nil) {
        self.harborMaskLayer = [CAShapeLayer layer];
        self.layer.mask = self.harborMaskLayer;
    }
    self.harborMaskLayer.frame = self.bounds;
    self.harborMaskLayer.path = path.CGPath;
    self.harborMaskLayer.fillColor = UIColor.blackColor.CGColor;

    if (self.harborBorderLayer == nil) {
        self.harborBorderLayer = [CAShapeLayer layer];
        self.harborBorderLayer.fillColor = UIColor.clearColor.CGColor;
        self.harborBorderLayer.strokeColor =
            [UIColor colorWithWhite:1.0 alpha:0.58].CGColor;
        self.harborBorderLayer.lineWidth = 0.5;
        self.harborBorderLayer.zPosition = 1000.0;
        [self.layer addSublayer:self.harborBorderLayer];
    }
    self.harborBorderLayer.frame = self.bounds;
    self.harborBorderLayer.path = path.CGPath;
}

- (void)hb_applyTargetFrame:(CGRect)frame cornerRadius:(CGFloat)cornerRadius {
    self.harborTargetFrame = frame;
    self.harborCornerRadius = cornerRadius;
    self.hasHarborTargetFrame = YES;
    [super setBounds:CGRectMake(0.0, 0.0,
                                CGRectGetWidth(frame),
                                CGRectGetHeight(frame))];
    [super setCenter:CGPointMake(CGRectGetMidX(frame),
                                 CGRectGetMidY(frame))];
    [self hb_updateShapeLayers];
}

@end

static BOOL HBIsIconView(UIView *view) {
    Class iconViewClass = NSClassFromString(@"SBIconView");
    return (iconViewClass != Nil && [view isKindOfClass:iconViewClass]) ||
           [view isKindOfClass:HBDynamicRunningIconView.class];
}

static void HBCollectIconViews(UIView *root, NSMutableArray<UIView *> *result) {
    for (UIView *view in root.subviews) {
        // A recycled icon can remain individually visible below a hidden list
        // container. Never recurse through an invisible ancestor, otherwise it
        // inflates both the icon count and the adaptive background envelope.
        if (view.hidden || view.alpha <= 0.01) continue;
        if (HBIsIconView(view)) {
            [result addObject:view];
        } else {
            HBCollectIconViews(view, result);
        }
    }
}

static NSArray<UIView *> *HBVisibleDockIconViews(UIView *dockView) {
    NSMutableArray<UIView *> *icons = [NSMutableArray array];
    HBCollectIconViews(dockView, icons);
    return icons;
}

static UIView *HBOuterDockViewForView(UIView *view) {
    Class dockViewClass = NSClassFromString(@"SBDockView");
    Class dockListClass = NSClassFromString(@"SBDockIconListView");
    UIView *candidate = nil;
    UIView *listCandidate = nil;
    for (UIView *current = view; current != nil; current = current.superview) {
        if (dockViewClass != Nil && [current isKindOfClass:dockViewClass]) {
            candidate = current;
        }
        if (dockListClass != Nil &&
            [current isKindOfClass:dockListClass]) {
            listCandidate = current;
        }
    }
    return candidate ?: listCandidate ?: view;
}

static void HBPlaceSlimBackgroundBehindIcons(UIView *background,
                                             UIView *dockView,
                                             NSArray<UIView *> *icons) {
    NSMutableOrderedSet<UIView *> *iconContainers =
        [NSMutableOrderedSet orderedSet];
    for (UIView *iconView in icons) {
        UIView *topLevel = iconView;
        while (topLevel.superview != nil &&
               topLevel.superview != dockView) {
            topLevel = topLevel.superview;
        }
        if (topLevel.superview == dockView && topLevel != background) {
            [iconContainers addObject:topLevel];
        }
    }

    // The A11 compositor can bury an ordinary custom view when it sits below
    // SBDockView's private material container. Raise Harbor above every native
    // background first, then raise the real icon containers and indicators.
    [dockView bringSubviewToFront:background];
    for (UIView *container in iconContainers) {
        [dockView bringSubviewToFront:container];
    }
    for (UIView *iconView in icons) {
        UIView *indicator = objc_getAssociatedObject(iconView,
                                                      HBRunningIndicatorKey);
        if (indicator.superview == dockView) {
            [dockView bringSubviewToFront:indicator];
        }
    }
}

static void HBUpdateSlimDockBackground(UIView *dockView, BOOL animated) {
    if (dockView == nil) return;
    HBManagedFrostedDockView *background = objc_getAssociatedObject(
        dockView, HBSlimDockBackgroundViewKey);
    BOOL shouldShow = HBEnabled() && HBSlimAdaptiveBackgroundEnabled() &&
                      !HBHideDockBackgroundEnabled();
    if (!shouldShow) {
        background.hidden = YES;
        return;
    }

    NSArray<UIView *> *icons = HBVisibleDockIconViews(dockView);
    if (icons.count == 0) {
        background.hidden = YES;
        return;
    }

    BOOL horizontal = CGRectGetWidth(dockView.bounds) >=
                      CGRectGetHeight(dockView.bounds);
    CGFloat baseExtent = HBTargetIconExtent(dockView, icons.count, horizontal) *
                         HBIconSizeScale();
    if (baseExtent < 1.0 || !isfinite(baseExtent)) baseExtent = 44.0;

    // Never derive the resting material from SpringBoard's private container
    // frames. On iOS 16.7 some recycled icon hosts temporarily report the
    // entire SBDockView bounds, which used to turn the compact frost back into
    // Apple's full-width/full-height platter. Use the same deterministic count
    // and size formula as Harbor's icon distributor instead.
    CGFloat gap = MAX(1.5, baseExtent * 0.05 * HBIconPaddingMultiplier());
    CGFloat groupedPrimary = (baseExtent * (CGFloat)icons.count) +
                             (gap * (CGFloat)(icons.count - 1));
    CGFloat targetPrimary = groupedPrimary + 16.0;
    CGFloat targetSecondary = baseExtent + 10.0;

    BOOL magnificationActive = [objc_getAssociatedObject(
        dockView, HBMagnificationActiveKey) boolValue];

    CGFloat dockPrimary = horizontal ? CGRectGetWidth(dockView.bounds)
                                     : CGRectGetHeight(dockView.bounds);
    targetPrimary = MAX(34.0, MIN(targetPrimary,
                                  MAX(34.0, dockPrimary - 8.0)));
    targetSecondary = MAX(34.0, MIN(targetSecondary, 126.0));

    CGPoint dockMiddle = CGPointMake(CGRectGetMidX(dockView.bounds),
                                     CGRectGetMidY(dockView.bounds));
    CGFloat primaryCenter = horizontal ? dockMiddle.x : dockMiddle.y;
    CGFloat secondaryCenter = horizontal ? dockMiddle.y : dockMiddle.x;
    if (!magnificationActive) {
        // Both the icon distributor and the compact material use the exact
        // Dock midpoint as their primary-axis origin. Measure only the
        // cross-axis row position so the frost follows iOS's vertical Dock
        // inset without letting stale/edit-mode icon frames pull it sideways.
        CGFloat secondaryCenterTotal = 0.0;
        NSUInteger validSecondaryCenters = 0;
        for (UIView *iconView in icons) {
            CGPoint center = [iconView.superview convertPoint:iconView.center
                                                       toView:dockView];
            CGFloat value = horizontal ? center.y : center.x;
            if (isfinite(value)) {
                secondaryCenterTotal += value;
                validSecondaryCenters++;
            }
        }
        if (validSecondaryCenters > 0) {
            secondaryCenter = secondaryCenterTotal /
                              (CGFloat)validSecondaryCenters;
        }
    }
    CGFloat primaryMinimum = horizontal ? CGRectGetMinX(dockView.bounds)
                                        : CGRectGetMinY(dockView.bounds);
    CGFloat primaryMaximum = horizontal ? CGRectGetMaxX(dockView.bounds)
                                        : CGRectGetMaxY(dockView.bounds);
    CGFloat minimumAllowedCenter = primaryMinimum +
                                   (targetPrimary * 0.5) + 2.0;
    CGFloat maximumAllowedCenter = primaryMaximum -
                                   (targetPrimary * 0.5) - 2.0;
    if (minimumAllowedCenter <= maximumAllowedCenter) {
        primaryCenter = MAX(minimumAllowedCenter,
                            MIN(primaryCenter, maximumAllowedCenter));
    }

    CGRect target = horizontal
        ? CGRectMake(primaryCenter - (targetPrimary * 0.5),
                     secondaryCenter - (targetSecondary * 0.5),
                     targetPrimary, targetSecondary)
        : CGRectMake(secondaryCenter - (targetSecondary * 0.5),
                     primaryCenter - (targetPrimary * 0.5),
                     targetSecondary, targetPrimary);
    CGFloat screenScale = MAX(1.0, UIScreen.mainScreen.scale);
    target.origin.x = round(target.origin.x * screenScale) / screenScale;
    target.origin.y = round(target.origin.y * screenScale) / screenScale;
    target.size.width = round(target.size.width * screenScale) / screenScale;
    target.size.height = round(target.size.height * screenScale) / screenScale;
    NSValue *restingFrameValue = objc_getAssociatedObject(
        dockView, HBSlimDockRestingFrameKey);
    if (magnificationActive && [restingFrameValue isKindOfClass:NSValue.class]) {
        target = restingFrameValue.CGRectValue;
    } else if (!magnificationActive) {
        objc_setAssociatedObject(dockView, HBSlimDockRestingFrameKey,
                                 [NSValue valueWithCGRect:target],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat cornerRadius = MIN(22.0, CGRectGetHeight(target) * 0.38);

    BOOL created = NO;
    if (background == nil) {
        background = [[HBManagedFrostedDockView alloc]
            initWithFrame:CGRectZero];
        background.layer.borderWidth = 0.0;
        if (@available(iOS 13.0, *)) {
            background.layer.cornerCurve = kCACornerCurveContinuous;
        }
        [background hb_applyTargetFrame:target cornerRadius:cornerRadius];
        [dockView insertSubview:background atIndex:0];
        objc_setAssociatedObject(dockView, HBSlimDockBackgroundViewKey,
                                 background,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        created = YES;
    }
    background.hidden = NO;
    // setBackgroundAlpha: belongs to Apple's material, but some 16.7 Dock
    // builds propagate its value to visual-effect descendants. Reassert the
    // Harbor material after the native background has been disabled.
    background.alpha = 1.0;
    background.layer.opacity = 1.0;
    HBPlaceSlimBackgroundBehindIcons(background, dockView, icons);

    BOOL frameChanged = fabs(CGRectGetMinX(background.frame) -
                             CGRectGetMinX(target)) > 0.25 ||
                        fabs(CGRectGetMinY(background.frame) -
                             CGRectGetMinY(target)) > 0.25 ||
                        fabs(CGRectGetWidth(background.frame) -
                             CGRectGetWidth(target)) > 0.25 ||
                        fabs(CGRectGetHeight(background.frame) -
                             CGRectGetHeight(target)) > 0.25;
    if (!frameChanged &&
        fabs(background.harborCornerRadius - cornerRadius) <= 0.1) {
        [background hb_updateShapeLayers];
        return;
    }
    void (^changes)(void) = ^{
        [background hb_applyTargetFrame:target cornerRadius:cornerRadius];
    };
    if (animated && !created && background.window != nil) {
        [UIView animateWithDuration:0.24
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction |
                                    UIViewAnimationOptionCurveEaseOut
                         animations:changes
                         completion:nil];
    } else {
        [UIView performWithoutAnimation:changes];
    }
}

static void HBSetNativeDockMaterialHidden(UIView *dockView, BOOL hidden) {
    if (dockView == nil) return;
    NSNumber *lastHidden = objc_getAssociatedObject(
        dockView, HBLastNativeMaterialHiddenKey);
    NSNumber *lastSubviewCount = objc_getAssociatedObject(
        dockView, HBLastNativeMaterialSubviewCountKey);
    NSUInteger currentSubviewCount = dockView.subviews.count;
    if (lastHidden != nil && lastHidden.boolValue == hidden &&
        lastSubviewCount != nil &&
        lastSubviewCount.unsignedIntegerValue == currentSubviewCount) {
        return;
    }
    UIView *harborBackground = objc_getAssociatedObject(
        dockView, HBSlimDockBackgroundViewKey);
    NSMutableOrderedSet<UIView *> *materials = [NSMutableOrderedSet orderedSet];

    // These are the actual SBDockView backing ivars. setBackgroundAlpha: does
    // not consistently suppress every one of them on 16.7 (notably the image
    // and accessibility fallbacks), so address each material directly.
    for (NSString *key in @[@"backgroundView", @"_backgroundView",
                              @"backgroundImageView", @"_backgroundImageView",
                              @"accessibilityBackgroundView",
                              @"_accessibilityBackgroundView",
                              @"backgroundMaterialView",
                              @"_backgroundMaterialView"]) {
        @try {
            id candidate = [dockView valueForKey:key];
            if ([candidate isKindOfClass:UIView.class] &&
                candidate != harborBackground && candidate != dockView) {
                [materials addObject:candidate];
            }
        } @catch (__unused NSException *exception) {
        }
    }

    // Minor iOS 16 builds rename the material ivar while retaining a clear
    // class name. Limit the fallback to direct Dock children so icon artwork,
    // badges, and Harbor's own nested blur are never touched.
    for (UIView *candidate in dockView.subviews) {
        if (candidate == harborBackground || HBIsIconView(candidate)) continue;
        NSString *name = NSStringFromClass(candidate.class).lowercaseString;
        NSMutableArray<UIView *> *containedIcons = [NSMutableArray array];
        HBCollectIconViews(candidate, containedIcons);
        CGRect dockRect = [candidate convertRect:candidate.bounds
                                          toView:dockView];
        BOOL coversDock = CGRectGetWidth(dockRect) >=
                              CGRectGetWidth(dockView.bounds) * 0.70 &&
                          CGRectGetHeight(dockRect) >=
                              CGRectGetHeight(dockView.bounds) * 0.55;
        if ([name containsString:@"wallpapereffect"] ||
            [name containsString:@"backgroundimage"] ||
            [name containsString:@"dockbackground"] ||
            [name containsString:@"materialview"] ||
            (coversDock && containedIcons.count == 0 &&
             !candidate.userInteractionEnabled)) {
            [materials addObject:candidate];
        }
    }

    for (UIView *material in materials) {
        NSNumber *savedAlpha = objc_getAssociatedObject(
            material, HBNativeMaterialOriginalAlphaKey);
        NSNumber *savedHidden = objc_getAssociatedObject(
            material, HBNativeMaterialOriginalHiddenKey);
        NSNumber *savedOpacity = objc_getAssociatedObject(
            material, HBNativeMaterialOriginalLayerOpacityKey);
        if (savedAlpha == nil) {
            savedAlpha = @(material.alpha);
            savedHidden = @(material.hidden);
            savedOpacity = @(material.layer.opacity);
            objc_setAssociatedObject(material, HBNativeMaterialOriginalAlphaKey,
                                     savedAlpha,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(material, HBNativeMaterialOriginalHiddenKey,
                                     savedHidden,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(material,
                                     HBNativeMaterialOriginalLayerOpacityKey,
                                     savedOpacity,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (hidden) {
            material.hidden = YES;
            material.alpha = 0.0;
            material.layer.opacity = 0.0;
        } else {
            material.hidden = savedHidden.boolValue;
            material.alpha = savedAlpha.doubleValue;
            material.layer.opacity = savedOpacity.floatValue;
        }
    }

    id savedColor = objc_getAssociatedObject(
        dockView, HBDockOriginalBackgroundColorKey);
    if (savedColor == nil) {
        savedColor = dockView.backgroundColor ?: NSNull.null;
        objc_setAssociatedObject(dockView, HBDockOriginalBackgroundColorKey,
                                 savedColor,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hidden) {
        dockView.backgroundColor = UIColor.clearColor;
    } else {
        dockView.backgroundColor = savedColor == NSNull.null
            ? nil : (UIColor *)savedColor;
    }
    objc_setAssociatedObject(dockView, HBLastNativeMaterialHiddenKey,
                             @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(dockView, HBLastNativeMaterialSubviewCountKey,
                             @(dockView.subviews.count),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void HBApplyDockBackgroundPreference(UIView *dockView) {
    if (dockView == nil) return;
    BOOL replacesNative = HBSlimAdaptiveBackgroundEnabled();
    BOOL hideNative = HBHideDockBackgroundEnabled() || replacesNative;
    BOOL shouldShowSlim = HBEnabled() && replacesNative &&
                          !HBHideDockBackgroundEnabled();
    NSString *signature = [NSString stringWithFormat:@"%d:%d:%d",
        HBEnabled(), hideNative, shouldShowSlim];
    NSString *previous = objc_getAssociatedObject(
        dockView, HBLastDockBackgroundSignatureKey);
    UIView *background = objc_getAssociatedObject(
        dockView, HBSlimDockBackgroundViewKey);
    if ([previous isEqualToString:signature] &&
        (!shouldShowSlim || background != nil)) {
        return;
    }
    objc_setAssociatedObject(dockView, HBLastDockBackgroundSignatureKey,
                             signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if ([dockView respondsToSelector:@selector(setBackgroundAlpha:)]) {
        NSNumber *original = objc_getAssociatedObject(
            dockView, HBOriginalDockBackgroundAlphaKey);
        double alpha = hideNative
            ? 0.0 : (original != nil ? original.doubleValue : 1.0);
        [(SBDockView *)dockView setBackgroundAlpha:alpha];
    }
    HBSetNativeDockMaterialHidden(dockView, hideNative);
    HBUpdateSlimDockBackground(dockView, YES);
}

static BOOL HBLooksLikeHomeSearchControl(UIView *view, UIView *rootView) {
    CGRect rect = [view convertRect:view.bounds toView:rootView];
    BOOL nearBottom = CGRectGetMidY(rect) > CGRectGetHeight(rootView.bounds) * 0.68;
    BOOL compact = CGRectGetHeight(rect) > 10.0 && CGRectGetHeight(rect) < 90.0 &&
                   CGRectGetWidth(rect) < 240.0;
    if (!nearBottom || !compact) return NO;

    NSString *className = NSStringFromClass(view.class).lowercaseString;
    BOOL namedSearchControl = [className containsString:@"search"];
    NSString *accessibility = view.accessibilityLabel.lowercaseString;
    BOOL labeledSearchControl = [accessibility containsString:@"search"] ||
                                [accessibility containsString:@"بحث"];
    if ([view isKindOfClass:UILabel.class]) {
        NSString *text = ((UILabel *)view).text.lowercaseString;
        labeledSearchControl = labeledSearchControl ||
            [text containsString:@"search"] || [text containsString:@"بحث"];
    }
    return namedSearchControl || labeledSearchControl;
}

static UIView *HBHomeSearchContainer(UIView *matchedView, UIView *rootView) {
    UIView *container = matchedView;
    for (UIView *ancestor = matchedView.superview;
         ancestor != nil && ancestor != rootView;
         ancestor = ancestor.superview) {
        CGRect rect = [ancestor convertRect:ancestor.bounds toView:rootView];
        BOOL compact = CGRectGetHeight(rect) < 90.0 &&
                       CGRectGetWidth(rect) < 240.0;
        BOOL nearBottom = CGRectGetMidY(rect) >
                          CGRectGetHeight(rootView.bounds) * 0.68;
        if (!compact || !nearBottom) break;
        container = ancestor;
    }
    return container;
}

static NSString *HBIconBundleIdentifier(UIView*);
static UIImage *HBImageFromIconImageCarrier(id);
static NSString *HBDisplayNameForIconView(UIView*);
static void HBLaunchDockIconView(UIView*,UIView*);
static char HBCircleMapKey,HBCircleRowsKey,HBCircleTimeKey;
static void HBApplyCircle(UIView*dock,CGRect content){
 if(!HBEnabled()||!HBCircularModeChosen()||HBIconManagerIsEditingOrDragging()){
 HBUpdateCircularDock(dock,nil,CGRectZero,@[],0,NO,nil,nil);
 objc_setAssociatedObject(dock,&HBCircleRowsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(dock,&HBCircleTimeKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);return;
 }
 UIView*surface=dock.superview;CGSize screen=dock.window.bounds.size;
 while(surface.superview&&(fabs(surface.bounds.size.width-screen.width)>1||fabs(surface.bounds.size.height-screen.height)>1))surface=surface.superview;
 NSMutableArray*rows=objc_getAssociatedObject(dock,&HBCircleRowsKey);NSMapTable*map=objc_getAssociatedObject(dock,&HBCircleMapKey);double now=NSDate.timeIntervalSinceReferenceDate;
 if(!rows||now-[objc_getAssociatedObject(dock,&HBCircleTimeKey)doubleValue]>.5){rows=[NSMutableArray new];map=[NSMapTable strongToWeakObjectsMapTable];
 for(UIView*icon in HBVisibleDockIconViews(dock)){NSString*key=HBIconBundleIdentifier(icon)?:[NSString stringWithFormat:@"icon-%p",icon];UIImage*image=HBImageFromIconImageCarrier(HBIconImageView(icon)?:icon);if(!image)image=[UIImage systemImageNamed:@"app.fill"];[rows addObject:@{@"key":key,@"title":HBDisplayNameForIconView(icon)?:@"",@"image":image,@"badge":@""}];[map setObject:icon forKey:key];}
 objc_setAssociatedObject(dock,&HBCircleRowsKey,rows,OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(dock,&HBCircleTimeKey,@(now),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 objc_setAssociatedObject(dock,&HBCircleMapKey,map,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}__weak UIView*weakDock=dock;
 HBCircularSetIconScale(dock,HBFloatPreference(@"CircularIconScale",1,.6,1.3));
 HBUpdateCircularDock(dock,surface,[dock convertRect:content toView:surface],rows,HBFloatPreference(@"CircularPhase",0,-1000000,1000000),YES,^(NSString*key){UIView*d=weakDock;UIView*icon=[objc_getAssociatedObject(d,&HBCircleMapKey)objectForKey:key];if(d&&icon&&!HBIconManagerIsEditingOrDragging())HBLaunchDockIconView(icon,d);},^(CGFloat phase){[HBPreferences() setDouble:phase forKey:@"CircularPhase"];});
 HBCircularSetSpeed(dock,HBFloatPreference(@"CircularSpeed",2,.5,4));
 HBCircularSetEditRequest(dock,^{
 UIView*d=weakDock;if(!d)return;
 Class controllerClass=NSClassFromString(@"SBIconController");if(![controllerClass respondsToSelector:@selector(sharedInstance)])return;
 id controller=[controllerClass sharedInstance];if(![controller respondsToSelector:@selector(iconManager)])return;
 id manager=[controller iconManager];if(!HBHookTypesMatch([manager class],@{@"setEditing:":@[@"v",@"B"]}))return;
 ((void(*)(id,SEL,BOOL))objc_msgSend)(manager,@selector(setEditing:),YES);
 if(HBIconManagerIsEditingOrDragging())HBUpdateCircularDock(d,nil,CGRectZero,@[],0,NO,nil,nil);
 });
}

static void HBApplyPositionPreference(UIView*dockView) {
 if(!NSThread.isMainThread||!dockView)return;
 if(!HBEnabled()){HBApplyCircle(dockView,CGRectZero);HBUpdateDockPosition(dockView,CGRectNull,0,NO,NO,nil);return;}
 CGRect content=CGRectNull;NSValue*value=objc_getAssociatedObject(dockView,HBSlimDockRestingFrameKey);
 UIView*background=objc_getAssociatedObject(dockView,HBSlimDockBackgroundViewKey);
 if(background&&!background.hidden&&[value isKindOfClass:NSValue.class])content=value.CGRectValue;
 if(CGRectIsNull(content)||CGRectIsEmpty(content))for(UIView*icon in HBVisibleDockIconViews(dockView)){UIView*image=HBIconImageView(icon)?:icon;content=CGRectUnion(content,[image convertRect:image.bounds toView:dockView]);}
 CGFloat requested=HBEnabled()?HBFloatPreference(@"DockVerticalOffset",0,-100,120):0;
 HBUpdateDockPosition(dockView,content,requested,HBEnabled()&&HBBoolPreference(@"DockPositionHandle",YES),HBIconManagerIsEditingOrDragging(),^(CGFloat offset){NSUserDefaults*p=HBPreferences();[p setDouble:offset forKey:@"DockVerticalOffset"];[p synchronize];CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.eswick.harbor16/preferences.changed"),NULL,NULL,YES);});
 HBApplyCircle(dockView,content);
}

static void HBApplyHomeSearchPreference(UIView *rootView) {
    if (rootView == nil) return;
    NSMutableArray<UIView *> *pending =
        [NSMutableArray arrayWithArray:rootView.subviews];
    while (pending.count > 0) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        NSNumber *savedAlpha = objc_getAssociatedObject(
            view, HBSearchOriginalAlphaKey);
        if (savedAlpha != nil) {
            if (HBHideHomeSearchEnabled()) {
                view.alpha = 0.0;
                view.userInteractionEnabled = NO;
            } else {
                view.alpha = savedAlpha.doubleValue;
                NSNumber *interaction = objc_getAssociatedObject(
                    view, HBSearchOriginalInteractionKey);
                view.userInteractionEnabled = interaction.boolValue;
            }
        } else if (HBHideHomeSearchEnabled() &&
                   HBLooksLikeHomeSearchControl(view, rootView)) {
            UIView *target = HBHomeSearchContainer(view, rootView);
            if (objc_getAssociatedObject(target,
                                         HBSearchOriginalAlphaKey) == nil) {
                objc_setAssociatedObject(target, HBSearchOriginalAlphaKey,
                                         @(target.alpha),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(target,
                                         HBSearchOriginalInteractionKey,
                                         @(target.userInteractionEnabled),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            target.alpha = 0.0;
            target.userInteractionEnabled = NO;
        }
        [pending addObjectsFromArray:view.subviews];
    }
}

static NSHashTable<UIView *> *HBKnownRootFolderViews(void) {
    static NSHashTable<UIView *> *views = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        views = [NSHashTable weakObjectsHashTable];
    });
    return views;
}

static NSUInteger HBAutoHideGeneration = 0;

static void HBShowDocksAndScheduleAutoHide(void) {
    NSUInteger generation = ++HBAutoHideGeneration;
    for (UIView *dockView in HBKnownDockHosts().allObjects) {
        NSValue *originalTransform = objc_getAssociatedObject(
            dockView, HBAutoHideOriginalTransformKey);
        NSNumber *originalAlpha = objc_getAssociatedObject(
            dockView, HBAutoHideOriginalAlphaKey);
        if (originalTransform == nil) {
            originalTransform = [NSValue valueWithCGAffineTransform:dockView.transform];
            originalAlpha = @(HBCircularNativeAlpha(dockView));
            objc_setAssociatedObject(dockView, HBAutoHideOriginalTransformKey,
                                     originalTransform,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(dockView, HBAutoHideOriginalAlphaKey,
                                     originalAlpha,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [UIView animateWithDuration:0.22 animations:^{
            dockView.transform = originalTransform.CGAffineTransformValue;
            dockView.alpha = originalAlpha.doubleValue;
        }];
    }
    if (!HBAutoHideDockEnabled()) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != HBAutoHideGeneration ||
            !HBAutoHideDockEnabled() || HBIconManagerIsEditingOrDragging()) return;
        for (UIView *dockView in HBKnownDockHosts().allObjects) {
            NSValue *originalTransform = objc_getAssociatedObject(
                dockView, HBAutoHideOriginalTransformKey);
            CGAffineTransform base = originalTransform != nil
                ? originalTransform.CGAffineTransformValue : CGAffineTransformIdentity;
            [UIView animateWithDuration:0.28 animations:^{
                dockView.transform = CGAffineTransformTranslate(
                    base, 0.0, CGRectGetHeight(dockView.bounds) * 0.82);
                dockView.alpha = 0.02;
            }];
        }
    });
}

@interface HBAutoHideGestureTarget : NSObject <UIGestureRecognizerDelegate>
- (void)handleEdgePan:(UIScreenEdgePanGestureRecognizer *)recognizer;
@end

@implementation HBAutoHideGestureTarget
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    (void)gestureRecognizer;
    return HBAutoHideDockEnabled();
}

- (void)handleEdgePan:(UIScreenEdgePanGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan ||
        recognizer.state == UIGestureRecognizerStateRecognized) {
        HBShowDocksAndScheduleAutoHide();
    }
}
@end

static void HBAttachAutoHideEdgeGestureIfNeeded(UIView *rootView) {
    if (rootView == nil ||
        objc_getAssociatedObject(rootView, HBAutoHideEdgeGestureKey) != nil) return;
    HBAutoHideGestureTarget *target = [HBAutoHideGestureTarget new];
    UIScreenEdgePanGestureRecognizer *edge = [[UIScreenEdgePanGestureRecognizer alloc]
        initWithTarget:target action:@selector(handleEdgePan:)];
    edge.delegate = target;
    edge.edges = UIRectEdgeBottom;
    edge.cancelsTouchesInView = NO;
    [rootView addGestureRecognizer:edge];
    objc_setAssociatedObject(rootView, HBAutoHideEdgeGestureKey, target,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSString *HBIconBundleIdentifier(UIView *iconView) {
    SEL directSelector = NSSelectorFromString(@"applicationBundleIdentifier");
    if ([iconView respondsToSelector:directSelector]) {
        NSString *direct = ((id (*)(id, SEL))objc_msgSend)(iconView,
                                                           directSelector);
        if ([direct isKindOfClass:NSString.class] && direct.length > 0) {
            return direct;
        }
    }
    @try {
        id icon = [iconView valueForKey:@"icon"];
        for (NSString *key in @[@"applicationBundleID", @"bundleIdentifier"]) {
            id value = [icon valueForKey:key];
            if ([value isKindOfClass:NSString.class] &&
                [(NSString *)value length] > 0) return value;
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static BOOL HBIconApplicationIsRunning(UIView *iconView) {
    @try {
        id icon = [iconView valueForKey:@"icon"];
        id application = nil;
        SEL applicationSelector = NSSelectorFromString(@"application");
        @try {
            if ([icon respondsToSelector:applicationSelector]) {
                application = ((id (*)(id, SEL))objc_msgSend)(icon,
                                                              applicationSelector);
            } else {
                application = [icon valueForKey:@"application"];
            }
        }
        @catch (__unused NSException *exception) {}
        if (application == nil) {
            NSString *bundleIdentifier = HBIconBundleIdentifier(iconView);
            Class controllerClass = NSClassFromString(@"SBApplicationController");
            if (bundleIdentifier.length > 0 && controllerClass != Nil) {
                id controller = nil;
                if ([controllerClass respondsToSelector:
                        @selector(sharedInstanceIfExists)]) {
                    controller = [(id)controllerClass sharedInstanceIfExists];
                }
                if (controller == nil &&
                    [controllerClass respondsToSelector:@selector(sharedInstance)]) {
                    controller = [(id)controllerClass sharedInstance];
                }
                if ([controller respondsToSelector:
                        @selector(applicationWithBundleIdentifier:)]) {
                    application = [controller
                        applicationWithBundleIdentifier:bundleIdentifier];
                } else if ([controller respondsToSelector:
                                @selector(applicationForBundleIdentifier:)]) {
                    application = [controller
                        applicationForBundleIdentifier:bundleIdentifier];
                }
            }
        }
        id processState = nil;
        if ([application respondsToSelector:@selector(processState)]) {
            processState = ((id (*)(id, SEL))objc_msgSend)(application,
                                                            @selector(processState));
        }
        if ([processState respondsToSelector:@selector(isRunning)]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(processState,
                                                     @selector(isRunning));
        }
        if ([application respondsToSelector:@selector(isRunning)]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(application,
                                                     @selector(isRunning));
        }
        if ([application respondsToSelector:@selector(activationState)]) {
            int state = ((int (*)(id, SEL))objc_msgSend)(application,
                                                         @selector(activationState));
            return state != 0;
        }
        for (NSString *key in @[@"running", @"activationState"]) {
            @try {
                id value = [application valueForKey:key];
                if ([value respondsToSelector:@selector(integerValue)]) {
                    return [value integerValue] > 0;
                }
            } @catch (__unused NSException *exception) {
            }
        }
    } @catch (__unused NSException *exception) {
    }
    return NO;
}

static BOOL HBValueRepresentsNotificationBadge(id value) {
    if (value == nil || value == NSNull.null) return NO;
    if ([value isKindOfClass:NSNumber.class]) {
        return [(NSNumber *)value integerValue] != 0;
    }
    if ([value isKindOfClass:NSString.class]) {
        NSString *text = [(NSString *)value
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return text.length > 0 && ![text isEqualToString:@"0"];
    }
    return NO;
}

static BOOL HBIconHasNotificationBadge(UIView *iconView) {
    if (iconView == nil) return NO;
    @try {
        id icon = [iconView valueForKey:@"icon"];
        for (id object in @[iconView, icon ?: NSNull.null]) {
            if (object == NSNull.null) continue;
            for (NSString *key in @[@"badgeValue", @"displayedBadgeValue",
                                     @"badgeNumberOrString"]) {
                @try {
                    if (HBValueRepresentsNotificationBadge(
                            [object valueForKey:key])) return YES;
                } @catch (__unused NSException *exception) {
                }
            }
        }
    } @catch (__unused NSException *exception) {
    }

    // iOS 16 builds do not all expose the same badge-value selector. The
    // visible SBIconBadgeView is a safe fallback and avoids private calls.
    NSMutableArray<UIView *> *pending =
        [NSMutableArray arrayWithArray:iconView.subviews];
    while (pending.count > 0) {
        UIView *candidate = pending.lastObject;
        [pending removeLastObject];
        if (candidate.hidden || candidate.alpha <= 0.01) continue;
        NSString *className = NSStringFromClass(candidate.class);
        if ([className rangeOfString:@"Badge"
                             options:NSCaseInsensitiveSearch].location != NSNotFound &&
            CGRectGetWidth(candidate.bounds) >= 4.0 &&
            CGRectGetHeight(candidate.bounds) >= 4.0) {
            return YES;
        }
        [pending addObjectsFromArray:candidate.subviews];
    }
    return NO;
}

static void HBUpdateNotificationBadgeBounce(UIView *iconView) {
    static NSString *animationKey = @"HarborNotificationBadgeBounce";
    BOOL shouldBounce = HBEnabled() && HBBadgeBounceEnabled() &&
                        iconView.window != nil &&
                        HBIconViewIsInDock(iconView) &&
                        !HBIconManagerIsEditingOrDragging() &&
                        HBIconHasNotificationBadge(iconView);
    if (!shouldBounce) {
        [iconView.layer removeAnimationForKey:animationKey];
        return;
    }
    if ([iconView.layer animationForKey:animationKey] != nil) return;

    CAKeyframeAnimation *bounce = [CAKeyframeAnimation
        animationWithKeyPath:@"transform.translation.y"];
    // Two light hops followed by a pause. Core Animation repeats this without
    // timers, layout changes, thumbnails, or additional SpringBoard views.
    bounce.values = @[@0.0, @-10.0, @0.0, @-5.0, @0.0, @0.0];
    bounce.keyTimes = @[@0.0, @0.12, @0.24, @0.34, @0.44, @1.0];
    bounce.duration = 1.65;
    bounce.repeatCount = HUGE_VALF;
    bounce.additive = YES;
    bounce.calculationMode = kCAAnimationCubic;
    [iconView.layer addAnimation:bounce forKey:animationKey];
}

static void HBUpdateRunningIndicator(UIView *iconView, UIView *dockView) {
    UIView *indicator = objc_getAssociatedObject(iconView, HBRunningIndicatorKey);
    BOOL visible = dockView != nil && HBRunningIndicatorsEnabled() &&
                   HBIconApplicationIsRunning(iconView);
    if (!visible) {
        indicator.hidden = YES;
        [indicator removeFromSuperview];
        return;
    }
    if (indicator == nil) {
        indicator = [[UIView alloc] initWithFrame:CGRectZero];
        indicator.userInteractionEnabled = NO;
        indicator.backgroundColor = [UIColor colorWithRed:0.25 green:0.92
                                                       blue:0.55 alpha:1.0];
        indicator.layer.cornerRadius = 2.5;
        indicator.layer.shadowColor = indicator.backgroundColor.CGColor;
        indicator.layer.shadowOpacity = 0.8;
        indicator.layer.shadowRadius = 3.0;
        indicator.layer.shadowOffset = CGSizeZero;
        objc_setAssociatedObject(iconView, HBRunningIndicatorKey, indicator,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (indicator.superview != dockView) {
        [indicator removeFromSuperview];
        [dockView addSubview:indicator];
    }
    UIView *imageView = HBIconImageView(iconView) ?: iconView;
    CGRect imageRect = [imageView convertRect:imageView.bounds toView:dockView];
    CGFloat y = MIN(CGRectGetMaxY(imageRect) + 2.0,
                    CGRectGetHeight(dockView.bounds) - 7.0);
    indicator.hidden = NO;
    indicator.frame = CGRectMake(CGRectGetMidX(imageRect) - 2.5, y,
                                 5.0, 5.0);
    [dockView bringSubviewToFront:indicator];
}

static BOOL HBLooksLikeRetiredRunningIndicator(UIView *view) {
    if (view == nil || view.userInteractionEnabled ||
        CGRectGetWidth(view.bounds) < 2.0 ||
        CGRectGetWidth(view.bounds) > 8.0 ||
        CGRectGetHeight(view.bounds) < 2.0 ||
        CGRectGetHeight(view.bounds) > 8.0 ||
        view.layer.cornerRadius < 1.5) {
        return NO;
    }
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
    if (![view.backgroundColor getRed:&red green:&green blue:&blue
                                 alpha:&alpha]) {
        return NO;
    }
    return alpha > 0.5 && green > 0.72 && blue > 0.30 &&
           red < 0.55 && green > red + 0.25;
}

static void HBPurgeRetiredRunningIndicators(UIView *dockView) {
    if (dockView == nil) return;
    for (UIView *iconView in HBVisibleDockIconViews(dockView)) {
        UIView *indicator = objc_getAssociatedObject(iconView,
                                                      HBRunningIndicatorKey);
        if (indicator != nil) {
            [indicator removeFromSuperview];
            objc_setAssociatedObject(iconView, HBRunningIndicatorKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    // Alpha 67 can inherit a marker whose owning icon was recycled, leaving no
    // association through which to remove it. Match only MaxDock's exact small,
    // round, noninteractive green view among direct Dock children.
    for (UIView *view in [dockView.subviews copy]) {
        if (HBLooksLikeRetiredRunningIndicator(view)) {
            [view removeFromSuperview];
        }
    }
}

static CGFloat HBEffectiveDockIconScale(UIView *iconView) {
    NSNumber *scale = objc_getAssociatedObject(
        iconView, HBIconSizeEffectiveScaleKey);
    CGFloat value = scale == nil ? 1.0 : scale.doubleValue;
    return value > 0.01 && isfinite(value) ? value : 1.0;
}

static void HBReapplyCachedDockIconSize(UIView *iconView) {
    if (iconView == nil || !HBIconViewIsInDock(iconView)) {
        HBApplyDockIconSize(iconView);
        return;
    }
    NSNumber *effective = objc_getAssociatedObject(
        iconView, HBIconSizeEffectiveScaleKey);
    if (effective == nil) {
        // Image creation also occurs while the Dock list is only partially
        // populated. Let the stable-count debounce size all icons together.
        HBScheduleDockCountRefresh();
        return;
    }
    CATransform3D current = iconView.layer.sublayerTransform;
    CATransform3D lastApplied = CATransform3DIdentity;
    if (HBGetAssociatedTransform3D(iconView, HBIconSizeLastTransformKey,
                                   &lastApplied)) {
        if (!HBTransform3DEqual(current, lastApplied)) {
            // Badge/image refreshes must not become a second source of native
            // geometry. Restore the exact cached model transform.
            HBSetSublayerTransformWithoutAnimation(iconView, lastApplied);
        }
        return;
    }
    HBApplyDockIconSize(iconView);
}

static void HBDistributeDockIconCenters(UIView *dockView) {
    if (dockView == nil || !HBEnabled() || !HBExtraDockAppsEnabled() ||
        HBIconManagerIsDraggingIcon()) return;
    NSArray<UIView *> *icons = HBVisibleDockIconViews(dockView);
    if (icons.count == 0) return;

    BOOL horizontal = CGRectGetWidth(dockView.bounds) >=
                      CGRectGetHeight(dockView.bounds);
    NSArray<UIView *> *ordered = [icons sortedArrayUsingComparator:
        ^NSComparisonResult(UIView *left, UIView *right) {
        CGPoint leftCenter = [left.superview convertPoint:left.center
                                                   toView:dockView];
        CGPoint rightCenter = [right.superview convertPoint:right.center
                                                    toView:dockView];
        CGFloat leftValue = horizontal ? leftCenter.x : leftCenter.y;
        CGFloat rightValue = horizontal ? rightCenter.x : rightCenter.y;
        if (leftValue < rightValue) return NSOrderedAscending;
        if (leftValue > rightValue) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    CGFloat dockMinimum = horizontal ? CGRectGetMinX(dockView.bounds)
                                     : CGRectGetMinY(dockView.bounds);
    CGFloat dockExtent = horizontal ? CGRectGetWidth(dockView.bounds)
                                    : CGRectGetHeight(dockView.bounds);
    CGFloat targetExtent = HBTargetIconExtent(dockView, ordered.count,
                                               horizontal) *
                           HBIconSizeScale();
    CGFloat gap = MAX(1.5, targetExtent * 0.05 *
                            HBIconPaddingMultiplier());
    CGFloat desiredCenterSpan = ordered.count > 1
        ? (targetExtent + gap) * (CGFloat)(ordered.count - 1) : 0.0;
    CGFloat safeEdge = (targetExtent * 0.5) + 18.0;
    CGFloat maximumCenterSpan = MAX(0.0,
        dockExtent - (2.0 * safeEdge));
    CGFloat centerSpan = MIN(desiredCenterSpan, maximumCenterSpan);
    CGFloat step = ordered.count > 1
        ? centerSpan / (CGFloat)(ordered.count - 1) : 0.0;
    CGFloat firstCenter = dockMinimum + (dockExtent * 0.5) -
                          (centerSpan * 0.5);

    [ordered enumerateObjectsUsingBlock:
        ^(UIView *iconView, NSUInteger index, BOOL *stop) {
        (void)stop;
        CGPoint center = [iconView.superview convertPoint:iconView.center
                                                   toView:dockView];
        CGFloat position = ordered.count > 1
            ? firstCenter + (step * (CGFloat)index)
            : dockMinimum + (dockExtent * 0.5);
        CGFloat currentPosition = horizontal ? center.x : center.y;
        if (fabs(currentPosition - position) <= 0.25) return;
        if (horizontal) center.x = position;
        else center.y = position;
        CGPoint correctedCenter = [dockView convertPoint:center
                                                   toView:iconView.superview];
        [UIView performWithoutAnimation:^{
            iconView.center = correctedCenter;
        }];
    }];
}

static void HBScheduleLateDockIconDistribution(UIView *listView) {
    if (listView == nil ||
        objc_getAssociatedObject(listView,
                                 HBDockLateDistributionScheduledKey) != nil) {
        return;
    }

    // SBIconListView finishes before some of its private layout helpers. A
    // single coalesced main-queue pass therefore has to be the final writer of
    // the sparse Dock positions. This fixes the 2-10 icon case without doing
    // expensive work continuously while the user pages the Home Screen.
    objc_setAssociatedObject(listView, HBDockLateDistributionScheduledKey,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakListView = listView;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *strongListView = weakListView;
        if (strongListView == nil) return;
        objc_setAssociatedObject(strongListView,
                                 HBDockLateDistributionScheduledKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (strongListView.window == nil ||
            !HBEnabled() || !HBExtraDockAppsEnabled() ||
            !HBListViewIsInDock(strongListView)) {
            return;
        }
        UIView *dockView = HBOuterDockViewForView(strongListView);
        HBDistributeDockIconCenters(dockView);
    });
}

static void HBRefreshDockIconSizes(UIView *dockView) {
    if (dockView == nil) return;
    NSArray<UIView *> *icons = HBVisibleDockIconViews(dockView);
    NSString *signature = [NSString stringWithFormat:
        @"%lu:%.2f:%.2f:%.3f:%.3f:%d",
        (unsigned long)icons.count,
        CGRectGetWidth(dockView.bounds), CGRectGetHeight(dockView.bounds),
        HBIconSizeScale(), HBIconInset(), HBEnabled()];
    NSString *previous = objc_getAssociatedObject(
        dockView, HBLastDockSizeSignatureKey);
    BOOL needsSlimBackground = HBEnabled() &&
                               HBSlimAdaptiveBackgroundEnabled() &&
                               !HBHideDockBackgroundEnabled();
    UIView *slimBackground = objc_getAssociatedObject(
        dockView, HBSlimDockBackgroundViewKey);
    if ([previous isEqualToString:signature] &&
        (!needsSlimBackground || slimBackground != nil)) {
        // SBDockView and its list are laid out repeatedly while paging. Their
        // count/bounds signature is unchanged, so touching icon centers or
        // material layers here only steals frames from SpringBoard.
        return;
    }

    HBPurgeRetiredRunningIndicators(dockView);
    HBUpdateDynamicRunningAppsForDock(dockView);
    HBDistributeDockIconCenters(dockView);
    icons = HBVisibleDockIconViews(dockView);
    signature = [NSString stringWithFormat:
        @"%lu:%.2f:%.2f:%.3f:%.3f:%d",
        (unsigned long)icons.count,
        CGRectGetWidth(dockView.bounds), CGRectGetHeight(dockView.bounds),
        HBIconSizeScale(), HBIconInset(), HBEnabled()];
    objc_setAssociatedObject(dockView, HBLastDockSizeSignatureKey, signature,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    for (UIView *iconView in icons) {
        HBUpdateRunningIndicator(iconView, dockView);
        HBUpdateNotificationBadgeBounce(iconView);
        HBApplyDockIconSize(iconView);
    }
    HBUpdateSlimDockBackground(dockView, YES);
}

static void HBInvalidateDockSizeSignature(UIView *dockView) {
    objc_setAssociatedObject(dockView, HBLastDockSizeSignatureKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSHashTable<UIView *> *HBKnownDockHosts(void) {
    static NSHashTable<UIView *> *hosts = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hosts = [NSHashTable weakObjectsHashTable];
    });
    return hosts;
}

static void HBRegisterDockHost(UIView *dockView) {
    if (dockView != nil) [HBKnownDockHosts() addObject:dockView];
}

static void HBRefreshAllDockHosts(void) {
    for (UIView *dockView in HBKnownDockHosts().allObjects) {
        if (dockView.window != nil) {
            HBApplyDockBackgroundPreference(dockView);
            HBRefreshDockIconSizes(dockView);
            HBApplyPositionPreference(dockView);
        }
    }
}

static void HBScheduleRunningIndicatorPoll(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        static NSUInteger dynamicFallbackTick = 0;
        if (HBDynamicRunningAppsEnabled() &&
            (++dynamicFallbackTick % 3) == 0) {
            // Lifecycle hooks are immediate on iOS 16.7.x. This six-second
            // invalidation is only a safety net for a missed private callback.
            HBApplicationStateGeneration++;
        }
        if (HBRunningIndicatorsEnabled() || HBBadgeBounceEnabled() ||
            HBDynamicRunningAppsEnabled()) {
            HBRefreshAllDockHosts();
        }
        for(UIView*dock in HBKnownDockHosts().allObjects)HBApplyPositionPreference(dock);
        HBScheduleRunningIndicatorPoll();
    });
}

static void HBScheduleApplicationStateRefresh(void) {
    NSUInteger generation = ++HBApplicationRefreshScheduleGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(0.08 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != HBApplicationRefreshScheduleGeneration) return;
        HBApplicationStateGeneration++;
        HBRefreshAllDockHosts();
    });
}

static void HBScheduleDockCountRefresh(void) {
    NSUInteger generation = ++HBDockCountRefreshScheduleGeneration;
    // didMoveToSuperview fires for every intermediate reparenting step. Wait
    // until the burst finishes so a temporary count of 1 or 2 never becomes
    // the scale used by the whole Dock.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(0.22 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != HBDockCountRefreshScheduleGeneration) return;
        if (HBIconManagerIsDraggingIcon()) {
            HBScheduleDockCountRefresh();
            return;
        }
        for (UIView *dockView in HBKnownDockHosts().allObjects) {
            HBInvalidateDockSizeSignature(dockView);
        }
        HBRefreshAllDockHosts();
    });
}

static id HBObjectForZeroArgumentSelector(id object, NSString *selectorName) {
    if (object == nil || selectorName.length == 0) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *HBIdentifierForModelIcon(id icon) {
    if (icon == nil) return nil;
    for (NSString *selectorName in @[@"applicationBundleIdentifier",
                                      @"bundleIdentifier",
                                      @"uniqueIdentifier",
                                      @"leafIdentifier"]) {
        id value = HBObjectForZeroArgumentSelector(icon, selectorName);
        if ([value isKindOfClass:NSString.class] &&
            [(NSString *)value length] > 0) return value;
        @try {
            value = [icon valueForKey:selectorName];
            if ([value isKindOfClass:NSString.class] &&
                [(NSString *)value length] > 0) return value;
        } @catch (__unused NSException *exception) {
        }
    }
    return nil;
}

static id HBApplicationForModelIcon(id icon) {
    id application = HBObjectForZeroArgumentSelector(icon, @"application");
    if (application != nil) return application;

    NSString *bundleIdentifier = HBIdentifierForModelIcon(icon);
    Class controllerClass = NSClassFromString(@"SBApplicationController");
    if (bundleIdentifier.length == 0 || controllerClass == Nil) return nil;
    id controller = nil;
    if ([controllerClass respondsToSelector:@selector(sharedInstanceIfExists)]) {
        controller = [(id)controllerClass sharedInstanceIfExists];
    }
    if (controller == nil &&
        [controllerClass respondsToSelector:@selector(sharedInstance)]) {
        controller = [(id)controllerClass sharedInstance];
    }
    if ([controller respondsToSelector:
            @selector(applicationWithBundleIdentifier:)]) {
        return [controller applicationWithBundleIdentifier:bundleIdentifier];
    }
    if ([controller respondsToSelector:
            @selector(applicationForBundleIdentifier:)]) {
        return [controller applicationForBundleIdentifier:bundleIdentifier];
    }
    return nil;
}

static BOOL HBApplicationObjectIsRunning(id application) {
    if (application == nil) return NO;
    @try {
        id processState = HBObjectForZeroArgumentSelector(application,
                                                          @"processState");
        SEL runningSelector = NSSelectorFromString(@"isRunning");
        if ([processState respondsToSelector:runningSelector]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(processState,
                                                     runningSelector);
        }
        if ([application respondsToSelector:runningSelector]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(application,
                                                     runningSelector);
        }
        SEL activationSelector = NSSelectorFromString(@"activationState");
        if ([application respondsToSelector:activationSelector]) {
            return ((int (*)(id, SEL))objc_msgSend)(application,
                                                    activationSelector) != 0;
        }
        for (NSString *key in @[@"running", @"activationState"]) {
            @try {
                id value = [application valueForKey:key];
                if ([value respondsToSelector:@selector(integerValue)]) {
                    return [value integerValue] > 0;
                }
            } @catch (__unused NSException *exception) {
            }
        }
    } @catch (__unused NSException *exception) {
    }
    return NO;
}

static NSString *HBIdentifierForApplicationObject(id application) {
    if (application == nil) return nil;
    for (NSString *selectorName in @[@"bundleIdentifier",
                                      @"applicationBundleIdentifier",
                                      @"displayIdentifier"]) {
        id value = HBObjectForZeroArgumentSelector(application, selectorName);
        if ([value isKindOfClass:NSString.class] &&
            [(NSString *)value length] > 0) return value;
    }
    return nil;
}

static NSMutableSet<NSString *> *HBUserPresentedApplications(void) {
    if (HBUserPresentedApplicationIdentifiers == nil) {
        HBUserPresentedApplicationIdentifiers = [NSMutableSet set];
    }
    return HBUserPresentedApplicationIdentifiers;
}

static BOOL HBApplicationObjectIsForeground(id application) {
    if (application == nil) return NO;
    @try {
        id processState = HBObjectForZeroArgumentSelector(application,
                                                          @"processState");
        SEL selector = NSSelectorFromString(@"isForeground");
        if ([processState respondsToSelector:selector]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(processState, selector);
        }
        if ([application respondsToSelector:selector]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(application, selector);
        }
    } @catch (__unused NSException *exception) {
    }
    return NO;
}

static void HBUpdateUserPresentedApplication(id application) {
    NSString *identifier = HBIdentifierForApplicationObject(application);
    if (identifier.length == 0 ||
        [identifier isEqualToString:@"com.apple.springboard"]) return;
    if (!HBApplicationObjectIsRunning(application)) {
        [HBUserPresentedApplications() removeObject:identifier];
    } else if (HBApplicationObjectIsForeground(application)) {
        // A process is admitted only after it has genuinely occupied the
        // foreground. Prewarming and background-only services never qualify.
        [HBUserPresentedApplications() addObject:identifier];
    }
}

static BOOL HBModelIconIsRunning(id icon) {
    id application = HBApplicationForModelIcon(icon);
    NSString *identifier = HBIdentifierForApplicationObject(application);
    return identifier.length > 0 && HBApplicationObjectIsRunning(application) &&
           [HBUserPresentedApplications() containsObject:identifier];
}

static NSString *HBDisplayNameForModelIcon(id icon) {
    for (NSString *selectorName in @[@"displayName", @"localizedDisplayName"]) {
        id value = HBObjectForZeroArgumentSelector(icon, selectorName);
        if ([value isKindOfClass:NSString.class] &&
            [(NSString *)value length] > 0) return value;
    }
    id application = HBApplicationForModelIcon(icon);
    for (NSString *selectorName in @[@"displayName", @"localizedDisplayName"]) {
        id value = HBObjectForZeroArgumentSelector(application, selectorName);
        if ([value isKindOfClass:NSString.class] &&
            [(NSString *)value length] > 0) return value;
    }
    return HBIdentifierForModelIcon(icon);
}

static UIImage *HBImageFromIconImageCarrier(id carrier) {
    if (carrier == nil) return nil;
    if ([carrier isKindOfClass:UIImage.class]) return carrier;
    if ([carrier isKindOfClass:UIImageView.class]) {
        UIImage *image = ((UIImageView *)carrier).image;
        if (image != nil) return image;
    }
    for (NSString *selectorName in @[@"iconImageSnapshot", @"displayedImage",
                                      @"contentsImage", @"squareContentsImage"]) {
        id image = HBObjectForZeroArgumentSelector(carrier, selectorName);
        if ([image isKindOfClass:UIImage.class]) return image;
    }
    for (NSString *selectorName in @[@"currentImageView", @"_iconImageView"]) {
        id nested = HBObjectForZeroArgumentSelector(carrier, selectorName);
        if (nested == nil || nested == carrier) continue;
        UIImage *image = HBImageFromIconImageCarrier(nested);
        if (image != nil) return image;
    }
    return nil;
}

static UIView *HBCreateNativeIconImageView(id icon, id manager) {
    Class imageViewClass = NSClassFromString(@"SBIconImageView");
    if (imageViewClass == Nil ||
        ![imageViewClass isSubclassOfClass:UIView.class]) return nil;
    UIView *imageView = nil;
    @try {
        imageView = [[imageViewClass alloc]
            initWithFrame:CGRectMake(0.0, 0.0, 60.0, 60.0)];
        imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                     UIViewAutoresizingFlexibleHeight;
        imageView.userInteractionEnabled = NO;

        id imageCache = HBObjectForZeroArgumentSelector(manager,
                                                         @"iconImageCache");
        SEL cacheSelector = NSSelectorFromString(@"setIconImageCache:");
        if (imageCache != nil &&
            [imageView respondsToSelector:cacheSelector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(imageView,
                                                  cacheSelector,
                                                  imageCache);
        }
        SEL infoSelector = NSSelectorFromString(@"setIconImageInfo:");
        if ([imageView respondsToSelector:infoSelector]) {
            HBModernIconImageInfo info = {
                CGSizeMake(60.0, 60.0), UIScreen.mainScreen.scale, 13.5
            };
            ((void (*)(id, SEL, HBModernIconImageInfo))objc_msgSend)(
                imageView, infoSelector, info);
        }
        SEL iconSelector = NSSelectorFromString(@"setIcon:location:animated:");
        if ([imageView respondsToSelector:iconSelector]) {
            ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(
                imageView, iconSelector, icon, @"SBIconLocationDock", NO);
        } else {
            @try {
                [imageView setValue:icon forKey:@"icon"];
                [imageView setValue:@"SBIconLocationDock" forKey:@"location"];
            } @catch (__unused NSException *exception) {
                return nil;
            }
        }
        SEL updateSelector = NSSelectorFromString(@"updateImageAnimated:");
        if ([imageView respondsToSelector:updateSelector]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(imageView,
                                                    updateSelector,
                                                    NO);
        }
    } @catch (__unused NSException *exception) {
        return nil;
    }
    return imageView;
}

static UIImage *HBImageForModelIcon(id icon, id manager) {
    SEL viewSelector = NSSelectorFromString(@"firstIconViewForIcon:");
    if ([manager respondsToSelector:viewSelector]) {
        @try {
            id iconView = ((id (*)(id, SEL, id))objc_msgSend)(manager,
                                                              viewSelector,
                                                              icon);
            UIImage *image = HBImageFromIconImageCarrier(iconView);
            if (image != nil) return image;
            UIView *imageView = [iconView isKindOfClass:UIView.class]
                ? HBIconImageView(iconView) : nil;
            image = HBImageFromIconImageCarrier(imageView);
            if (image != nil) return image;
        } @catch (__unused NSException *exception) {
        }
    }

    HBModernIconImageInfo info = {
        CGSizeMake(60.0, 60.0), UIScreen.mainScreen.scale, 13.5
    };
    for (NSString *selectorName in @[@"generateIconImageWithInfo:",
                                      @"genericIconImageWithInfo:"]) {
        SEL imageSelector = NSSelectorFromString(selectorName);
        if (![icon respondsToSelector:imageSelector]) continue;
        @try {
            id image = ((id (*)(id, SEL, HBModernIconImageInfo))objc_msgSend)(
                icon, imageSelector, info);
            if ([image isKindOfClass:UIImage.class]) return image;
        } @catch (__unused NSException *exception) {
        }
    }

    // Read the model icon's cache directly; generating is the final fallback
    // and happens only once when a temporary icon is first inserted.
    for (NSString *selectorName in @[@"getIconImage:",
                                      @"generateIconImage:"]) {
        SEL imageSelector = NSSelectorFromString(selectorName);
        if (![icon respondsToSelector:imageSelector]) continue;
        for (NSNumber *format in @[@2, @0, @1]) {
            @try {
                id image = ((id (*)(id, SEL, int))objc_msgSend)(
                    icon, imageSelector, format.intValue);
                if ([image isKindOfClass:UIImage.class]) return image;
            } @catch (__unused NSException *exception) {
            }
        }
    }
    return nil;
}

static NSArray *HBRunningModelIcons(id manager) {
    if (HBCachedRunningIconsGeneration == HBApplicationStateGeneration &&
        HBCachedRunningModelIcons != nil) {
        return HBCachedRunningModelIcons;
    }
    id iconModel = HBObjectForZeroArgumentSelector(manager, @"iconModel");
    id leafCollection = HBObjectForZeroArgumentSelector(iconModel, @"leafIcons");
    NSArray *leafIcons = nil;
    if ([leafCollection isKindOfClass:NSSet.class]) {
        leafIcons = [(NSSet *)leafCollection allObjects];
    } else if ([leafCollection isKindOfClass:NSArray.class]) {
        leafIcons = leafCollection;
    }

    NSMutableArray *running = [NSMutableArray array];
    for (id icon in leafIcons) {
        NSString *className = NSStringFromClass([icon class]);
        if ([className rangeOfString:@"ApplicationIcon"
                             options:NSCaseInsensitiveSearch].location ==
            NSNotFound) continue;
        NSString *identifier = HBIdentifierForModelIcon(icon);
        if (identifier.length == 0 ||
            [identifier isEqualToString:@"com.apple.springboard"] ||
            !HBModelIconIsRunning(icon)) continue;
        [running addObject:icon];
    }
    HBCachedRunningModelIcons = [running copy];
    HBCachedRunningIconsGeneration = HBApplicationStateGeneration;
    return HBCachedRunningModelIcons;
}

static void HBLaunchApplicationBundleIdentifier(NSString *bundleIdentifier) {
    if (bundleIdentifier.length == 0) return;
    UIApplication *application = UIApplication.sharedApplication;
    SEL launchSelector =
        NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    if ([application respondsToSelector:launchSelector]) {
        ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(
            application, launchSelector, bundleIdentifier, NO);
        return;
    }
    id modelApplication = nil;
    Class controllerClass = NSClassFromString(@"SBApplicationController");
    if ([controllerClass respondsToSelector:@selector(sharedInstance)]) {
        id controller = [(id)controllerClass sharedInstance];
        if ([controller respondsToSelector:
                @selector(applicationWithBundleIdentifier:)]) {
            modelApplication = [controller
                applicationWithBundleIdentifier:bundleIdentifier];
        }
    }
    SEL activateSelector = NSSelectorFromString(@"activate");
    if ([modelApplication respondsToSelector:activateSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(modelApplication, activateSelector);
    }
}

static void HBRemoveAllDynamicRunningViews(UIView *dockView,
                                           NSMutableDictionary *views) {
    for (HBDynamicRunningIconView *view in views.allValues) {
        HBUpdateRunningIndicator(view, nil);
        [view.layer removeAllAnimations];
        [view removeFromSuperview];
    }
    [views removeAllObjects];
    objc_setAssociatedObject(dockView, HBLastDockSizeSignatureKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void HBUpdateDynamicRunningAppsForDock(UIView *dockView) {
    if (dockView == nil) return;
    NSMutableDictionary<NSString *, HBDynamicRunningIconView *> *views =
        objc_getAssociatedObject(dockView, HBDynamicRunningViewsKey);
    if (views == nil) {
        views = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(dockView, HBDynamicRunningViewsKey, views,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!HBEnabled() || !HBExtraDockAppsEnabled() ||
        !HBDynamicRunningAppsEnabled()) {
        if (views.count > 0) HBRemoveAllDynamicRunningViews(dockView, views);
        return;
    }
    if (HBIconManagerIsEditingOrDragging()) return;

    Class controllerClass = NSClassFromString(@"SBIconController");
    if (controllerClass == Nil ||
        ![controllerClass respondsToSelector:@selector(sharedInstance)]) return;
    id controller = [(id)controllerClass sharedInstance];
    id manager = [controller respondsToSelector:@selector(iconManager)]
        ? [controller iconManager] : nil;
    if (manager == nil) return;

    NSMutableSet<NSString *> *pinnedIdentifiers = [NSMutableSet set];
    NSMutableArray<UIView *> *nativeViews = [NSMutableArray array];
    for (UIView *iconView in HBVisibleDockIconViews(dockView)) {
        if ([iconView isKindOfClass:HBDynamicRunningIconView.class]) continue;
        [nativeViews addObject:iconView];
        NSString *identifier = HBIconBundleIdentifier(iconView);
        if (identifier.length > 0) [pinnedIdentifiers addObject:identifier];
    }

    NSMutableDictionary<NSString *, id> *desiredIcons =
        [NSMutableDictionary dictionary];
    for (id icon in HBRunningModelIcons(manager)) {
        NSString *identifier = HBIdentifierForModelIcon(icon);
        if (identifier.length > 0 &&
            ![pinnedIdentifiers containsObject:identifier]) {
            desiredIcons[identifier] = icon;
        }
    }

    BOOL changed = NO;
    for (NSString *identifier in [views.allKeys copy]) {
        if (desiredIcons[identifier] != nil) continue;
        HBDynamicRunningIconView *view = views[identifier];
        HBUpdateRunningIndicator(view, nil);
        [view.layer removeAllAnimations];
        [view removeFromSuperview];
        [views removeObjectForKey:identifier];
        changed = YES;
    }

    CGFloat nativeCenterY = CGRectGetMidY(dockView.bounds);
    if (nativeViews.count > 0) {
        CGFloat total = 0.0;
        for (UIView *view in nativeViews) {
            total += [view.superview convertPoint:view.center
                                            toView:dockView].y;
        }
        nativeCenterY = total / (CGFloat)nativeViews.count;
    }
    for (NSString *identifier in desiredIcons) {
        id icon = desiredIcons[identifier];
        HBDynamicRunningIconView *view = views[identifier];
        if (view == nil) {
            UIImage *image = HBImageForModelIcon(icon, manager);
            UIView *nativeImageView = image == nil
                ? HBCreateNativeIconImageView(icon, manager) : nil;
            view = [[HBDynamicRunningIconView alloc]
                initWithBundleIdentifier:identifier modelIcon:icon image:image];
            view.sequence = ++HBDynamicRunningSequence;
            view.accessibilityLabel = HBDisplayNameForModelIcon(icon);
            view.center = CGPointMake(CGRectGetMidX(dockView.bounds),
                                      nativeCenterY);
            if (nativeImageView != nil) {
                [view.iconImageView removeFromSuperview];
                nativeImageView.frame = view.bounds;
                view.iconImageView = nativeImageView;
                [view insertSubview:nativeImageView atIndex:0];
            } else if (image == nil) {
                view.iconImageView.backgroundColor =
                    [UIColor colorWithWhite:0.22 alpha:1.0];
                UILabel *fallback = [[UILabel alloc] initWithFrame:view.bounds];
                fallback.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                            UIViewAutoresizingFlexibleHeight;
                fallback.textAlignment = NSTextAlignmentCenter;
                fallback.textColor = UIColor.whiteColor;
                fallback.font = [UIFont boldSystemFontOfSize:24.0];
                NSString *name = HBDisplayNameForModelIcon(icon);
                fallback.text = name.length > 0 ? [name substringToIndex:1] : @"•";
                fallback.userInteractionEnabled = NO;
                [view addSubview:fallback];
            }
            [dockView addSubview:view];
            views[identifier] = view;
            changed = YES;
        } else {
            view.modelIcon = icon;
            if (view.superview != dockView) {
                [dockView addSubview:view];
                changed = YES;
            }
        }
        [dockView bringSubviewToFront:view];
    }
    if (changed) {
        objc_setAssociatedObject(dockView, HBLastDockSizeSignatureKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// First-install random Dock insertion removed: users arrange their own icons.

static void HBPreferencesChanged(CFNotificationCenterRef center,
                                 void *observer,
                                 CFStringRef name,
                                 const void *object,
                                 CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        [HBPreferences() synchronize];
        for (UIView *dockView in HBKnownDockHosts().allObjects) {
            HBInvalidateDockSizeSignature(dockView);
        }
        for (UIView *rootView in HBKnownRootFolderViews().allObjects) {
            HBApplyHomeSearchPreference(rootView);
        }
        HBShowDocksAndScheduleAutoHide();
        for(UIView*dock in HBKnownDockHosts().allObjects)HBApplyPositionPreference(dock);
        HBScheduleDockCountRefresh();
    });
}

static CGFloat HBScaleMagnitude(CGAffineTransform transform) {
    CGFloat horizontal = hypot(transform.a, transform.b);
    CGFloat vertical = hypot(transform.c, transform.d);
    CGFloat magnitude = (horizontal + vertical) * 0.5;
    return magnitude > 0.001 && isfinite(magnitude) ? magnitude : 1.0;
}

static void HBCaptureIconState(
    UIView *dockView,
    NSMapTable<UIView *, NSValue *> *baseTransforms,
    NSMapTable<UIView *, NSNumber *> *baseZPositions) {
    for (UIView *iconView in HBVisibleDockIconViews(dockView)) {
        if ([baseTransforms objectForKey:iconView] == nil) {
            [baseTransforms setObject:[NSValue valueWithCGAffineTransform:iconView.transform]
                                forKey:iconView];
            [baseZPositions setObject:@(iconView.layer.zPosition) forKey:iconView];
        }
    }
}

static UIView *HBApplyMagnification(
    UIView *dockView,
    CGPoint focus,
    NSMapTable<UIView *, NSValue *> *baseTransforms,
    NSMapTable<UIView *, NSNumber *> *baseZPositions) {
    HBCaptureIconState(dockView, baseTransforms, baseZPositions);
    CGFloat influenceRadius = HBInfluenceRadius();
    CGFloat maximumScale = HBMaximumScale();

    NSArray<UIView *> *icons = HBVisibleDockIconViews(dockView);
    if (icons.count == 0) return nil;
    CGFloat minimumX = CGFLOAT_MAX;
    CGFloat maximumX = -CGFLOAT_MAX;
    CGFloat minimumY = CGFLOAT_MAX;
    CGFloat maximumY = -CGFLOAT_MAX;
    for (UIView *iconView in icons) {
        CGPoint center = [iconView.superview convertPoint:iconView.center toView:dockView];
        minimumX = MIN(minimumX, center.x);
        maximumX = MAX(maximumX, center.x);
        minimumY = MIN(minimumY, center.y);
        maximumY = MAX(maximumY, center.y);
    }
    BOOL horizontal = (maximumX - minimumX) >= (maximumY - minimumY);
    UIView *highlightedIconView = nil;
    CGFloat strongestInfluence = 0.0;

    for (UIView *iconView in icons) {
        NSValue *baseValue = [baseTransforms objectForKey:iconView];
        if (baseValue == nil) continue;

        CGPoint center = [iconView.superview convertPoint:iconView.center toView:dockView];
        CGFloat distance = horizontal ? fabs(center.x - focus.x) : fabs(center.y - focus.y);
        CGFloat influence = MAX(0.0, 1.0 - (distance / influenceRadius));
        CGFloat easedInfluence = 0.5 - (0.5 * cos(influence * M_PI));
        if (easedInfluence > strongestInfluence) {
            strongestInfluence = easedInfluence;
            highlightedIconView = iconView;
        }

        CGAffineTransform baseTransform = baseValue.CGAffineTransformValue;
        CGFloat baseScale = HBScaleMagnitude(baseTransform);
        CGFloat contentScale = HBEffectiveDockIconScale(iconView);
        CGFloat restingVisualScale = baseScale * contentScale;
        CGFloat focusedVisualScale = MAX(maximumScale, restingVisualScale);
        CGFloat targetVisualScale = restingVisualScale +
            ((focusedVisualScale - restingVisualScale) * easedInfluence);
        CGFloat targetOuterScale = targetVisualScale / contentScale;
        CGFloat relativeScale = targetOuterScale / baseScale;
        CGFloat lift = -HBLiftDistance() * easedInfluence;

        CGAffineTransform harborTransform = horizontal
            ? CGAffineTransformMakeTranslation(0.0, lift)
            : CGAffineTransformMakeTranslation(lift, 0.0);
        harborTransform = CGAffineTransformScale(harborTransform,
                                                 relativeScale,
                                                 relativeScale);
        iconView.transform = CGAffineTransformConcat(baseTransform, harborTransform);
        iconView.layer.zPosition =
            [[baseZPositions objectForKey:iconView] doubleValue] +
            (easedInfluence * 1000.0);
    }
    HBUpdateSlimDockBackground(dockView, NO);
    return strongestInfluence > 0.0 ? highlightedIconView : nil;
}

static BOOL HBIconViewIsPlaceholder(UIView *iconView) {
    @try {
        id icon = [iconView valueForKey:@"icon"];
        if (icon == nil) return YES;
        return [NSStringFromClass([icon class]) containsString:@"Placeholder"];
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static NSString *HBDisplayNameForIconView(UIView *iconView) {
    @try {
        id icon = [iconView valueForKey:@"icon"];
        for (NSString *key in @[@"displayName", @"localizedDisplayName"]) {
            id value = [icon valueForKey:key];
            if ([value isKindOfClass:NSString.class] &&
                [(NSString *)value length] > 0) return value;
        }
    } @catch (__unused NSException *exception) {
    }
    NSString *label = iconView.accessibilityLabel;
    return label.length > 0 ? label : nil;
}

static BOOL HBCanLaunchDockIconView(UIView *iconView, UIView *dockView) {
    return iconView != nil && dockView != nil && iconView.window != nil &&
           !iconView.hidden && iconView.alpha > 0.01 &&
           [iconView isDescendantOfView:dockView] &&
           HBIconViewIsInDock(iconView) &&
           !HBIconViewIsPlaceholder(iconView) &&
           [iconView respondsToSelector:@selector(_handleTap)];
}

static void HBLaunchDockIconView(UIView *iconView, UIView *dockView) {
    if (!HBCanLaunchDockIconView(iconView, dockView)) return;
    if (!HBLaunchBounceEnabled()) {
        [(SBIconView *)iconView _handleTap];
        return;
    }
    CAKeyframeAnimation *bounce = [CAKeyframeAnimation
        animationWithKeyPath:@"transform.translation.y"];
    bounce.values = @[@0.0, @-15.0, @0.0, @-8.0, @0.0];
    bounce.keyTimes = @[@0.0, @0.30, @0.55, @0.75, @1.0];
    bounce.duration = 0.32;
    bounce.additive = YES;
    [iconView.layer addAnimation:bounce forKey:@"HarborLaunchBounce"];
    __weak UIView *weakIconView = iconView;
    __weak UIView *weakDockView = dockView;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(0.18 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIView *strongIconView = weakIconView;
        UIView *strongDockView = weakDockView;
        if (HBCanLaunchDockIconView(strongIconView, strongDockView)) {
            [(SBIconView *)strongIconView _handleTap];
        }
    });
}

static void HBRestoreIcons(
    UIView *dockView,
    NSMapTable<UIView *, NSValue *> *baseTransforms,
    NSMapTable<UIView *, NSNumber *> *baseZPositions,
    BOOL animated) {
    NSArray<UIView *> *icons = baseTransforms.keyEnumerator.allObjects;
    void (^changes)(void) = ^{
        for (UIView *iconView in icons) {
            if (iconView.window == nil || ![iconView isDescendantOfView:dockView]) continue;
            NSValue *transformValue = [baseTransforms objectForKey:iconView];
            NSNumber *zPosition = [baseZPositions objectForKey:iconView];
            if (transformValue != nil) {
                iconView.transform = transformValue.CGAffineTransformValue;
            }
            if (zPosition != nil) iconView.layer.zPosition = zPosition.doubleValue;
        }
        HBUpdateSlimDockBackground(dockView, NO);
    };

    void (^completion)(BOOL) = ^(BOOL finished) {
        (void)finished;
        [baseTransforms removeAllObjects];
        [baseZPositions removeAllObjects];
    };

    if (animated) {
        [UIView animateWithDuration:HBAnimationDuration()
                              delay:0.0
             usingSpringWithDamping:0.86
              initialSpringVelocity:0.25
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:changes
                         completion:completion];
    } else {
        changes();
        completion(YES);
    }
}

@interface HBDockGestureTarget : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *dockView;
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, strong) NSMapTable<UIView *, NSValue *> *baseTransforms;
@property(nonatomic, strong) NSMapTable<UIView *, NSNumber *> *baseZPositions;
@property(nonatomic, weak) UIView *highlightedIconView;
@property(nonatomic, strong) UILabel *appNameLabel;
@property(nonatomic, strong) UIView *selectionGlow;
@property(nonatomic, strong) UIColor *selectionColor;
@property(nonatomic, strong) UISelectionFeedbackGenerator *selectionFeedback;
@property(nonatomic) CGPoint currentFocus;
@property(nonatomic) CGPoint targetFocus;
@property(nonatomic) BOOL launchInProgress;
- (instancetype)initWithDockView:(UIView *)dockView;
- (void)handlePan:(UIPanGestureRecognizer *)recognizer;
- (void)displayLinkFired:(CADisplayLink *)displayLink;
@end

@implementation HBDockGestureTarget

- (instancetype)initWithDockView:(UIView *)dockView {
    self = [super init];
    if (self) _dockView = dockView;
    return self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    (void)gestureRecognizer;
    // SpringBoard page scrolling uses a pan recognizer. Coexist with it so a
    // horizontal swipe that starts near the Dock never stalls page movement.
    return [otherGestureRecognizer isKindOfClass:UIPanGestureRecognizer.class] ||
           [otherGestureRecognizer isKindOfClass:UISwipeGestureRecognizer.class];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (![gestureRecognizer isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    UIView *dockView = self.dockView;
    if (!HBEnabled() || dockView == nil || HBCircularDockActive(dockView) || self.launchInProgress ||
        HBIconManagerIsEditingOrDragging()) {
        return NO;
    }

    NSValue *restingFrameValue = objc_getAssociatedObject(
        dockView, HBSlimDockRestingFrameKey);
    if ([restingFrameValue isKindOfClass:NSValue.class]) {
        CGRect activeStrip = CGRectInset(restingFrameValue.CGRectValue,
                                         -10.0, -8.0);
        CGPoint touch = [gestureRecognizer locationInView:dockView];
        if (!CGRectContainsPoint(activeStrip, touch)) return NO;
    }

    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer
        velocityInView:dockView];
    BOOL horizontal = CGRectGetWidth(dockView.bounds) >=
                      CGRectGetHeight(dockView.bounds);
    return horizontal ? fabs(velocity.x) > fabs(velocity.y)
                      : fabs(velocity.y) > fabs(velocity.x);
}

- (void)startDisplayLinkIfNeeded {
    if (self.displayLink != nil) return;
    self.displayLink = [CADisplayLink displayLinkWithTarget:self
                                                   selector:@selector(displayLinkFired:)];
    if (@available(iOS 15.0, *)) {
        self.displayLink.preferredFrameRateRange =
            CAFrameRateRangeMake(30.0, 60.0, 60.0);
    }
    [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)stopDisplayLink {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (void)hideSelectionUI {
    [self.appNameLabel removeFromSuperview];
    self.appNameLabel = nil;
    [self.selectionGlow removeFromSuperview];
    self.selectionGlow = nil;
    self.selectionFeedback = nil;
    self.selectionColor = nil;
}

- (void)updateSelectionUIForIconView:(UIView *)iconView {
    BOOL changed = self.highlightedIconView != iconView;
    self.highlightedIconView = iconView;

    if (changed && iconView != nil && HBHapticFeedbackEnabled()) {
        if (self.selectionFeedback == nil) {
            self.selectionFeedback = [[UISelectionFeedbackGenerator alloc] init];
            [self.selectionFeedback prepare];
        }
        [self.selectionFeedback selectionChanged];
        [self.selectionFeedback prepare];
    }

    if (iconView == nil || self.dockView.window == nil) {
        [self hideSelectionUI];
        return;
    }

    UIView *imageView = HBIconImageView(iconView) ?: iconView;
    CGRect iconRect = [imageView convertRect:imageView.bounds
                                      toView:self.dockView.window];
    if (HBSelectionGlowEnabled()) {
        if (changed || self.selectionColor == nil) {
            UIImage *artwork = HBImageFromIconImageCarrier(imageView);
            if (artwork == nil) artwork = HBImageFromIconImageCarrier(iconView);
            self.selectionColor = HBSelectionColorForImage(artwork);
        }
        UIColor *selectionColor = self.selectionColor ?: [UIColor colorWithWhite:0.72 alpha:1.0];
        if (self.selectionGlow == nil) {
            UIView *glow = [[UIView alloc] initWithFrame:CGRectZero];
            glow.userInteractionEnabled = NO;
            glow.backgroundColor = UIColor.clearColor;
            glow.layer.borderWidth = 2.0;

            glow.layer.shadowOpacity = 0.85;
            glow.layer.shadowRadius = 8.0;
            glow.layer.shadowOffset = CGSizeZero;
            CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
            pulse.fromValue = @0.55;
            pulse.toValue = @1.0;
            pulse.duration = 0.55;
            pulse.autoreverses = YES;
            pulse.repeatCount = HUGE_VALF;
            [glow.layer addAnimation:pulse forKey:@"HarborSelectionPulse"];
            self.selectionGlow = glow;
            [self.dockView.window addSubview:glow];
        }
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.selectionGlow.layer.borderColor = [selectionColor colorWithAlphaComponent:0.95].CGColor;
        self.selectionGlow.layer.shadowColor = selectionColor.CGColor;
        [CATransaction commit];
        self.selectionGlow.frame = CGRectInset(iconRect, -4.0, -4.0);
        self.selectionGlow.layer.cornerRadius =
            MIN(CGRectGetWidth(self.selectionGlow.bounds),
                CGRectGetHeight(self.selectionGlow.bounds)) * 0.23;
    } else {
        [self.selectionGlow removeFromSuperview];
        self.selectionGlow = nil;
    }

    if (!HBShowAppNameEnabled()) {
        [self.appNameLabel removeFromSuperview];
        self.appNameLabel = nil;
        return;
    }

    NSString *name = HBDisplayNameForIconView(iconView);
    if (name.length == 0) {
        [self.appNameLabel removeFromSuperview];
        self.appNameLabel = nil;
        return;
    }
    if (self.appNameLabel == nil) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        label.textColor = UIColor.whiteColor;
        label.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.82];
        label.textAlignment = NSTextAlignmentCenter;
        label.layer.cornerRadius = 9.0;
        label.layer.masksToBounds = YES;
        self.appNameLabel = label;
        [self.dockView.window addSubview:label];
    }
    self.appNameLabel.text = name;
    CGSize size = [self.appNameLabel sizeThatFits:CGSizeMake(220.0, 28.0)];
    CGFloat width = MIN(220.0, MAX(54.0, size.width + 20.0));
    CGFloat x = CGRectGetMidX(iconRect) - width * 0.5;
    x = MAX(8.0, MIN(x, CGRectGetWidth(self.dockView.window.bounds) - width - 8.0));
    self.appNameLabel.frame = CGRectMake(x, CGRectGetMinY(iconRect) - 34.0,
                                         width, 26.0);
}

- (void)beginTrackingAtPoint:(CGPoint)focus {
    HBShowDocksAndScheduleAutoHide();
    HBRefreshDockIconSizes(self.dockView);
    self.baseTransforms = [NSMapTable strongToStrongObjectsMapTable];
    self.baseZPositions = [NSMapTable strongToStrongObjectsMapTable];
    HBCaptureIconState(self.dockView, self.baseTransforms, self.baseZPositions);
    self.currentFocus = focus;
    self.targetFocus = focus;
    objc_setAssociatedObject(self.dockView, HBMagnificationActiveKey,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *highlighted = HBApplyMagnification(
        self.dockView, focus, self.baseTransforms, self.baseZPositions);
    [self updateSelectionUIForIconView:highlighted];
    [self startDisplayLinkIfNeeded];
}

- (void)displayLinkFired:(CADisplayLink *)displayLink {
    (void)displayLink;
    UIView *dockView = self.dockView;
    if (dockView == nil || self.baseTransforms == nil) {
        [self stopDisplayLink];
        return;
    }

    CGFloat differenceX = self.targetFocus.x - self.currentFocus.x;
    CGFloat differenceY = self.targetFocus.y - self.currentFocus.y;
    self.currentFocus = CGPointMake(self.currentFocus.x + (differenceX * 0.32),
                                    self.currentFocus.y + (differenceY * 0.32));
    if (fabs(differenceX) < 0.1 && fabs(differenceY) < 0.1) {
        self.currentFocus = self.targetFocus;
    }
    UIView *highlighted = HBApplyMagnification(
        dockView, self.currentFocus, self.baseTransforms, self.baseZPositions);
    [self updateSelectionUIForIconView:highlighted];
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    UIView *dockView = self.dockView;
    if (dockView == nil || !HBEnabled()) return;

    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
            [self beginTrackingAtPoint:[recognizer locationInView:dockView]];
            break;
        case UIGestureRecognizerStateChanged:
            self.targetFocus = [recognizer locationInView:dockView];
            break;
        case UIGestureRecognizerStateEnded: {
            [self stopDisplayLink];
            objc_setAssociatedObject(dockView, HBMagnificationActiveKey,
                                     @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            CGPoint releasePoint = [recognizer locationInView:dockView];
            CGRect activationBounds = CGRectInset(dockView.bounds, -24.0, -24.0);
            UIView *selectedIconView =
                HBLaunchOnReleaseEnabled() && !self.launchInProgress &&
                !HBIconManagerIsEditingOrDragging() &&
                CGRectContainsPoint(activationBounds, releasePoint)
                    ? self.highlightedIconView : nil;
            NSMapTable<UIView *, NSValue *> *transforms = self.baseTransforms;
            NSMapTable<UIView *, NSNumber *> *zPositions = self.baseZPositions;
            self.baseTransforms = nil;
            self.baseZPositions = nil;
            self.highlightedIconView = nil;
            [self hideSelectionUI];
            if (transforms != nil && zPositions != nil) {
                HBRestoreIcons(dockView, transforms, zPositions,
                               selectedIconView == nil);
            }
            if (selectedIconView != nil) {
                self.launchInProgress = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!HBIconManagerIsEditingOrDragging()) {
                        HBLaunchDockIconView(selectedIconView, dockView);
                    }
                    self.launchInProgress = NO;
                });
            }
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            [self stopDisplayLink];
            objc_setAssociatedObject(dockView, HBMagnificationActiveKey,
                                     @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSMapTable<UIView *, NSValue *> *transforms = self.baseTransforms;
            NSMapTable<UIView *, NSNumber *> *zPositions = self.baseZPositions;
            self.baseTransforms = nil;
            self.baseZPositions = nil;
            self.highlightedIconView = nil;
            [self hideSelectionUI];
            if (transforms != nil && zPositions != nil) {
                HBRestoreIcons(dockView, transforms, zPositions, YES);
            }
            break;
        }
        default:
            break;
    }
}

@end

static void HBAttachGestureIfNeeded(UIView *view) {
    if (!HBEnabled() || view == nil) return;
    UIView *dockView = HBOuterDockViewForView(view);
    HBRegisterDockHost(dockView);
    if (objc_getAssociatedObject(dockView, HBPanGestureKey) != nil) return;

    HBDockGestureTarget *target = [[HBDockGestureTarget alloc] initWithDockView:dockView];
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:target action:@selector(handlePan:)];
    pan.delegate = target;
    pan.cancelsTouchesInView = NO;
    pan.delaysTouchesBegan = NO;
    pan.delaysTouchesEnded = NO;
    pan.maximumNumberOfTouches = 1;
    [dockView addGestureRecognizer:pan];
    objc_setAssociatedObject(dockView, HBPanGestureKey, target,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%group HarborDockViewCore

%hook SBDockView

- (void)setAlpha:(CGFloat)alpha {
 HBCircularSetNativeAlpha((UIView*)self,alpha,^(CGFloat adjusted){
 %orig(adjusted);
 });
}

- (void)setCenter:(CGPoint)center {
 HBPositionSetNativeCenter((UIView*)self,center,^(CGPoint adjusted){%orig(adjusted);});
}
- (void)setFrame:(CGRect)frame {
 HBPositionSetNativeFrame((UIView*)self,frame,^(CGRect adjusted){%orig(adjusted);});
}


- (void)setBackgroundAlpha:(double)alpha {
    UIView *dockView = (UIView *)self;
    if (alpha > 0.0 &&
        objc_getAssociatedObject(dockView,
                                 HBOriginalDockBackgroundAlphaKey) == nil) {
        objc_setAssociatedObject(dockView,
                                 HBOriginalDockBackgroundAlphaKey,
                                 @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL hideNative = HBHideDockBackgroundEnabled() ||
                      HBSlimAdaptiveBackgroundEnabled();
    %orig(hideNative ? 0.0 : alpha);
    HBSetNativeDockMaterialHidden(dockView, hideNative);
}

- (void)didMoveToWindow {
    %orig;
    UIView *dockView = (UIView *)self;
    if (dockView.window != nil) {
        HBAttachGestureIfNeeded(dockView);
        HBShowDocksAndScheduleAutoHide();
    }
}

- (void)layoutSubviews {
    %orig;
    UIView *dockView = (UIView *)self;
    HBAttachGestureIfNeeded(dockView);
    HBApplyDockBackgroundPreference(dockView);
    HBApplyPositionPreference(dockView);
}

%end

%end

%group HarborHomeSearchAppearance

%hook SBRootFolderView

- (void)layoutSubviews {
    %orig;
    UIView *rootView = (UIView *)self;
    [HBKnownRootFolderViews() addObject:rootView];
    HBAttachAutoHideEdgeGestureIfNeeded(rootView);
    HBApplyHomeSearchPreference(rootView);
}

%end

%end


%group HarborRunningStateUpdates

%hook SBApplication

- (void)setRunning:(BOOL)running {
    %orig(running);
    dispatch_async(dispatch_get_main_queue(), ^{
        HBUpdateUserPresentedApplication(self);
        HBScheduleApplicationStateRefresh();
    });
}

%end

%end

%group HarborActivationStateUpdates

%hook SBApplication

- (void)_setActivationState:(int)state {
    %orig(state);
    dispatch_async(dispatch_get_main_queue(), ^{
        HBUpdateUserPresentedApplication(self);
        HBScheduleApplicationStateRefresh();
    });
}

%end

%end

%group HarborProcessStateUpdates

%hook SBApplication

- (void)_setInternalProcessState:(id)state {
    %orig(state);
    dispatch_async(dispatch_get_main_queue(), ^{
        HBUpdateUserPresentedApplication(self);
        HBScheduleApplicationStateRefresh();
    });
}

%end

%end

%group HarborNativeEditingTransitions
%hook SBHIconManager
- (void)setEditing:(BOOL)editing {
 %orig(editing);
 dispatch_async(dispatch_get_main_queue(), ^{
 for(UIView*dock in HBKnownDockHosts().allObjects)HBApplyPositionPreference(dock);
 });
}
%end
%end

%group HarborDockIconScaleLifecycle

%hook SBIconView

- (void)didMoveToSuperview {
    %orig;
    UIView *iconView = (UIView *)self;
    if (!HBIconViewIsInDock(iconView)) {
        HBUpdateRunningIndicator(iconView, nil);
        HBUpdateNotificationBadgeBounce(iconView);
        HBApplyDockIconSize(iconView);
        return;
    }
    // Never calculate a size from this transitional callback. The coalesced
    // count refresh below runs once after every Dock icon has settled.
    dispatch_async(dispatch_get_main_queue(), ^{
        HBScheduleDockCountRefresh();
    });
}

%end

%end

%group HarborDockIconScaleRefresh

%hook SBIconView

- (void)_updateIconImageViewAnimated:(BOOL)animated {
    %orig(animated);
    // Image refreshes happen for badges, focus, and wallpaper changes too.
    // Reuse the stable scale instead of treating each refresh as a new layout.
    UIView *iconView = (UIView *)self;
    HBReapplyCachedDockIconSize(iconView);
    dispatch_async(dispatch_get_main_queue(), ^{
        HBUpdateNotificationBadgeBounce(iconView);
    });
}

%end

%end

%group HarborDockListFallbackCore

%hook SBDockIconListView

- (void)setAlpha:(CGFloat)alpha {
 HBCircularSetNativeAlpha((UIView*)self,alpha,^(CGFloat adjusted){
 %orig(adjusted);
 });
}

- (void)setCenter:(CGPoint)center {
 HBPositionSetNativeCenter((UIView*)self,center,^(CGPoint adjusted){%orig(adjusted);});
}
- (void)setFrame:(CGRect)frame {
 HBPositionSetNativeFrame((UIView*)self,frame,^(CGRect adjusted){%orig(adjusted);});
}


- (void)didMoveToWindow {
    %orig;
    UIView *dockListView = (UIView *)self;
    if (dockListView.window != nil) HBAttachGestureIfNeeded(dockListView);
}

- (void)layoutSubviews {
    %orig;
    UIView *dockListView = (UIView *)self;
    HBAttachGestureIfNeeded(dockListView);
    UIView *dockView = HBOuterDockViewForView(dockListView);
    // Native iOS 16 can reset sparse Dock cells during layout. Reapply only
    // the lightweight center positions here; scaling and material work remain
    // protected by HBRefreshDockIconSizes's stable signature.
    HBDistributeDockIconCenters(dockView);
    HBRefreshDockIconSizes(dockView);
}

%end


%end

%group HarborModernIconListLayout

%hook SBIconListView

- (CGPoint)centerForIconAtIndex:(NSUInteger)index {
    CGPoint center = %orig(index);
    return HBCorrectedDockCenterForIndex((UIView *)self, index, center);
}

- (CGPoint)centerForIconAtIndex:(NSUInteger)index metrics:(id)metrics {
    CGPoint center = %orig(index, metrics);
    return HBCorrectedDockCenterForIndex((UIView *)self, index, center);
}

- (CGPoint)centerForIcon:(id)icon {
    CGPoint center = %orig(icon);
    NSUInteger index = [self indexOfIcon:icon];
    return HBCorrectedDockCenterForIndex((UIView *)self, index, center);
}

- (CGPoint)centerForIcon:(id)icon metrics:(id)metrics {
    CGPoint center = %orig(icon, metrics);
    NSUInteger index = [self indexOfIcon:icon];
    return HBCorrectedDockCenterForIndex((UIView *)self, index, center);
}

- (CGPoint)originForIconAtCoordinate:(SBIconCoordinate)coordinate
                             metrics:(id)metrics {
    CGPoint origin = %orig(coordinate, metrics);
    return HBCorrectedDockOriginForCoordinate(self, coordinate, metrics,
                                               origin);
}

- (CGPoint)originForIconAtCoordinate:(SBIconCoordinate)coordinate
                             metrics:(id)metrics
                             options:(NSUInteger)options {
    CGPoint origin = %orig(coordinate, metrics, options);
    return HBCorrectedDockOriginForCoordinate(self, coordinate, metrics,
                                               origin);
}

- (void)layoutSubviews {
    %orig;
    UIView *listView = (UIView *)self;
    if (HBEnabled() && HBExtraDockAppsEnabled() &&
        HBListViewIsInDock(listView)) {
        HBScheduleLateDockIconDistribution(listView);
    }
}

- (SBIconListFlowExtendedLayout *)layout {
    SBIconListFlowExtendedLayout *layout = %orig;
    if (HBEnabled() && HBExtraDockAppsEnabled() &&
        HBListViewIsInDock((UIView *)self)) {
        NSUInteger columns = HBVisualColumnsForListView(self);
        UIView *listView = (UIView *)self;
        layout = HBVisualDockLayoutForListView(listView, layout, columns);
    }
    return layout;
}

- (CGSize)iconSpacing {
    // Keep SpringBoard's native metric stable. MaxDock applies its spacing once
    // in the final center distributor instead of altering the layout engine too.
    return %orig;
}

- (UIEdgeInsets)additionalLayoutInsets {
    return %orig;
}

- (BOOL)automaticallyAdjustsLayoutMetricsToFit {
    return %orig;
}

%end


%end

%group HarborDockCapacityProvider

%hook SBHDefaultIconListLayoutProvider

- (SBIconListFlowExtendedLayout *)layoutForIconLocation:(NSString *)iconLocation {
    SBIconListFlowExtendedLayout *layout = %orig(iconLocation);
    if (HBEnabled() && HBExtraDockAppsEnabled() && HBIsDockLocation(iconLocation)) {
        // This path runs while the model is being created. Give the model the
        // full ceiling; SBIconListView -layout later selects the adaptive
        // visual column count for the actual icons and drag placeholder.
        HBConfigureDockLayout(layout, HBDockCapacity());
    }
    return layout;
}

%end

%end


%ctor {
    @autoreleasepool {
        if (!HBIsSpringBoardProcess()) return;
        long major=NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
        if(!HBSupportsOSMajor(major)||!HBStartupAllowedForOS(major,HBBoolPreference(@"Enabled",HBDefaultEnabledForOS(major)),[HBPreferenceValue(@"RuntimeOptInMajor")integerValue]))return;
        // Hook the model's configuration factory before SpringBoard builds or caches it.
        // No views, icon insertion, or persistent layout writes occur in this initializer.
        Class provider=NSClassFromString(@"SBHDefaultIconListLayoutProvider");
        if(HBHookTypesMatch(provider,@{@"layoutForIconLocation:":@[@"@",@"@"]})) {
            %init(HarborDockCapacityProvider, SBHDefaultIconListLayoutProvider = provider);
        } else {
            os_log_error(OS_LOG_DEFAULT,"[Harbor] capacity provider signature unavailable; skipped");
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
    @autoreleasepool {
        if (!HBIsSpringBoardProcess()) return;
        long major=NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
        if(!HBStartupAllowedForOS(major,HBBoolPreference(@"Enabled",HBDefaultEnabledForOS(major)),[HBPreferenceValue(@"RuntimeOptInMajor")integerValue]))return;

        // Gate before migrations, observers, timers, hooks, or icon-model writes.
        if (!HBSupportsOSMajor(NSProcessInfo.processInfo.operatingSystemVersion.majorVersion)) {
            os_log_error(OS_LOG_DEFAULT, "[Harbor] unsupported release family; disabled");
            return;
        }

        HBMigrateIconSizePreference();
        HBScheduleRunningIndicatorPoll();
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            HBPreferencesChanged,
            CFSTR("com.eswick.harbor16/preferences.changed"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);

        Class iconClass = NSClassFromString(@"SBIconView");
        Class dockListClass = NSClassFromString(@"SBDockIconListView");
        Class dockClass = NSClassFromString(@"SBDockView");
        Class iconListClass = NSClassFromString(@"SBIconListView");
        Class rootFolderViewClass = NSClassFromString(@"SBHRootFolderView");
        if (rootFolderViewClass == Nil) {
            rootFolderViewClass = NSClassFromString(@"SBRootFolderView");
        }
        Class applicationClass = NSClassFromString(@"SBApplication");
        if (iconClass == Nil) {
            os_log_error(OS_LOG_DEFAULT, "[Harbor] icon runtime unavailable; disabled");
            return;
        }

        if (![iconClass isSubclassOfClass:UIView.class]) {
            os_log_error(OS_LOG_DEFAULT,
                         "[Harbor] invalid icon runtime; disabled");
            return;
        }

        // didMoveToSuperview is inherited from UIView, so the core size option
        // remains available even if a minor iOS build lacks the private image
        // refresh selector.
        Class editingManagerClass=NSClassFromString(@"SBHIconManager");
        if(HBHookTypesMatch(editingManagerClass,@{@"setEditing:":@[@"v",@"B"]})) { %init(HarborNativeEditingTransitions,SBHIconManager=editingManagerClass); }
        if (HBHookTypesMatch(iconClass, @{@"didMoveToSuperview":@[@"v"]})) { %init(HarborDockIconScaleLifecycle, SBIconView = iconClass); } else { os_log_error(OS_LOG_DEFAULT, "[Harbor] HarborDockIconScaleLifecycle: incompatible method signature; skipped"); }
        if ([iconClass instancesRespondToSelector:
                @selector(_updateIconImageViewAnimated:)]) {
            if (HBHookTypesMatch(iconClass, @{@"_updateIconImageViewAnimated:":@[@"v",@"B"]})) { %init(HarborDockIconScaleRefresh, SBIconView = iconClass); } else { os_log_error(OS_LOG_DEFAULT, "[Harbor] HarborDockIconScaleRefresh: incompatible method signature; skipped"); }
        } else {
            os_log_error(OS_LOG_DEFAULT,
                         "[Harbor] using lifecycle-only dock icon sizing");
        }
        if (dockClass != Nil && [dockClass isSubclassOfClass:UIView.class]) {
            if (HBHookTypesMatch(dockClass, @{@"setBackgroundAlpha:":@[@"v",@"d"],@"didMoveToWindow":@[@"v"],@"layoutSubviews":@[@"v"],@"setAlpha:":@[@"v",@(@encode(CGFloat))],@"setCenter:":@[@"v",@(@encode(CGPoint))],@"setFrame:":@[@"v",@(@encode(CGRect))]})) { %init(HarborDockViewCore, SBDockView = dockClass); } else { os_log_error(OS_LOG_DEFAULT, "[Harbor] HarborDockViewCore: incompatible method signature; skipped"); }
        } else if (dockListClass != Nil && [dockListClass isSubclassOfClass:UIView.class]) {
            if (HBHookTypesMatch(dockListClass, @{@"didMoveToWindow":@[@"v"],@"layoutSubviews":@[@"v"],@"setAlpha:":@[@"v",@(@encode(CGFloat))],@"setCenter:":@[@"v",@(@encode(CGPoint))],@"setFrame:":@[@"v",@(@encode(CGRect))]})) { %init(HarborDockListFallbackCore, SBDockIconListView = dockListClass); } else { os_log_error(OS_LOG_DEFAULT, "[Harbor] HarborDockListFallbackCore: incompatible method signature; skipped"); }
            os_log_error(OS_LOG_DEFAULT, "[Harbor] using inner dock gesture fallback");
        }

        if (rootFolderViewClass != Nil &&
            [rootFolderViewClass isSubclassOfClass:UIView.class]) {
            if (HBHookTypesMatch(rootFolderViewClass, @{@"layoutSubviews":@[@"v"]})) { %init(HarborHomeSearchAppearance,
                  SBRootFolderView = rootFolderViewClass); } else { os_log_error(OS_LOG_DEFAULT, "[Harbor] HarborHomeSearchAppearance: incompatible method signature; skipped"); }
        }


        if (applicationClass != Nil &&
            [applicationClass instancesRespondToSelector:@selector(setRunning:)]) {
            if (HBHookTypesMatch(applicationClass, @{@"setRunning:":@[@"v",@"B"]})) { %init(HarborRunningStateUpdates, SBApplication = applicationClass); } else { os_log_error(OS_LOG_DEFAULT, "[Harbor] HarborRunningStateUpdates: incompatible method signature; skipped"); }
        }
        if (applicationClass != Nil &&
            [applicationClass instancesRespondToSelector:@selector(_setActivationState:)]) {
            if (HBHookTypesMatch(applicationClass, @{@"_setActivationState:":@[@"v",@"i"]})) { %init(HarborActivationStateUpdates, SBApplication = applicationClass); } else { os_log_error(OS_LOG_DEFAULT, "[Harbor] HarborActivationStateUpdates: incompatible method signature; skipped"); }
        }
        if (applicationClass != Nil &&
            [applicationClass instancesRespondToSelector:
                @selector(_setInternalProcessState:)]) {
            if (HBHookTypesMatch(applicationClass, @{@"_setInternalProcessState:":@[@"v",@"@"]})) { %init(HarborProcessStateUpdates, SBApplication = applicationClass); } else { os_log_error(OS_LOG_DEFAULT, "[Harbor] HarborProcessStateUpdates: incompatible method signature; skipped"); }
        }

        BOOL hasIconListLayout =
            iconListClass != Nil && [iconListClass isSubclassOfClass:UIView.class] &&
            [iconListClass instancesRespondToSelector:@selector(layout)] &&
            [iconListClass instancesRespondToSelector:@selector(iconSpacing)] &&
            [iconListClass instancesRespondToSelector:@selector(additionalLayoutInsets)] &&
            [iconListClass instancesRespondToSelector:
                @selector(automaticallyAdjustsLayoutMetricsToFit)];
        if (hasIconListLayout) {
            if (HBHookTypesMatch(iconListClass, @{
 @"centerForIconAtIndex:":@[@(@encode(CGPoint)),@"Q"],
 @"centerForIconAtIndex:metrics:":@[@(@encode(CGPoint)),@"Q",@"@"],
 @"centerForIcon:":@[@(@encode(CGPoint)),@"@"],
 @"centerForIcon:metrics:":@[@(@encode(CGPoint)),@"@",@"@"],
 @"originForIconAtCoordinate:metrics:":@[@(@encode(CGPoint)),@(@encode(SBIconCoordinate)),@"@"],
 @"originForIconAtCoordinate:metrics:options:":@[@(@encode(CGPoint)),@(@encode(SBIconCoordinate)),@"@",@"Q"],
 @"layoutSubviews":@[@"v"],@"layout":@[@"@"],@"iconSpacing":@[@(@encode(CGSize))],
 @"additionalLayoutInsets":@[@(@encode(UIEdgeInsets))],@"automaticallyAdjustsLayoutMetricsToFit":@[@"B"],
 @"indexOfIcon:":@[@"Q",@"@"]
 })) { %init(HarborModernIconListLayout, SBIconListView = iconListClass); } else { os_log_error(OS_LOG_DEFAULT, "[Harbor] HarborModernIconListLayout: incompatible method signature; skipped"); }
        } else {
            os_log_error(OS_LOG_DEFAULT,
                         "[Harbor] iOS 16 dock layout API unavailable; capacity disabled");
        }

        if (dockListClass == Nil && dockClass == Nil) {
            os_log_error(OS_LOG_DEFAULT, "[Harbor] no compatible dock view class");
        }

    }
    });
}
