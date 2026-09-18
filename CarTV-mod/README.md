# CarTV-Plus — النسخة الكاملة (الحزمة الموحدة)

حزمة واحدة تجمع كل شيء: التحليل الكامل للتطبيق + أداة إنشاء النسخة الموازية + تقرير الاكتشافات.

## البنية

```
CarTV-mod/
├── README.md         ← هذا الملف
├── patch-ipa.sh      ← أداة إنشاء النسخة الموازية بهوية جديدة
├── FINDINGS.md       ← تقرير الاكتشافات المؤكدة (StoreKit 2، Keychain، الحماية)
└── analysis/         ← التحليل الساكن الكامل للنسخة 1.0.8
    ├── strings/      ← 12,143 سطر مستخرجة من الباينري الرئيسي
    ├── advanced/     ← تقارير LLVM/LIEF (رموز، أقسام، مكتبات مربوطة)
    ├── network-domains.txt
    ├── file-inventory.tsv
    ├── binary-summary.json
    ├── SHA256SUMS
    └── ...           ← بقية تقارير JSON/TSV
```

## ماذا تفعل الأداة

`patch-ipa.sh` يحوّل `CarTV.ipa` إلى نسخة **موازية** تعمل بجانب الأصلية:

| العنصر | قبل | بعد |
|---|---|---|
| Bundle ID | `com.lyntra.player` | `app.zain.cartvplus` (قابل للتخصيص) |
| اسم العرض | CarTV | CarTV Zain (قابل للتخصيص) |
| UISupportedDevices | مقيدة (iPhone11+) | محذوفة — دعم أوسع |

## المتطلبات والاستخدام

```bash
# جيلبريك (افتراضي — يحافظ على entitlements الأصلية)
./patch-ipa.sh CarTV.ipa

# تثبيت جانبي (macOS + شهادة مطور)
./patch-ipa.sh CarTV.ipa --signer "Apple Development: you@mail.com"

# هوية مخصصة
./patch-ipa.sh CarTV.ipa --name "CarTV Pro" --bundle app.zain.mytv
```

> يتطلب IPA **مفكوك التشفير** مسبقاً — ملف App Store المشفر لن يعمل.

## ملاحظات

- الثنائيات لا تُعدَّل — تعديل هوية وموارد فقط (انظر `FINDINGS.md` لما اكتشفناه داخل الباينري).
- الثنائيات تُعاد توقيعها مع استخراج entitlements الأصلية تلقائياً (`ldid -e`) — أي entitlement مثل CarPlay يُحفظ.
- مصدر كل الأرقام والادعاءات في `FINDINGS.md` هو `analysis/strings/CarTV.txt` — البيانات الخام موجودة دائماً للمراجعة.
