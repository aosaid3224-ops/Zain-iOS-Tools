#import "SignatureAnalyzer.h"
#import "SPRootHide.h"
#import "RootlessManager.h"
#import <spawn.h>
#import <sys/wait.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

@implementation SignatureInfo
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"isSigned"] = @(self.isSigned);
    d[@"isAdHocSigned"] = @(self.isAdHocSigned);
    if (self.teamID) d[@"teamID"] = self.teamID;
    if (self.identifier) d[@"identifier"] = self.identifier;
    if (self.authority) d[@"authority"] = self.authority;
    if (self.signatureStatus) d[@"signatureStatus"] = self.signatureStatus;
    if (self.source) d[@"source"] = self.source;
    if (self.parseError) d[@"parseError"] = self.parseError;
    return d;
}
@end

@interface SignatureAnalyzer ()
@property (nonatomic, strong) NSString *ldidPath;
@end

@implementation SignatureAnalyzer

+ (instancetype)sharedAnalyzer {
    static SignatureAnalyzer *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _ldidPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ldid"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:_ldidPath]) {
            _ldidPath = @"ldid";
        }
    }
    return self;
}

- (NSString *)runLdid:(NSString *)arg target:(NSString *)path {
    return [self runCommand:self.ldidPath args:@[arg, path]];
}

- (NSString *)runCommand:(NSString *)cmd args:(NSArray *)args {
    NSMutableArray *cArgs = [NSMutableArray arrayWithObject:cmd ?: @""];
    [cArgs addObjectsFromArray:SPToolArguments(cmd ?: @"", args ?: @[])];
    char **argv = calloc(cArgs.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < cArgs.count; i++) argv[i] = strdup([cArgs[i] fileSystemRepresentation]);
    pid_t pid = 0;
    posix_spawn_file_actions_t action;
    posix_spawn_file_actions_init(&action);
    int outPipe[2];
    if (pipe(outPipe) != 0) {
        posix_spawn_file_actions_destroy(&action);
        for (NSUInteger i = 0; i < cArgs.count; i++) free(argv[i]);
        free(argv);
        return nil;
    }
    posix_spawn_file_actions_adddup2(&action, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&action, outPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&action, outPipe[0]);
    posix_spawn_file_actions_addclose(&action, outPipe[1]);
    int spawnStatus = posix_spawn(&pid, cmd.fileSystemRepresentation, &action, NULL, argv, NULL);
    posix_spawn_file_actions_destroy(&action);
    for (NSUInteger i = 0; i < cArgs.count; i++) free(argv[i]);
    free(argv);
    close(outPipe[1]);
    if (spawnStatus != 0) {
        close(outPipe[0]);
        return nil;
    }

    int flags = fcntl(outPipe[0], F_GETFL, 0);
    if (flags >= 0) fcntl(outPipe[0], F_SETFL, flags | O_NONBLOCK);
    NSMutableData *data = [NSMutableData data];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:300.0];
    int waitStatus = 0;
    BOOL reaped = NO;
    BOOL timedOut = NO;
    char buffer[4096];
    for (;;) {
        ssize_t n;
        while ((n = read(outPipe[0], buffer, sizeof(buffer))) > 0) [data appendBytes:buffer length:(NSUInteger)n];
        pid_t waited = waitpid(pid, &waitStatus, WNOHANG);
        if (waited == pid) reaped = YES;
        else if (waited < 0 && errno != EINTR) {
            kill(pid, SIGKILL);
            while (waitpid(pid, &waitStatus, 0) < 0 && errno == EINTR) { }
            timedOut = YES;
            reaped = YES;
            break;
        }
        if (reaped) {
            while ((n = read(outPipe[0], buffer, sizeof(buffer))) > 0) [data appendBytes:buffer length:(NSUInteger)n];
            break;
        }
        if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
            timedOut = YES;
            kill(pid, SIGKILL);
            while (waitpid(pid, &waitStatus, 0) < 0 && errno == EINTR) { }
            reaped = YES;
            break;
        }
        usleep(10000);
    }
    close(outPipe[0]);
    if (timedOut || !reaped || !WIFEXITED(waitStatus) || WEXITSTATUS(waitStatus) != 0) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (SignatureInfo *)analyzeSignatureAtPath:(NSString *)path {
    SignatureInfo *info = [[SignatureInfo alloc] init];
    info.source = @"ldid";

    NSString *output = [self runLdid:@"-h" target:path];
    if (!output || output.length == 0) {
        info.isSigned = NO;
        info.signatureStatus = @"unsigned";
        return info;
    }

    info.isSigned = YES;
    info.signatureStatus = @"signed";

    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;
        NSRange separator = [trimmed rangeOfString:@"="];
        if (separator.location == NSNotFound) continue;
        NSString *key = [trimmed substringToIndex:separator.location];
        NSString *value = [[trimmed substringFromIndex:separator.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([key isEqualToString:@"Identifier"]) {
            info.identifier = value;
        } else if ([key isEqualToString:@"TeamIdentifier"]) {
            info.teamID = value;
        } else if ([key isEqualToString:@"Authority"]) {
            if (!info.authority.length) info.authority = value;
            if ([value rangeOfString:@"adhoc" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [value rangeOfString:@"AdHoc" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                info.isAdHocSigned = YES;
            }
        }
    }

    if (!info.authority && info.isSigned) {
        info.isAdHocSigned = YES;
        info.authority = @"AdHoc";
    }

    return info;
}

- (NSDictionary *)extractEntitlementsAtPath:(NSString *)path {
    NSString *output = [self runLdid:@"-e" target:path];
    if (!output || output.length < 10) return nil;

    NSString *plistPayload = output;
    NSRange xmlStart = [output rangeOfString:@"<?xml"];
    NSRange plistEnd = [output rangeOfString:@"</plist>" options:NSBackwardsSearch];
    if (xmlStart.location != NSNotFound && plistEnd.location != NSNotFound &&
        NSMaxRange(plistEnd) > xmlStart.location) {
        plistPayload = [output substringWithRange:NSMakeRange(xmlStart.location,
                                                               NSMaxRange(plistEnd) - xmlStart.location)];
    }

    NSData *data = [plistPayload dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;

    NSError *error = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                            options:NSPropertyListImmutable
                                                             format:nil
                                                              error:&error];
    if ([plist isKindOfClass:[NSDictionary class]]) return plist;

    NSLog(@"[SignatureAnalyzer] Could not parse ldid entitlements for %@: %@", path, error.localizedDescription ?: @"unknown format");
    return nil;
}

@end
