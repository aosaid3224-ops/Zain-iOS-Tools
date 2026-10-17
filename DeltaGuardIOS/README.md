مهمه تحقيق انجاز بناء esp 🎉🎉🎉

## ⚠️ الحقيقة الكبرى (من سجل كراش رسمي)
**Delta Force mobile = Unreal Engine 4** — TaskGraphThreadNP / FAsyncLoadingThread / RenderThread / GameThread / physx / `ue4::imp_cache` / ue4commandline.txt
كل مسارات il2cpp السابقة كانت خاطئة المسار — رموز il2cpp الـ13 مجرد بقايا GPM SDK.

## سجل التطوير

### v0.6.4 — التحول لـ UE4
- إصلاح كراش الماسح: القراءة المباشرة للذاكرة استبدلت بنسخ آمن عبر kernel `mach_vm_read` (مستحيل يكراش)
- **محلل جدول الرموز nlist**: الثنائي يحتفظ برموز محلية كاملة (الدليل: سجل الكراش يعرض `GCloud::CFile::Exist` و`physx::…`)
- يستخرج كل رمز يحوي: GEngine/GWorld/UObjectArray/GNames/Player/Character/Pawn/Camera/Transform… → `deltaguard_symbols.txt`

### v0.6.3 — فحص ذاكرة كامل
### v0.6.1 — المستكشف الحي (Profiler Bridge — كان يستهدف il2cpp، الآن عُطّل ضمنيًا)
### v0.6.0 — إصلاح _underscore + DGOffsets

## خطة ESP على UE4 (الجديدة)
1. `deltaguard_symbols.txt` ← يعطينا عناوين GEngine / GUObjectArray / GNames بالاسم
2. نمشي على UObjectArray → كل Actors → نفلتر PlayerController/Pawn
3. RootComponent → RelativeLocation/Transform → إحداثيات كل لاعب
4. الإسقاط على الشاشة عبر الكاميرا (من PlayerCameraManager)

## الاختبار الآن
1. ابنِ وثبّت v0.6.4 → افتح اللعبة دقيقة (بدون كراش هذه المرة)
2. `cat /var/mobile/Containers/Data/Application/*/tmp/deltaguard_symbols.txt | head -60`
3. وابعث لي المخرجات + سطر `syms=` من التشخيص
