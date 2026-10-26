# DragonCheat Crack — Final Recon Map (2026-10-26)

## المؤكد بالدليل
- API: hackgamefile.com (lookup/verify) — forgeable ✅ (GameForge)
- code check: reads ONLY "code" via dict at +0x1fd448 (closure blr) — "success" يطابق ✅
- لا قراءات dict لـ sig/valid/sig_ed → التوقيع على **RAW BYTES** للرد
- HMAC (CC_SHA256 K=SHA256("")): موجود لكنه ليس بوابة القرار
- SHA256 داخلي: 0xdc5d4..0xdd178 (K-table @0x3b9cd0, H0 @0x3b9b40)
- SHA-512 داخلي: K-table @0x3c2300 (محرك Ed25519)
- Ed25519: يوقّع الرد الخام — عناوينه عبر جداول مؤشرات (تدفق مسطّح)
- نمط التعمية: Control-Flow Flattening — كل بلوك: LDRB حالة → CMP → جدول قفز → BR x8

## خريطة النقاط الجراحية (file offsets == runtime offsets من base)
| العنصر | الأوفست |
|---|---|
| قراءة code (closure استدعاء) | 0x1fd414–0x1fd448 |
| موزّع التدفق (نموذجي) | 0x1fd3c8–0x1fd3f0 |
| نص "Expires: " | 0x3caf0d (يقرأ @0x2cc9c) |
| نص "Invalid: " | 0x3ca82b (يقرأ @0x2fbfc) |
| "[verify] key bad" handler | 0x3ccad4 |
| SHA256 core | 0xdc5d4–0xdd178 |
| SHA-512 K-table | 0x3c2300 |

## خطة النهاية (Ghidra)
1. تحميل DragonGA.dylib في Ghidra (arm64, base 0)
2. Goto 0x1fd3c8 — دالة معالج التحقق (flattened)
3. Decompile — البحث عن compare code=="success" ثم call verify(rawBytes, sig, pk)
4. عزل فرع النجاح/الفشل → Patch: فرع الفشل → NOP أو تحويله لنجاح
5. bytes الجاهزة عبر dd → ldid -S → استبدال → تفعيل دائم

## أدواتنا الجاهزة
- GameForge (ريبو، يعمل): forge كامل + مراقبة + تسميم MAC
- GameRecon, DeviceMask, LoaderRecon(NetWatch) — كلها في الريبو
