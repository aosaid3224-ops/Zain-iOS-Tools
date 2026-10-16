# DeltaGuard iOS 0.2.6

نسخة iOS أصلية من واجهة حارس دلتا، مع طبقة وظائف حقيقية تعمل على جهاز Rootless/jailbroken بدل محاكاة نجاح Android.

## الوظائف الفعلية

- فحص بيئة Rootless ووجود `/var/jb` وUID الحالي.
- فحص توفر `LSApplicationWorkspace` وكتالوج التطبيقات.
- اكتشاف تطبيقات خوادم اللعبة من خلال Bundle ID.
- حفظ الخادم المحدد عبر `NSUserDefaults`.
- تشغيل الخادم المحدد عبر `LSApplicationWorkspace` عند توفره.
- مراقبة PID للعملية بعد التشغيل باستخدام `libproc`.
- سجل تشغيل دائم مع النسخ والمسح.
- مسح كاش DeltaGuard من إعداداته.
- أداة عائمة حقيقية داخل واجهة DeltaGuard نفسها.
- واجهة عربية RTL كاملة.

## الحدود المقصودة

آليات Android مثل Shizuku وSAF وحقن ذاكرة لعبة Android لا تنتقل حرفيًا إلى iOS. لا تعرض النسخة نجاحًا وهميًا للحقن ولا تعدّل ذاكرة لعبة دون محرك iOS مستقل ومصرح به. الأداة الحالية تنفذ إدارة البيئة والتطبيقات والتشغيل والمراقبة فعليًا على iOS.

## البناء

```sh
make clean
make package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
```

الإصدار الحالي `0.2.6`، والحد الأدنى iOS 15 مع Rootless.
