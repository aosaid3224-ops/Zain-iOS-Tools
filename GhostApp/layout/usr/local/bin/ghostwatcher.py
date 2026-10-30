#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""GHOST WATCHER v1.2 — نبض حي + لصق تلقائي | ZAIN iOS Tools"""
import os, glob, shutil, time, subprocess

GAME_BID  = "com.garena.game.df"
SRC       = "/var/mobile/Documents/luasource_ghost.bin"
NAME_CONF = "/var/mobile/Documents/.ghost_name"
LOG       = "/var/mobile/Documents/ghost_watcher.log"
HB        = "/var/mobile/Documents/.ghost_hb"

def log(m):
    try:
        with open(LOG, "a") as f:
            f.write(time.strftime("%H:%M:%S ") + m + "\n")
    except Exception:
        pass

def heartbeat(running):
    now = time.time()
    last = 0
    if os.path.isfile(HB):
        try: last = float(open(HB).read().strip() or 0)
        except Exception: last = 0
    if now - last >= 300:
        with open(HB, "w") as f: f.write(str(now))
        log("💓 المراقب حي | اللعبة: %s | الملف: %s" % (
            "تعمل 🎮" if running else "لا",
            "جاهز ✅" if os.path.isfile(SRC) else "ناقص ⚠️"))

def game_running():
    try:
        r = subprocess.run(["pgrep", "-x", "DeltaForceClient"], capture_output=True, timeout=5)
        if r.returncode == 0: return True
    except FileNotFoundError:
        pass
    try:
        r = subprocess.run(["ps", "-A"], capture_output=True, timeout=5)
        return b"DeltaForceClient" in r.stdout
    except Exception:
        return False

def find_lua():
    for d in glob.glob("/var/mobile/Containers/Data/Application/*"):
        meta = os.path.join(d, ".com.apple.mobile_container_manager.metadata.plist")
        if os.path.isfile(meta):
            try:
                if GAME_BID.encode() in open(meta, "rb").read():
                    return os.path.join(d, "Documents/DeltaForce/Saved/LuaSource")
            except Exception:
                pass
    return None

def main():
    running = game_running()
    heartbeat(running)
    if not os.path.isfile(SRC):
        log("⚠️ ملف الهاك ناقص — أعد تثبيت الحزمة"); return
    if not running:
        return
    lua = find_lua()
    if not lua:
        log("⚠️ حاوية اللعبة غير موجودة"); return
    name = "GhostUpdate.lua"
    if os.path.isfile(NAME_CONF):
        name = open(NAME_CONF, "rb").read().decode("utf-8", "surrogateescape")
    dst = os.path.join(lua, name)
    need = True
    if os.path.isfile(dst):
        try:
            need = open(SRC, "rb").read() != open(dst, "rb").read()
        except Exception:
            need = True
    if need:
        try:
            os.makedirs(lua, exist_ok=True)
            shutil.copyfile(SRC, dst)
            os.chmod(dst, 0o644)
            log("PASTED 👻 (" + name[:28] + ")")
        except Exception as e:
            log("PASTE FAIL: " + str(e))

if __name__ == "__main__":
    main()
