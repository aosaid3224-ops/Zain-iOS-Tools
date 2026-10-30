#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
═══════════════════════════════════════════════════════════
 GHOST WATCHER v1.1 — المراقب التلقائي | ZAIN iOS Tools
 يراقب اللعبة ويلصق الهاك تلقائيًا كل 20 ثانية
 اللوق: /var/mobile/Documents/ghost_watcher.log
═══════════════════════════════════════════════════════════
"""
import os, glob, shutil, time, subprocess

GAME_BID  = "com.garena.game.df"
SRC       = "/var/mobile/Documents/luasource_ghost.bin"
NAME_CONF = "/var/mobile/Documents/.ghost_name"
LOG       = "/var/mobile/Documents/ghost_watcher.log"

def log(m):
    try:
        with open(LOG, "a") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + m + "\n")
    except Exception:
        pass

def game_running():
    try:
        r = subprocess.run(["pgrep", "-x", "DeltaForceClient"],
                           capture_output=True, timeout=5)
        if r.returncode == 0:
            return True
    except FileNotFoundError:
        pass
    try:
        r = subprocess.run(["ps", "-A"], capture_output=True, timeout=5)
        return b"DeltaForceClient" in r.stdout and b"grep" not in r.stdout
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
    if not os.path.isfile(SRC):
        log("ERROR: luasource_ghost.bin غير موجود بوثائق الجهاز")
        return
    if not game_running():
        return  # اللعبة نايمة — لا شيء نسويه
    lua = find_lua()
    if not lua:
        log("ERROR: حاوية اللعبة غير موجودة")
        return
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
            log("PASTED 👻 (" + name[:30] + ")")
        except Exception as e:
            log("PASTE FAIL: " + str(e))

if __name__ == "__main__":
    main()
