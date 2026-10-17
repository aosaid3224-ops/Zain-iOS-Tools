مهمه تحقيق انجاز بناء esp 🎉🎉🎉

## سجل التطوير

### v0.6.2 — تجهيز مسار Il2CppDumper (بواسطة كمبيوتر)
- **مستخرج metadata مدمج**: يبحث في ذاكرة اللعبة عن توقيع `global-metadata.dat` (0xFAB11BAF) ويستخرجه إلى `/var/mobile/Documents/global-metadata.dat`
- **فحص cryptid**: يكشف إذا كان الثنائي مشفرًا FairPlay قبل نقله للكمبيوتر
- **مضيف المراسي**: يحدد أي صورة (DeltaForceClient أو GPM…) تصدر رموز il2cpp الـ13

### v0.6.1 — المستكشف الحي (Profiler Bridge)

### v0.6.0 — إصلاح _underscore + مراسي + DGOffsets

## سير العمل الكامل (كمبيوتر + جهاز)
1. ابنِ وثبّت التويك، افتح اللعبة دقيقة → يستخرج global-metadata.dat تلقائيًا
2. تأكد من `metadata-extracted=1` و `cryptid=` في ملف التشخيص
3. انقل الملفين للكمبيوتر (خادم HTTP في NewTerm — انظر التعليمات في المحادثة)
4. شغّل Il2CppDumper على الكمبيوتر → dump.cs + script.json
5. dump.cs = كل الكلاسات والأوفسيتات | script.json = عناوين Il2CppCodeRegistration/MetadataRegistration = مفتاح بناء runtime كامل داخل التويك
