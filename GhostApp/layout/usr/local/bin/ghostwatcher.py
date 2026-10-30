#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""GHOST WATCHER v1.3 — python يراقب + المساعد (root) يلصق | ZAIN"""
import os, time, subprocess

SRC = "/var/mobile/Documents/luasource_ghost.bin"
LOG = "/var/mobile/Documents/ghost_watcher.log"
HB  = "/var/mobile/Documents/.ghost_hb"
HELPER = "/var/jb/usr/bin/ghosthelper"

def log(m):
    try:
        with open(LOG, "a") as f: f.write(time.strftime("%H:%M:%S ") + m + "\n")
    except Exception: pass

def heartbeat(running):
    now = time.time(); last = 0
    if os.path.isfile(HB):
        try: last = float(open(HB).read().strip() or 0)
        except Exception: last = 0
    if now - last >= 300:
        open(HB, "w").write(str(now))
        log("💓 المراقب حي | اللعبة: %s | الملف: %s" % (
            "تعمل 🎮" if running else "لا",
            "جاهز ✅" if os.path.isfile(SRC) else "ناقص ⚠️"))

def game_running():
    try:
        r = subprocess.run(["pgrep", "-x", "DeltaForceClient"], capture_output=True, timeout=5)
        return r.returncode == 0
    except Exception:
        return False

def main():
    running = game_running()
    heartbeat(running)
    if not running: return
    if not os.path.isfile(SRC):
        log("⚠️ ملف الهاك ناقص"); return
    # اللصق عبر المساعد root (يتجاوز sandbox الدايمون)
    try:
        r = subprocess.run([HELPER, "dopaste"], capture_output=True, timeout=30)
        if r.returncode != 0 and r.returncode != 2:
            log("helper rc=%d" % r.returncode)
    except Exception as e:
        log("helper err: %s" % e)

if __name__ == "__main__":
    main()
