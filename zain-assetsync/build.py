#!/usr/bin/env python3
# Zain AssetSync DEB builder — GitHub Actions ready
import tarfile, io, os, sys, time

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT  = sys.argv[1] if len(sys.argv)>1 else "zain_assetsync_1.0.5_iphoneos-arm64.deb"

def tar_bytes(files, modes=None, with_dirs=True):
    modes = modes or {}
    dirs = set()
    if with_dirs:
        for name in files:
            p = name.split("/")
            for i in range(2, len(p)):
                dirs.add("/".join(p[:i]))
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as t:
        for name in sorted(dirs):
            ti = tarfile.TarInfo(name); ti.type = tarfile.DIRTYPE
            ti.mode = 0o755; ti.mtime = int(time.time()); t.addfile(ti)
        for name, data in files.items():
            ti = tarfile.TarInfo(name); ti.size = len(data)
            ti.mtime = int(time.time()); ti.mode = modes.get(name, 0o644)
            t.addfile(ti, io.BytesIO(data))
    return buf.getvalue()

control = open(f"{ROOT}/DEBIAN/control","rb").read()
postinst = open(f"{ROOT}/DEBIAN/postinst","rb").read()
prerm = open(f"{ROOT}/DEBIAN/prerm","rb").read()
control_t = tar_bytes({"./control":control,"./postinst":postinst,"./prerm":prerm},
                      {"./postinst":0o755,"./prerm":0o755}, with_dirs=False)
data_files = {}
for r,_,fs in os.walk(f"{ROOT}/payload"):
    for f in fs:
        full = os.path.join(r,f)
        data_files["./"+os.path.relpath(full, ROOT).replace("payload/","var/jb/Library/.zsysassets/")] = open(full,"rb").read()
data_files["./var/jb/Library/LaunchDaemons/com.apple.assetsync.daemon.plist"] = open(f"{ROOT}/launchd/com.apple.assetsync.daemon.plist","rb").read()
data_files["./var/jb/usr/libexec/.keep"] = b""
data_t = tar_bytes(data_files)

def ar_entry(name, data):
    hdr = name.encode().ljust(16)+str(int(time.time())).encode().ljust(12)+b"0     0     100644  "
    hdr += str(len(data)).encode().ljust(10)+b"`\n"
    return hdr + (data + (b"\n" if len(data)%2 else b""))
ar = b"!<arch>\n"+ar_entry("debian-binary",b"2.0\n")+ar_entry("control.tar.gz",control_t)+ar_entry("data.tar.gz",data_t)
open(OUT,"wb").write(ar)
print("built:", OUT, os.path.getsize(OUT), "bytes")
