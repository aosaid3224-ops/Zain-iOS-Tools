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
    if (getuid() != 0 && geteuid() != 0) { st("❌ المساعد يحتاج root"); return 1; }
    if (argc < 2) { st("usage: ghosthelper start|stop|paste|status"); return 2; }
    remove("/var/mobile/Documents/ghost_status.txt");
    if (!strcmp(argv[1], "start")) {
        int r = run("launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.zain.ghostwatcher.plist");
        st("▶️ تفعيل المراقب: %s", r == 0 ? "تم ✅" : "ربما شغال أصلًا");
    } else if (!strcmp(argv[1], "stop")) {
        int r = run("launchctl bootout system/com.zain.ghostwatcher");
        st("⏹ إيقاف المراقب: %s", r == 0 ? "تم ✅" : "ربما متوقف أصلًا");
    } else if (!strcmp(argv[1], "paste")) {
        int r = run("python3 /var/jb/usr/local/bin/ghostwatcher.py");
        st("👻 اللصق اليدوي: انتهى (%d) — راجع اللوق", r);
    } else if (!strcmp(argv[1], "status")) {
        run("launchctl list | grep ghostwatcher > /var/mobile/Documents/ghost_status.txt 2>&1");
        st("✅ تم تحديث الحالة");
    }
    return 0;
}
