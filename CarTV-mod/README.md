# CarTV-Plus — نسخة موازية بهوية جديدة

يحوّل `CarTV.ipa` إلى نسخة **متوازية** تعمل بجانب الأصلية بهوية مستقلة.

## ما يغيّره

| العنصر | الأصلي | الجديد |
|---|---|---|
| Bundle ID | `com.lyntra.player` | `app.zain.cartvplus` (افتراضي) |
| اسم العرض | CarTV | CarTV+ |
| ScreenRelay | `com.lyntra.player.ScreenRelay` | `…cartvplus.ScreenRelay` |
| CastWidget | `com.lyntra.player.CastWidget` | `…cartvplus.CastWidget` |
| UISupportedDevices | قائمة مقيدة (iPhone11+) | **محذوفة** — دعم أوسع |

## المتطلبات

- IPA **مفكوك التشفير** (decrypted) مسبقاً — ملف App Store المشفر لن يعمل
- `plutil` (متوفر على iOS/macOS)
- توقيع: `ldid` (جيلبريك) أو حساب مطوّر مع `codesign` (تثبيت جانبي)

## الاستخدام

```bash
# وضع الجيلبريك (الافتراضي)
./patch-ipa.sh CarTV.ipa

# تخصيص الهوية
./patch-ipa.sh CarTV.ipa --name "CarTV Zain" --bundle app.zain.mytv

# وضع التثبيت الجانبي (macOS + شهادة مطور)
./patch-ipa.sh CarTV.ipa --signer "Apple Development: you@example.com"
```

## ملاحظات تقنية

1. **Entitlements تُستخرج من الثنائيات الأصلية** وتُعاد كما هي — إن كان CarTV يملك entitlement خاص بـ CarPlay سيُحفظ (مهم في وضع الجيلبريك).
2. **CarPlay في التثبيت الجانبي**: entitlement الـ CarPlay لا يُمنح إلا لحسابات مطورة معتمدة من Apple للفيديو — في النسخة المجانية قد لا تظهر واجهة CarPlay (باقي التطبيق يعمل طبيعي).
3. **المشتريات داخل النسخة**: منتجات StoreKit مرتبطة بالـ Bundle ID الأصلي — زر الاشتراك في النسخة المعدلة لن يشتري من حسابك (متوقع).
4. **خدمة الكاست** `_lyntracast._tcp` تبقى كما هي — إذا عملت النسختان معاً قد تتشاركان اسم الخدمة محلياً (لا يؤثر على الوظائف).
5. الثنائيات لا تُمسّ — تعديل هوية وموارد فقط، بدون أي تغيير في الكود.
