#!/usr/bin/env python3
# check_il2cpp.py — فحص تصديرات IL2CPP في ثنائي IPA محلياً (بلا بحث في الذاكرة)
# الاستخدام: python3 check_il2cpp.py <مسار DeltaForceClient.app> [-v]
import sys, struct, os

def read_at(f, off, n):
    f.seek(off); return f.read(n)

def uleb(f, end):
    r=0; s=0
    while f.tell()<end:
        b=f.read(1)[0]; r |= (b&0x7f)<<s
        if not (b&0x80): return r
        s+=7
    return r

def walk_trie(buf, node, start, end, prefix, out, limit):
    if node<start or node>=end or len(out)>=limit: return
    p=node
    tsz, i = uleb_buf(buf, p, end); p=i
    term = p+tsz; 
    if tsz>0 and prefix: out.add(prefix)
    p=term
    if p>=end: return
    kids, p = uleb_buf(buf, p, end)
    for _ in range(kids):
        if p>=end: return
        e=buf.index(b'\0', p, end); label=buf[p:e].decode('latin1'); p=e+1
        off, p = uleb_buf(buf, p, end)
        walk_trie(buf, start+off, start, end, prefix+label, out, limit)

def uleb_buf(buf, p, end):
    r=0; s=0
    while p<end:
        b=buf[p]; p+=1; r |= (b&0x7f)<<s
        if not (b&0x80): return r,p
        s+=7
    return r,p

def exports_of(path):
    with open(path,'rb') as f:
        head = read_at(f,0,0x4000)
        if head[:4]==b'\xca\xfe\xba\xbe':  # fat
            n=struct.unpack('>I',head[4:8])[0]
            best=None
            for i in range(n):
                off=8+i*20
                cpu,sub,size,align,foff=struct.unpack('>IIIII',head[off:off+20])
                if cpu==0x0100000c: best=(foff,size)  # arm64
            if not best: return None,"no arm64 slice"
            foff,size=best
        else:
            foff=0
        hdr=read_at(f,foff,0x4000)
        if hdr[:4]!=b'\xcf\xfa\xed\xfe': return None,"not mach-o 64"
        ncmds=struct.unpack('<I',hdr[16:20])[0]
        off=foff+struct.unpack('<I',hdr[20:24])[0]
        for _ in range(ncmds):
            cmd,csz=struct.unpack('<II',read_at(f,off,8))
            if cmd==0x80000033:  # LC_DYLD_EXPORTS_TRIE
                dfo,dsz=struct.unpack('<QQ',read_at(f,off+8,16))
                data=read_at(f,dfo,dsz)
                out=set(); walk_trie(data,0,0,len(data),"",out,200000)
                return sorted(out),"ok"
            off+=csz
        return None,"no exports trie"

def main():
    root=sys.argv[1]; verbose='-v' in sys.argv
    bins=[]
    main_bin=None
    for dirpath,_,files in os.walk(root):
        for fn in files:
            p=os.path.join(dirpath,fn)
            with open(p,'rb') as f: magic=f.read(4)
            if magic in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'):
                if fn==os.path.basename(root).replace('.app','') or 'DeltaForceClient' in fn:
                    main_bin=p
                elif '.framework' in p or fn.endswith('.dylib'):
                    bins.append(p)
    targets=([main_bin] if main_bin else [])+sorted(set(bins))
    found_any=False
    need=["il2cpp_domain_get","il2cpp_class_from_name","il2cpp_runtime_invoke",
          "il2cpp_object_unbox","il2cpp_string_chars","il2cpp_image_get_class",
          "il2cpp_domain_get_assemblies","il2cpp_class_get_method_from_name"]
    for p in targets:
        syms,status=exports_of(p)
        name=os.path.basename(p)
        if syms is None:
            print(f"[{name}] {status}"); continue
        il2=[s for s in syms if s.startswith('il2cpp')]
        print(f"[{name}] exports={len(syms)} il2cpp={len(il2)}")
        if il2:
            found_any=True
            for n in need:
                print(("  ✅ " if any(s==n for s in il2) else "  ❌ ")+n)
            if verbose:
                for s in il2[:80]: print("   ",s)
    print("\nVERDICT:", "IL2CPP EXPORTS PRESENT ✅ الجسر سيشتغل" if found_any
          else "IL2CPP EXPORTS MISSING ❌ ننتقل للخطة ب (SDKWALK بالاسم)")
if __name__=="__main__": main()
