#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
═══════════════════════════════════════════════════════════
  GHOST PASTE v1.0 — نظام الشبح | ZAIN iOS Tools
  لصق هاك Delta Force في اللحظة الصحيحة — بدون لودر خارجي
═══════════════════════════════════════════════════════════
  الاستخدام:
    python3 ghostpaste.py setup   ← مرة وحدة (يحصد اسم الملف من باتش اللودر)
    python3 ghostpaste.py now     ← الصق أثناء تحميل موارد الماتش!
  ملف الهاك: ضع luasource_ghost.bin في /var/mobile/Documents/
═══════════════════════════════════════════════════════════
"""
import os, sys, shutil, glob

GAME_BID  = "com.garena.game.df"
NAME_CONF = "/var/mobile/Documents/.ghost_name"
SOURCES   = ["/var/mobile/Documents/luasource_ghost.bin",
             "/var/mobile/Documents/luasource_patched.bin"]

def find_game_dir():
    for d in glob.glob("/var/mobile/Containers/Data/Application/*"):
        meta = os.path.join(d, ".com.apple.mobile_container_manager.metadata.plist")
        if os.path.isfile(meta):
            try:
                if GAME_BID.encode() in open(meta, "rb").read():
                    return d
            except Exception:
                pass
    return None

def lua_dir(data_dir):
    return os.path.join(data_dir, "Documents/DeltaForce/Saved/LuaSource")

def harvest_name(lua):
    big = [n for n in os.listdir(lua)
           if os.path.getsize(os.path.join(lua, n)) > 300000] if os.path.isdir(lua) else []
    if len(big) == 1:
        with open(NAME_CONF, "wb") as f:
            f.write(big[0].encode("utf-8", "surrogateescape"))
        return big[0]
    return None

def saved_name():
    if os.path.isfile(NAME_CONF):
        return open(NAME_CONF, "rb").read().decode("utf-8", "surrogateescape")
    return None

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "now"
    data = find_game_dir()
    if not data:
        print("❌ اللعبة غير مثبتة على الجهاز"); sys.exit(1)
    lua = lua_dir(data)

    if cmd == "setup":
        n = harvest_name(lua)
        print("✅ تم حصد اسم الملف:", (n[:45] + "...") if n else "⚠️ شغّل باتش اللودر مرة أخيرة ثم أعد setup")
        return

    src = next((s for s in SOURCES if os.path.isfile(s)), None)
    if not src:
        print("❌ ضع luasource_ghost.bin في /var/mobile/Documents/"); sys.exit(1)

    os.makedirs(lua, exist_ok=True)
    name = saved_name() or "GhostUpdate.lua"
    dst = os.path.join(lua, name)
    try:
        shutil.copyfile(src, dst)
        os.chmod(dst, 0o644)
    except PermissionError:
        print("❌ صلاحية مرفوضة — تأكد من فك أقفال: chflags nouchg + chmod 755 على LuaSource")
        sys.exit(1)

    b = open(dst, "rb").read()
    print(f"👻 تم اللصق: {name[:40]}")
    print(f"   الحجم: {len(b)} بايت | بصمة الشبح: {'✅' if b'ZAINIOS8' in b else '⚠️ ملف قديم'}")
    print("⏱️  الآن: عدّ للعبة واستمتع — القائمة بتظهر مع الماتش")

if __name__ == "__main__":
    main()
