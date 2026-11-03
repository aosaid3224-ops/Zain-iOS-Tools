#!/usr/bin/env python3
"""CrackRecon v2.0 — Mach-O 64 recon engine (stdlib only)."""
import struct, sys, json, math, re, os

LC_SEGMENT_64, LC_SYMTAB, LC_ENCRYPTION_INFO_64 = 0x19, 0x2, 0x2C

class MachO:
    def __init__(self, path):
        self.path = path
        self.data = open(path, "rb").read()
        assert struct.unpack("<I", self.data[:4])[0] == 0xFEEDFACF
        (_, _, self.filetype, self.ncmds, _, _, _) = struct.unpack("<iiIIIII", self.data[4:32])
        self.segments, self.sections, self.encryption, self.symtab = [], [], None, None
        off = 32
        for _ in range(self.ncmds):
            cmd, cmdsize = struct.unpack("<II", self.data[off:off+8])
            if cmd == LC_SEGMENT_64:
                seg = self.data[off+8:off+24].split(b"\0")[0].decode("latin1")
                vm, vmsz, foff, fsz, _, _, nsects, _ = struct.unpack("<QQQQIIII", self.data[off+24:off+72])
                self.segments.append(dict(name=seg, vm=vm, vmsize=vmsz, fileoff=foff, filesize=fsz))
                so = off + 72
                for _ in range(nsects):
                    sn = self.data[so:so+16].split(b"\0")[0].decode("latin1")
                    sg = self.data[so+16:so+32].split(b"\0")[0].decode("latin1")
                    addr, size, fo = struct.unpack("<QQI", self.data[so+32:so+52])
                    self.sections.append(dict(seg=sg, name=sn, addr=addr, size=size, fileoff=fo))
                    so += 80
            elif cmd == LC_ENCRYPTION_INFO_64:
                self.encryption = struct.unpack("<III", self.data[off+8:off+20])
            elif cmd == LC_SYMTAB:
                self.symtab = struct.unpack("<IIIIII", self.data[off+8:off+32])
            off += cmdsize
    def section(self, seg, name):
        for s in self.sections:
            if s["seg"] == seg and s["name"] == name:
                return self.data[s["fileoff"]:s["fileoff"]+s["size"]]
        return b""

def entropy(b):
    if not b: return 0.0
    f = [0]*256
    for x in b: f[x] += 1
    n = len(b)
    return -sum((c/n)*math.log2(c/n) for c in f if c)

def analyze(path):
    m = MachO(path)
    report = dict(file=os.path.basename(path), size=len(m.data),
                  fairplay_encrypted=(m.encryption or {}).get("cryptid",0)==1,
                  segments=m.segments, sections=[{k:v for k,v in s.items()} for s in m.sections])
    # كشف packer/تشفير
    report["findings"] = []
    for seg in m.segments:
        if seg["name"].startswith("__RT") or "PACK" in seg["name"].upper():
            report["findings"].append(f"custom segment {seg['name']} ({seg['filesize']//1024}KB) — runtime payload")
    for s in m.sections:
        if s["size"] > 0x10000 and s["fileoff"]:
            b = m.data[s["fileoff"]:s["fileoff"]+min(s["size"],0x100000)]
            e = entropy(b)
            if e > 7.6: report["findings"].append(f"{s['seg']},{s['name']} entropy={e:.2f} — encrypted blob")
    # بصمات مكتبات
    head = m.data[:0xA00000]
    libs = {"libcurl":b"Connection closure while negotiating auth","nghttp2":b"nghttp2_session",
            "OpenSSL":b"ASN1_item_verify_ctx","Dear ImGui":b"Dear ImGui is licensed under the MIT"}
    report["libs"] = [k for k,v in libs.items() if v in head]
    # سلاسل + مفاتيح
    raw = m.section("__TEXT","__cstring").decode("latin1","ignore")
    report["urls"] = sorted(set(re.findall(r"https?://[A-Za-z0-9.\-_~%+/]+", raw)))[:50]
    report["anubis_keys"] = sorted(set(re.findall(r"\bAnu[A-Za-z0-9]{29}\b", raw + m.section("__RTDATA","__rtdata").decode("latin1","ignore"))))[:20]
    report["objc_alert_selectors"] = [x for x in m.section("__TEXT","__objc_methname").decode("latin1","ignore").split("\0") if "alert" in x.lower()]
    # مؤشرات من RTDATA → RTCODE
    return report

if __name__ == "__main__":
    rep = analyze(sys.argv[1])
    print(json.dumps(rep, indent=2, default=str)[:8000])
    if "--json" in sys.argv:
        json.dump(rep, open(sys.argv[sys.argv.index("--json")+1],"w"), indent=2, default=str)
