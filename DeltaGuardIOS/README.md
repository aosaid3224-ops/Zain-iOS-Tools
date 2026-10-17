مهمه تحقيق انجاز بناء esp 🎉🎉🎉

## سجل التطوير

### v0.6.1 — المستكشف الحي (Profiler Bridge)
- استخدام `il2cpp_profiler_install_allocation` + `il2cpp_profiler_set_events` المصدَّرة — callbacks على كل تخصيص كائن داخل اللعبة
- الـ callback يلتقط: الكائن الحي + الكلاس → الاسم يُقرأ عبر `_il2cpp_class_get_name` المصدَّرة
- سجل حي: عدّاد alloc/enter، حتى 64 كلاس مرئي، مطابقات Player/Character/Soldier/Avatar/Pawn/Entity/Hero (12)
- كله بدون أوفسيتات وبدون IDA — التحقق بالأسماء مباشرة
- النتائج في اللوحة (🧪) وفي `deltaguard_il2cpp_diag.txt` (PROBE + SEEN + MATCHES)

### v0.6.0 — القرار الجراحي
- إصلاح الشرطة السفلية `_name` | مراسي il2cpp 13 مصدَّرة | محرك DGOffsets بالتحقق الحتمي

## اختبار v0.6.1 (مهم)
1. ابنِ وثبّت، افتح اللعبة، ادخل **مباراتين أو تدريب 3 دقائق**
2. افتح اللوحة — سطر 🧪 يجب أن يتحرك: alloc يكبر، كلاسات تظهر
3. إذا بقي `fired=0` → التثبيت المتأخر للـ profiler لا يعمل في هذه النسخة → ننتقل للخطة ب (frame-walk)
4. ابعث لي ملف التشخيص — سطور SEEN هي ذهب المرحلة 2

## أسئلة بانتظار إجاباتها (أدلة)
- `grep -iE "domain|invoke|assembly" deltaguard_exports.txt` — الأسماء الـ18 (طلع لنا العدد فقط)
- `grep -B8 "^_il2cpp_class_get_name$" deltaguard_exports.txt` — أي صورة تصدر الرموز الـ13
