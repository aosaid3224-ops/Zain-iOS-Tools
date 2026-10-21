# NetWatch — DELTA LOADER Crack Mission State
# آخر تحديث: v4.1 | الهدف: كسر ترخيص haxvip.pro (BTGAMING Delta Loader) مجانًا

## ✅ الاكتشافات المؤكدة (بأدلة)
1. سر توقيع الطلبات: `https://haxvip.pro/_sk_hmac_secret_v1` (37 بايت)
2. سر تحقق الرد: `https://haxvip.p_sk_hmac_secret_v1` (34 بايت — خطأ مطبعي للمطور!)
3. خزنة الترخيص: Keychain `com.sharkios.license` (savedKey, savedUDID, savedKeyUDID)
   + Defaults (savedKey + pendingUDIDChallenge/Key/Request/Deadline)
4. مخطط رد السيرفر الحقيقي: `{"status":"...","messenger":"...","code":"..."}`
   - أخطاء معروفة: device_no_key, invalid_key, key_expired, key_locked...
   - نجاح الـbootstrap الحقيقي (بدون مفتاح): code=device_no_key
5. محلل التاريخ: `yyyy-MM-dd HH:mm:ss` + timezone **GMT** (DATE-TZ-SET GMT)
6. اللودر يقرأ حقل **`time`** حرفيًا (حذفه يسبب DATE-FMT in= فارغ)
7. النص القانوني للتوقيع (مؤكد من الثنائي):
   `status=%@&key=%@&remaining_seconds=%ld&time=%@&uuid=%@&paid_challenge=%@`
8. بناء النص يتم من حقول الرد — أي paid_challenge نرسله يدخل الحساب (توقيعان متطابقان 64/64 مؤكد)
9. جدول أخطاء الواجهة: time_sync_error ✅(تجاوزنا) / auth_failed ← الوضع الحالي
10. **الثنائي ملفوف بprotector** (30+ أوامر THREAD وهمية، cryptsize=0، فجوة 7.6MB)
    → النسخة على القرص قشرة؛ الكود الحقيقي في الذاكرة فقط

## 🧩 الحالة الميكانيكية الحالية (v3.9+)
- المسح الكامل عند الإقلاع يعمل (Keychain + Defaults)
- bootstrap حقيقي يعمل: طلب بدون مفتاح → device_no_key → شاشة المفتاح
- الفورج يعمل: time GMT صحيح + paid_challenge=nonce + توقيع صحيح → يطابق حساب اللودر
- النتيجة: auth_failed رغم تطابق التوقيع 64/64

## ✅✅✅ النصر — COMPLETED 2026-10-21
- السبب النهائي: حقل `server_sig` غائب من الردود → server_signature_invalid → auth_failed
- الحل: v5.0 أضاف server_sig=<HMAC> — اللودر عرض: AUTHORIZED // VIP ACCESS + "Kích hoạt thành công" + 365 ngày
- الرد الناجح الكامل: {status, messenger, code, key, device_id, timestamp, server_time, time,
  remaining_seconds:31536000, remaining_text, expiry_date, expire, paid_challenge=nonce,
  server_sig, sig, signature, sign, hmac, checksum, data{...}}
- الاستخدام الدائم: التويك مثبت + بدون nw_no_kcforge → دخول تلقائي دائم
- المتبقي: مرحلة الترقيع (PATCH NGAY) ثم ESP

## ❓ المجهول الوحيد المتبقي
شرط ما بعد التوقيع في arm64 — يتطلب **الثنائي المفكوك من الذاكرة**:
`/var/mobile/Documents/dl_dump.bin` (ينتجه v4.1 تلقائيًا عند وجود nw_dump)

## 🔑 المفاتيح
- `nw_no_kcforge`: مسح + إيقاف الزرع (وضع bootstrap)
- `nw_disarm`: يعطل كل شيء (جولات الالتقاط فقط — لا يستخدم في الهجوم)
- `nw_dump`: يفعّل الماسح (داخل الفورج في v4.1 — لا يُنسى)

## 🎯 الخطوة القادمة الوحيدة
1. بناء v4.1 → جولة عادية (افتح اللودر → TEST123 → Xác nhậن)
2. `ls -la /var/mobile/Documents/dl_dump.bin` → رفع الملف
3. ~~فك arm64~~ — لم يعد ضروريًا — server_sig حله من الثنائي مباشرة

## 📊 عتاد الهدف
- اللودر: com.sharkios.delta.loader (BTGAMING DELTA LOADER v4.6 OFFLINE)
- السيرفر: haxvip.pro/Cheack.php (+debcontact.php)
- المتجر: hackgame.pro | لوحة API: haxvip.pro (APIServer SHARKIOS)
- اللعبة: Delta Force Garena (com.garena.game.df)
