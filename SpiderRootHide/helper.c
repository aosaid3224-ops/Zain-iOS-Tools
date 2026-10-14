#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <errno.h>
#include <string.h>
#include <copyfile.h>

#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE) && __has_include(<roothide.h>)
#include <roothide.h>
#define SP_HELPER_ROOTHIDE 1
#endif

int main(int argc, char *argv[], char *envp[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <command> [args...]\n", argv[0]);
        return 1;
    }

    uid_t original_uid = getuid();

    if (setuid(0) != 0) {
        if (seteuid(0) != 0) {
            fprintf(stderr, "Warning: Could not acquire root (errno=%d). Running as uid=%d\n", errno, original_uid);
        } else {
            setegid(0);
        }
    } else {
        setgid(0);
        seteuid(0);
        setegid(0);
    }

    uid_t current_uid = getuid();
    uid_t current_euid = geteuid();
    if (current_euid != 0) {
        fprintf(stderr, "ERROR: Could not acquire root (uid=%d, euid=%d)\n", current_uid, current_euid);
        return 126;
    }

    if (argc == 4 && strcmp(argv[1], "--copy-tree") == 0) {
        int copyFlags = COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC;
#ifdef COPYFILE_CLONE
        copyFlags |= COPYFILE_CLONE;
#endif
        int copyResult = copyfile(argv[2], argv[3], NULL, copyFlags);
        if (copyResult != 0) {
            int cloneError = errno;
            if (cloneError == ENOTSUP || cloneError == EINVAL || cloneError == EXDEV) {
                fprintf(stderr, "copyfile clone unavailable; using regular copy errno=%d\n", cloneError);
                copyResult = copyfile(argv[2], argv[3], NULL,
                                      COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC);
            }
        }
        if (copyResult != 0) {
            fprintf(stderr, "copyfile failed: %s -> %s errno=%d\n", argv[2], argv[3], errno);
            return 1;
        }
        return 0;
    }

    execve(argv[1], &argv[1], envp);
#ifdef SP_HELPER_ROOTHIDE
    if (errno == ENOENT && argv[1][0] == '/') {
        const char *real = jbroot(argv[1]);
        if (real && strcmp(real, argv[1]) != 0) execve(real, &argv[1], envp);
    }
#endif

    fprintf(stderr, "execve failed for %s: errno=%d\n", argv[1], errno);
    return 1;
}
