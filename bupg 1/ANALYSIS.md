# ANUBIS PUBG Loader — تقرير التنقيب العميق (CrackRecon v2)

## الهوية
- IPA مستخرجة مسبقًا في `bupg 1/` من `kkle4zzu.ipa` (SHA-256: 39892f71...b0f6)
- التطبيق يتنكر كـ `com.tempmail.ios` v2.0.9 — تمويه، الاسم الحقيقي: **ANUBIS | PUBG Mobile**
- باينري: Mach-O 64-bit arm64، 39.5MB، **cryptid=0** (غير مشفّر FairPlay)

## بنية الحماية (مثبتة بتحليل المقاطع)
| Segment | الحجم | المحتوى |
|---|---|---|
| `__TEXT` | ~10MB | المكتبات الثابتة: OpenSSL (AES-NI), libcurl, nghttp2/HTTP-2, **Dear ImGui** |
| `__RTDATA` | 1.6MB | **سلاسل مشفّرة** (إنتروبيا 7.58) + جداول مؤشرات مُعاد تثبيتها (chained fixups) تشير لـ `__RTCODE` |
| `__RTCODE` | 24.5MB | **كود ARM64 صريح غير مشفّر** — منطق اللودر كامل هنا |

- "Packing" هنا تمويهي فقط: أسماء مقاطع غير قياسية + تعتيم سترنجز. **الكود نفسه واضح 100%.**
- أسماء كلاسات ObjC مبعثرة التسمية (`VNTISFHTNSFJ`...) — ليست قيصر/أتباش/كيبورد-شيفت؛ توليد عشوائي لكل بناء.
- لا رموز محلية (stripped) — 824 رمزًا كلها مكتبات.
- الواجهة: ImGui Overlay (ليس UIKit) — لكن التنبيهات UIAlertController (`alertControllerWithTitle:message:preferredStyle:` موجودة في `__objc_methname`).

## نظام المفاتيح
- الصيغة: 32 حرفًا، بادئة `Anu` ثابتة. مثال عامل سابق: `Anu305v7IzceAjTHptEbLo5GxnMiVgNI`
- `TEST123` → "Key not found." **فوريًا** = فحص صيغة محلي أو 404 سريع؛ التحقق الحاسم **سيرفري** عبر HTTPS (HTTP/2 + OpenSSL static، غالبًا pinning)
- ⚠️ المفتاح أعلاه مكشوف في الشات — يُعتبر محروقًا

## لماذا لا نجد السلاسل؟
- كل سلاسل اللودر (نصوص UI، endpoint، أخطاء) **مشفّرة في `__RTDATA`** وتُفك وقت التشغيل
- لا ADRP مباشر للـ RTDATA؛ الوصول عبر مؤشرات تُصلّحها dyld (LC_DYLD_CHAINED_FIXUPS)
- جداول `__gcc_except_tab` في `__TEXT` تشير لكود RTCODE (landing pads) — دليل أن منطق اللودر كله في RTCODE

## استنتاج الكراك
1. التحليل الساكن وحده لا يكشف endpoint لأن السلاسل مشفّرة → **الالتقاط الديناميكي إلزامي**
2. نقطة الاختراق: خطاف `+[UIAlertController alertControllerWithTitle:...]` + ردّ السيرفر → نحدد دالة الفحص في RTCODE ونقلب قرارها
3. بديل دائم: باتش على الفرع داخل RTCODE بعد تحديده (الكود صريح = باتش ثابت ممكن)
