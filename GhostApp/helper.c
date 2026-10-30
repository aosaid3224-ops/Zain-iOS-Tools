#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <spawn.h>
#include <sys/wait.h>

static void st(const char *fmt, ...) {
    FILE *f = fopen("/var/mobile/Documents/ghost_status.txt", "a");
    if (!f) return;
    va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap);
    fputc('\n', f); fclose(f);
}

static int run(const char *cmd) {
    pid_t pid;
    char *argv[] = {"/bin/sh", "-c", (char *)cmd, NULL};
    if (posix_spawn(&pid, "/bin/sh", NULL, NULL, argv, NULL) != 0) return -1;
    int status; waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

int main(int argc, char **argv) {
    if (getuid() != 0 && geteuid() != 0) { st("❌ المساعد يحتاج صلاحية root — أعد تثبيت الحزمة"); return 1; }
    if (argc < 2) { st("usage: ghosthelper activate|stop|status"); return 2; }
    remove("/var/mobile/Documents/ghost_status.txt");

    if (!strcmp(argv[1], "activate")) {
        if (access("/var/mobile/Documents/luasource_ghost.bin", F_OK) != 0)
            st("⚠️ ملف الهاك غير موجود — أعد تثبيت الحزمة");
        int r1 = run("launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.zain.ghostwatcher.plist");
        st("1️⃣ المراقب التلقائي: %s", r1 == 0 ? "مفعّل ✅" : "يعمل أصلًا ✅");
        int r2 = run("python3 /var/jb/usr/local/bin/ghostwatcher.py");
        st("2️⃣ لصق فوري: %s", r2 == 0 ? "تم 👻" : "فشل — افتح اللعبة أولًا");
        int r3 = run("launchctl list | grep -q ghostwatcher");
        st("3️⃣ الحالة النهائية: %s", r3 == 0 ? "الشبح جاهز — افتح اللعبة والعب 🎮" : "⚠️ الدايمون غير ظاهر");
    }
    else if (!strcmp(argv[1], "stop")) {
        int r = run("launchctl bootout system/com.zain.ghostwatcher");
        st("⏹ إيقاف الشبح: %s", r == 0 ? "تم" : "متوقف أصلًا");
    }
    else if (!strcmp(argv[1], "status")) {
        run("echo '═══ الدايمون ═══' > /var/mobile/Documents/ghost_status.txt");
        run("launchctl list | grep ghostwatcher >> /var/mobile/Documents/ghost_status.txt 2>&1");
        run("echo '═══ اللوق ═══' >> /var/mobile/Documents/ghost_status.txt");
        run("tail -12 /var/mobile/Documents/ghost_watcher.log >> /var/mobile/Documents/ghost_status.txt 2>&1");
        st("✅ محدّث");
    }
    return 0;
}
