#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <spawn.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <dirent.h>
#include <fcntl.h>
#include <time.h>

#define SRC "/var/mobile/Documents/luasource_ghost.bin"
#define NAMEF "/var/mobile/Documents/.ghost_name"
#define LOG "/var/mobile/Documents/ghost_watcher.log"
#define KNOWN "/var/mobile/Containers/Data/Application/C04896B7-CE45-4D09-B181-8EC051DF9CFC/Documents/DeltaForce/Saved/LuaSource"

static void st(const char *fmt, ...) {
    FILE *f = fopen("/var/mobile/Documents/ghost_status.txt", "a");
    if (f) { va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap); fputc('\n', f); fclose(f); }
}
static void lg(const char *fmt, ...) {
    FILE *f = fopen(LOG, "a");
    if (!f) return;
    fprintf(f, "%ld ", (long)time(NULL));
    va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap);
    fputc('\n', f); fclose(f);
}
static int run(const char *cmd) {
    pid_t pid; char *argv[] = {"/bin/sh", "-c", (char *)cmd, NULL};
    if (posix_spawn(&pid, "/bin/sh", NULL, NULL, argv, NULL) != 0) return -1;
    int s; waitpid(pid, &s, 0);
    return WIFEXITED(s) ? WEXITSTATUS(s) : -1;
}

static int copy_file(const char *src, const char *dst) {
    int fi = open(src, O_RDONLY); if (fi < 0) return -1;
    int fo = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0644); if (fo < 0) { close(fi); return -2; }
    char buf[65536]; ssize_t n; int rc = 0;
    while ((n = read(fi, buf, sizeof buf)) > 0) {
        ssize_t off = 0;
        while (off < n) { ssize_t w = write(fo, buf + off, n - off); if (w < 0) { rc = -3; break; } off += w; }
        if (rc) break;
    }
    close(fi); close(fo); return rc;
}

static int is_game_lua_dir(const char *path) {
    /* تحقق سريع: المسار يحوي DeltaForce/Saved/LuaSource */
    return strstr(path, "LuaSource") != NULL;
}

static int dopaste(void) {
    struct stat sb;
    lg("diag: Containers isdir=%d", stat("/var/mobile/Containers/Data/Application", &sb) == 0 && S_ISDIR(sb.st_mode));
    if (stat(SRC, &sb) != 0) { lg("ERROR: ملف الهاك ناقص"); return 1; }

    /* اسم الملف الهدف */
    char name[512] = "GhostUpdate.lua";
    int nf = open(NAMEF, O_RDONLY);
    if (nf >= 0) { ssize_t n = read(nf, name, sizeof(name)-1); if (n > 0) name[n] = 0; close(nf); }

    /* جرّب المسار المعروف أولًا */
    const char *base = KNOWN;
    struct stat st2;
    if (stat(KNOWN, &st2) != 0 || !S_ISDIR(st2.st_mode)) {
        /* fallback: glob يدوي */
        base = NULL;
        DIR *ad = opendir("/var/mobile/Containers/Data/Application");
        if (ad) {
            struct dirent *e;
            while ((e = readdir(ad))) {
                if (e->d_name[0] == '.') continue;
                char p[1024];
                snprintf(p, sizeof p, "/var/mobile/Containers/Data/Application/%s/Documents/DeltaForce/Saved/LuaSource", e->d_name);
                if (stat(p, &st2) == 0 && S_ISDIR(st2.st_mode)) { base = strdup(p); break; }
            }
            closedir(ad);
        }
    }
    if (!base || !is_game_lua_dir(base)) { lg("ERROR: حاوية اللعبة غير موجودة (helper)"); return 2; }

    char dst[1200];
    snprintf(dst, sizeof dst, "%s/%s", base, name);
    lg("diag: paste -> %s", name);
    int r = copy_file(SRC, dst);
    if (r == 0) { chmod(dst, 0644); lg("PASTED 👻 (helper)"); return 0; }
    lg("PASTE FAIL: %d", r);
    return 3;
}

int main(int argc, char **argv) {
    if (getuid() != 0 && geteuid() != 0) { st("❌ المساعد يحتاج root"); return 1; }
    if (argc < 2) { st("usage: activate|stop|status|dopaste"); return 2; }
    remove("/var/mobile/Documents/ghost_status.txt");
    if (!strcmp(argv[1], "dopaste")) return dopaste();
    if (!strcmp(argv[1], "activate")) {
        int r1 = run("launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.zain.ghostwatcher.plist");
        st("1️⃣ المراقب التلقائي: %s", r1 == 0 ? "مفعّل ✅" : "يعمل أصلًا ✅");
        int r2 = dopaste();
        st("2️⃣ لصق فوري: %s", r2 == 0 ? "تم 👻" : "تجاهل — اللعبة مو شغالة");
        int r3 = run("launchctl list | grep -q ghostwatcher");
        st("3️⃣ %s", r3 == 0 ? "الشبح جاهز 🎮" : "⚠️ الدايمون غير ظاهر");
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
