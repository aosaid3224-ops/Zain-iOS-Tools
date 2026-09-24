# Naver Series Bypass v3.3.1

## Advanced Device Ban Bypass with Built-in Diagnostics & Arabic UI

### Features
- **IDFV Spoofing** - Randomizes device vendor identifier on every call
- **Keychain Interception** - Blocks all Naver-related keychain reads/writes
- **NSUserDefaults Protection** - Prevents reading ban-related local storage
- **Network Monitoring** - Logs and analyzes all API requests/responses
- **Header Spoofing** - Modifies `x-consumer-id`, `x-hmac-msgpad`, `x-hmac-md`, `x-adid`
- **Jailbreak Detection Bypass** - Hides jailbreak paths from app scanning
- **Hardware Fingerprint Spoofing** - `uname`, `sysctl` hooks
- **iOS 16-18 Support** - Tested on Rootless jailbreaks (Dopamine, Palera1n)
- **Arabic Settings UI** - Full Arabic preference bundle with live stats

### Arabic UI (واجهة عربية)

After installation, go to **Settings → Naver Series Bypass (نافر سيريس بايباس)**

The UI shows:
- **حالة التطبيق** - App status (Working / Blocked / Waiting)
- **الإحصائيات** - Live statistics:
  - الطلبات المرسلة (Total requests)
  - محاولات الحظر (Block attempts)
  - عناصر تم تغييرها (Spoofed items)
  - JB-Bypass count
- **سجل الأحداث (Logs)** - Live log viewer with:
  - Auto-refresh every 2 seconds
  - Copy button (نسخ)
  - Clear button (مسح)

### Installation

```bash
# Build
make clean && make package

# Install on device
scp packages/com.aosaid.naverseriesbypass_3.3.1_iphoneos-arm64.deb root@DEVICE_IP:/tmp/
ssh root@DEVICE_IP "dpkg -i /tmp/*.deb && killall -9 SpringBoard"
```

### Diagnostic Logs

All activity is logged to:
```
/var/mobile/Documents/NaverBypass_Diagnostics.log
```

View logs via:
- **Settings UI** (preferred) - Settings → Naver Series Bypass
- **SSH**: `tail -f /var/mobile/Documents/NaverBypass_Diagnostics.log`
- **Filza**: `/var/mobile/Documents/NaverBypass_Diagnostics.log`

### What to Look For

**If bypass works:**
- Content loads normally
- No "안전조치" popup
- Status code 200 in logs
- UI shows: ✅ التطبيق يعمل

**If bypass fails:**
- Check logs for `[ALERT] BLOCKED! Server returned 403/401`
- Check logs for `[ALERT] BAN MESSAGE DETECTED IN RESPONSE!`
- UI shows: ❌ التطبيق محظور (خادمي)
- This means the ban is **server-side** based on non-spoofable identifiers

### Troubleshooting

| Problem | Solution |
|---------|----------|
| Tweak not loading | Ensure `com.naver.series` is correct bundle ID |
| No logs | Check `/var/mobile/Documents/` exists and is writable |
| App crashes | Check logs, may need to disable specific hook |
| Still banned after tweak | Server-side ban (Serial/ECID/IP) - not fixable with tweak |
| Settings not showing | Respring or reinstall preference bundle |

### Technical Details

**Spoofed Values:**
- `identifierForVendor` -> Random UUID
- `x-consumer-id` -> Random 32-char string
- `x-adid` -> Random UUID
- `uname.machine` -> iPhone15,2
- `systemVersion` -> 18.3.1

**Blocked Keychain Patterns:**
- naver, series, ntracker, nhncorp, YAZD8YA78S, device, ban, block, safety, action, previous, idfv, consumer, hmac, adid

### License
Private tool for authorized testing only.
