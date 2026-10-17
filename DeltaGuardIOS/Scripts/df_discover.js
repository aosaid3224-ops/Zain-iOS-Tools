/*
 * df_discover.js — اكتشاف FNamePool في Delta Force (Frida)
 * التشغيل: frida -U -n DeltaForceClient -l df_discover.js
 * الناتج: عناوين بلوكات الأسماء + مؤشرات GNamePool المرشحة مع سياقها الخام
 */
'use strict';
function log(s){ console.log('[DF] ' + s); }
function rp(p){ try { return p.readU64(); } catch(e){ return null; } }
function hex(p){ return '0x' + p.toString(16); }
function ptrPat(p){ let s=''; for (let i=0;i<8;i++) s += ('0'+p.shr(i*8).and(0xff).toString(16)).slice(-2)+(i<7?' ':''); return s; }

const mainMod = Process.findModuleByName('DeltaForceClient') || Process.mainModule;
const textLo = mainMod.base, textHi = textLo.add(mainMod.size);
log('module=' + mainMod.name + ' text=' + hex(textLo) + '-' + hex(textHi));

let ranges = [];
for (const pr of ['r--','rw-']) {
  try { for (const r of Process.enumerateRanges({protection: pr, coalesce: true}))
    if (r.size > 0 && r.size <= 0x40000000) ranges.push(r); } catch(e){}
}
ranges.sort((a,b)=>a.base.compare(b.base));
log('readable ranges: ' + ranges.length);

/* المرحلة 1: بلوكات الأسماء عبر None + كثافة الإدخالات */
const nonePat = '?? 00 4e 6f 6e 65 00';
let noneHits = [];
for (const r of ranges) {
  if (r.size > 0x20000000) continue;
  let hs; try { hs = Memory.scanSync(r.base, r.size, nonePat); } catch(e){ continue; }
  for (const h of hs) noneHits.push(h.address);
}
log('None candidates: ' + noneHits.length);

let poolEntries = [];
for (const a of noneHits.slice(0, 800)) {
  let density = 0;
  try {
    const u8 = new Uint8Array(a.sub(2).readByteArray(2048));
    for (let i=0;i<2048-8;i+=4)
      if (u8[i]<0x10 && u8[i+1]<0x10 && u8[i+2]>=0x20 && u8[i+2]<0x7f) density++;
  } catch(e){ continue; }
  if (density > 130) { poolEntries.push({a, density}); if (poolEntries.length>=8) break; }
}
log('dense name-blocks: ' + poolEntries.length);
poolEntries.forEach(p=>log('  entry=' + hex(p.a) + ' density=' + p.density));

/* المرحلة 2: ابحث عن مؤشرات لبدايات البلوكات = GNamePool.Blocks */
if (!poolEntries.length) { log('FAIL: no dense blocks'); } else {
  const bases = new Set();
  for (const p of poolEntries) {
    for (let back=0; back<=0x40; back+=0x8) {
      bases.add(p.a.sub(back).and(ptr('ffffffffffff0000',16)));
      bases.add(p.a.sub(back).and(ptr('fffffffffffff000',16)));
    }
  }
  log('base candidates: ' + bases.size);
  let found = 0;
  for (const b of bases) {
    let hits;
    try { hits = Memory.scanSync(ranges[0].base, ranges[ranges.length-1].base.add(ranges[ranges.length-1].size).sub(ranges[0].base), ptrPat(b)); }
    catch(e){ continue; }
    for (const h of hits) {
      found++;
      let ctx = '';
      try { const c = new Uint8Array(h.address.sub(0x20).readByteArray(0x40));
        for (const x of c) ctx += ('0'+x.toString(16)).slice(-2);
      } catch(e){ ctx='?'; }
      log('PTR @ ' + hex(h.address) + ' -> base ' + hex(b) + ' ctx=' + ctx);
      if (found >= 12) break;
    }
    if (found >= 12) break;
  }
  log('pointer hits: ' + found);
  log('DONE — أرسل كل الناتج');
}
