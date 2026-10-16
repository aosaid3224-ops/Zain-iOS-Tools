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
#include <sys/time.h>
#include <unistd.h>

#define MAX_LINE 2048
#define SOCKET_PATH_COUNT 3

static const char *socket_paths[SOCKET_PATH_COUNT] = {
    "/var/jb/var/run/com.aosaid.deltaguard.helper.sock",
    "/private/var/jb/var/run/com.aosaid.deltaguard.helper.sock",
    "/var/run/com.aosaid.deltaguard.helper.sock"
};
static const char *active_socket = NULL;

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
    char line[MAX_LINE];
    ssize_t n = read(fd, line, sizeof(line) - 1);
    if (n <= 0) return;
    line[n] = '\0';
    if (strncmp(line, "HASH ", 5) != 0) { write_error(fd, "unsupported-request"); return; }
    char *path = line + 5;
    path[strcspn(path, "\r\n")] = '\0';
    if (!allowed_path(path)) { write_error(fd, "path-not-allowed"); return; }
    struct stat st;
    if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) { write_error(fd, "file-not-readable"); return; }
    int input = open(path, O_RDONLY);
    if (input < 0) { write_error(fd, "open-failed"); return; }
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    size_t buffer_size = 64 * 1024;
    unsigned char *buf = malloc(buffer_size);
    ssize_t got = 0;
    if (buf) while ((got = read(input, buf, buffer_size)) > 0) CC_SHA256_Update(&ctx, buf, (CC_LONG)got);
    int saved_errno = errno;
    free(buf);
    close(input);
    if (!buf || got < 0) { errno = saved_errno; write_error(fd, "read-failed"); return; }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    char hex[CC_SHA256_DIGEST_LENGTH * 2 + 1];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) snprintf(hex + (i * 2), 3, "%02x", digest[i]);
    dprintf(fd, "OK %.16s %lld\n", hex, (long long)st.st_size);
}

static int bind_server(int server) {
    for (int i = 0; i < SOCKET_PATH_COUNT; i++) {
        const char *path = socket_paths[i];
        if (strncmp(path, "/var/jb/var/run/", 17) == 0) {
            mkdir("/var/jb/var", 0755);
            mkdir("/var/jb/var/run", 0755);
        } else if (strncmp(path, "/private/var/jb/var/run/", 25) == 0) {
            mkdir("/private/var/jb/var", 0755);
            mkdir("/private/var/jb/var/run", 0755);
        }
        unlink(path);
        struct sockaddr_un address;
        memset(&address, 0, sizeof(address));
        address.sun_family = AF_UNIX;
        strlcpy(address.sun_path, path, sizeof(address.sun_path));
        if (bind(server, (struct sockaddr *)&address, sizeof(address)) == 0) {
            active_socket = path;
            chmod(path, 0666);
            return 0;
        }
    }
    return errno ? errno : EADDRNOTAVAIL;
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) return 10;
    int bind_error = bind_server(server);
    if (bind_error != 0) { close(server); return 11; }
    if (listen(server, 8) != 0) { int e = errno; unlink(active_socket); close(server); return e == 0 ? 12 : e; }
    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client < 0) { if (errno == EINTR) continue; break; }
        struct timeval htv = { 5, 0 };
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &htv, sizeof(htv));
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &htv, sizeof(htv));
        handle_client(client);
        close(client);
    }
    close(server);
    if (active_socket) unlink(active_socket);
    return 0;
}
