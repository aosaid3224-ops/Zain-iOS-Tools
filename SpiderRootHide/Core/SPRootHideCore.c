#include "SPRootHideCore.h"

#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define SP_FAT_MAGIC        0xcafebabeu
#define SP_FAT_MAGIC_64     0xcafebabfu
#define SP_MH_MAGIC         0xfeedfaceu
#define SP_MH_MAGIC_64      0xfeedfacfu
#define SP_LC_REQ_DYLD      0x80000000u
#define SP_LC_LOAD_DYLIB         0x0cu
#define SP_LC_LOAD_WEAK_DYLIB    (0x18u | SP_LC_REQ_DYLD)
#define SP_LC_REEXPORT_DYLIB     (0x1fu | SP_LC_REQ_DYLD)
#define SP_LC_LAZY_LOAD_DYLIB    0x20u
#define SP_LC_LOAD_UPWARD_DYLIB  (0x23u | SP_LC_REQ_DYLD)
#define SP_MAX_SLICES   32
#define SP_MAX_CMDS     (16u * 1024u * 1024u)

static int sp_read_at(int fd, uint64_t offset, void *buffer, size_t length) {
    size_t done = 0;
    while (done < length) {
        ssize_t n = pread(fd, (char *)buffer + done, length - done, (off_t)(offset + done));
        if (n <= 0) return -1;
        done += (size_t)n;
    }
    return 0;
}

static uint32_t sp_le32(const unsigned char *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint32_t sp_be32(const unsigned char *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static uint64_t sp_be64(const unsigned char *p) {
    return ((uint64_t)sp_be32(p) << 32) | (uint64_t)sp_be32(p + 4);
}

static int sp_name_is_roothide(const char *name, size_t max) {
    size_t len = strnlen(name, max);
    const char *needles[] = { "libroothide", "libvroot" };
    for (size_t n = 0; n < sizeof(needles) / sizeof(needles[0]); n++) {
        size_t nl = strlen(needles[n]);
        for (size_t i = 0; i + nl <= len; i++) {
            if (memcmp(name + i, needles[n], nl) == 0) return 1;
        }
    }
    return 0;
}

static int sp_scan_slice(int fd, uint64_t offset) {
    unsigned char header[32];
    if (sp_read_at(fd, offset, header, sizeof(header)) != 0) return -1;
    uint32_t magic = sp_le32(header);
    size_t headerSize;
    if (magic == SP_MH_MAGIC_64) headerSize = 32;
    else if (magic == SP_MH_MAGIC) headerSize = 28;
    else return -1;

    uint32_t ncmds = sp_le32(header + 16);
    uint32_t sizeofcmds = sp_le32(header + 20);
    if (sizeofcmds == 0 || sizeofcmds > SP_MAX_CMDS) return 0;

    unsigned char *cmds = malloc(sizeofcmds);
    if (!cmds) return -1;
    if (sp_read_at(fd, offset + headerSize, cmds, sizeofcmds) != 0) { free(cmds); return -1; }

    int found = 0;
    uint32_t pos = 0;
    for (uint32_t i = 0; i < ncmds && pos + 8 <= sizeofcmds; i++) {
        uint32_t cmd = sp_le32(cmds + pos);
        uint32_t cmdsize = sp_le32(cmds + pos + 4);
        if (cmdsize < 8 || pos + cmdsize > sizeofcmds) break;
        if (cmd == SP_LC_LOAD_DYLIB || cmd == SP_LC_LOAD_WEAK_DYLIB || cmd == SP_LC_REEXPORT_DYLIB ||
            cmd == SP_LC_LAZY_LOAD_DYLIB || cmd == SP_LC_LOAD_UPWARD_DYLIB) {
            if (cmdsize >= 24) {
                uint32_t nameOffset = sp_le32(cmds + pos + 8);
                if (nameOffset >= 24 && nameOffset < cmdsize &&
                    sp_name_is_roothide((const char *)cmds + pos + nameOffset, cmdsize - nameOffset)) {
                    found = 1;
                    break;
                }
            }
        }
        pos += cmdsize;
    }
    free(cmds);
    return found;
}

int sp_macho_uses_roothide(const char *path) {
    if (!path || !*path) return -1;
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;

    unsigned char magicBytes[8];
    if (sp_read_at(fd, 0, magicBytes, sizeof(magicBytes)) != 0) { close(fd); return -1; }

    int result = -1;
    uint32_t fatMagic = sp_be32(magicBytes);
    if (fatMagic == SP_FAT_MAGIC || fatMagic == SP_FAT_MAGIC_64) {
        uint32_t count = sp_be32(magicBytes + 4);
        if (count == 0 || count > SP_MAX_SLICES) { close(fd); return -1; }
        size_t entrySize = (fatMagic == SP_FAT_MAGIC_64) ? 32 : 20;
        for (uint32_t i = 0; i < count; i++) {
            unsigned char entry[32];
            if (sp_read_at(fd, 8 + (uint64_t)i * entrySize, entry, entrySize) != 0) break;
            uint64_t sliceOffset = (fatMagic == SP_FAT_MAGIC_64) ? sp_be64(entry + 8) : sp_be32(entry + 8);
            int slice = sp_scan_slice(fd, sliceOffset);
            if (slice == 1) { result = 1; break; }
            if (slice == 0) result = 0;
        }
    } else {
        result = sp_scan_slice(fd, 0);
    }
    close(fd);
    return result;
}

long sp_arg_path_offset(const char *arg) {
    if (!arg || !arg[0]) return -1;
    if (arg[0] == '/') return 0;
    if (arg[0] == '-' && arg[1] != '\0' && arg[1] != '-' && arg[2] == '/') return 2;
    if (arg[0] == '-' && arg[1] == '-') {
        const char *eq = strchr(arg, '=');
        if (eq && eq[1] == '/') return (long)(eq - arg) + 1;
    }
    return -1;
}
