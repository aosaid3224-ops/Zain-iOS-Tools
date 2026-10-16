#include <CommonCrypto/CommonDigest.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#define SOCKET_PATH "/var/jb/var/run/com.aosaid.deltaguard.helper.sock"
#define MAX_LINE 2048

static int allowed_path(const char *path) {
    if (!path || path[0] != '/') return 0;
    if (strstr(path, "..")) return 0;
    return strncmp(path, "/private/var/containers/Bundle/Application/", 43) == 0 ||
           strncmp(path, "/var/containers/Bundle/Application/", 38) == 0;
}

static void write_error(int fd, const char *reason) {
    dprintf(fd, "ERR %s\n", reason ? reason : "unknown");
}

static void handle_client(int fd) {
    char line[MAX_LINE]; ssize_t n = read(fd, line, sizeof(line) - 1);
    if (n <= 0) return; line[n] = '\0';
    if (strncmp(line, "HASH ", 5) != 0) { write_error(fd, "unsupported-request"); return; }
    char *path = line + 5; path[strcspn(path, "\r\n")] = '\0';
    if (!allowed_path(path)) { write_error(fd, "path-not-allowed"); return; }
    struct stat st; if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) { write_error(fd, "file-not-readable"); return; }
    int input = open(path, O_RDONLY); if (input < 0) { write_error(fd, "open-failed"); return; }
    CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx); unsigned char buf[1024 * 1024]; ssize_t got;
    while ((got = read(input, buf, sizeof(buf))) > 0) CC_SHA256_Update(&ctx, buf, (CC_LONG)got);
    int saved_errno = errno; close(input); if (got < 0) { errno = saved_errno; write_error(fd, "read-failed"); return; }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest, &ctx); char hex[CC_SHA256_DIGEST_LENGTH * 2 + 1];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) snprintf(hex + (i * 2), 3, "%02x", digest[i]);
    dprintf(fd, "OK %.16s %lld\n", hex, (long long)st.st_size);
}

int main(void) {
    signal(SIGPIPE, SIG_IGN); mkdir("/var/jb/var", 0755); mkdir("/var/jb/var/run", 0755); unlink(SOCKET_PATH);
    int server = socket(AF_UNIX, SOCK_STREAM, 0); if (server < 0) return 10;
    struct sockaddr_un address; memset(&address, 0, sizeof(address)); address.sun_family = AF_UNIX; strlcpy(address.sun_path, SOCKET_PATH, sizeof(address.sun_path));
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0) return 11; chmod(SOCKET_PATH, 0666); if (listen(server, 8) != 0) return 12;
    for (;;) { int client = accept(server, NULL, NULL); if (client < 0) { if (errno == EINTR) continue; break; } handle_client(client); close(client); }
    close(server); unlink(SOCKET_PATH); return 0;
}
