مهمه تحقيق انجاز بناء esp 🎉🎉🎉

## سجل التطوير

### v0.6.0 — القرار الجراحي بعد الأدلة
- **الأدلة من الجهاز**: 1224 صورة ممسوحة | 13 رمز il2cpp مصدَّر (class_get_name/method_get_name/profiler…) | `il2cpp_domain_get/runtime_invoke/class_from_name` غير مصدَّرة
- **السبب الجذري المثبت**: TiMi تستخدم KiwiVM (kgvmp_dy.framework) — واجهة il2cpp الكاملة موجودة داخل الثنائي لكن غير مصدَّرة، ولا UnityFramework منفصلة
- **الإصلاح**: البحث بالشرطة السفلية `_name` (شجرة التصدير تخزنها للدوال C)
- **مراسي مثبتة**: `partial:4/4` = حضور زمن التشغيل مؤكد
- **محرك الأوفسيتات `DGOffsets`**: يقبل File Offsets من IDA — يفعَّل فقط بعد تحقق حتمي (domain_get() يرجع غير NULL) وإلا يفشل صادقًا
- **فحص ماسك متعدد المراسي**: probe لكل من NSLog/malloc/objc_msgSend/il2cpp_class_get_name

## ما يلزم لإكمال ESP (من تحليلك — أنت قلت اللعبة محللة)
File Offsets داخل `DeltaForceClient` من IDA:
1. `il2cpp_domain_get`
2. `il2cpp_domain_get_assemblies`
3. `il2cpp_assembly_get_image`
4. `il2cpp_class_from_name`
5. `il2cpp_class_get_method_from_name`
6. `il2cpp_runtime_invoke`
7. (اختياري: unbox/string_chars/string_length — ولها بدائل يدوية)

تُوضع في `DGOffsets` في أعلى قسم المرحلة 2 في Tweak.m — صفر = معطّل.

## ملفات التشخيص (tmp حاوية اللعبة)
- `deltaguard_il2cpp_diag.txt` — مراسي الماسك + حالة المحلل
- `deltaguard_exports.txt` — كل رموز التصدير
