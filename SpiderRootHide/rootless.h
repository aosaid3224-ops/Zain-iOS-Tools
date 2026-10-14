#import <Foundation/Foundation.h>
#ifndef ROOTLESS_H
#define ROOTLESS_H

#import "Core/SPRootHide.h"

static inline const char *SPLibrootJBRoot(void) {
    NSString *root = SPJBRootPath();
    return root.length ? root.fileSystemRepresentation : NULL;
}

static inline NSString *SPJBRRootPath(NSString *path) { return SPJBPath(path); }
static inline NSString *ROOT_PATH_NS(NSString *path) { return SPJBPath(path); }
static inline const char *ROOT_PATH_C(const char *path) {
    if (!path) return path;
    return SPJBPath([NSString stringWithUTF8String:path]).fileSystemRepresentation;
}

#endif
