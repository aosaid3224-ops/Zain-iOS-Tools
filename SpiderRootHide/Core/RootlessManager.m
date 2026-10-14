#import "RootlessManager.h"
#import "RuntimeEnvironment.h"
#import "Logger.h"
#import "../rootless.h"

@implementation RootlessManager

+ (instancetype)sharedManager {
    static RootlessManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
    }
    return self;
}

- (NSString *)resolvePath:(NSString *)path {
    return SPJBPath(path);
}

- (NSString *)rootlessPathForPath:(NSString *)path {
    return [self resolvePath:path];
}

- (NSString *)standardPathForPath:(NSString *)path {
    NSString *relative = SPJBRelativePath(path);
    if (relative) return relative;
    RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];
    if (rt.bootstrapPath.length && [path hasPrefix:rt.bootstrapPath]) {
        NSString *rest = [path substringFromIndex:rt.bootstrapPath.length];
        return [rest hasPrefix:@"/"] ? rest : [@"/" stringByAppendingString:rest];
    }
    return path;
}

- (BOOL)fileExistsAtLogicalPath:(NSString *)path {
    NSString *resolved = [self resolvePath:path];
    return [[NSFileManager defaultManager] fileExistsAtPath:resolved];
}

- (BOOL)createDirectoryAtLogicalPath:(NSString *)path error:(NSError **)error {
    NSString *resolved = [self resolvePath:path];
    return [[NSFileManager defaultManager] createDirectoryAtPath:resolved withIntermediateDirectories:YES attributes:nil error:error];
}

- (BOOL)fileExistsAtRootlessPath:(NSString *)path {
    return [self fileExistsAtLogicalPath:path];
}

- (BOOL)isFileAtPathExecutable:(NSString *)path {
    NSString *resolved = [self resolvePath:path];
    return [[NSFileManager defaultManager] isExecutableFileAtPath:resolved];
}

@end
