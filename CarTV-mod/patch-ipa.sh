#!/bin/bash
# ============================================================
# CarTV-Plus — Parallel Identity Patcher (v1.2)
# يُنشئ نسخة موازية من CarTV بهوية جديدة (Bundle ID + اسم)
# + شاشة إقلاع تحمل رصيد المعدّل (تُعرض عند فتح التطبيق)
# الاستخدام:
#   ./patch-ipa.sh CarTV.ipa
#   ./patch-ipa.sh CarTV.ipa --name "CarTV+" --bundle app.zain.cartvplus
#   ./patch-ipa.sh CarTV.ipa --signer "Apple Development: you@mail.com"
#   ./patch-ipa.sh CarTV.ipa --no-credit          (تعطيل رسالة الفتح)
#   ./patch-ipa.sh CarTV.ipa --credit "سطر 1" --credit-sub "سطر 2"
#
# وضع التوقيع الافتراضي: ldid (لأجهزة الجيلبريك)
# وضع --signer: codesign (للتثبيت الجانبي)
#
# v1.2: حقن شاشة الإقليد برسالة "معدّلة بواسطة Zain" (مستوى الموارد فقط)
# v1.1: كشف Mach-O عبر od+case (BSD/iOS)، وبنية IPA قياسية (Payload/)
# ============================================================
set -e

IN="${1:?usage: patch-ipa.sh <input.ipa> [options]}"
NAME="CarTV Zain"
BUNDLE="app.zain.cartvplus"
SIGNER=""
CREDIT=1
CREDIT_TITLE="هذه النسخة معدلة وتمت بواسطة المطور Zain"
CREDIT_SUB="لا تنسَ تدعمنا ❤️"

while [ $# -gt 1 ]; do
  case "$2" in
    --name)        NAME="$3";        shift 2;;
    --bundle)      BUNDLE="$3";      shift 2;;
    --signer)      SIGNER="$3";      shift 2;;
    --no-credit)   CREDIT=0;         shift 1;;
    --credit)      CREDIT_TITLE="$3"; shift 2;;
    --credit-sub)  CREDIT_SUB="$3";   shift 2;;
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

# ---------- 3) شاشة الإقليد: رصيد المعدّل (موارد فقط — بدون لمس الثنائي) ----------
if [ "$CREDIT" = "1" ]; then
  STORY="$APP/LaunchScreen.storyboard"
  if [ ! -f "$STORY" ]; then
    cat > "$STORY" <<'XEOF'
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="17150" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="Zain01">
    <device id="retina6_1" orientation="portrait" appearance="light"/>
    <dependencies><deployment identifier="iOS"/><plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="17125"/></dependencies>
    <scenes><scene sceneID="Zain01"><objects><viewController id="Zain01" sceneMemberID="viewController"><view key="view" contentMode="scaleToFill" id="Zain02"><rect key="frame" x="0.0" y="0.0" width="414" height="896"/><autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/><subviews>__ZAIN_LABELS__</subviews><color key="backgroundColor" white="0.0" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/></view></viewController></objects></scene></scenes>
</document>
XEOF
    plutil -replace UILaunchStoryboardName -string LaunchScreen "$PLIST"
  fi

  LABELS="$(mktemp)"
  cat > "$LABELS" <<XEOF
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" fixedFrame="YES" text="$CREDIT_TITLE" textAlignment="center" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="zainCreditTitle">
    <rect key="frame" x="16" y="596" width="343" height="24"/>
    <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
    <fontDescription key="fontDescription" type="boldSystem" pointSize="15"/>
    <color key="textColor" white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
    <nil key="highlightedColor"/>
</label>
<label opaque="NO" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" fixedFrame="YES" text="$CREDIT_SUB" textAlignment="center" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" translatesAutoresizingMaskIntoConstraints="NO" id="zainCreditSub">
    <rect key="frame" x="16" y="624" width="343" height="24"/>
    <autoresizingMask key="autoresizingMask" flexibleMaxX="YES" flexibleMaxY="YES"/>
    <fontDescription key="fontDescription" type="system" pointSize="14"/>
    <color key="textColor" red="1" green="0.4" blue="0.5" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
    <nil key="highlightedColor"/>
</label>
XEOF

  if grep -q "__ZAIN_LABELS__" "$STORY"; then
    # ملف جديد أنشأناه للتو: ضع الليبلات مكان العلامة
    LABELS_ALL="$(mktemp)"
    { printf '<subviews>'; cat "$LABELS"; printf '</subviews>'; } > "$LABELS_ALL"
    sed "/__ZAIN_LABELS__/r $LABELS_ALL" "$STORY" | sed "/__ZAIN_LABELS__/d" > "$STORY.tmp"
    mv "$STORY.tmp" "$STORY"
    rm -f "$LABELS_ALL"
  elif grep -q "</subviews>" "$STORY"; then
    # storyboard موجود: أضف الليبلات داخل subviews
    sed '/<\/subviews>/r '"$LABELS" "$STORY" > "$STORY.tmp"
    mv "$STORY.tmp" "$STORY"
  elif grep -q "</view>" "$STORY"; then
    # لا يوجد subviews: أنشئه
    LABELS_ALL="$(mktemp)"
    { printf '<subviews>'; cat "$LABELS"; printf '</subviews>'; } > "$LABELS_ALL"
    sed '/<\/view>/r '"$LABELS_ALL" "$STORY" > "$STORY.tmp"
    mv "$STORY.tmp" "$STORY"
    rm -f "$LABELS_ALL"
  else
    echo "    [!] تعذر حقن شاشة الإقليد — بنية غير متوقعة"
  fi
  rm -f "$LABELS"

  if plutil -lint "$STORY" >/dev/null 2>&1; then
    echo "    [√] رسالة الفتح: \"$CREDIT_TITLE / $CREDIT_SUB\""
  else
    echo "    [!] تحذير: فحص storyboard فشل — قد لا تظهر الرسالة"
  fi
fi

# ---------- 4) تنظيف توقيع App Store ----------
rm -f "$APP/embedded.mobileprovision"
rm -f "$APP/iTunesMetadata.plist"
find "$APP" -name ".DS_Store" -delete 2>/dev/null || true
echo "    [√] تنظيف بقايا التوقيع القديم"

# ---------- 5) إعادة التوقيع ----------
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

# ---------- 6) إعادة الضغط (بنية IPA قياسية: Payload/…) ----------
echo "[*] بناء: $OUT"
(cd "$WORK" && zip -qr "$OLDPWD/$OUT" Payload)
rm -rf "$WORK"

echo ""
echo "════════════════════════════════════════"
echo " تم! الملف: $OUT"
echo " الهوية: $BUNDLE ($NAME)"
if [ "$CREDIT" = "1" ]; then
echo " رسالة الفتح: مفعّلة"
fi
echo "════════════════════════════════════════"
echo ""
if [ -z "$SIGNER" ]; then
  echo " التثبيت (جيلبريك): appinst / TrollStore / Sileo"
else
  echo " ملاحظة: ميزات CarPlay تحتاج entitlement من حساب مدفوع"
  echo " التثبيت: AltStore / SideStore / TrollStore"
fi
