# CarTV 1.0.8 — خريطة المميزات القابلة للتعديل

> تحليل مبني على حزمة `CarTV-analysis-1.0.8` الموجودة في هذا المستودع.
> الهدف: تحديد كل نقطة قابلة للتعديل (Hook / Tweak / Resource / Config) مع الرموز الدقيقة المُرصودة من الثنائي.

## 1. نظام Pro / الاشتراك (الهدف الأهم)

الرموز المرصودة في الثنائي:

| الرمز | النوع |
|---|---|
| `_TtC5CarTV14LyntraProStore` | Swift class |
| `LyntraProEntitlement` | نموذج الاستحقاق |
| `LyntraProPlan` | الخطة |
| `LyntraProStoreError` | أخطاء المتجر |
| `LyntraPaywallViewController` | شاشة الدفع |
| `LyntraPaywallProductCard` / `LyntraPaywallSkeletonCard` / `LyntraPaywallArrowsView` | واجهات الدفع |
| `LyntraAddSubscriptionSheetViewController` | إضافة اشتراك يدوي |
| `LyntraSubscriptionInputParser` | محلل إدخال الاشتراك |
| `lyntra.proStatusDidChange` | إشعار تغيّر الحالة |
| `lyntra.proProductsDidChange` | إشعار تغيّر المنتجات |
| `com.lyntra.player.pro.` | بادئة معرّفات منتجات StoreKit |

**StoreKit2 مُستخدم فعلياً**: `Product.SubscriptionInfo`, `Transaction.currentEntitlements` موجودة في الثنائي.

**نقاط الـ Hook العملية (Theos/Logos):**
- هوك على getter حالة الاشتراك في `LyntraProStore` لإرجاع "مفعّل" دائماً.
- هوك `LyntraPaywallViewController` لتخطي العرض مباشرة.
- كتابة `UserDefaults` key الخاص بـ proStatus لتثبيت الحالة.

## 2. حدود ميزة Cast

| الرمز | الوظيفة |
|---|---|
| `castLimitReached:` | سيليكتور التحقق من الحد |
| `lyntra.castLimitReached` | UserDefaults |
| `lyntra.cast.grace` | فترة السماح |
| `lyntra.cast.configID` / `lyntra.cast.deviceName` / `lyntra.cast.everUsed` | إعدادات الكاست |
| `_lyntracast._tcp` | خدمة Bonjour |

**قابل للتعديل:** رفع/إزالة حد الكاست عبر هوك على `castLimitReached:`.

## 3. التتبّع والتحليلات (قابلة للحذف/الحظر)

| المكوّن | الدليل |
|---|---|
| **Umeng SDK** (كامل) | `ulogs.umeng.com`, `ucc.umeng.com`, `aspect-upush.umeng.com`, `cnlogs.umeng.com`, `UTokenSDK`, `serial.umeng.sdk.queue` |
| **FirstFew SDK** | `api.firstfew.ai`, `com.firstfew.sdk`, `com.firstfew.sdk.installed`, `com.firstfew.sdk.attribution_reported` |

**قابل للتعديل:**
- حظر النطاقات أعلاه في DNS/الشبكة.
- أو Stripping: حذف كود Umeng/FirstFew من الثنائي مع إعادة التوقيع.
- أو Hook: تعطيل `FirstFew` init.

## 4. الهوية والموارد (تعديل مباشر بدون هوك)

| العنصر | القيمة الحالية | القابلية |
|---|---|---|
| Bundle ID | `com.lyntra.player` | تغيير → نسخة متوازية (مدمج في IPAMultiInstancePreparer) |
| الاسم المعروض | `CarTV` | قابل للتغيير |
| الأيقونات | AppIcon60x60/76x76 | قابلة للاستبدال |
| الإصدارات المدعومة | iPhone11,2 → iPhone18,5 | توسيع القائمة ممكن |
| ATS | `NSAllowsArbitraryLoads = true` | أصلاً مفتوح |
| السينينات | CarPlay + External Display + Default | قابلة للإضافة/الحذف |
| Orientation | iPhone: Portrait أساساً | تعديل ممكن |

## 5. الإضافات (PlugIns)

| الإضافة | الحجم | القرار |
|---|---|---|
| `ScreenRelay.appex` (ReplayKit) | 160KB | إبقاء/حذف |
| `CastWidgetExtension.appex` | 134KB | إبقاء/حذف |
| `MobileVLCKit.framework` | 37MB | **لا تُمَسّ** — محرك التشغيل الأساسي |

## 6. ميزات إضافية مرصودة (قابلة للتعديل عبر Hook)

- **الترجمة التلقائية للترجمة الصوتية**: `LyntraSubtitleTranslator`, `softSubtitleSignature`, `lyntra.subtitles.autoEnabled`
- **فلاتر المصدر في الرئيسية**: `LyntraHomeSourceFilter`, `lyntra.home.sourceFilter`
- **صحة المصادر**: `LyntraSourceHealthService`, `lyntra.sourceHealth.lastFullScan`
- **التحديثات القسرية**: `LyntraUpdateNoticeViewController` — هوك لتعطيل شاشة "التحديث مطلوب"
- **الكاش/البروكسي**: `LyntraMediaCacheProxy`, `com.lyntra.cartv.mediaproxy`
- **سيرفرات UPnP/DLNA**: `LyntraSSDPResponder`, `LyntraSOAP`, `LyntraDIDL`, `LyntraUPnPHTTPServer`

## ملخص الأولويات

| الأولوية | التعديل | الطريقة |
|---|---|---|
| 1 | فك اشتراك Pro | Hook على `LyntraProStore` |
| 2 | إزالة حد الكاست | Hook على `castLimitReached:` |
| 3 | تعطيل التتبّع (Umeng/FirstFew) | حظر نطاقات + Hook |
| 4 | تعطيل شاشة التحديث الإجباري | Hook على `LyntraUpdateNoticeViewController` |
| 5 | هوية/أيقونة/اسم مخصص | تعديل مباشر + Re-sign |


---

## حكم التحقق العميق: جدوى تفعيل Pro (تحليل فني محض)

### السؤال: هل فحص Pro محلي بالكامل أم يوجد تحقق خادمي؟
**الإجابة من الأدلة: فحص محلي بالكامل. لا يوجد أي تحقق خادمي.**

### الأدلة من الثنائي:

1. **لا توجد أي نقطة نهاية API للتحقق من الاشتراك.** كل النطاقات المرصودة مصنفة:
   - `api.firstfew.ai` → تحليلات/attribution فقط (SDK مدمج)
   - `*.umeng.com` → تحليلات Umeng فقط
   - `ocsp.apple.com` / `crl.apple.com` → شهادات Apple (توقيع)
   - `https://lyntra.app` → يظهر فقط داخل XML الخاص بـ UPnP (manufacturerURL) وليس في كود الشبكة
   - لا يوجد `api.lyntra.app` ولا أي مسار مثل `/verify` أو `/receipt` أو `/subscription`

2. **الآلية المعمارية المرصودة:**
   - `LyntraProStore` غلاف حول StoreKit 2 (`Transaction.currentEntitlements` موجود حرفياً في الثنائي)
   - StoreKit 2 يتحقق من إيصال JWS **على الجهاز نفسه**
   - النتيجة تُخزَّن في نموذج `LyntraProEntitlement` وتُبث عبر `lyntra.proStatusDidChange` (NotificationCenter)
   - هذا يعني **نقطة حقيقة واحدة (single point of truth)** قابلة للتأثير من داخل العملية

3. **الرموز المصدَّرة:** `_TtC5CarTV14LyntraProStore` — كلاس Swift ظاهر في ObjC runtime (يرث NSObject) → سطح حقن قياسي.

4. **لا حمايات مرصودة:** لا anti-debug، لا فحص jailbreak، لا تشفير للكلاسات، لا مؤشرات على App Store Server API.

### الخلاصة الفنية:
| المعيار | النتيجة |
|---|---|
| تحقق خادمي | غير موجود |
| تحقق محلي قابل للتأثير | نعم (كاش + إشعارات) |
| سطح Hook واضح | `_TtC5CarTV14LyntraProStore` |
| حمايات مضادة | لا شيء مرصود |
| **الجدوى الفنية** | **ممكنة بالكامل من الناحية الهندسية** |

> تقرير تحليل ثنائي لأغراض بحثية. التنفيذ الفعلي خارج نطاق هذا المستودع.
