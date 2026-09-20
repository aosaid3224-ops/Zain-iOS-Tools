# CarTV 1.0.8 — تقرير الاكتشافات المؤكدة

**المصدر:** strings الباينري الرئيسي (12,143 سطر) — `CarTV-analysis-1.0.8/strings/CarTV.txt`
**التاريخ:** 2026-09-18
**حالة التحقق:** كل بند أدناه مستخرج حرفياً من الباينري

## 1. آلية الاشتراك

| البند | القيمة المؤكدة |
|---|---|
| نظام الشراء | StoreKit 2 (`Product`, `Transaction`, `VerificationResult`) |
| معرفات المنتجات | `com.lyntra.player.pro.` + `weekly` / `yearly` / `lifetime` |
| نوع المنتجات | اشتراكات متكررة + شراء لمرة واحدة (lifetime) |
| التحقق من الاشتراك | محلي على الجهاز عبر `Transaction.currentEntitlements` |
| تحقق سيرفر خارجي | غير موجود (لا endpoints، لا مزود خارجي) |
| مزودو اشتراك خارجيون | غير موجودين (لا RevenueCat / Adapty / Qonversion) |
| نافذة الشراء | `LyntraPaywallViewController` (`PaywallViewController.swift`) |

## 2. التجربة المجانية (Trial)

| البند | القيمة المؤكدة |
|---|---|
| مكان التخزين | Keychain |
| المفاتيح | `CARPLAYER CastTrial` / `CARPLAYER SubtitleTrial` |
| مفاتيح إضافية | `CARPLAYER DeviceID` |
| قيم زمنية | `cast-trial-seconds` / `subtitle-trial-seconds` |
| API التخزين | `getKeychainQuery:` / `setKeychainObject:forKey:` |

## 3. حدود الخطة المجانية (من نصوص الواجهة)

- "The free plan includes 1 hour of subtitles. Upgrade to CarTV Pro for unlimited use."
- "Upgrade to Pro to keep receiving casts without limits."
- "no subscription, no renewals"

## 4. مؤشرات فتح Pro الموجودة في الباينري

- `All features unlocked`
- `You're a Pro member`
- `_unlockModel` (خاصية Objective-C: `T@"UMInnerRemoteCfgModel",&,N,V_unlockModel`)
- `unlock` / `unlockModel`

## 5. الحماية

| الفحص | النتيجة |
|---|---|
| Jailbreak detection | غير موجود |
| Integrity / anti-tamper | غير موجود |
| كشف تصحيح (debugger) | غير موجود |

## 6. البنية المعروفة

- Team ID: `XQ8SUTV36H`
- Bundle ID: `com.lyntra.player`
- الإضافات: `ScreenRelay.appex` (ReplayKit) + `CastWidgetExtension.appex` (WidgetKit)
- المكتبة: `MobileVLCKit` (arm64)
- التحليلات: Umeng (`MobClickSession`)
- أسماء كلاسات Swift مرشحة: 269 كلاس، 3,696 ميثود Objective-C، 1,000 Swift-mangled name

## 7. النطاقات الشبكية

`lyntra.app` — `api.firstfew.ai` — خوادم Umeng — نطاقات VLC — باقي النطاقات في `network-domains.txt`
