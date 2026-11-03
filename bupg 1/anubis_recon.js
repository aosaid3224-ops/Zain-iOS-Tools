// ANUBIS Loader — Recon & Crack Capture Script (CrackRecon v2)
// Run: frida -U -n TempMail -l anubis_recon.js
// أو: frida -U -f com.tempmail.ios -l anubis_recon.js

const RTDATA_VM  = ptr("0x100bc8000");
const RTDATA_END = ptr("0x100c0c000");
const RTCODE_VM  = ptr("0x100e08000");
const RTCODE_END = ptr("0x102608000");

// ── 1) التقاط تنبيه "Key not found." + تتبّع الرجوع لدالة الفحص ──
var UIAlertController = ObjC.classes.UIAlertController;
Interception.attach(UIAlertController["+ alertControllerWithTitle:message:preferredStyle:"].implementation, {
  onEnter: function (args) {
    var title = ObjC.Object(args[2]).toString();
    var msg   = args[3].isNull() ? "<null>" : ObjC.Object(args[3]).toString();
    console.log("\n[ALERT] title=" + JSON.stringify(title) + " msg=" + JSON.stringify(msg));
    console.log(Thread.backtrace(this.context, Backtracer.ACCURATE)
      .map(DebugSymbol.fromAddress).join("\n    "));
    // دالة الفحص = الإطار الأبعد الذي يرجع للكود (RTCODE)
    console.log("[*] x30 (الرجوع) = " + this.context.lr);
  }
});

// ── 2) التقاط endpoint + رد التحقق (OpenSSL مربوط ثابتًا داخل الباينري) ──
function hookExport(name) {
  try {
    var p = Module.getExportByName(null, name);
    if (!p) return;
    Interceptor.attach(p, {
      onEnter: function (args) {
        if (name === "SSL_read")  console.log("[SSL_read] len=" + args[2]);
        if (name === "SSL_write") {
          var buf = args[1].readUtf8String(args[2].toInt32());
          console.log("[SSL_write] " + buf);
        }
        if (name === "curl_easy_setopt") {
          var opt = args[1].toInt32();
          if (opt === 10002 || opt === 10015) // CURLOPT_URL / POSTFIELDS
            console.log("[curl_setopt " + opt + "] " + args[2].readUtf8String());
        }
        if (name === "curl_easy_perform") console.log("[curl_perform] →");
      },
      onLeave: function (ret) {
        if (name === "SSL_read" || name === "curl_easy_perform")
          console.log("[← " + name + " ret=" + ret + "]");
      }
    });
    console.log("[+] hooked " + name + " @ " + p);
  } catch (e) { console.log("[-] " + name + ": " + e); }
}
["SSL_read","SSL_write","curl_easy_setopt","curl_easy_perform"].forEach(hookExport);

// ── 3) سحب RTDATA بعد فك التشفير (يُفك عند أول استخدام) ──
function dumpRTDATA() {
  var found = [];
  Process.enumerateRanges("rw-").forEach(function (r) {
    if (r.base.compare(RTDATA_VM) >= 0 && r.base.compare(RTDATA_END) < 0) {
      var sz = Number(r.size);
      var buf = r.base.readByteArray(Math.min(sz, 0x190000));
      var u8 = new Uint8Array(buf);
      // استخراج سلاسل ASCII ≥ 6
      var cur = "";
      for (var i = 0; i < u8.length; i++) {
        var c = u8[i];
        if (c >= 32 && c < 127) cur += String.fromCharCode(c);
        else {
          if (cur.length >= 6 && /[a-zA-Z]{3}/.test(cur)) found.push(cur);
          cur = "";
        }
      }
    }
  });
  var uniq = Array.from(new Set(found));
  console.log("[RTDATA strings] " + uniq.length + " extracted:");
  uniq.filter(function (s) {
    return /http|key|Anu|api|login|hwid|device|found|error|token|status|1\.[0-9]{2,3}\.[0-9]{2,3}/i.test(s);
  }).forEach(function (s) { console.log("    " + s); });
  return uniq;
}

// نفّذ السحب بعد 20 ثانية (بعد فتح اللودر وتجربة المفتاح)
setTimeout(dumpRTDATA, 20000);
console.log("[*] ANUBIS recon armed. جرّب: TEST123 ثم المفتاح الحقيقي، وقارن.");
