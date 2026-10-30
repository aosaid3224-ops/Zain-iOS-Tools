#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>

static void st(const char *fmt, ...) {
    FILE *f = fopen("/var/mobile/Documents/ghost_status.txt", "a");
    if (!f) return;
    va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap);
    fputc('\n', f); fclose(f);
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (getuid() != 0 && geteuid() != 0) { st("❌ المساعد يحتاج صلاحية root"); return 1; }
    if (argc < 2) { st("usage: ghosthelper start|stop|paste|status"); return 2; }
    remove("/var/mobile/Documents/ghost_status.txt");
    if (!strcmp(argv[1], "start")) {
        int r = system("launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.zain.ghostwatcher.plist 2>&1");
        st("▶️ تفعيل المراقب: %s", r == 0 ? "تم ✅" : "ربما يكون شغالًا أصلًا");
    } else if (!strcmp(argv[1], "stop")) {
        int r = system("launchctl bootout system/com.zain.ghostwatcher 2>&1");
        st("⏹ إيقاف المراقب: %s", r == 0 ? "تم ✅" : "ربما يكون متوقفًا أصلًا");
    } else if (!strcmp(argv[1], "paste")) {
        int r = system("python3 /var/jb/usr/local/bin/ghostwatcher.py 2>&1");
        st("👻 اللصق اليدوي: انتهى (%d) — شوف اللوق", r);
    } else if (!strcmp(argv[1], "status")) {
        system("launchctl list | grep ghostwatcher > /var/mobile/Documents/ghost_status.txt 2>&1");
        st("✅ حالة الدايمون محدثة");
    }
    return 0;
}
