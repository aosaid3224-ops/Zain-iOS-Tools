#!/bin/bash
# بناء ANUBISCrack على الجهاز (NewTerm + Dopamine)
set -e
cd "$(dirname "$0")"
export THEOS=~/theos
[ -d "$THEOS" ] || { echo "installing theos..."; bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"; }
make clean && make package
echo "✅ DEB READY: packages/com.zain.anubiscrack_*_iphoneos-arm64.deb"
echo "install: sudo dpkg -i packages/com.zain.anubiscrack_*_iphoneos-arm64.deb && killall -9 TempMail"
