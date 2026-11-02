#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <spawn.h>
#import <CoreFoundation/CoreFoundation.h>
#import <unistd.h>
#import <math.h>
#import "../HBCompatibility.h"

extern char **environ;

@interface HPRootListController : PSListController
@end

static BOOL HPUsesArabic(void) {
    NSString *language = [NSLocale preferredLanguages].firstObject;
    return [language hasPrefix:@"ar"];
}

static NSString *HPLocalized(NSString *english) {
    if (!HPUsesArabic()) return english;
    NSDictionary<NSString *, NSString *> *arabic = @{
        @"MaxDock": @"ماكس دوك",
 @"Dock Mode":@"وضع الدوك",@"Choose Dock Mode":@"اختيار وضع الدوك",@"Normal":@"طبيعي",@"Circular":@"دائري",@"Cancel":@"إلغاء",
 @"Swipe to rotate. Tap an icon to open. Normal Dock appears while editing.":@"اسحب لتدوير الحلقة واضغط على الأيقونة لفتح التطبيق. يظهر الدوك الطبيعي أثناء تعديل الأيقونات.",
        @"Compatibility Status": @"حالة التوافق",
        @"iOS16 is the tested baseline. On iOS15/17/18/26 this is experimental: enable the tool, then Apply and Respring. The engine stays off at first installation on those versions.": @"iOS 16 هو المسار المختبر. على 15 و17 و18 و26 التوافق تجريبي: فعّل الأداة ثم تطبيق وإعادة تشغيل الواجهة. المحرك مطفأ عند أول تثبيت على هذه الإصدارات.",
        @"Dock Position": @"مكان الدوك",
        @"Vertical Offset": @"الموضع العمودي",
        @"Show Drag Handle While Editing": @"إظهار مقبض السحب وقت التعديل",
        @"Positive values lower the Dock. Drag the handle while icons are editing to save its position. Movement is limited to the screen edges and hidden in landscape.": @"القيم الموجبة تنزل الدوك. اسحب المقبض وقت تعديل الأيقونات لحفظ الموضع. الحركة محدودة بحواف الشاشة وتتعطل أفقياً.",
        @"Developed by Flip Max • Most changes apply immediately.": @"المطوّر: Flip Max • تُطبّق أغلب التغييرات مباشرة.",
        @"Enabled": @"تفعيل الأداة",
        @"Icon Appearance": @"مظهر الأيقونات",
        @"Multiplies MaxDock's automatic resting size. Changes require a respring.": @"يضبط حجم الأيقونات التلقائي.",
        @"Icon Size": @"حجم الأيقونات",
        @"Maximum Magnification": @"أقصى تكبير",
        @"Interaction": @"التفاعل",
        @"Slide across the Dock, then release to open the highlighted app.": @"مرّر على الدوك ثم ارفع إصبعك لفتح التطبيق المحدد.",
        @"Open Highlighted App": @"فتح التطبيق المحدد",
        @"Show App Name": @"إظهار اسم التطبيق",
        @"Selection Haptic": @"اهتزاز عند التحديد",
        @"Selection Glow": @"إضاءة التطبيق المحدد",
        @"Hide Dock Background": @"إخفاء خلفية الدوك",
        @"Frosted Adaptive Dock Background": @"خلفية دوك ثلجية شفافة",
        @"Hide Home Screen Search": @"إخفاء بحث الشاشة الرئيسية",
        @"Auto-Hide Dock": @"إخفاء الدوك تلقائياً",
        @"Launch Bounce": @"ارتداد عند فتح التطبيق",
        @"Notification Badge Bounce": @"قفز أيقونات الإشعارات",
        @"Ready Profiles": @"ملفات جاهزة",
        @"macOS Profile": @"نمط macOS",
        @"Compact Profile": @"النمط المضغوط",
        @"Transparent Profile": @"النمط الشفاف",
        @"Gaming Profile": @"نمط الألعاب",
        @"Allow Extra Dock Apps": @"السماح بتطبيقات إضافية",
        @"Dock Capacity": @"سعة الدوك",
        @"Choose the capacity, then use Apply and Respring before adding more apps.": @"اختر السعة ثم اضغط تطبيق وإعادة تشغيل الواجهة قبل إضافة التطبيقات.",
        @"Dock Margin — Icon Inset": @"هوامش الدوك والأيقونات",
        @"Uses the native adaptive iOS 16 Dock grid.": @"يستخدم تخطيط الدوك التلقائي في iOS 16.",
        @"Icon Inset": @"هامش الأيقونات",
        @"Icon Padding Multiplier": @"مضاعف المسافة بين الأيقونات",
        @"Wave Width — Effective Range": @"عرض موجة التكبير",
        @"These MaxDock controls are read directly by the iOS 16 engine.": @"تتحكم هذه الخيارات مباشرة بمحرك ماكس دوك.",
        @"Effective Range": @"نطاق التأثير",
        @"Wave Height — Evasion Distance": @"ارتفاع موجة التكبير",
        @"Evasion Distance": @"مسافة الارتفاع",
        @"Animation Duration": @"مدة الحركة",
        @"Reset MaxDock Layout Defaults": @"استعادة الإعدادات الافتراضية",
        @"Apply and Respring": @"تطبيق وإعادة تشغيل الواجهة"
    };
    return arabic[english] ?: english;
}

@implementation HPRootListController
- (NSNumber*)getCircularSpeed:(PSSpecifier*)specifier{return [self preferenceValueForKey:@"CircularSpeed" defaultValue:@2];}
- (void)setCircularSpeed:(NSNumber*)value forSpecifier:(PSSpecifier*)specifier{double speed=value.doubleValue;[self setValue:@(isfinite(speed)?MAX(.5,MIN(4,speed)):2) forPreferenceKey:@"CircularSpeed"];}
- (NSNumber*)getCircularIconScale:(PSSpecifier*)specifier{return [self preferenceValueForKey:@"CircularIconScale" defaultValue:@1];}
- (void)setCircularIconScale:(NSNumber*)value forSpecifier:(PSSpecifier*)specifier{double scale=value.doubleValue;[self setValue:@(isfinite(scale)?MAX(.6,MIN(1.3,scale)):1) forPreferenceKey:@"CircularIconScale"];}
- (void)chooseDockMode {
 UIAlertController*a=[UIAlertController alertControllerWithTitle:HPLocalized(@"Dock Mode") message:nil preferredStyle:UIAlertControllerStyleAlert];
 for(NSString*mode in @[@"normal",@"circular"]){[a addAction:[UIAlertAction actionWithTitle:HPLocalized([mode isEqual:@"normal"]?@"Normal":@"Circular") style:UIAlertActionStyleDefault handler:^(UIAlertAction*action){[self setValue:mode forPreferenceKey:@"DockMode"];}]];}
 [a addAction:[UIAlertAction actionWithTitle:HPLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
}


- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.semanticContentAttribute = HPUsesArabic()
        ? UISemanticContentAttributeForceRightToLeft
        : UISemanticContentAttributeForceLeftToRight;
}

- (id)preferenceValueForKey:(NSString *)key defaultValue:(id)defaultValue {
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                                CFSTR("com.eswick.harbor16"));
    return value ?: defaultValue;
}

- (void)setValue:(id)value forPreferenceKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             CFSTR("com.eswick.harbor16"));
    CFPreferencesAppSynchronize(CFSTR("com.eswick.harbor16"));
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.eswick.harbor16/preferences.changed"),
                                         NULL, NULL, true);
}

- (NSNumber *)getEnabled:(PSSpecifier *)specifier {long major=NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;return @(HBEngineEnabledForOS(major,[[self preferenceValueForKey:@"Enabled" defaultValue:@(HBDefaultEnabledForOS(major))]boolValue],[[self preferenceValueForKey:@"RuntimeOptInMajor" defaultValue:@0]integerValue]));}
- (void)setEnabled:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier {long major=NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;if(value.boolValue)[self setValue:@(major)forPreferenceKey:@"RuntimeOptInMajor"];[self setValue:value forPreferenceKey:@"Enabled"];}
- (NSNumber *)getMaximumScale:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"MaximumScale" defaultValue:@1.55]; }
- (void)setMaximumScale:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"MaximumScale"]; }
- (NSNumber *)getIconSizeScale:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"IconSizeScale" defaultValue:@1.0]; }
- (void)setIconSizeScale:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"IconSizeScale"]; }
- (NSNumber *)getExtraDockApps:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"ExtraDockApps" defaultValue:@YES]; }
- (void)setExtraDockApps:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"ExtraDockApps"]; }
- (NSNumber *)getLaunchOnRelease:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"LaunchOnRelease" defaultValue:@YES]; }
- (void)setLaunchOnRelease:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"LaunchOnRelease"]; }
- (NSNumber *)getShowAppName:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"ShowAppName" defaultValue:@YES]; }
- (void)setShowAppName:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"ShowAppName"]; }
- (NSNumber *)getHapticFeedback:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"HapticFeedback" defaultValue:@YES]; }
- (void)setHapticFeedback:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"HapticFeedback"]; }
- (NSNumber *)getSelectionGlow:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"SelectionGlow" defaultValue:@YES]; }
- (void)setSelectionGlow:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"SelectionGlow"]; }
- (NSNumber *)getHideDockBackground:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"HideDockBackground" defaultValue:@NO]; }
- (void)setHideDockBackground:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"HideDockBackground"]; }
- (NSNumber *)getSlimAdaptiveBackground:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"SlimAdaptiveBackground" defaultValue:@YES]; }
- (void)setSlimAdaptiveBackground:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"SlimAdaptiveBackground"]; }
- (NSNumber *)getHideHomeSearch:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"HideHomeSearch" defaultValue:@NO]; }
- (void)setHideHomeSearch:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"HideHomeSearch"]; }
- (NSNumber *)getAutoHideDock:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"AutoHideDock" defaultValue:@NO]; }
- (void)setAutoHideDock:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"AutoHideDock"]; }
- (NSNumber *)getLaunchBounce:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"LaunchBounce" defaultValue:@YES]; }
- (void)setLaunchBounce:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"LaunchBounce"]; }
- (NSNumber *)getBadgeBounce:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"BadgeBounce" defaultValue:@YES]; }
- (void)setBadgeBounce:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"BadgeBounce"]; }
- (NSNumber *)getDockCapacity:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"DockCapacity" defaultValue:@12]; }
- (void)setDockCapacity:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"DockCapacity"]; }
- (NSNumber *)getIconInset:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"IconInset" defaultValue:@15.0]; }
- (void)setIconInset:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"IconInset"]; }
- (NSNumber *)getIconPaddingMultiplier:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"IconPaddingMultiplier" defaultValue:@0.25]; }
- (void)setIconPaddingMultiplier:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"IconPaddingMultiplier"]; }
- (NSNumber *)getEffectiveRange:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"EffectiveRange" defaultValue:@115.0]; }
- (void)setEffectiveRange:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"EffectiveRange"]; }
- (NSNumber *)getEvasionDistance:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"EvasionDistance" defaultValue:@28.0]; }
- (void)setEvasionDistance:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"EvasionDistance"]; }
- (NSNumber *)getAnimationDuration:(PSSpecifier *)specifier { return [self preferenceValueForKey:@"AnimationDuration" defaultValue:@0.32]; }
- (void)setAnimationDuration:(NSNumber *)value forSpecifier:(PSSpecifier *)specifier { [self setValue:value forPreferenceKey:@"AnimationDuration"]; }

- (NSNumber*)getDockVerticalOffset:(PSSpecifier*)specifier{return [self preferenceValueForKey:@"DockVerticalOffset" defaultValue:@0];}
- (void)setDockVerticalOffset:(NSNumber*)value forSpecifier:(PSSpecifier*)specifier{double v=value.doubleValue;if(!isfinite(v))v=0;[self setValue:@(MAX(-100,MIN(120,v)))forPreferenceKey:@"DockVerticalOffset"];}
- (NSNumber*)getDockPositionHandle:(PSSpecifier*)specifier{return [self preferenceValueForKey:@"DockPositionHandle" defaultValue:@YES];}
- (void)setDockPositionHandle:(NSNumber*)value forSpecifier:(PSSpecifier*)specifier{[self setValue:value forPreferenceKey:@"DockPositionHandle"];}

- (NSString*)getCompatibilityStatus:(PSSpecifier*)specifier{(void)specifier;long major=NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;NSString*status=!HBSupportsOSMajor(major)?(HPUsesArabic()?@"غير مدعوم":@"Unsupported"):(major==16?(HPUsesArabic()?@"المسار المختبر":@"Tested baseline"):(HPUsesArabic()?@"تجريبي — التفعيل يحتاج إعادة تشغيل الواجهة":@"Experimental — enable and respring"));return [NSString stringWithFormat:@"iOS %ld — %@",major,status];}

- (NSArray *)specifiers {
    if (_specifiers != nil) return _specifiers;

    // Use PSListController's loader instead of a manually declared private C ABI.
    _specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
    for (PSSpecifier *specifier in _specifiers) {
        NSString *name = [specifier name];
        if (name.length > 0) [specifier setName:HPLocalized(name)];
        NSString *footer = [specifier propertyForKey:@"footerText"];
        if (footer.length > 0) {
            [specifier setProperty:HPLocalized(footer) forKey:@"footerText"];
        }
    }
    [self setTitle:HPLocalized(@"MaxDock")];
    return _specifiers ?: @[];
}

- (void)applyProfileValues:(NSDictionary<NSString *, id> *)values {
    [values enumerateKeysAndObjectsUsingBlock:
        ^(NSString *key, id value, BOOL *stop) {
        (void)stop;
        CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                 (__bridge CFPropertyListRef)value,
                                 CFSTR("com.eswick.harbor16"));
    }];
    CFPreferencesAppSynchronize(CFSTR("com.eswick.harbor16"));
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.eswick.harbor16/preferences.changed"),
                                         NULL, NULL, true);
    [self reloadSpecifiers];
}

- (void)applyMacOSProfile {
    [self applyProfileValues:@{@"IconSizeScale": @1.0,
                               @"MaximumScale": @1.75,
                               @"EffectiveRange": @130.0,
                               @"EvasionDistance": @34.0,
                               @"AnimationDuration": @0.28,
                               @"SelectionGlow": @YES,
                               @"LaunchBounce": @YES,
                               @"HideDockBackground": @NO,
                               @"SlimAdaptiveBackground": @YES}];
}

- (void)applyCompactProfile {
    [self applyProfileValues:@{@"IconSizeScale": @0.82,
                               @"MaximumScale": @1.42,
                               @"IconInset": @8.0,
                               @"EffectiveRange": @90.0,
                               @"EvasionDistance": @18.0,
                               @"SelectionGlow": @NO,
                               @"HideDockBackground": @NO,
                               @"SlimAdaptiveBackground": @YES}];
}

- (void)applyTransparentProfile {
    [self applyProfileValues:@{@"IconSizeScale": @1.0,
                               @"MaximumScale": @1.60,
                               @"HideDockBackground": @YES,
                               @"SlimAdaptiveBackground": @YES,
                               @"HideHomeSearch": @YES,
                               @"SelectionGlow": @YES}];
}

- (void)applyGamingProfile {
    [self applyProfileValues:@{@"IconSizeScale": @1.05,
                               @"MaximumScale": @1.90,
                               @"EffectiveRange": @155.0,
                               @"EvasionDistance": @42.0,
                               @"AnimationDuration": @0.20,
                               @"HapticFeedback": @YES,
                               @"LaunchBounce": @YES,
                               @"HideDockBackground": @NO,
                               @"SlimAdaptiveBackground": @YES}];
}

- (void)resetLayoutDefaults {
    [self setValue:@0 forPreferenceKey:@"DockVerticalOffset"];
    [self setValue:@12 forPreferenceKey:@"DockCapacity"];
    [self setValue:@1 forPreferenceKey:@"CircularIconScale"];
    [self setValue:@2 forPreferenceKey:@"CircularSpeed"];
    [self setValue:@1.0 forPreferenceKey:@"IconSizeScale"];
    [self setValue:@YES forPreferenceKey:@"LaunchOnRelease"];
    [self setValue:@YES forPreferenceKey:@"ShowAppName"];
    [self setValue:@YES forPreferenceKey:@"HapticFeedback"];
    [self setValue:@YES forPreferenceKey:@"SelectionGlow"];
    [self setValue:@NO forPreferenceKey:@"HideDockBackground"];
    [self setValue:@YES forPreferenceKey:@"SlimAdaptiveBackground"];
    [self setValue:@NO forPreferenceKey:@"HideHomeSearch"];
    [self setValue:@YES forPreferenceKey:@"RunningIndicators"];
    [self setValue:@NO forPreferenceKey:@"AutoHideDock"];
    [self setValue:@YES forPreferenceKey:@"LaunchBounce"];
    [self setValue:@YES forPreferenceKey:@"BadgeBounce"];
    [self setValue:@YES forPreferenceKey:@"DynamicRunningApps"];
    [self setValue:@15.0 forPreferenceKey:@"IconInset"];
    [self setValue:@0.25 forPreferenceKey:@"IconPaddingMultiplier"];
    [self setValue:@115.0 forPreferenceKey:@"EffectiveRange"];
    [self setValue:@28.0 forPreferenceKey:@"EvasionDistance"];
    [self setValue:@0.32 forPreferenceKey:@"AnimationDuration"];
    [self setValue:@54 forPreferenceKey:@"LayoutEngineVersion"];
    [self reloadSpecifiers];
}

- (void)respring {
    pid_t pid;
    const char *path = access("/var/jb/usr/bin/sbreload", X_OK) == 0
        ? "/var/jb/usr/bin/sbreload" : "/usr/bin/sbreload";
    const char *args[] = {path, NULL};
    posix_spawn(&pid, path, NULL, NULL, (char *const *)args, environ);
}

@end
