#import "ForensicRegistrationProbe.h"
#import "SPRootHide.h"
#import "OperationLog.h"
#import "RootlessManager.h"
#import <objc/message.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#import "RuntimeEnvironment.h"

extern char **environ;

@implementation ForensicRegistrationProbe

+ (instancetype)sharedProbe {
    static ForensicRegistrationProbe *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (NSString *)uicachePath {
    RootlessManager *manager = [RootlessManager sharedManager];
    RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];
    NSMutableArray<NSString *> *candidates = [NSMutableArray arrayWithObjects:
        [manager resolvePath:@"/usr/bin/uicache"],
        @"/usr/bin/uicache",
        nil];
    if (rt.bootstrapPath) {
        [candidates insertObject:[rt.bootstrapPath stringByAppendingPathComponent:@"usr/bin/uicache"] atIndex:1];
        [candidates insertObject:[rt.bootstrapPath stringByAppendingPathComponent:@"bin/uicache"] atIndex:2];
    } else {
        [candidates addObject:@"/var/jb/usr/bin/uicache"];
        [candidates addObject:@"/var/jb/bin/uicache"];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *candidate in candidates) {
        if (candidate.length && [fm isExecutableFileAtPath:candidate]) return candidate;
    }
    return @"";
}

- (NSDictionary *)runCommand:(NSString *)path arguments:(NSArray<NSString *> *)arguments {
    if (!path.length) return @{
        @"spawned": @NO,
        @"pid": @0,
        @"exitStatus": @-1,
        @"signal": @0,
        @"stdout": @"",
        @"stderr": @"",
        @"error": @"uicache executable not found"
    };

    int outPipe[2] = {-1, -1};
    int errPipe[2] = {-1, -1};
    if (pipe(outPipe) != 0 || pipe(errPipe) != 0) {
        if (outPipe[0] >= 0) { close(outPipe[0]); close(outPipe[1]); }
        if (errPipe[0] >= 0) { close(errPipe[0]); close(errPipe[1]); }
        return @{@"spawned": @NO, @"pid": @0, @"exitStatus": @-1, @"signal": @0, @"stdout": @"", @"stderr": @"", @"error": @"pipe failed"};
    }

    NSMutableArray<NSString *> *argvStrings = [NSMutableArray arrayWithObject:path];
    [argvStrings addObjectsFromArray:SPToolArguments(path, arguments ?: @[])];
    NSMutableArray<NSString *> *argv = [NSMutableArray arrayWithCapacity:argvStrings.count];
    for (NSString *value in argvStrings) [argv addObject:value ?: @""];

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    posix_spawn_file_actions_addclose(&actions, errPipe[0]);

    NSMutableArray<NSValue *> *cArguments = [NSMutableArray arrayWithCapacity:argv.count];
    for (NSString *value in argv) [cArguments addObject:[NSValue valueWithPointer:(void *)value.UTF8String]];
    char **cArgv = calloc(cArguments.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < cArguments.count; i++) cArgv[i] = (char *)cArguments[i].pointerValue;
    cArgv[cArguments.count] = NULL;

    pid_t pid = 0;
    int spawnError = posix_spawn(&pid, path.fileSystemRepresentation, &actions, NULL, cArgv, environ);
    posix_spawn_file_actions_destroy(&actions);
    free(cArgv);
    close(outPipe[1]);
    close(errPipe[1]);

    if (spawnError != 0) {
        close(outPipe[0]);
        close(errPipe[0]);
        return @{@"spawned": @NO, @"pid": @0, @"exitStatus": @-1, @"signal": @0, @"stdout": @"", @"stderr": @"", @"error": [NSString stringWithFormat:@"posix_spawn errno=%d", spawnError]};
    }

    NSMutableData *outData = [NSMutableData data];
    NSMutableData *errData = [NSMutableData data];
    char buffer[4096];
    ssize_t length = 0;
    while ((length = read(outPipe[0], buffer, sizeof(buffer))) > 0 && outData.length < (512 * 1024)) [outData appendBytes:buffer length:(NSUInteger)length];
    while ((length = read(errPipe[0], buffer, sizeof(buffer))) > 0 && errData.length < (512 * 1024)) [errData appendBytes:buffer length:(NSUInteger)length];
    close(outPipe[0]);
    close(errPipe[0]);

    int status = -1;
    waitpid(pid, &status, 0);
    int exitStatus = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    int signal = WIFSIGNALED(status) ? WTERMSIG(status) : 0;
    return @{
        @"spawned": @YES,
        @"pid": @(pid),
        @"exitStatus": @(exitStatus),
        @"signal": @(signal),
        @"stdout": [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?: @"",
        @"stderr": [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"",
        @"error": @""
    };
}

- (NSDictionary *)launchServicesFactsForBundleID:(NSString *)bundleID {
    NSMutableDictionary *facts = [NSMutableDictionary dictionaryWithDictionary:@{
        @"workspaceClassAvailable": @NO,
        @"workspaceEnumerationSupported": @NO,
        @"registered": @NO,
        @"bundleURL": @"",
        @"localizedName": @"",
        @"proxyClassAvailable": @NO,
        @"proxyLookupSupported": @NO
    }];
    if (!bundleID.length) return facts;

    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    facts[@"workspaceClassAvailable"] = @(workspaceClass != Nil);
    id workspace = nil;
    if (workspaceClass && [workspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
        @try { workspace = [workspaceClass performSelector:@selector(defaultWorkspace)]; } @catch (__unused NSException *exception) { workspace = nil; }
    }
    SEL allAppsSel = nil;
    if (@available(iOS 16.0, *)) {
        allAppsSel = @selector(allApplications);
    } else {
        allAppsSel = @selector(allInstalledApplications);
    }
    if (workspace && [workspace respondsToSelector:allAppsSel]) {
        facts[@"workspaceEnumerationSupported"] = @YES;
        @try {
            IMP allAppsIMP = [workspace methodForSelector:allAppsSel];
            NSArray *apps = allAppsIMP ? ((id (*)(id, SEL))allAppsIMP)(workspace, allAppsSel) : @[];
            for (id app in apps) {
                NSString *candidateID = nil;
                @try { candidateID = [app performSelector:@selector(bundleIdentifier)]; } @catch (__unused NSException *exception) { candidateID = nil; }
                if (![candidateID isEqualToString:bundleID]) continue;
                facts[@"registered"] = @YES;
                if ([app respondsToSelector:@selector(bundleURL)]) {
                    NSURL *url = nil;
                    @try { url = [app performSelector:@selector(bundleURL)]; } @catch (__unused NSException *exception) { url = nil; }
                    if ([url isKindOfClass:[NSURL class]]) facts[@"bundleURL"] = url.path ?: @"";
                }
                if ([app respondsToSelector:@selector(localizedName)]) {
                    @try { facts[@"localizedName"] = [app performSelector:@selector(localizedName)] ?: @""; } @catch (__unused NSException *exception) {}
                }
                break;
            }
        } @catch (__unused NSException *exception) {}
    }

    Class proxyClass = objc_getClass("LSApplicationProxy");
    facts[@"proxyClassAvailable"] = @(proxyClass != Nil);
    if (proxyClass && [proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
        facts[@"proxyLookupSupported"] = @YES;
        @try {
            id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleID];
            if (proxy) {
                facts[@"registered"] = @YES;
                if ([proxy respondsToSelector:@selector(bundleURL)]) {
                    NSURL *url = nil;
                    @try { url = [proxy performSelector:@selector(bundleURL)]; } @catch (__unused NSException *exception) { url = nil; }
                    if ([url isKindOfClass:[NSURL class]] && [url.path length]) facts[@"bundleURL"] = url.path;
                }
                if ([proxy respondsToSelector:@selector(localizedName)]) {
                    @try { facts[@"localizedName"] = [proxy performSelector:@selector(localizedName)] ?: @""; } @catch (__unused NSException *exception) {}
                }
            }
        } @catch (__unused NSException *exception) {}
    }
    return facts;
}

- (NSDictionary *)probeBundleID:(NSString *)bundleID
                   transactionID:(NSString *)transactionID
                    operationLog:(OperationLog *)operationLog
                    logicalPath:(NSString *)logicalPath
                   resolvedPath:(NSString *)resolvedPath {
    NSString *path = [self uicachePath];
    NSString *query = bundleID ?: @"";
    NSString *command = path.length ? [NSString stringWithFormat:@"%@ -i %@", path, query] : @"uicache -i";
    NSString *recordID = [operationLog beginPhase:OperationPhaseUICache operation:@"forensic uicache -i" target:query input:command transactionID:transactionID ?: @""];
    NSDate *started = [NSDate date];
    NSDictionary *info = [self runCommand:path arguments:@[@"-i", query]];
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:started];
    BOOL commandSucceeded = [info[@"spawned"] boolValue] && [info[@"exitStatus"] intValue] == 0;
    [operationLog endPhase:recordID
                  exitCode:[info[@"exitStatus"] intValue]
                 rawOutput:info[@"stdout"] ?: @""
                  rawError:info[@"stderr"] ?: info[@"error"] ?: @""
              verification:commandSucceeded ? @"uicache -i completed; result is observational" : @"uicache -i failed; result is observational"
                  verified:commandSucceeded
                  duration:duration
                   context:@{ @"pid": info[@"pid"] ?: @0, @"signal": info[@"signal"] ?: @0, @"spawned": info[@"spawned"] ?: @NO, @"command": command, @"logicalPath": logicalPath ?: @"", @"resolvedPath": resolvedPath ?: @"" }];

    NSString *listRecordID = [operationLog beginPhase:OperationPhaseVerify operation:@"forensic uicache -l exact Bundle ID" target:query input:path.length ? [NSString stringWithFormat:@"%@ -l", path] : @"uicache -l" transactionID:transactionID ?: @""];
    NSDictionary *list = [self runCommand:path arguments:@[@"-l"]];
    NSString *listOutput = list[@"stdout"] ?: @"";
    BOOL listed = NO;
    for (NSString *line in [listOutput componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmedLine isEqualToString:bundleID]) { listed = YES; break; }
    }
    [operationLog endPhase:listRecordID
                  exitCode:[list[@"exitStatus"] intValue]
                 rawOutput:listOutput
                  rawError:list[@"stderr"] ?: list[@"error"] ?: @""
              verification:listed ? @"Exact Bundle ID found in uicache -l output" : @"Exact Bundle ID not found in uicache -l output"
                  verified:listed
                  duration:0
                   context:@{ @"pid": list[@"pid"] ?: @0, @"signal": list[@"signal"] ?: @0, @"spawned": list[@"spawned"] ?: @NO, @"command": path.length ? [NSString stringWithFormat:@"%@ -l", path] : @"uicache -l" }];

    NSDictionary *ls = [self launchServicesFactsForBundleID:bundleID];
    NSString *lsRecordID = [operationLog beginPhase:OperationPhaseVerify operation:@"forensic LaunchServices Bundle ID lookup" target:query input:@"LSApplicationWorkspace + LSApplicationProxy" transactionID:transactionID ?: @""];
    [operationLog endPhase:lsRecordID exitCode:[ls[@"registered"] boolValue] ? 0 : 1 rawOutput:@"" rawError:[ls[@"registered"] boolValue] ? @"" : @"Bundle ID not proven by LaunchServices lookup" verification:[ls[@"registered"] boolValue] ? @"LaunchServices reports Bundle ID" : @"LaunchServices does not report Bundle ID" verified:[ls[@"registered"] boolValue] duration:0 context:ls];

    return @{
        @"bundleID": bundleID ?: @"",
        @"uicachePath": path,
        @"logicalPath": logicalPath ?: @"",
        @"resolvedPath": resolvedPath ?: @"",
        @"uicacheInfo": info ?: @{},
        @"uicacheListedExact": @(listed),
        @"uicacheList": list ?: @{},
        @"launchServices": ls ?: @{},
        @"registeredByAllSources": @([ls[@"registered"] boolValue] && listed),
        @"readOnly": @YES
    };
}

@end
