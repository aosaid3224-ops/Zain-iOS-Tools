# 🔓 BTGAMING DELTA LOADER — Crack Reference Document
**تاريخ الإنجاز: 2026-10-21 | الإصدار الحاسم: v5.0+ | المفتاح الناجح: `TEST123`**

---

## 🎯 الهدف
- **اللودر**: BTGAMING DELTA LOADER v4.6 (Hệ thống quản lý LuaSource & Patch game)
- **Bundle**: com.sharkios.delta.loader | الفئة: `OBF_SK92E1B48` (مُعفاة الاسم)
- **السيرفر**: `haxvip.pro/Cheack.php` (+ `debcontact.php`)
- **الحماية**: ترخيص مفتاح VIP مدفوع + تحقق محلي متعدد الطبقات + ثنائي ملفوف
- **النتيجة**: `AUTHORIZED // VIP ACCESS` — تفعيل 365 يوم — مجانًا

---

## 🔑 الأسرار المستخرجة (مؤكدة بالأدلة)

### 1. أسرار HMAC (خطآن مطبعيان ذهبيان)
| الغرض | السر | الطول |
|---|---|---|
| توقيع **الطلبات** | `https://haxvip.pro/_sk_hmac_secret_v1` | 37 |
| تحقق **الردود** | `https://haxvip.p_sk_hmac_secret_v1` ⚠️ (ناقص "ro/") | 34 |

**آلية بناء السر** (من الثنائي): `"%@_sk_hmac_secret_v1"` — بادئة ديناميكية + قالب ثابت.

### 2. مخططات السيرفر الحقيقية
- **الرد القياسي**: `{"status":"...","messenger":"...","code":"..."}`
- **bootstrap (بدون مفتاح)**: `{"status":"error","messenger":"Thiết bị chưa có key hợp lệ...","code":"device_no_key"}`
- **المفتاح الخاطئ**: `{"code":"invalid_key"}`
- **رموم الأخطاء في الثنائي**: `invalid_server_time`, `time_drift`, `server_signature_invalid`, `time_sync_error`, `auth_failed`, `device_no_key`, `invalid_key`, `key_expired`, `key_locked`, `key_capacity_reached`...

### 3. النص القانوني للتوقيع (مقروء حرفيًا من الثنائي)
```
status=%@&key=%@&remaining_seconds=%ld&time=%@&uuid=%@&paid_challenge=%@
```
- يُبنى **من حقول الرد** — أي قيم نرسلها تدخل الحساب
- `time` بصيغة `yyyy-MM-dd HH:mm:ss` بتوقيت **GMT** (`en_US_POSIX`)
- `paid_challenge` = **nonce الطلب** (ربط الرد بالطلب)
- **حقل المقارنة**: `server_sig` ← 🎯 كان غائبًا من كل ردودنا — سبب `auth_failed`

### 4. خزنة الترخيص
- **Keychain** (خدمة `com.sharkios.license`): `savedKey`, `savedUDID`, `savedKeyUDID`
- **Defaults**: `savedKey` + `pendingUDIDChallenge/Key/Request/Deadline`
- اللودر يخزن التفعيل **بنفسه** بعد أي "نجاح"

### 5. حلقات التحقق بالترتيب (مثبتة باللوغات)
```
1. قراءة savedKey (Keychain→Defaults)      → تخطّي الشاشة أو إظهارها
2. bootstrap: طلب بدون مفتاح               → device_no_key → شاشة المفتاح
3. الطلب الموقّع (HMAC-37)                   → نفورجه بالرد الناجح
4. تحليل time (GMT, yyyy-MM-dd HH:mm:ss)   → كان يفشل بالمنطقة الزمنية المحلية
5. بناء canon من الرد + HMAC-34            → مطابق لحسابنا 64/64 ✅
6. مقارنة canon == response[server_sig]    → 🎯 server_sig الغائب كان الجدار الأخير
7. نجاح → KC-ADD savedKey/savedKeyUDID     → VIP ACCESS + 365 ngày
```

---

## 📦 الرد المزوّر الناجح (الكامل)
```json
{
  "status": "success",
  "messenger": "Kích hoạt thành công",
  "code": "success",
  "key": "TEST123",
  "device_id": "<UDID>",
  "timestamp": "<epoch>",
  "server_time": "<GMT now>",
  "time": "<GMT now>",
  "remaining_seconds": 31536000,
  "remaining_text": "365 days",
  "expiry_date": "<GMT now+1y>",
  "expire": "<date+1y>",
  "paid_challenge": "<nonce الطلب>",
  "server_sig": "<HMAC-SHA256(secret34, canon)>",
  "sig": "...", "signature": "...", "sign": "...",
  "hmac": "...", "checksum": "...",
  "data": {"status":"active","expire":"<date+1y>","expired_time":"<GMT now+1y>"}
}
```
canon = `status=success&key=TEST123&remaining_seconds=31536000&time=<GMT>&uuid=<UDID>&paid_challenge=<nonce>`

---

## ⚔️ سجل المعركة (17 إصدارًا)
| الإصدار | الإنجاز الحاسم |
|---|---|
| v1.0-v1.2 | خطافات Keychain/KVS/CCHmac + فورج أولي |
| v1.1 | 💎 سر HMAC الأول من اللوغ (key/data hex) |
| v1.3 | 💎 KC-FORGE — زرع savedKey في الذاكرة → شاشة المفتاح سقطت |
| v1.5 | nw_disarm — أول رؤية لرد السيرفر الحقيقي |
| v2.0-2.3 | 💎 تحويل الحقول الزمنية لنصوص + **GMT/UTC** → time_sync_error سقطت |
| v2.4-3.2 | اكتمال مخطط successPayload + paid_challenge تجارب |
| v3.3-3.6 | إحياء bootstrap: مسح Keychain+Defaults تلقائيًا |
| v3.7 | bootstrap حقيقي مكشوف: `device_no_key` — لا تحدٍّ مخزن |
| v3.9 | إعادة حقل `time` (حذفه كسر التحليل) |
| **v5.0** | 💎💎 **server_sig** — اسم الحقل من الثنائي بجانب canon → **النصر** |
| v5.1 | إصلاح ماسح الذاكرة (slide) |

---

## 🔬 منهجية الاختراق (للمرجع)
1. **الخطافات الشاملة أولًا**: CCHmac / Keychain / Defaults / NSURLSession / JSON — رؤية كل شيء قبل فهمه
2. **جولة نزع السلاح** (nw_disarm): رؤية مخطط السيرفر الحقيقي بدل تخمينه
3. **الثنائي مرجع دائم**: strings أعطت المخططات والمفاتيح وserver_sig — حتى مع الالتفاف
4. **خطأ مطبعي للمطور = ثغرة**: سرّان بفرق 3 بايت كشفا آلية التحقق كلها
5. **إثبات رياضي قبل كل بناء**: مطابقة 64/64 hex في بايثون قبل أي جولة
6. **متغير واحد لكل جولة**: عزل السبب باستبعاد منهجي

## ⚠️ ملاحظات فنية
- الثنائي **ملفوف** (protector): 30+ أوامر THREAD وهمية، إنتروبي 7.72، cryptsize=0 — الفك الساكن غير ممكن؛ الذاكرة الحية هي المرجع
- النجاح الدائم: التويك مثبت + **بدون** nw_no_kcforge / nw_disarm / nw_dump
- اللودر الآن يخزن تفعيله بنفسه — حتى إن توقف الفورج يبقى التفعيل محليًا
