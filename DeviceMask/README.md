# DeviceMask v1.0 — تزوير هوية الجهاز

## الوظيفة
يزوّر ما تقرأه التطبيقات من معرّفات الجهاز:
SerialNumber | ProductType (الموديل) | ProductVersion | UDID | IDFV | IDFA | MAC (Wifi/BT)

## الاستخدام
- التثبيت: `dpkg -i com.nw.devicemask_1.0_iphoneos-arm64.deb` ثم `ldrestart`
- البروفايلات: `/var/mobile/Documents/DeviceMask/<bundle>.plist`
  - يُولّد تلقائيًا أول إقلاع (هوية مستقرة)
- هوية جديدة عشوائية: `rm /var/mobile/Documents/DeviceMask/*.plist && ldrestart`
- هوية يدوية: عدّل أي مفتاح في ملف البروفايل (نص عادي) ثم `ldrestart`

## ⚠️ قواعد البقاء
1. لا تغيّر الهوية كل إقلاع — مزارع الحسابات تفعل ذلك وتُحظر
2. بدّل الهوية فقط عند: حساب جديد / بعد باند / جهاز "جديد"
3. استخدمه مع: Dopamine Hide Jailbreak + Hestia/Shadow
4. فترة صمت 3-7 أيام بعد أي باند قبل أي نشاط
