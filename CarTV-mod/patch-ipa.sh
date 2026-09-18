#!/bin/bash
# ============================================================
# CarTV-Plus — Parallel Identity Patcher (v1.1)
# يُنشئ نسخة موازية من CarTV بهوية جديدة (Bundle ID + اسم)
# الاستخدام:
#   ./patch-ipa.sh CarTV.ipa
#   ./patch-ipa.sh CarTV.ipa --name "CarTV+" --bundle app.zain.cartvplus
#   ./patch-ipa.sh CarTV.ipa --signer "Apple Development: you@mail.com"
#
# وضع التوقيع الافتراضي: ldid (لأجهزة الجيلبريك)
# وضع --signer: codesign (للتثبيت الجانبي AltStore/TrollStore/سيديا)
#
# v1.1: إصلاحان جراحيان لبيئة iOS:
#   1) كشف Mach-O عبر od+case بدل grep \|\| (BSD grep على iOS لا يدعم alternation — كان سيتخطى إعادة توقيع كل الثنائيات)
#   2) إعادة الضغط تشمل مجلد Payload/ نفسه (البنية السابقة كانت تنتج IPA غير قياسي)
# ============================================================
set -e

IN="${1:?usage: patch-ipa.sh <input.ipa> [options]}"
NAME="CarTV Zain"
BUNDLE="app.zain.cartvplus"
SIGNER=""

while [ $# -gt 1 ]; do
  case "$2" in
    --name)   NAME="$3";   shift 2;;
    --bundle) BUNDLE="$3"; shift 2;;
    --signer) SIGNER="$3"; shift 2;;
    *) echo "unknown option: $2"; exit 1;;
  esac
done

command -v plutil >/dev/null || { echo "[!] plutil مطلوب (iOS/macOS)"; exit 1; }
if [ -z "$SIGNER" ]; then
  command -v ldid >/dev/null || { echo "[!] ldid مطلوب (أو استخدم --signer)"; exit 1; }
fi

# ---------- كشف Mach-O متوافق مع BSD (iOS) ----------
is_macho() {
  local magic
  magic="$(head -c 4 "$1" | od -An -tx1 -N4 | tr -d ' \n')"
  case "$magic" in
    cffaedfe|cefaedfe|cafebabe|cafebabf) return 0 ;;  # arm64/armv7/fat/fat64
    *) return 1 ;;
  esac
}

WORK="$(mktemp -d)"
OUT="CarTV-Plus.ipa"
echo "[*] فك الضغط: $IN"
unzip -q "$IN" -d "$WORK"

APP="$(ls -d "$WORK"/Payload/*.app | head -1)"
[ -d "$APP" ] || { echo "[!] بنية IPA غير صالحة"; exit 1; }

echo "[*] تعديل الهوية:"
echo "    الاسم   : $NAME"
echo "    الحزمة : $BUNDLE"

# ---------- 1) Info.plist الرئيسي ----------
PLIST="$APP/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE" "$PLIST"
plutil -replace CFBundleDisplayName -string "$NAME" "$PLIST"
plutil -replace CFBundleName -string "$NAME" "$PLIST"
plutil -remove UISupportedDevices "$PLIST" 2>/dev/null || true   # دعم أوسع للأجهزة
echo "    [√] الهوية الرئيسية"

# ---------- 2) إضافات (PlugIns) ----------
find "$APP/PlugIns" -name "*.appex" -type d 2>/dev/null | while read -r APPEX; do
  AP=$(basename "$APPEX")
  case "$AP" in
    ScreenRelay.appex)         EXTID="$BUNDLE.ScreenRelay" ;;
    CastWidgetExtension.appex) EXTID="$BUNDLE.CastWidget" ;;
    *)                         EXTID="$BUNDLE.$AP" ;;
  esac
  plutil -replace CFBundleIdentifier -string "$EXTID" "$APPEX/Info.plist"
  echo "    [√] $AP → $EXTID"
done

# ---------- 3) تنظيف توقيع App Store ----------
rm -f "$APP/embedded.mobileprovision"
rm -f "$APP/iTunesMetadata.plist"
find "$APP" -name ".DS_Store" -delete 2>/dev/null || true
echo "    [√] تنظيف بقايا التوقيع القديم"

# ---------- 4) إعادة التوقيع ----------
resign_ldid() {
  local bin="$1"
  local ent
  ent="$(mktemp).plist"
  if ldid -e "$bin" 2>/dev/null | grep -q "<key>"; then
    ldid -e "$bin" > "$ent"
    ldid -S"$ent" "$bin"
  else
    ldid -S "$bin"
  fi
  rm -f "$ent"
}

echo "[*] إعادة توقيع الثنائيات:"
if [ -z "$SIGNER" ]; then
  # وضع الجيلبريك: حافظ على entitlements الأصلية (تشمل CarPlay إن وُجدت)
  find "$APP" -type f | while read -r f; do
    if is_macho "$f"; then
      resign_ldid "$f"
      echo "    [√] ldid: $(basename "$f")"
    fi
  done
else
  find "$APP" -type f | while read -r f; do
    if is_macho "$f"; then
      ent="$(mktemp).plist"
      ldid -e "$f" > "$ent" 2>/dev/null || echo -n "" > "$ent"
      codesign -fs "$SIGNER" --entitlements "$ent" --generate-entitlement-der "$f" 2>/dev/null \
        || codesign -fs "$SIGNER" --entitlements "$ent" "$f"
      rm -f "$ent"
      echo "    [√] codesign: $(basename "$f")"
    fi
  done
fi

# توقيع الحاويات الخارجية (appex ثم app)
if [ -n "$SIGNER" ]; then
  find "$APP/PlugIns" -name "*.appex" -type d 2>/dev/null | while read -r a; do
    codesign -fs "$SIGNER" "$a"
  done
  codesign -fs "$SIGNER" "$APP"
fi

# ---------- 5) إعادة الضغط (بنية IPA قياسية: Payload/…) ----------
echo "[*] بناء: $OUT"
(cd "$WORK" && zip -qr "$OLDPWD/$OUT" Payload)
rm -rf "$WORK"

echo ""
echo "════════════════════════════════════════"
echo " تم! الملف: $OUT"
echo " الهوية: $BUNDLE ($NAME)"
echo "════════════════════════════════════════"
echo ""
if [ -z "$SIGNER" ]; then
  echo " التثبيت (جيلبريك): appinst / TrollStore / Sileo"
else
  echo " ملاحظة: ميزات CarPlay تحتاج entitlement من حساب مدفوع"
  echo " التثبيت: AltStore / SideStore / TrollStore"
fi
