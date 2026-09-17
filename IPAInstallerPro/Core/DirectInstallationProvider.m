// DirectInstallationProvider.m
// IPA Installer Pro
//
// v2.2 — STANDALONE with rollback, safe delete order, symlink/traversal checks
//

#import "DirectInstallationProvider.h"
#import "JBHide/SpiderInstalledAppsStore.h"
#import "RootlessManager.h"
#import "OperationLog.h"
#import "InstallationTransactionCoordinator.h"
#import "ForensicRegistrationProbe.h"
#import "JailbreakEnvironment.h"
#import "IPAStructuralAnalyzer.h"
#import "IPAStructuralResult.h"
#import "SpiderInstallationGraph.h"
#import "SigningPlanner.h"
#import "MachORPathRepair.h"
#import "MachOAnalyzer.h"
#import "SigningPlan.h"
#import "SigningTarget.h"
#import "EntitlementSet.h"
#import "SignatureAnalyzer.h"
#import "ExecutableValidator.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <objc/runtime.h>
#include <spawn.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <copyfile.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#import "RuntimeEnvironment.h"

extern char **environ;

@interface DirectInstallationProvider ()
@property (nonatomic, strong) NSString *ldidPath;
@property (nonatomic, strong) NSString *uicachePath;
@property (nonatomic, strong) NSString *chmodPath;
@property (nonatomic, strong) NSString *chownPath;
@property (nonatomic, strong) NSString *rmPath;
@property (nonatomic, strong) NSString *unzipPath;
@property (nonatomic, strong) NSString *whoamiPath;
@property (nonatomic, strong) NSString *helperPath;
@property (nonatomic, strong) NSString *mkdirPath;
@property (nonatomic, strong) NSString *mvPath;
@property (nonatomic, strong) NSString *cpPath;
@property (nonatomic, strong) NSString *statPath;
@property (nonatomic, strong) NSMutableString *diagnosticsLog;
@property (nonatomic, assign) NSUInteger diagFrameworksSigned;
@property (nonatomic, assign) NSUInteger diagDylibsSigned;
@property (nonatomic, assign) NSUInteger diagAppexSigned;
@property (nonatomic, assign) NSUInteger diagDeepCopyTotal;
@property (nonatomic, assign) NSUInteger diagDeepCopyMissing;
@property (nonatomic, assign) NSUInteger diagDeepCopySizeMismatch;
@property (nonatomic, strong) NSString *diagDeepCopyDetail;
@property (nonatomic, strong) NSString *lastMachOVerificationDetail;
@property (nonatomic, strong) SigningPlan *activeSigningPlan;
@property (nonatomic, strong) NSString *lastInstalledAppPath;
- (BOOL)signBundleExecutableAtPath:(NSString *)bundlePath label:(NSString *)label hasHelper:(BOOL)hasH opLog:(OperationLog *)opLog txnID:(NSString *)txnID;
- (void)signExe:(NSString *)path hasHelper:(BOOL)hasH opLog:(OperationLog *)opLog txnID:(NSString *)txnID;
- (BOOL)remapSigningPlan:(SigningPlan *)plan toInstalledAppPath:(NSString *)installedAppPath;
- (BOOL)verifyPlannedEntitlements:(SigningPlan *)plan opLog:(OperationLog *)opLog txnID:(NSString *)txnID;
- (BOOL)waitForProcess:(pid_t)pid status:(int *)status timeout:(NSTimeInterval)timeout;
- (BOOL)runCmdCapture:(NSString *)cmd args:(NSArray *)args opLog:(OperationLog *)opLog recordID:(NSString *)recordID operation:(NSString *)operation;
- (NSArray<NSString *> *)machOPathsAtPath:(NSString *)rootPath;
- (BOOL)verifyAllMachOSignedAtPath:(NSString *)appPath opLog:(OperationLog *)opLog txnID:(NSString *)txnID;
- (BOOL)postSignVerification:(NSString *)destApp opLog:(OperationLog *)opLog txnID:(NSString *)txnID;
- (BOOL)verifyLaunchReadinessAtPath:(NSString *)appPath bundleID:(NSString *)bundleID exeName:(NSString *)exeName opLog:(OperationLog *)opLog txnID:(NSString *)txnID reason:(NSString **)reason;
- (BOOL)dependency:(NSString *)dependency resolvesForBinary:(NSString *)binaryPath appPath:(NSString *)appPath rpaths:(NSArray<MachORPath *> *)rpaths;
- (NSUInteger)cleanupStaleStageDirectoriesAtRoot:(NSString *)applicationsPath hasHelper:(BOOL)hasHelper opLog:(OperationLog *)opLog txnID:(NSString *)txnID;
- (BOOL)isBundleIDRegistered:(NSString *)bundleID;
- (BOOL)verifyRegistrationForBundleID:(NSString *)bundleID path:(NSString *)appPath opLog:(OperationLog *)opLog txnID:(NSString *)txnID;
- (BOOL)rollbackRegistrationForBundleID:(NSString *)bundleID path:(NSString *)appPath opLog:(OperationLog *)opLog txnID:(NSString *)txnID;
@end

@implementation DirectInstallationProvider

- (NSString *)providerName { return @"Direct Install"; }
- (NSString *)providerDescription { return @"Standalone installation with full signing — IPA Installer Pro signature"; }
- (NSInteger)priority { return 100; }

- (instancetype)init {
 self = [super init];
 if (self) {
 RootlessManager *rm = [RootlessManager sharedManager];
 self.ldidPath = [rm resolvePath:@"/usr/bin/ldid"];
 self.uicachePath = [rm resolvePath:@"/usr/bin/uicache"];
 self.chmodPath = [rm resolvePath:@"/usr/bin/chmod"];
 self.chownPath = [rm resolvePath:@"/usr/sbin/chown"];
 self.rmPath = [rm resolvePath:@"/bin/rm"];
 if (![[NSFileManager defaultManager] isExecutableFileAtPath:self.rmPath]) {
     // Build candidates dynamically from bootstrapPath
     RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];
     NSMutableArray<NSString *> *rmCandidates = [NSMutableArray arrayWithObjects:
         @"/usr/bin/rm",
         @"/bin/rm",
         nil];
     if (rt.bootstrapPath) {
         [rmCandidates insertObject:[rt.bootstrapPath stringByAppendingPathComponent:@"usr/bin/rm"] atIndex:0];
         [rmCandidates insertObject:[rt.bootstrapPath stringByAppendingPathComponent:@"bin/rm"] atIndex:1];
     }
     for (NSString *candidate in rmCandidates) {
         if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
             self.rmPath = candidate;
             break;
         }
     }
 }
 self.unzipPath = [rm resolvePath:@"/usr/bin/unzip"];
 self.whoamiPath = [rm resolvePath:@"/usr/bin/whoami"];
 self.mkdirPath = [rm resolvePath:@"/bin/mkdir"];
 self.mvPath = [rm resolvePath:@"/bin/mv"];
 self.cpPath = [rm resolvePath:@"/bin/cp"];
 self.statPath = [rm resolvePath:@"/usr/bin/stat"];
 [self findWorkingHelper];
 }
 return self;
}

- (void)findWorkingHelper {
 RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];
 NSMutableArray *candidates = [NSMutableArray arrayWithObjects:
 [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ipainstallerpro_helper"],
 @"/usr/bin/ipainstallerpro_helper",
 nil];
 if (rt.bootstrapPath) {
     [candidates addObject:[rt.bootstrapPath stringByAppendingPathComponent:@"usr/bin/ipainstallerpro_helper"]];
 }
 for (NSString *path in candidates) {
 if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
 if ([self testHelperAtPath:path]) {
 self.helperPath = path;
 NSLog(@"[IPAInstallerPro] Helper active: %@", path);
 return;
 }
 }
 }
 self.helperPath = nil;
 NSLog(@"[IPAInstallerPro] WARNING: No root helper — falling back to direct execution");
}

- (BOOL)testHelperAtPath:(NSString *)path {
 pid_t pid;
 const char *h = [path UTF8String];
 const char *w = [self.whoamiPath UTF8String];
 char *argv[] = {(char*)h, (char*)w, NULL};
 if (posix_spawn(&pid, h, NULL, NULL, argv, environ) != 0) return NO;
 int ws = 0;
 BOOL reaped = [self waitForProcess:pid status:&ws timeout:10.0];
 return (reaped && WIFEXITED(ws) && WEXITSTATUS(ws) == 0);
}

- (BOOL)isAvailable {
 return (
 [[NSFileManager defaultManager] fileExistsAtPath:self.ldidPath] &&
 [[NSFileManager defaultManager] fileExistsAtPath:self.uicachePath] &&
 [[NSFileManager defaultManager] fileExistsAtPath:self.unzipPath]
 );
}
- (BOOL)hasRootHelper { return (self.helperPath != nil && self.helperPath.length > 0); }

- (BOOL)waitForProcess:(pid_t)pid status:(int *)status timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    int localStatus = 0;
    for (;;) {
        pid_t waited = waitpid(pid, &localStatus, WNOHANG);
        if (waited == pid) {
            if (status) *status = localStatus;
            return YES;
        }
        if (waited < 0) {
            if (errno == EINTR) continue;
            if (status) *status = localStatus;
            return NO;
        }
        if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
            kill(pid, SIGKILL);
            while (waitpid(pid, &localStatus, 0) < 0 && errno == EINTR) { }
            if (status) *status = localStatus;
            NSLog(@"[IPAInstallerPro] Process %d timed out after %.0f seconds and was terminated", pid, timeout);
            return NO;
        }
        usleep(100000);
    }
}

- (BOOL)runCmdCapture:(NSString *)cmd args:(NSArray *)args opLog:(OperationLog *)opLog recordID:(NSString *)recordID operation:(NSString *)operation {
    if (!cmd.length) {
        if (recordID && opLog) [opLog endPhase:recordID exitCode:1 rawOutput:@"" rawError:@"Command path is empty" verification:@"Invalid command path" verified:NO duration:0 context:@{@"operation": operation ?: @"", @"spawned": @NO}];
        return NO;
    }
    int outPipe[2] = {-1, -1}, errPipe[2] = {-1, -1};
    if (pipe(outPipe) != 0 || pipe(errPipe) != 0) {
        if (outPipe[0] >= 0) { close(outPipe[0]); close(outPipe[1]); }
        if (errPipe[0] >= 0) { close(errPipe[0]); close(errPipe[1]); }
        if (recordID && opLog) [opLog endPhase:recordID exitCode:errno ?: 1 rawOutput:@"" rawError:[NSString stringWithFormat:@"pipe failed: errno=%d", errno] verification:@"Could not create stdout/stderr pipes" verified:NO duration:0 context:@{@"operation": operation ?: @"", @"spawned": @NO}];
        return NO;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    posix_spawn_file_actions_addclose(&actions, errPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outPipe[1]);
    posix_spawn_file_actions_addclose(&actions, errPipe[1]);

    NSString *spawnRecordID = [opLog beginPhase:OperationPhaseIPAExtract operation:@"process-spawn" target:cmd input:[NSString stringWithFormat:@"operation=%@ args=%@", operation ?: @"", [args componentsJoinedByString:@" "]] transactionID:opLog.activeTransactionID];
    pid_t pid = 0;
    const char *c = cmd.fileSystemRepresentation;
    char **argv = calloc(args.count + 2, sizeof(char *));
    argv[0] = (char *)c;
    for (NSUInteger i = 0; i < args.count; i++) argv[i + 1] = (char *)[args[i] fileSystemRepresentation];
    int spawnStatus = posix_spawn(&pid, c, &actions, NULL, argv, environ);
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    close(outPipe[1]);
    close(errPipe[1]);

    if (spawnStatus != 0) {
        close(outPipe[0]);
        close(errPipe[0]);
        if (spawnRecordID && opLog) [opLog endPhase:spawnRecordID exitCode:spawnStatus rawOutput:@"" rawError:[NSString stringWithFormat:@"posix_spawn failed: errno=%d", spawnStatus] verification:@"process not spawned" verified:NO duration:0 context:@{@"operation": operation ?: @"", @"pid": @(0), @"spawned": @NO}];
        if (recordID && opLog) [opLog endPhase:recordID exitCode:spawnStatus rawOutput:@"" rawError:[NSString stringWithFormat:@"posix_spawn failed: errno=%d", spawnStatus] verification:@"Command could not be executed" verified:NO duration:0 context:@{@"operation": operation ?: @"", @"pid": @(0), @"spawned": @NO}];
        return NO;
    }

    if (spawnRecordID && opLog) [opLog endPhase:spawnRecordID exitCode:0 rawOutput:@"" rawError:@"" verification:[NSString stringWithFormat:@"spawned pid=%d; stdout/stderr pipes attached; timeout=300s", pid] verified:YES duration:0 context:@{@"operation": operation ?: @"", @"pid": @(pid), @"spawned": @YES, @"timeoutSeconds": @300}];

    int outFlags = fcntl(outPipe[0], F_GETFL, 0);
    int errFlags = fcntl(errPipe[0], F_GETFL, 0);
    if (outFlags >= 0) fcntl(outPipe[0], F_SETFL, outFlags | O_NONBLOCK);
    if (errFlags >= 0) fcntl(errPipe[0], F_SETFL, errFlags | O_NONBLOCK);

    NSMutableData *stdoutData = [NSMutableData data];
    NSMutableData *stderrData = [NSMutableData data];
    const NSUInteger maxCapturedBytes = 4 * 1024 * 1024;
    NSDate *start = [NSDate date];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:300.0];
    int waitStatus = 0;
    BOOL reaped = NO, timedOut = NO, waitFailed = NO;
    char buffer[8192];

    for (;;) {
        for (int fdIndex = 0; fdIndex < 2; fdIndex++) {
            int fd = (fdIndex == 0) ? outPipe[0] : errPipe[0];
            NSMutableData *sink = (fdIndex == 0) ? stdoutData : stderrData;
            ssize_t n = 0;
            while ((n = read(fd, buffer, sizeof(buffer))) > 0) {
                if (sink.length < maxCapturedBytes) {
                    NSUInteger allowed = MIN((NSUInteger)n, maxCapturedBytes - sink.length);
                    [sink appendBytes:buffer length:allowed];
                }
            }
        }
        pid_t waited = waitpid(pid, &waitStatus, WNOHANG);
        if (waited == pid) {
            reaped = YES;
            // Drain output produced before process exit without blocking.
            for (int fdIndex = 0; fdIndex < 2; fdIndex++) {
                int fd = (fdIndex == 0) ? outPipe[0] : errPipe[0];
                NSMutableData *sink = (fdIndex == 0) ? stdoutData : stderrData;
                ssize_t n = 0;
                while ((n = read(fd, buffer, sizeof(buffer))) > 0) {
                    if (sink.length < maxCapturedBytes) {
                        NSUInteger allowed = MIN((NSUInteger)n, maxCapturedBytes - sink.length);
                        [sink appendBytes:buffer length:allowed];
                    }
                }
            }
            break;
        }
        if (waited < 0 && errno != EINTR) {
            waitFailed = YES;
            kill(pid, SIGKILL);
            while (waitpid(pid, &waitStatus, 0) < 0 && errno == EINTR) { }
            reaped = YES;
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
    close(errPipe[0]);

    NSString *stdoutText = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";
    BOOL exited = reaped && WIFEXITED(waitStatus);
    int exitCode = exited ? WEXITSTATUS(waitStatus) : (timedOut ? 124 : 125);
    BOOL ok = exited && exitCode == 0 && !timedOut && !waitFailed;
    NSString *rawError = stderrText;
    if (timedOut) rawError = [NSString stringWithFormat:@"%@%@", rawError.length ? [rawError stringByAppendingString:@" | "] : @"", @"timeout after 300s; child killed and reaped"];
    if (waitFailed) rawError = [NSString stringWithFormat:@"%@%@", rawError.length ? [rawError stringByAppendingString:@" | "] : @"", @"waitpid failed; child was killed and reaped"];
    if (!ok && !rawError.length) rawError = [NSString stringWithFormat:@"command exited with status %d", exitCode];
    NSTimeInterval duration = -[start timeIntervalSinceNow];
    NSDictionary *context = @{
        @"operation": operation ?: @"",
        @"pid": @(pid),
        @"command": cmd,
        @"arguments": args ?: @[],
        @"timeoutSeconds": @300,
        @"timedOut": @(timedOut),
        @"waitFailed": @(waitFailed),
        @"reaped": @(reaped),
        @"stdoutBytes": @(stdoutData.length),
        @"stderrBytes": @(stderrData.length),
        @"durationSeconds": @(duration)
    };
    if (recordID && opLog) [opLog endPhase:recordID exitCode:exitCode rawOutput:stdoutText rawError:rawError verification:[NSString stringWithFormat:@"%@ pid=%d exit=%d reaped=%@ timeout=%@", operation ?: @"command", pid, exitCode, reaped ? @"YES" : @"NO", timedOut ? @"YES" : @"NO"] verified:ok duration:duration context:context];
    return ok;
}

#pragma mark - Command Execution with OperationLog

- (BOOL)runCmd:(NSString *)cmd args:(NSArray *)args opLog:(OperationLog *)opLog recordID:(NSString *)recID {
    NSDate *started = [NSDate date];
    if (!cmd.length) {
        if (recID && opLog) [opLog endPhase:recID exitCode:1 rawOutput:@"" rawError:@"Command path is empty" verification:@"Invalid command path" verified:NO duration:0];
        return NO;
    }
    pid_t pid = 0;
    const char *c = cmd.fileSystemRepresentation;
    char **argv = calloc(args.count + 2, sizeof(char *));
    argv[0] = (char *)c;
    for (NSUInteger i = 0; i < args.count; i++) argv[i + 1] = (char *)[args[i] fileSystemRepresentation];
    int spawnStatus = posix_spawn(&pid, c, NULL, NULL, argv, environ);
    free(argv);
    if (spawnStatus != 0) {
        if (recID && opLog) [opLog endPhase:recID exitCode:spawnStatus rawOutput:@"" rawError:[NSString stringWithFormat:@"posix_spawn failed: errno=%d", spawnStatus] verification:@"Command could not be executed" verified:NO duration:0];
        return NO;
    }
    int waitStatus = 0;
    BOOL reaped = [self waitForProcess:pid status:&waitStatus timeout:300.0];
    BOOL exited = reaped && WIFEXITED(waitStatus);
    int exitCode = exited ? WEXITSTATUS(waitStatus) : 124;
    BOOL ok = exited && exitCode == 0;
    if (recID && opLog) {
        NSString *failure = ok ? @"" : (reaped ? [NSString stringWithFormat:@"Command failed with exit code %d", exitCode] : @"Command timed out or was terminated");
        [opLog endPhase:recID exitCode:exitCode rawOutput:@"" rawError:failure verification:[NSString stringWithFormat:@"cmd=%@ args=%@", cmd, [args componentsJoinedByString:@" "]] verified:ok duration:-[started timeIntervalSinceNow] context:@{ @"wallClockSeconds": @(-[started timeIntervalSinceNow]), @"command": cmd ?: @"" }];
    }
    return ok;
}

- (BOOL)runRoot:(NSString *)cmd args:(NSArray *)args opLog:(OperationLog *)opLog recordID:(NSString *)recID {
    NSDate *started = [NSDate date];
    if (![self hasRootHelper]) {
        NSLog(@"[IPAInstallerPro] No helper, running as current user: %@", cmd);
        return [self runCmd:cmd args:args opLog:opLog recordID:recID];
    }

    // FIX(v3.0.20): Capture stderr to diagnose root helper failures.
    int stdoutPipe[2], stderrPipe[2];
    if (pipe(stdoutPipe) != 0 || pipe(stderrPipe) != 0) {
        NSLog(@"[IPAInstallerPro] pipe() failed for root helper stderr capture");
        return NO;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addclose(&actions, stdoutPipe[0]);
    posix_spawn_file_actions_addclose(&actions, stderrPipe[0]);
    posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, stdoutPipe[1]);
    posix_spawn_file_actions_addclose(&actions, stderrPipe[1]);

    pid_t pid = 0;
    const char *helper = self.helperPath.fileSystemRepresentation;
    const char *command = cmd.fileSystemRepresentation;
    char **argv = calloc(args.count + 3, sizeof(char *));
    argv[0] = (char *)helper;
    argv[1] = (char *)command;
    for (NSUInteger i = 0; i < args.count; i++) argv[i + 2] = (char *)[args[i] fileSystemRepresentation];

    int spawnStatus = posix_spawn(&pid, helper, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    free(argv);
    close(stdoutPipe[1]);
    close(stderrPipe[1]);

    if (spawnStatus != 0) {
        close(stdoutPipe[0]);
        close(stderrPipe[0]);
        NSLog(@"[IPAInstallerPro] Root helper spawn failed; command was not retried without root (errno=%d)", spawnStatus);
        if (recID && opLog) [opLog endPhase:recID exitCode:spawnStatus rawOutput:@"" rawError:@"Root helper could not be spawned; no unsafe fallback was attempted" verification:@"root helper spawn failed" verified:NO duration:0];
        return NO;
    }

    int waitStatus = 0;
    BOOL reaped = [self waitForProcess:pid status:&waitStatus timeout:300.0];
    BOOL exited = reaped && WIFEXITED(waitStatus);
    int exitCode = exited ? WEXITSTATUS(waitStatus) : 124;

    // Read captured stderr
    NSMutableString *stderrOutput = [NSMutableString string];
    char buffer[4096];
    ssize_t n;
    while ((n = read(stderrPipe[0], buffer, sizeof(buffer) - 1)) > 0) {
        buffer[n] = '\0';
        [stderrOutput appendString:[NSString stringWithUTF8String:buffer]];
    }
    close(stdoutPipe[0]);
    close(stderrPipe[0]);

    BOOL ok = exited && exitCode == 0;
    if (recID && opLog) {
        NSString *failure = ok ? @"" : (reaped ? [NSString stringWithFormat:@"Root helper failed with exit code %d | stderr: %@", exitCode, stderrOutput.length > 0 ? stderrOutput : @"(no stderr)"] : @"Root helper timed out or was terminated");
        [opLog endPhase:recID exitCode:exitCode rawOutput:@"" rawError:failure verification:[NSString stringWithFormat:@"root cmd=%@ args=%@", cmd, [args componentsJoinedByString:@" "]] verified:ok duration:-[started timeIntervalSinceNow] context:@{ @"wallClockSeconds": @(-[started timeIntervalSinceNow]), @"command": cmd ?: @"", @"rootHelper": @YES, @"stderr": stderrOutput ?: @"" }];
    }
    return ok;
}

- (NSUInteger)cleanupStaleStageDirectoriesAtRoot:(NSString *)applicationsPath hasHelper:(BOOL)hasHelper opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = applicationsPath.stringByStandardizingPath;
    BOOL allowedRoot = [root.lastPathComponent isEqualToString:@"Applications"] || [root.lastPathComponent isEqualToString:@"IPAInstallerPro-Staging"];
    if (root.length == 0 || !allowedRoot || ![fm fileExistsAtPath:root]) return 0;

    NSString *recordID = [opLog beginPhase:OperationPhaseCleanup operation:@"cleanup-stale-ipa-stage" target:root input:@"only *.app.ipa-stage-* older than 5 minutes" transactionID:txnID];
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-300.0];
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSMutableArray<NSString *> *removed = [NSMutableArray array];
    NSMutableArray<NSString *> *failed = [NSMutableArray array];
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:root error:nil] ?: @[];

    for (NSString *entry in entries) {
        if (![entry containsString:@".app.ipa-stage-"]) continue;
        NSString *candidate = [root stringByAppendingPathComponent:entry];
        NSDictionary *attributes = [fm attributesOfItemAtPath:candidate error:nil];
        NSString *fileType = attributes[NSFileType];
        BOOL removableStage = [fileType isEqualToString:NSFileTypeDirectory] || [fileType isEqualToString:NSFileTypeSymbolicLink];
        if (!removableStage) continue;
        NSDate *modified = attributes[NSFileModificationDate];
        if (modified && [modified compare:cutoff] == NSOrderedDescending) continue;
        [candidates addObject:candidate];
    }

    for (NSString *candidate in candidates) {
        BOOL deleted = NO;
        if (hasHelper) {
            deleted = [self runRoot:self.rmPath args:@[@"-rf", candidate] opLog:opLog recordID:nil];
        } else {
            deleted = [fm removeItemAtPath:candidate error:nil];
        }
        struct stat postDeleteStat;
        BOOL stillExists = (lstat(candidate.fileSystemRepresentation, &postDeleteStat) == 0);
        if (deleted && !stillExists) [removed addObject:candidate.lastPathComponent];
        else [failed addObject:candidate.lastPathComponent];
    }

    BOOL verified = (failed.count == 0);
    NSString *rawOutput = [NSString stringWithFormat:@"candidates=%lu removed=%lu", (unsigned long)candidates.count, (unsigned long)removed.count];
    NSString *rawError = failed.count ? [NSString stringWithFormat:@"stale stage paths not removed: %@", [failed componentsJoinedByString:@", "]] : @"";
    [opLog endPhase:recordID exitCode:verified ? 0 : 1 rawOutput:rawOutput rawError:rawError verification:verified ? @"no eligible stale ipa-stage directories remain" : @"some eligible stale ipa-stage directories remain" verified:verified duration:0 context:@{ @"root": root, @"cutoffSeconds": @300, @"candidates": candidates, @"removed": removed, @"failed": failed }];
    return removed.count;
}

- (NSString *)runCmdOutput:(NSString *)cmd args:(NSArray *)args {
    int pipefd[2];
    if (!cmd.length || pipe(pipefd) != 0) return nil;
    pid_t pid = 0;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);
    const char *c = cmd.fileSystemRepresentation;
    char **argv = calloc(args.count + 2, sizeof(char *));
    argv[0] = (char *)c;
    for (NSUInteger i = 0; i < args.count; i++) argv[i + 1] = (char *)[args[i] fileSystemRepresentation];
    int spawnStatus = posix_spawn(&pid, c, &actions, NULL, argv, environ);
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);
    if (spawnStatus != 0) {
        close(pipefd[0]);
        return nil;
    }

    int flags = fcntl(pipefd[0], F_GETFL, 0);
    if (flags >= 0) fcntl(pipefd[0], F_SETFL, flags | O_NONBLOCK);
    NSMutableData *data = [NSMutableData data];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:300.0];
    int waitStatus = 0;
    BOOL reaped = NO;
    BOOL timedOut = NO;
    char buffer[4096];
    for (;;) {
        ssize_t n = read(pipefd[0], buffer, sizeof(buffer));
        if (n > 0) [data appendBytes:buffer length:(NSUInteger)n];
        pid_t waited = waitpid(pid, &waitStatus, WNOHANG);
        if (waited == pid) { reaped = YES; }
        else if (waited < 0 && errno != EINTR) {
            kill(pid, SIGKILL);
            while (waitpid(pid, &waitStatus, 0) < 0 && errno == EINTR) { }
            timedOut = YES;
            reaped = YES;
            break;
        }
        if (reaped) {
            while ((n = read(pipefd[0], buffer, sizeof(buffer))) > 0) [data appendBytes:buffer length:(NSUInteger)n];
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
    close(pipefd[0]);
    if (timedOut || !reaped || !WIFEXITED(waitStatus) || WEXITSTATUS(waitStatus) != 0) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

#pragma mark - Security Checks

- (BOOL)containsDangerousPaths:(NSString *)path {
 if (!path) return YES;
 // Check for directory traversal
 if ([path containsString:@".."]) return YES;
 if ([path containsString:@"~"]) return YES;
 // Check for absolute paths that escape expected structure
 if ([path hasPrefix:@"/"]) {
 // Only allow /Payload/... and /Info.plist patterns inside IPA
 if (![path hasPrefix:@"Payload/"] && ![path isEqualToString:@"Payload"]) return YES;
 }
 // Check for symlinks in path
 if ([path containsString:@"->"]) return YES;
 return NO;
}

- (BOOL)validateIPAPathSafety:(NSString *)ipaPath opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 NSString *rec = [opLog beginPhase:OperationPhaseIPAOpen operation:@"pathSafetyCheck" target:ipaPath input:@"" transactionID:txnID];

 // Check file size (max 2GB)
 NSFileManager *fm = [NSFileManager defaultManager];
 NSDictionary *attrs = [fm attributesOfItemAtPath:ipaPath error:nil];
 long long size = attrs.fileSize;
 if (size > 2147483648LL) {
 [opLog endPhase:rec exitCode:1 rawOutput:@"" rawError:@"IPA exceeds 2GB limit"
 verification:[NSString stringWithFormat:@"size=%lld (max=2147483648)", size] verified:NO duration:0];
 return NO;
 }

 // Check available space (need at least 3x IPA size)
 NSString *tmpDir = NSTemporaryDirectory();
 NSDictionary *fsAttrs = [fm attributesOfFileSystemForPath:tmpDir error:nil];
 long long freeSpace = [fsAttrs[NSFileSystemFreeSize] longLongValue];
 if (freeSpace < size * 3) {
 [opLog endPhase:rec exitCode:1 rawOutput:@"" rawError:@"Insufficient disk space"
 verification:[NSString stringWithFormat:@"free=%lld needed=%lld", freeSpace, size * 3] verified:NO duration:0];
 return NO;
 }

 [opLog endPhase:rec exitCode:0 rawOutput:@"" rawError:@""
 verification:[NSString stringWithFormat:@"size=%lld free=%lld", size, freeSpace] verified:YES duration:0];
 return YES;
}

- (BOOL)checkForSymlinksInExtractedPath:(NSString *)path opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *items = [fm subpathsAtPath:path];
  for (NSString *item in items) {
    NSString *fullPath = [path stringByAppendingPathComponent:item];
    // Check if it's a symlink
    NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
    if (attrs.fileType == NSFileTypeSymbolicLink) {
      NSString *dest = [fm destinationOfSymbolicLinkAtPath:fullPath error:nil];
      if (!dest || dest.length == 0) continue;

      // FIX(v3.0.19): Properly resolve and validate symlinks.
      // Many valid apps (Cydia, etc.) contain symlinks inside the bundle.
      // Only reject symlinks that escape the bundle AND point outside known safe areas.
      BOOL isSafe = NO;

      // 1. Allow Mach-O rpaths (@executable_path, @loader_path, @rpath)
      if ([dest hasPrefix:@"@"]) { isSafe = YES; }

      // 2. If absolute path, check if it stays within the bundle
      else if ([dest hasPrefix:@"/"]) {
        // Normalize: resolve ".." components
        NSString *normalized = dest.stringByStandardizingPath;
        if ([normalized hasPrefix:path]) { isSafe = YES; }
        // Also allow symlinks to system frameworks/libs (common in jailbreak apps)
        else if ([normalized hasPrefix:@"/System/"] ||
                 [normalized hasPrefix:@"/usr/lib/"] ||
                 [normalized hasPrefix:@"/var/tmp/"]) { isSafe = YES; }
        // FIX(Palera1n): Check against dynamic bootstrapPath instead of hardcoded /var/jb
        RuntimeEnvironment *rtEnv = [RuntimeEnvironment sharedEnvironment];
        if (rtEnv.bootstrapPath && [normalized hasPrefix:rtEnv.bootstrapPath]) { isSafe = YES; }
      }

      // 3. If relative path, resolve it relative to the symlink's parent directory
      else {
        NSString *parentDir = [fullPath stringByDeletingLastPathComponent];
        NSString *resolved = [parentDir stringByAppendingPathComponent:dest];
        NSString *normalized = resolved.stringByStandardizingPath;
        if ([normalized hasPrefix:path]) { isSafe = YES; }
      }

      if (!isSafe) {
        NSString *rec = [opLog beginPhase:OperationPhaseVerify operation:@"symlinkCheck" target:fullPath input:dest transactionID:txnID];
        [opLog endPhase:rec exitCode:1 rawOutput:@"" rawError:[NSString stringWithFormat:@"Dangerous symlink: %@ -> %@", fullPath, dest]
        verification:@"Symlink escapes app bundle to unknown location" verified:NO duration:0];
        return NO;
      }
    }
  }
  return YES;
}

#pragma mark - Verification Helpers

- (BOOL)verifyStat:(NSString *)path mode:(mode_t *)outMode uid:(uid_t *)outUid gid:(gid_t *)outGid {
 struct stat st;
 if (stat([path UTF8String], &st) != 0) return NO;
 if (outMode) *outMode = st.st_mode & 0777;
 if (outUid) *outUid = st.st_uid;
 if (outGid) *outGid = st.st_gid;
 return YES;
}

- (BOOL)verifyDeepCopy:(NSString *)src dst:(NSString *)dst opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
    NSDate *started = [NSDate date];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *srcItems = [fm subpathsAtPath:src] ?: @[];
    NSArray<NSString *> *dstItems = [fm subpathsAtPath:dst] ?: @[];
    NSSet<NSString *> *srcSet = [NSSet setWithArray:srcItems];
    NSMutableString *detail = [NSMutableString string];
    BOOL ok = YES;
    NSUInteger missing = 0, extra = 0, typeMismatch = 0, sizeMismatch = 0, linkMismatch = 0;
    NSUInteger detailCount = 0;

    if (srcItems.count != dstItems.count) {
        [detail appendFormat:@"countMismatch(src=%lu,dst=%lu) ", (unsigned long)srcItems.count, (unsigned long)dstItems.count];
        ok = NO;
    }
    for (NSString *sub in srcItems) {
        NSString *sPath = [src stringByAppendingPathComponent:sub];
        NSString *dPath = [dst stringByAppendingPathComponent:sub];
        struct stat sStat = {0}, dStat = {0};
        if (lstat(sPath.fileSystemRepresentation, &sStat) != 0 || lstat(dPath.fileSystemRepresentation, &dStat) != 0) {
            missing++;
            ok = NO;
            if (detailCount++ < 12) [detail appendFormat:@"missing:%@ ", sub];
            continue;
        }
        BOOL sLink = S_ISLNK(sStat.st_mode), dLink = S_ISLNK(dStat.st_mode);
        BOOL sDir = S_ISDIR(sStat.st_mode), dDir = S_ISDIR(dStat.st_mode);
        if (sLink != dLink || sDir != dDir) {
            typeMismatch++;
            ok = NO;
            if (detailCount++ < 12) [detail appendFormat:@"type:%@ ", sub];
            continue;
        }
        if (sLink) {
            NSString *sDest = [fm destinationOfSymbolicLinkAtPath:sPath error:nil];
            NSString *dDest = [fm destinationOfSymbolicLinkAtPath:dPath error:nil];
            if (![sDest isEqualToString:dDest]) {
                linkMismatch++;
                ok = NO;
                if (detailCount++ < 12) [detail appendFormat:@"link:%@(%@!=%@) ", sub, sDest ?: @"nil", dDest ?: @"nil"];
            }
        } else if (!sDir && sStat.st_size != dStat.st_size) {
            sizeMismatch++;
            ok = NO;
            if (detailCount++ < 12) [detail appendFormat:@"size:%@(%lld!=%lld) ", sub, (long long)sStat.st_size, (long long)dStat.st_size];
        }
    }
    for (NSString *sub in dstItems) {
        if (![srcSet containsObject:sub]) {
            extra++;
            ok = NO;
            if (detailCount++ < 12) [detail appendFormat:@"extra:%@ ", sub];
        }
    }
    [detail appendFormat:@"missing=%lu extra=%lu typeMismatch=%lu sizeMismatch=%lu linkMismatch=%lu", (unsigned long)missing, (unsigned long)extra, (unsigned long)typeMismatch, (unsigned long)sizeMismatch, (unsigned long)linkMismatch];
    self.diagDeepCopyDetail = [detail copy];

    NSString *rec = [opLog beginPhase:OperationPhaseFileCopy operation:@"deepCopyVerification" target:dst input:@"lstat topology + symlink + regular-file size" transactionID:txnID];
    NSTimeInterval elapsed = -[started timeIntervalSinceNow];
    [opLog endPhase:rec exitCode:ok ? 0 : 1 rawOutput:detail rawError:ok ? @"" : @"Copied bundle does not match source" verification:detail verified:ok duration:elapsed context:@{ @"wallClockSeconds": @(elapsed), @"sourceItems": @(srcItems.count), @"destinationItems": @(dstItems.count) }];
    self.diagDeepCopyTotal = srcItems.count;
    self.diagDeepCopyMissing = missing + extra;
    self.diagDeepCopySizeMismatch = sizeMismatch + typeMismatch + linkMismatch;
    return ok;
}

- (BOOL)verifySignature:(NSString *)path opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 NSLog(@"[IPAInstallerPro] verifySignature: path=%@ ldid=%@", path, self.ldidPath);
 NSString *output = [self runCmdOutput:self.ldidPath args:@[@"-h", path]];
 BOOL hasSig = (output && output.length > 0);
 NSString *rec = [opLog beginPhase:OperationPhaseSign operation:@"ldid -h code signature check" target:path input:@"" transactionID:txnID];
 [opLog endPhase:rec exitCode:hasSig ? 0 : 1 rawOutput:output ?: @"" rawError:hasSig ? @"" : @"No signature detected"
 verification:hasSig ? @"Signature present" : @"No signature" verified:hasSig duration:0];
 NSLog(@"[IPAInstallerPro] verifySignature result: hasSig=%d output=%@", hasSig, output);
 return hasSig;
}

#pragma mark - Rollback

- (BOOL)backupExistingApp:(NSString *)destApp to:(NSString *)backupPath opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 NSFileManager *fm = [NSFileManager defaultManager];
 if (![fm fileExistsAtPath:destApp]) {
     // A stale backup must never be restored into a new installation.
     if ([fm fileExistsAtPath:backupPath]) {
         BOOL removedStale = [self hasRootHelper] ? [self runRoot:self.rmPath args:@[@"-rf", backupPath] opLog:opLog recordID:nil] : [fm removeItemAtPath:backupPath error:nil];
         if (!removedStale || [fm fileExistsAtPath:backupPath]) return NO;
     }
     return YES;
 }

 NSString *rec = [opLog beginPhase:OperationPhaseFileCopy operation:@"backupExisting" target:destApp input:backupPath transactionID:txnID];

 // Remove old backup if exists
 if ([fm fileExistsAtPath:backupPath]) {
 [fm removeItemAtPath:backupPath error:nil];
 }

  // FIX(v3.0.20): Use helper --copy-tree for backup (same mechanism that succeeded in staging).
  // cp -Rf fails silently on rootless jailbreaks; --copy-tree has already proven reliable.
  BOOL backedUp = NO;
  if ([self hasRootHelper]) {
      backedUp = [self runCmd:self.helperPath args:@[@"--copy-tree", destApp, backupPath] opLog:opLog recordID:rec];
      if (backedUp) {
          [self runRoot:self.rmPath args:@[@"-rf", destApp] opLog:opLog recordID:nil];
          // FIX(v3.0.19): Strip quarantine and harmful xattrs after backup copy
          NSString *xattrPathB = [[ExecutableValidator sharedValidator] findExecutableNamed:@"xattr"];
          if (xattrPathB) {
              [self runRoot:xattrPathB args:@[@"-cr", backupPath] opLog:nil recordID:nil];
          }
      }
  } else {
      int rv = copyfile([destApp UTF8String], [backupPath UTF8String], NULL, COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC);
      backedUp = (rv == 0);
      if (!backedUp) {
          NSError *err;
          [fm copyItemAtPath:destApp toPath:backupPath error:&err];
          backedUp = (err == nil);
      }
      if (backedUp) {
          [fm removeItemAtPath:destApp error:nil];
      }
      if (backedUp && rec && opLog) {
          [opLog endPhase:rec exitCode:0 rawOutput:@"" rawError:@""
          verification:@"NSFileManager backup success" verified:YES duration:0];
      }
  }
 if (!backedUp) {
 [opLog endPhase:rec exitCode:1 rawOutput:@"" rawError:@"Backup failed"
 verification:@"Could not backup existing app" verified:NO duration:0];
 }
 return backedUp;
}

- (void)restoreBackup:(NSString *)backupPath to:(NSString *)destApp opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 NSFileManager *fm = [NSFileManager defaultManager];
 if (![fm fileExistsAtPath:backupPath]) {
     // There was no pre-existing installation. Never leave a partial bundle
     // behind, otherwise the next cp -R may merge into it.
     if ([fm fileExistsAtPath:destApp]) {
         if ([self hasRootHelper]) [self runRoot:self.rmPath args:@[@"-rf", destApp] opLog:opLog recordID:nil];
         else [fm removeItemAtPath:destApp error:nil];
     }
     return;
 }

 NSString *rec = [opLog beginPhase:OperationPhaseFileCopy operation:@"restoreBackup" target:backupPath input:destApp transactionID:txnID];

 // Remove failed installation
 if ([fm fileExistsAtPath:destApp]) {
 if ([self hasRootHelper]) [self runRoot:self.rmPath args:@[@"-rf", destApp] opLog:opLog recordID:nil];
 else [fm removeItemAtPath:destApp error:nil];
 }

  // FIX(v3.0.19): Use cp -R + rm -rf instead of mv for restore.
  // In rootless jailbreaks, mv may fail with EXDEV (cross-device link).
  BOOL restored = NO;
  if ([self hasRootHelper]) {
      restored = [self runRoot:self.cpPath args:@[@"-Rf", backupPath, destApp] opLog:opLog recordID:rec];
      if (restored) {
          [self runRoot:self.rmPath args:@[@"-rf", backupPath] opLog:opLog recordID:nil];
      // FIX(v3.0.19): Strip quarantine and harmful xattrs after restore copy
      NSString *xattrPathR = [[ExecutableValidator sharedValidator] findExecutableNamed:@"xattr"];
      if (xattrPathR) {
          [self runRoot:xattrPathR args:@[@"-cr", destApp] opLog:nil recordID:nil];
      }
      }
  } else {
      int rv = copyfile([backupPath UTF8String], [destApp UTF8String], NULL, COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC);
      restored = (rv == 0);
      if (!restored) {
          NSError *err;
          [fm copyItemAtPath:backupPath toPath:destApp error:&err];
          restored = (err == nil);
      }
      if (restored) {
          [fm removeItemAtPath:backupPath error:nil];
      }
      if (restored && rec && opLog) {
          [opLog endPhase:rec exitCode:0 rawOutput:@"" rawError:@""
          verification:@"NSFileManager restore success" verified:YES duration:0];
      }
  }
 if (!restored) {
 [opLog endPhase:rec exitCode:1 rawOutput:@"" rawError:@"Restore failed"
 verification:@"Could not restore backup" verified:NO duration:0];
 }
}

- (void)cleanupBackup:(NSString *)backupPath opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 NSFileManager *fm = [NSFileManager defaultManager];
 if (![fm fileExistsAtPath:backupPath]) return;

 NSString *rec = [opLog beginPhase:OperationPhaseCleanup operation:@"cleanupBackup" target:backupPath input:@"" transactionID:txnID];
 if ([self hasRootHelper]) {
 [self runRoot:self.rmPath args:@[@"-rf", backupPath] opLog:opLog recordID:rec];
 } else {
 [fm removeItemAtPath:backupPath error:nil];
 if (rec && opLog) {
 [opLog endPhase:rec exitCode:0 rawOutput:@"" rawError:@""
 verification:@"Backup cleaned up" verified:YES duration:0];
 }
 }
}

#pragma mark - Diagnostics

- (void)diagLog:(NSString *)fmt, ... {
    if (!self.diagnosticsLog) self.diagnosticsLog = [NSMutableString string];
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    [self.diagnosticsLog appendString:msg];
    [self.diagnosticsLog appendString:@"\n"];
}

- (void)emitDiagnosticsReport:(OperationLog *)opLog txnID:(NSString *)txnID bundleID:(NSString *)bundleID {
    NSMutableString *r = [NSMutableString string];
    [r appendString:@"\n═══════════════════════════════════════════════════════════════\n"];
    [r appendFormat:@"📊 DIAGNOSTICS REPORT | Bundle: %@\n", bundleID ?: @"N/A"];
    [r appendString:@"═══════════════════════════════════════════════════════════════\n\n"];

    // ─── [ENTITLEMENTS] ───
    [r appendString:@"[ENTITLEMENTS]\n"];
    if (self.diagnosticsLog && self.diagnosticsLog.length > 0) {
        [r appendString:self.diagnosticsLog];
    } else {
        [r appendString:@"  ⚠️ No per-binary entitlement diagnostics captured\n"];
    }

    // ─── [POST-SIGN VERIFICATION] ───
    if (self.lastInstalledAppPath) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *exeName = [[self.lastInstalledAppPath lastPathComponent] stringByDeletingPathExtension];
        NSString *mainExe = [self.lastInstalledAppPath stringByAppendingPathComponent:exeName];

        [r appendString:@"\n[POST-SIGN VERIFICATION]\n"];

        // Main executable entitlements
        if ([fm fileExistsAtPath:mainExe]) {
            NSString *mainEnts = [self runCmdOutput:self.ldidPath args:@[@"-e", mainExe]];
            if (mainEnts && mainEnts.length > 10) {
                BOOL hasGTA = [mainEnts containsString:@"get-task-allow"];
                BOOL hasPlatform = [mainEnts containsString:@"platform-application"];
                BOOL hasNoSandbox = [mainEnts containsString:@"com.apple.private.security.no-sandbox"];
                BOOL hasSkipLib = [mainEnts containsString:@"com.apple.private.skip-library-validation"];
                BOOL hasAppID = [mainEnts containsString:@"application-identifier"];
                BOOL hasTeamID = [mainEnts containsString:@"team-identifier"] || [mainEnts containsString:@"com.apple.developer.team-identifier"];
                [r appendFormat:@"  Main exe (%@):\n", exeName];
                [r appendFormat:@"    get-task-allow:        %@\n", hasGTA ? @"✅" : @"❌"];
                [r appendFormat:@"    platform-application:  %@\n", hasPlatform ? @"✅" : @"❌"];
                [r appendFormat:@"    no-sandbox:            %@\n", hasNoSandbox ? @"✅" : @"❌"];
                [r appendFormat:@"    skip-library-validation: %@\n", hasSkipLib ? @"✅" : @"❌"];
                [r appendFormat:@"    application-identifier: %@\n", hasAppID ? @"✅" : @"❌"];
                [r appendFormat:@"    team-identifier:       %@\n", hasTeamID ? @"✅" : @"❌"];
            } else {
                [r appendFormat:@"  ❌ Main exe (%@): NO entitlements found after signing!\n", exeName];
            }
        }

        // Check all dylibs/frameworks signing
        NSString *fwDir = [self.lastInstalledAppPath stringByAppendingPathComponent:@"Frameworks"];
        if ([fm fileExistsAtPath:fwDir]) {
            NSUInteger fwCount = 0, fwSigned = 0;
            for (NSString *item in [fm contentsOfDirectoryAtPath:fwDir error:nil]) {
                if ([item hasSuffix:@".framework"]) {
                    fwCount++;
                    NSString *fwExe = [fwDir stringByAppendingPathComponent:[item stringByAppendingPathComponent:[item stringByDeletingPathExtension]]];
                    if ([fm fileExistsAtPath:fwExe]) {
                        NSString *fwSig = [self runCmdOutput:self.ldidPath args:@[@"-h", fwExe]];
                        if (fwSig && fwSig.length > 0) fwSigned++;
                    }
                }
            }
            [r appendFormat:@"  Frameworks:              %lu/%lu signed\n", (unsigned long)fwSigned, (unsigned long)fwCount];
        }
    }

    // ─── [BUNDLE STRUCTURE — CRITICAL CHECKS] ───
    if (self.lastInstalledAppPath) {
        NSFileManager *fm = [NSFileManager defaultManager];
        [r appendString:@"\n[BUNDLE STRUCTURE — CRITICAL CHECKS]\n"];

        // Check Info.plist keys
        NSString *infoPath = [self.lastInstalledAppPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];

        NSString *mainStoryboard = info[@"UIMainStoryboardFile"];
        NSString *launchStoryboard = info[@"UILaunchStoryboardName"];
        NSString *mainNib = info[@"NSMainNibFile"];

        [r appendFormat:@"  Info.plist UIMainStoryboardFile:   %@\n", mainStoryboard ?: @"(not set)"];
        [r appendFormat:@"  Info.plist UILaunchStoryboardName: %@\n", launchStoryboard ?: @"(not set)"];
        [r appendFormat:@"  Info.plist NSMainNibFile:          %@\n", mainNib ?: @"(not set)"];

        // Check if referenced storyboards exist
        if (mainStoryboard) {
            NSString *sbPath = [self.lastInstalledAppPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.storyboardc", mainStoryboard]];
            BOOL exists = [fm fileExistsAtPath:sbPath];
            [r appendFormat:@"  Main.storyboardc exists:           %@\n", exists ? @"✅ YES" : @"❌ NO — referenced resource missing"];
        }
        if (launchStoryboard) {
            NSString *sbPath = [self.lastInstalledAppPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.storyboardc", launchStoryboard]];
            BOOL exists = [fm fileExistsAtPath:sbPath];
            [r appendFormat:@"  LaunchScreen.storyboardc exists:   %@\n", exists ? @"✅ YES" : @"❌ NO"];
        }

        // Check for .dylib files
        NSString *fwDir = [self.lastInstalledAppPath stringByAppendingPathComponent:@"Frameworks"];
        NSUInteger dylibCount = 0;
        if ([fm fileExistsAtPath:fwDir]) {
            for (NSString *item in [fm contentsOfDirectoryAtPath:fwDir error:nil]) {
                if ([item hasSuffix:@".dylib"]) dylibCount++;
            }
        }
        [r appendFormat:@"  .dylib files in Frameworks:       %lu\n", (unsigned long)dylibCount];

        // List ALL files in bundle root (to see if anything is missing)
        [r appendString:@"\n  Bundle root contents:\n"];
        NSArray *rootItems = [fm contentsOfDirectoryAtPath:self.lastInstalledAppPath error:nil];
        for (NSString *item in rootItems) {
            [r appendFormat:@"    %@\n", item];
        }
    }

    // ─── [SIGNING COVERAGE] ───
    [r appendString:@"\n[SIGNING COVERAGE]\n"];
    [r appendFormat:@"  Frameworks signed: %lu\n", (unsigned long)self.diagFrameworksSigned];
    [r appendFormat:@"  Dylibs signed:     %lu\n", (unsigned long)self.diagDylibsSigned];
    [r appendFormat:@"  AppEx signed:      %lu\n", (unsigned long)self.diagAppexSigned];

    // ─── [DEEP COPY] ───
    [r appendString:@"\n[DEEP COPY]\n"];
    [r appendFormat:@"  Total files:       %lu\n", (unsigned long)self.diagDeepCopyTotal];
    [r appendFormat:@"  Missing:           %lu %@\n", (unsigned long)self.diagDeepCopyMissing, self.diagDeepCopyMissing > 0 ? @"❌" : @"✅"];
    [r appendFormat:@"  Size mismatch:     %lu %@\n", (unsigned long)self.diagDeepCopySizeMismatch, self.diagDeepCopySizeMismatch > 0 ? @"⚠️" : @"✅"];

    // ─── [CRITICAL CHECKS] ───
    [r appendString:@"\n[CRITICAL CHECKS]\n"];
    if ([self.diagnosticsLog containsString:@"hasAppID=NO"]) [r appendString:@"  ❌ application-identifier MISSING — app may crash on launch\n"];
    if ([self.diagnosticsLog containsString:@"hasTeamID=NO"]) [r appendString:@"  ❌ team-identifier MISSING — app may crash on launch\n"];
    if ([self.diagnosticsLog containsString:@"hasGTA=NO"]) [r appendString:@"  ❌ get-task-allow MISSING — app may crash on launch\n"];
    if ([self.diagnosticsLog containsString:@"hasPlatform=NO"]) [r appendString:@"  ❌ platform-application MISSING — app may crash on jailbreak\n"];
    if ([self.diagnosticsLog containsString:@"hasNoSandbox=NO"]) [r appendString:@"  ⚠️ no-sandbox MISSING — some apps may be restricted\n"];
    if ([self.diagnosticsLog containsString:@"source:fallback"]) [r appendString:@"  ⚠️ Entitlements used FALLBACK — original entitlements not found\n"];
    if (self.diagDeepCopyMissing > 0) [r appendString:@"  ❌ Deep copy MISSING files — installation incomplete\n"];
    if (self.diagFrameworksSigned == 0 && self.diagDylibsSigned == 0 && self.diagAppexSigned == 0) [r appendString:@"  ⚠️ NO binaries signed — signing may have failed silently\n"];

    // ─── [CRASH REPORTS] ───
    [r appendString:@"\n[CRASH REPORTS]\n"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *crashDir = @"/var/mobile/Library/Logs/CrashReporter";
    BOOL foundCrash = NO;
    if ([fm fileExistsAtPath:crashDir]) {
        NSArray *items = [fm contentsOfDirectoryAtPath:crashDir error:nil];
        NSDate *now = [NSDate date];
        for (NSString *item in items) {
            if (([item hasSuffix:@".ips"] || [item hasSuffix:@".crash"]) && 
                ([item containsString:bundleID] || [item containsString:@"Runner"])) {
                NSString *fullPath = [crashDir stringByAppendingPathComponent:item];
                NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
                NSDate *modDate = attrs[NSFileModificationDate];
                if (modDate && [now timeIntervalSinceDate:modDate] < 300) {
                    [r appendFormat:@"  🚨 Recent crash found: %@\n", item];
                    foundCrash = YES;
                }
            }
        }
    }
    if (!foundCrash) [r appendString:@"  No recent crash reports found ✅\n"];

    [r appendString:@"═══════════════════════════════════════════════════════════════\n"];
    NSString *rec = [opLog beginPhase:OperationPhaseComplete operation:@"diagnostics-report" target:bundleID ?: @"" input:@"" transactionID:txnID];
    [opLog endPhase:rec exitCode:0 rawOutput:r rawError:@"" verification:@"diagnostics complete" verified:YES duration:0];
}

- (void)installIPA:(NSString *)ipaPath transactionID:(NSString *)txnID operationLog:(OperationLog *)opLog completion:(void (^)(InstallationResult *))completion {
 NSFileManager *fm = [NSFileManager defaultManager];
 if (!txnID.length) txnID = [opLog beginTransactionForIPA:ipaPath];
 InstallationTransactionCoordinator *transaction = [InstallationTransactionCoordinator sharedCoordinator];
 BOOL transactionStarted = [transaction beginTransaction:txnID];
 if (!transactionStarted) {
     if (completion) completion([InstallationResult failureResult:@"Installation transaction already exists" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
     return;
 }
 [transaction transitionTransaction:txnID toState:InstallationTransactionStateAnalyzing reason:@"IPA validation and structural analysis started"];
 BOOL hasH = [self hasRootHelper];
 NSString *bundleID = nil;
  // Reset diagnostics counters for this installation
  self.diagnosticsLog = [NSMutableString string];
  self.diagFrameworksSigned = 0;
  self.diagDylibsSigned = 0;
  self.diagAppexSigned = 0;
  self.diagDeepCopyTotal = 0;
  self.diagDeepCopyMissing = 0;
  self.diagDeepCopySizeMismatch = 0;
 // If txnID is provided by the engine, use it directly without creating a duplicate OperationLog entry

 // Remove only old, uniquely named staging directories left by an interrupted transaction.
 // This is intentionally age-bounded so an active installation is never touched.
 NSString *resolvedApplicationsPath = [[RootlessManager sharedManager] resolvePath:@"/Applications"];
 [self cleanupStaleStageDirectoriesAtRoot:resolvedApplicationsPath hasHelper:hasH opLog:opLog txnID:txnID];

 // PHASE 0: SAFETY CHECKS
 if (![self validateIPAPathSafety:ipaPath opLog:opLog txnID:txnID]) {
 NSLog(@"[IPAInstallerPro] EARLY FAIL: IPA safety check failed for: %@", ipaPath);
  // Emit diagnostics report even on failure
  [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultFailed];
 if (completion) completion([InstallationResult failureResult:@"IPA safety check failed" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
 return;
 }

 // PHASE 1: IPA_OPEN
 NSLog(@"[IPAInstallerPro] === PHASE 1: IPA_OPEN ===");
 NSString *rec1 = [opLog beginPhase:OperationPhaseIPAOpen operation:@"fileExistsAtPath" target:ipaPath input:ipaPath transactionID:txnID];
 BOOL ipaExists = [fm fileExistsAtPath:ipaPath];
 BOOL ipaReadable = [fm isReadableFileAtPath:ipaPath];
 NSDictionary *ipaAttrs = ipaExists ? [fm attributesOfItemAtPath:ipaPath error:nil] : nil;
 [opLog endPhase:rec1 exitCode:ipaExists ? 0 : ENOENT rawOutput:@"" rawError:ipaExists ? @"" : @"IPA not found"
 verification:[NSString stringWithFormat:@"exists=%@ readable=%@ size=%lld", ipaExists ? @"YES" : @"NO", ipaReadable ? @"YES" : @"NO", ipaAttrs ? ipaAttrs.fileSize : 0]
 verified:(ipaExists && ipaReadable) duration:0];

 if (!ipaExists || !ipaReadable) {
 NSLog(@"[IPAInstallerPro] EARLY FAIL: IPA not found or unreadable: %@ exists=%d readable=%d", ipaPath, ipaExists, ipaReadable);
  // Emit diagnostics report even on failure
  [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultFailed];
 if (completion) completion([InstallationResult failureResult:@"IPA not found or unreadable" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
 return;
 }

 // PHASE 2: IPA_EXTRACT
 NSLog(@"[IPAInstallerPro] === PHASE 2: IPA_EXTRACT ===");
 NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
 NSString *rec2 = [opLog beginPhase:OperationPhaseIPAExtract operation:@"createDirectoryAtPath" target:tmp input:@"" transactionID:txnID];
 BOOL tmpCreated = [fm createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil];
 [opLog endPhase:rec2 exitCode:tmpCreated ? 0 : 1 rawOutput:@"" rawError:tmpCreated ? @"" : @"Failed to create temp dir"
 verification:[NSString stringWithFormat:@"created=%@", tmpCreated ? @"YES" : @"NO"] verified:tmpCreated duration:0];

 if (!tmpCreated) {
 NSLog(@"[IPAInstallerPro] EARLY FAIL: Temp directory creation failed");
  // Emit diagnostics report even on failure
  [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultFailed];
 if (completion) completion([InstallationResult failureResult:@"Temp directory creation failed" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
 return;
 }

 NSString *rec3 = [opLog beginPhase:OperationPhaseIPAExtract operation:@"unzip-primary" target:ipaPath input:[NSString stringWithFormat:@"tmp=%@ payload=%@", tmp, [tmp stringByAppendingPathComponent:@"Payload"]] transactionID:txnID];
 BOOL unzipOk = NO;
 NSString *payload = [tmp stringByAppendingPathComponent:@"Payload"];

 // Each extractor attempt gets its own record. A single reused record can
 // overwrite evidence and leave the UI showing only BEGIN for the first call.
 unzipOk = [self runCmdCapture:self.unzipPath args:@[@"-o", ipaPath, @"-d", tmp] opLog:opLog recordID:rec3 operation:@"unzip-primary"];

 if (!unzipOk || ![fm fileExistsAtPath:payload]) {
     NSLog(@"[IPAInstallerPro] Primary unzip failed or Payload is absent; trying system unzip");
     NSString *sysUnzip = @"/usr/bin/unzip";
     if ([fm fileExistsAtPath:sysUnzip] && ![sysUnzip isEqualToString:self.unzipPath]) {
         NSString *fallbackRec = [opLog beginPhase:OperationPhaseIPAExtract operation:@"unzip-system-fallback" target:ipaPath input:[NSString stringWithFormat:@"tmp=%@ payloadExists=%@", tmp, [fm fileExistsAtPath:payload] ? @"YES" : @"NO"] transactionID:txnID];
         unzipOk = [self runCmdCapture:sysUnzip args:@[@"-o", ipaPath, @"-d", tmp] opLog:opLog recordID:fallbackRec operation:@"unzip-system-fallback"];
     }
 }

 if (!unzipOk || ![fm fileExistsAtPath:payload]) {
     NSLog(@"[IPAInstallerPro] unzip failed or Payload is absent; trying tar extraction");
     NSString *tarPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/tar"];
     if ([fm fileExistsAtPath:tarPath]) {
         NSString *tarRec = [opLog beginPhase:OperationPhaseIPAExtract operation:@"tar-fallback" target:ipaPath input:[NSString stringWithFormat:@"tmp=%@ payloadExists=%@", tmp, [fm fileExistsAtPath:payload] ? @"YES" : @"NO"] transactionID:txnID];
         unzipOk = [self runCmdCapture:tarPath args:@[@"-xf", ipaPath, @"-C", tmp] opLog:opLog recordID:tarRec operation:@"tar-fallback"];
     }
 }

 BOOL payloadExists = [fm fileExistsAtPath:payload];
 NSUInteger payloadEntryCount = payloadExists ? [fm subpathsAtPath:payload].count : 0;
 NSString *extractSummary = [NSString stringWithFormat:@"tmp=%@ payload=%@ payloadExists=%@ payloadEntries=%lu unzipOK=%@", tmp, payload, payloadExists ? @"YES" : @"NO", (unsigned long)payloadEntryCount, unzipOk ? @"YES" : @"NO"];
 NSString *extractAudit = [opLog beginPhase:OperationPhaseIPAExtract operation:@"extraction-postcondition" target:tmp input:extractSummary transactionID:txnID];
 [opLog endPhase:extractAudit exitCode:(payloadExists && unzipOk) ? 0 : 1 rawOutput:extractSummary rawError:(payloadExists && unzipOk) ? @"" : @"Extractor returned failure or Payload is absent" verification:@"Payload directory and extracted entries must exist" verified:(payloadExists && unzipOk) duration:0 context:@{@"tempDirectory": tmp ?: @"", @"payload": payload ?: @"", @"payloadExists": @(payloadExists), @"payloadEntryCount": @(payloadEntryCount), @"extractorReportedSuccess": @(unzipOk)}];
 if (!unzipOk || !payloadExists) {
 NSLog(@"[IPAInstallerPro] EARLY FAIL: Extraction postcondition failed (extractorOK=%d payloadExists=%d)", unzipOk, payloadExists);
 [fm removeItemAtPath:tmp error:nil];
  // Each extractor attempt already has its own completed record with PID,
  // stdout, stderr, exit status and timeout state. Do not overwrite it here.
  [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultFailed];
 if (completion) completion([InstallationResult failureResult:[NSString stringWithFormat:@"IPA extraction failed — extractorOK:%@ payload:%@", unzipOk ? @"YES" : @"NO", payloadExists ? @"YES" : @"NO"] provider:[self providerName] transaction:txnID error:nil evidence:@{ @"extractSummary": extractSummary ?: @"", @"payloadEntryCount": @(payloadEntryCount) }]);
 return;
 }

 // PHASE 3: APP_IDENTIFY + SECURITY CHECK
// PHASE 3: APP_IDENTIFY + SECURITY CHECK
 NSString *rec4 = [opLog beginPhase:OperationPhaseAppIdentify operation:@"find .app in Payload" target:payload input:@"" transactionID:txnID];
 NSArray *items = [fm contentsOfDirectoryAtPath:payload error:nil];
 NSString *appFolder = nil;
 for (NSString *i in items) { if ([i hasSuffix:@".app"]) { appFolder = i; break; } }
 BOOL appFound = (appFolder != nil);
 [opLog endPhase:rec4 exitCode:appFound ? 0 : 1 rawOutput:@"" rawError:appFound ? @"" : @"No .app folder found"
 verification:[NSString stringWithFormat:@"found=%@ name=%@", appFound ? @"YES" : @"NO", appFolder ?: @"N/A"] verified:YES duration:0];

 if (!appFound) {
 NSLog(@"[IPAInstallerPro] EARLY FAIL: No .app found in Payload");
 [fm removeItemAtPath:tmp error:nil];
  // Emit diagnostics report even on failure
  [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultFailed];
 if (completion) completion([InstallationResult failureResult:@"No .app found" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
 return;
 }

 NSString *srcApp = [payload stringByAppendingPathComponent:appFolder];

 // Security: Check for dangerous symlinks
 if (![self checkForSymlinksInExtractedPath:srcApp opLog:opLog txnID:txnID]) {
 NSLog(@"[IPAInstallerPro] EARLY FAIL: Dangerous symlinks detected");
 [fm removeItemAtPath:tmp error:nil];
  // Emit diagnostics report even on failure
  [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultFailed];
 if (completion) completion([InstallationResult failureResult:@"Dangerous symlinks detected in IPA" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
 return;
 }

 NSString *infoPath = [srcApp stringByAppendingPathComponent:@"Info.plist"];
 NSString *rec5 = [opLog beginPhase:OperationPhaseAppIdentify operation:@"read Info.plist" target:infoPath input:@"" transactionID:txnID];
 NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
 BOOL infoRead = (info != nil);
 bundleID = info[@"CFBundleIdentifier"];
 NSString *exeName = info[@"CFBundleExecutable"];
 BOOL infoHasKeys = infoRead && (bundleID.length > 0) && (exeName.length > 0);
 [opLog endPhase:rec5 exitCode:infoRead ? 0 : 1 rawOutput:@"" rawError:infoRead ? @"" : @"Info.plist unreadable"
 verification:[NSString stringWithFormat:@"read=%@ bundleID=%@ exe=%@", infoRead ? @"YES" : @"NO", bundleID ?: @"N/A", exeName ?: @"N/A"]
 verified:YES duration:0];

 if (!infoHasKeys) {
 NSLog(@"[IPAInstallerPro] EARLY FAIL: Invalid Info.plist — bundleID=%@ exe=%@", bundleID, exeName);
 [fm removeItemAtPath:tmp error:nil];
  // Emit diagnostics report even on failure
  [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultFailed];
 if (completion) completion([InstallationResult failureResult:@"Invalid Info.plist" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
 return;
 }

// PHASE 3.5: SMART SIGNING PLAN
 [transaction transitionTransaction:txnID toState:InstallationTransactionStatePreparing reason:@"structural preparation and signing plan"];
 NSString *recPlan = [opLog beginPhase:OperationPhaseAppIdentify operation:@"smart-signing-plan" target:srcApp input:@"analyzing structure" transactionID:txnID];
  __block SigningPlan *signingPlan = nil;
 self.activeSigningPlan = nil;
 BOOL planGenerated = NO;
 @try {
 IPAStructuralResult *structResult = [[IPAStructuralAnalyzer sharedAnalyzer] analyzeExtractedPayloadAtPath:payload sourceIPAPath:ipaPath];
 SpiderInstallationGraph *spiderGraph = [SpiderInstallationGraph graphFromStructuralResult:structResult];
 NSString *spiderRecord = [opLog beginPhase:OperationPhaseAppIdentify operation:@"spider-bundle-graph" target:srcApp input:@"role-aware structural graph" transactionID:txnID];
 NSString *spiderSummary = [spiderGraph summary];
 NSString *spiderErrors = [spiderGraph.fatalFindings componentsJoinedByString:@" | "];
  // FIX(v3.0.19): Spider warnings must NEVER block installation.
  // In v3.0.7 there was no Spider graph — ldid + uicache handled everything.
  // The spider is now a WARNING-ONLY diagnostic tool. Legacy signer is the fallback.
  if (!spiderGraph.coherent) {
      NSLog(@"[Spider] Structural warnings detected: %@", spiderErrors);
      NSLog(@"[Spider] Continuing with legacy signer fallback...");
      [opLog endPhase:spiderRecord exitCode:0 rawOutput:spiderSummary rawError:spiderErrors ?: @"" verification:@"continuing with legacy signer despite structural warnings" verified:YES duration:0 context:spiderGraph.evidence];
  } else {
      [opLog endPhase:spiderRecord exitCode:0 rawOutput:spiderSummary rawError:@"" verification:@"host/child bundle graph coherent" verified:YES duration:0 context:spiderGraph.evidence];
  }
 BOOL parseComplete = YES;
 for (IPAStructuralExecutable *executable in structResult.executables) {
     if (executable.parseStatus == IPAStructuralParseFailed) {
         parseComplete = NO;
         NSLog(@"[SmartSign] Refusing authoritative plan because Mach-O parse failed: %@ (%@)", executable.path, executable.parseError ?: @"unknown");
     }
 }
 if (structResult.success && structResult.executables.count > 0 && parseComplete) {
 signingPlan = [[SigningPlanner sharedPlanner] createPlanForStructuralResult:structResult];
  planGenerated = signingPlan.isViable;
  if (planGenerated) self.activeSigningPlan = signingPlan;
 if (planGenerated) {
 NSLog(@"[SmartSign] Plan: %ld targets, %ld preserve, %ld generic, %ld minimal",
 (long)signingPlan.totalTargets,
 (long)signingPlan.preserveCount,
 (long)signingPlan.genericCount,
 (long)signingPlan.minimalCount);
 }
 } else if (!parseComplete) {
     NSLog(@"[SmartSign] Structural plan unavailable due to parse failure; legacy signer will run with strict post-sign verification");
 }
 } @catch (NSException *e) {

 NSLog(@"[SmartSign] Plan failed: %@", e.reason);
 }
 [opLog endPhase:recPlan exitCode:0 rawOutput:planGenerated ? @"Smart signing plan generated" : @"Smart signing plan unavailable, using legacy fallback" rawError:@"" verification:@"smart signing plan" verified:YES duration:0];

 // Repair clearly non-portable build-host LC_RPATH values while the extracted
 // source is still writable. The repaired bytes are then copied and signed;
 // this avoids requiring the app process to write into the root-owned target.
 NSArray *changedRPaths = nil;
 NSString *rpathError = nil;
 NSString *rpathRecord = [opLog beginPhase:OperationPhaseVerify operation:@"mach-o rpath portability" target:srcApp input:@"repair build-host LC_RPATH" transactionID:txnID];
 BOOL rpathOk = [[MachORPathRepair sharedRepair] repairAppAtPath:srcApp changedPaths:&changedRPaths error:&rpathError];
 [opLog endPhase:rpathRecord exitCode:rpathOk ? 0 : 1 rawOutput:[NSString stringWithFormat:@"changed=%lu", (unsigned long)changedRPaths.count] rawError:rpathError ?: @"" verification:rpathOk ? @"portable LC_RPATH state" : @"unsafe LC_RPATH could not be repaired" verified:rpathOk duration:0];
 if (!rpathOk) {
     NSLog(@"[IPAInstallerPro] Mach-O rpath repair failed — refusing installation: %@", rpathError);
     [fm removeItemAtPath:tmp error:nil];
     [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
     [opLog endTransaction:txnID finalResult:OperationResultFailed];
     if (completion) completion([InstallationResult failureResult:@"Non-portable Mach-O rpath could not be repaired" provider:[self providerName] transaction:txnID error:nil evidence:@{ @"reason": rpathError ?: @"unknown" }]);
     return;
 }

 // PHASE 4: FILE_COPY (with backup/rollback)
 [transaction transitionTransaction:txnID toState:InstallationTransactionStateInstalling reason:@"verified source ready for promotion"];
 NSLog(@"[IPAInstallerPro] === PHASE 4: FILE_COPY ===");
 NSString *logicalDest = [@"/Applications" stringByAppendingPathComponent:appFolder];
 NSString *rec7 = [opLog beginPhase:OperationPhaseFileCopy operation:@"resolvePath" target:logicalDest input:logicalDest transactionID:txnID];
 NSString *destApp = [[RootlessManager sharedManager] resolvePath:logicalDest];
 BOOL destResolved = (destApp != nil && destApp.length > 0);
 [opLog endPhase:rec7 exitCode:destResolved ? 0 : 1 rawOutput:destApp ?: @"" rawError:destResolved ? @"" : @"RootlessManager failed"
 verification:[NSString stringWithFormat:@"resolved=%@ path=%@", destResolved ? @"YES" : @"NO", destApp ?: @"N/A"] verified:destResolved duration:0];

 if (!destResolved) {
 NSLog(@"[IPAInstallerPro] EARLY FAIL: Could not resolve destination for: %@", logicalDest);
 [fm removeItemAtPath:tmp error:nil];
  // Emit diagnostics report even on failure
  [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultFailed];
 if (completion) completion([InstallationResult failureResult:@"Could not resolve destination" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
 return;
 }
 self.lastInstalledAppPath = destApp;

 // Ensure Applications directory exists
 NSString *appsDir = [destApp stringByDeletingLastPathComponent];
 if (![fm fileExistsAtPath:appsDir]) {
 NSString *recMkdir = [opLog beginPhase:OperationPhaseFileCopy operation:@"mkdir -p Applications" target:appsDir input:@"" transactionID:txnID];
 BOOL dirCreated = [self runRoot:self.mkdirPath args:@[@"-p", appsDir] opLog:opLog recordID:recMkdir];
 if (!dirCreated) {
 NSError *mkErr;
 [fm createDirectoryAtPath:appsDir withIntermediateDirectories:YES attributes:nil error:&mkErr];
 }
 }

 // BACKUP existing app (rollback support)
 NSString *backupPath = [destApp stringByAppendingString:@".backup"];
 if (![self backupExistingApp:destApp to:backupPath opLog:opLog txnID:txnID]) {
 NSLog(@"[IPAInstallerPro] EARLY FAIL: Backup failed for: %@", destApp);
 [fm removeItemAtPath:tmp error:nil];
  // Emit diagnostics report even on failure
  [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultFailed];
 if (completion) completion([InstallationResult failureResult:@"Failed to backup existing app" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
 return;
 }

 // Copy only into a fresh destination. cp -R merges when the target exists,
 // which can create extra stale files after a previous failed attempt.
 if ([fm fileExistsAtPath:destApp]) {
     NSString *clearRec = [opLog beginPhase:OperationPhaseFileCopy operation:@"clear destination before copy" target:destApp input:@"rm -rf" transactionID:txnID];
     BOOL cleared = hasH ? [self runRoot:self.rmPath args:@[@"-rf", destApp] opLog:opLog recordID:clearRec] : [fm removeItemAtPath:destApp error:nil];
     struct stat clearStat = {0};
     BOOL destStillExists = (lstat(destApp.fileSystemRepresentation, &clearStat) == 0);
     if (!cleared || destStillExists) {
         [opLog endPhase:clearRec exitCode:1 rawOutput:@"" rawError:@"Destination remained before copy" verification:@"destination must be absent" verified:NO duration:0];
         [fm removeItemAtPath:tmp error:nil];
         [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
         [opLog endTransaction:txnID finalResult:OperationResultFailed];
         if (completion) completion([InstallationResult failureResult:@"Destination was not empty before copy — rollback executed" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
         return;
     }
 }
  NSString *stagingRoot = [[RootlessManager sharedManager] resolvePath:@"/var/tmp/IPAInstallerPro-Staging"];
  NSString *stageRootRec = [opLog beginPhase:OperationPhaseFileCopy operation:@"prepare private staging root" target:stagingRoot input:@"mkdir -p outside Applications" transactionID:txnID];
  BOOL stagingRootReady = [fm fileExistsAtPath:stagingRoot];
  if (!stagingRootReady) {
      stagingRootReady = hasH ? [self runRoot:self.mkdirPath args:@[@"-p", stagingRoot] opLog:opLog recordID:stageRootRec] : [fm createDirectoryAtPath:stagingRoot withIntermediateDirectories:YES attributes:nil error:nil];
      if (!hasH && stageRootRec) {
          [opLog endPhase:stageRootRec exitCode:stagingRootReady ? 0 : 1 rawOutput:@"" rawError:stagingRootReady ? @"" : @"Unable to create private staging root" verification:@"staging root exists outside Applications" verified:stagingRootReady duration:0];
      }
  } else if (stageRootRec) {
      [opLog endPhase:stageRootRec exitCode:0 rawOutput:@"already exists" rawError:@"" verification:@"staging root exists outside Applications" verified:YES duration:0];
  }
  if (!stagingRootReady) {
      [fm removeItemAtPath:tmp error:nil];
      [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
      [opLog endTransaction:txnID finalResult:OperationResultFailed];
      if (completion) completion([InstallationResult failureResult:@"Private staging root could not be created" provider:[self providerName] transaction:txnID error:nil evidence:@{ @"stagingRoot": stagingRoot ?: @"" }]);
      return;
  }
  [self cleanupStaleStageDirectoriesAtRoot:stagingRoot hasHelper:hasH opLog:opLog txnID:txnID];
  NSString *stagedDest = [stagingRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.ipa-stage-%@", appFolder, [NSUUID UUID].UUIDString]];
  BOOL copied = NO;
 if (hasH && self.helperPath.length > 0) {
     NSString *rec9 = [opLog beginPhase:OperationPhaseFileCopy operation:@"copy app bundle to isolated staging" target:[NSString stringWithFormat:@"%@ -> %@", srcApp, stagedDest] input:@"root helper --copy-tree (copyfile)" transactionID:txnID];
     // The root helper owns the copyfile call. This avoids platform-specific
     // cp recursion behavior that can silently omit framework resources.
     copied = [self runCmd:self.helperPath args:@[@"--copy-tree", srcApp, stagedDest] opLog:opLog recordID:rec9];
 }
 if (!copied) {
     NSString *fallbackRec = [opLog beginPhase:OperationPhaseFileCopy operation:@"copyfile fallback into isolated staging" target:[NSString stringWithFormat:@"%@ -> %@", srcApp, stagedDest] input:@"COPYFILE_ALL|COPYFILE_RECURSIVE|COPYFILE_NOFOLLOW_SRC" transactionID:txnID];
     int rv = copyfile([srcApp UTF8String], [stagedDest UTF8String], NULL, COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC);
     copied = (rv == 0);
     // FIX(iOS16+): Strip quarantine and other harmful xattrs that break rootless
     if (copied) {
         NSString *xattrPath = [[ExecutableValidator sharedValidator] findExecutableNamed:@"xattr"];
         if (xattrPath) {
             [self runRoot:xattrPath args:@[@"-cr", stagedDest] opLog:nil recordID:nil];
         }
     }
     NSString *fallbackError = copied ? @"" : [NSString stringWithFormat:@"copyfile failed: rv=%d errno=%d", rv, errno];
     if (!copied) {
         NSError *e = nil;
         [fm copyItemAtPath:srcApp toPath:stagedDest error:&e];
         copied = (e == nil);
         if (!copied && e) fallbackError = e.localizedDescription ?: fallbackError;
     }
     [opLog endPhase:fallbackRec exitCode:copied ? 0 : 1 rawOutput:@"" rawError:copied ? @"" : fallbackError verification:copied ? @"copyfile/NSFileManager fallback success into isolated staging" : @"all copy fallbacks failed" verified:copied duration:0 context:@{@"source": srcApp ?: @"", @"destination": stagedDest ?: @"", @"copyfileReturn": @(rv)}];
 }
 if (!copied) {
 [fm removeItemAtPath:stagedDest error:nil];
 [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
 [fm removeItemAtPath:tmp error:nil];
  // Emit diagnostics report even on failure
  [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultFailed];
 if (completion) completion([InstallationResult failureResult:@"Copy failed — all methods exhausted, rollback attempted" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
 return;
 }
 // Verify before promotion. The destination remains untouched until the
 // complete source tree passes topology, symlink and size verification.
 BOOL deepOk = [self verifyDeepCopy:srcApp dst:stagedDest opLog:opLog txnID:txnID];
 if (!deepOk) {
 NSLog(@"[IPAInstallerPro] Deep copy mismatch in isolated staging — rolling back installation");
 [fm removeItemAtPath:stagedDest error:nil];
 [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
 [fm removeItemAtPath:tmp error:nil];
 [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultFailed];
 if (completion) completion([InstallationResult failureResult:[NSString stringWithFormat:@"Deep copy verification failed — missing/extra:%lu, mismatches:%lu — %@ — rollback executed", (unsigned long)self.diagDeepCopyMissing, (unsigned long)self.diagDeepCopySizeMismatch, self.diagDeepCopyDetail ?: @"no manifest details"] provider:[self providerName] transaction:txnID error:nil evidence:@{ @"sourceItems": @(self.diagDeepCopyTotal), @"missingOrExtra": @(self.diagDeepCopyMissing), @"mismatches": @(self.diagDeepCopySizeMismatch), @"manifest": self.diagDeepCopyDetail ?: @"" }]);
 return;
 }
  // FIX(v3.0.19): Use cp -R + rm -rf instead of mv for promotion.
  // In rootless jailbreaks, /var/tmp and /Applications (or /var/jb/Applications)
  // may reside on different filesystems, causing mv to fail with EXDEV (cross-device link).
  // cp -R works across filesystems and is the reliable method.
  // FIX(v3.0.20): Use helper --copy-tree for promotion (same mechanism that succeeded in staging).
  // cp -Rf fails silently on rootless jailbreaks; --copy-tree has already proven reliable.
  NSString *promoteRec = [opLog beginPhase:OperationPhaseFileCopy operation:@"promote verified staging bundle" target:[NSString stringWithFormat:@"%@ -> %@", stagedDest, destApp] input:@"helper --copy-tree" transactionID:txnID];
  BOOL promoted = [self runCmd:self.helperPath args:@[@"--copy-tree", stagedDest, destApp] opLog:opLog recordID:promoteRec];
  if (promoted) {
      [self runRoot:self.rmPath args:@[@"-rf", stagedDest] opLog:opLog recordID:nil];
      // FIX(v3.0.19): Strip quarantine and harmful xattrs after promotion
      NSString *xattrPath2 = [[ExecutableValidator sharedValidator] findExecutableNamed:@"xattr"];
      if (xattrPath2) {
          [self runRoot:xattrPath2 args:@[@"-cr", destApp] opLog:nil recordID:nil];
      }
  }
  // FIX: fileExistsAtPath may return NO for root-owned files even when cp succeeded.
  // Use lstat() which checks filesystem reality regardless of current user permissions.
  struct stat promoteStat = {0};
  BOOL destActuallyExists = (lstat(destApp.fileSystemRepresentation, &promoteStat) == 0);
  if (!promoted || !destActuallyExists) {
      [fm removeItemAtPath:stagedDest error:nil];
      [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
      [fm removeItemAtPath:tmp error:nil];
      [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
      [opLog endTransaction:txnID finalResult:OperationResultFailed];
      if (completion) completion([InstallationResult failureResult:@"Verified bundle promotion failed — rollback executed" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
      return;
  }

 // PHASE 5: PERMISSION
 NSLog(@"[IPAInstallerPro] === PHASE 5: PERMISSION ===");
 NSString *rec10a = [opLog beginPhase:OperationPhasePermission operation:@"preserve executable permissions" target:destApp input:@"u+rwX,go+rX" transactionID:txnID];
 // Do not make every resource executable. Preserve existing executable bits,
 // make directories traversable, and keep regular resources non-executable.
 [self runRoot:self.chmodPath args:@[@"-R", @"u+rwX,go+rX", destApp] opLog:opLog recordID:rec10a];

 // FIX(iOS16+): Ensure the main executable has +x (extracted IPAs often lose it)
 NSString *installedInfoPath = [destApp stringByAppendingPathComponent:@"Info.plist"];
 NSDictionary *installedInfo = [NSDictionary dictionaryWithContentsOfFile:installedInfoPath];
 NSString *execName = [installedInfo[@"CFBundleExecutable"] isKindOfClass:[NSString class]] ? installedInfo[@"CFBundleExecutable"] : nil;
 if (execName.length > 0) {
     NSString *execPath = [destApp stringByAppendingPathComponent:execName];
     if ([[NSFileManager defaultManager] fileExistsAtPath:execPath]) {
         NSString *rec10a_exec = [opLog beginPhase:OperationPhasePermission operation:@"chmod +x main executable" target:execPath input:@"+x" transactionID:txnID];
         [self runRoot:self.chmodPath args:@[@"+x", execPath] opLog:opLog recordID:rec10a_exec];
     }
 }

 // FIX(rootless): Detect correct uid:gid from an existing app in /Applications
 // instead of hardcoding root:wheel (Palera1n uses 0:0 or 501:501 on some setups).
 NSString *ownerSpec = @"root:wheel";
 NSString *installedAppsDir = [destApp stringByDeletingLastPathComponent];
 NSArray *existingApps = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:installedAppsDir error:nil];
 for (NSString *existing in existingApps) {
     if ([existing hasSuffix:@".app"] && ![existing isEqualToString:[destApp lastPathComponent]]) {
         NSString *existingPath = [installedAppsDir stringByAppendingPathComponent:existing];
         struct stat st;
         if (stat([existingPath UTF8String], &st) == 0) {
             ownerSpec = [NSString stringWithFormat:@"%u:%u", st.st_uid, st.st_gid];
             break;
         }
     }
 }
 NSString *rec10b = [opLog beginPhase:OperationPhasePermission operation:@"chown -R" target:destApp input:ownerSpec transactionID:txnID];
 [self runRoot:self.chownPath args:@[@"-R", ownerSpec, destApp] opLog:opLog recordID:rec10b];

 // Embedded framework binaries are executable code even when an IPA archive
 // preserved them as 0644. Set the execute bit only on Mach-O files; never
 // make images, plists, nibs, or other resources executable.
 NSString *rec10d = [opLog beginPhase:OperationPhasePermission operation:@"ensure Mach-O executable bits" target:destApp input:@"u+x on Mach-O only" transactionID:txnID];
 BOOL machoModesOk = [self ensureExecutablePermissionsForMachOAtPath:destApp hasHelper:hasH opLog:opLog txnID:txnID];
 [opLog endPhase:rec10d exitCode:machoModesOk ? 0 : 1 rawOutput:@"Mach-O executable permissions checked" rawError:machoModesOk ? @"" : @"Unable to set executable bit on one or more Mach-O files" verification:@"all Mach-O files executable" verified:machoModesOk duration:0];
 if (!machoModesOk) {
     [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
     [fm removeItemAtPath:tmp error:nil];
     [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
     [opLog endTransaction:txnID finalResult:OperationResultFailed];
     if (completion) completion([InstallationResult failureResult:@"Mach-O executable permission repair failed — rollback executed" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
     return;
 }

 // STAT verification (experimental branch only; Golden baseline is untouched)
 NSString *destExe = [destApp stringByAppendingPathComponent:exeName];
 mode_t mode = 0; uid_t uid = 0; gid_t gid = 0;
 BOOL statOk = [self verifyStat:destExe mode:&mode uid:&uid gid:&gid];
 mode_t appMode = 0; uid_t appUID = 0; gid_t appGID = 0;
 BOOL appStatOk = [self verifyStat:destApp mode:&appMode uid:&appUID gid:&appGID];
 // Validate the actual runtime access available to the installer/app user rather than
 // assuming a fixed uid/gid or requiring owner-only mode bits. Group/world write remains
 // forbidden, and the executable must have the same owner/group as its containing bundle.
 BOOL executableAccess = statOk && (access([destExe UTF8String], R_OK | X_OK) == 0);
 BOOL bundleAccess = appStatOk && (access([destApp UTF8String], R_OK | X_OK) == 0);
 BOOL secureMode = statOk && ((mode & (S_IWGRP | S_IWOTH)) == 0);
 BOOL ownershipMatchesBundle = statOk && appStatOk && uid == appUID && gid == appGID;
 BOOL permissionVerified = statOk && appStatOk && executableAccess && bundleAccess && secureMode && ownershipMatchesBundle;
 NSString *statFailure = permissionVerified ? @"" : [NSString stringWithFormat:@"statOk=%@ appStatOk=%@ mode=%o uid=%d gid=%d appMode=%o appUid=%d appGid=%d executableAccess=%@ bundleAccess=%@ secureMode=%@ ownershipMatchesBundle=%@ errno=%d", statOk ? @"YES" : @"NO", appStatOk ? @"YES" : @"NO", mode, uid, gid, appMode, appUID, appGID, executableAccess ? @"YES" : @"NO", bundleAccess ? @"YES" : @"NO", secureMode ? @"YES" : @"NO", ownershipMatchesBundle ? @"YES" : @"NO", errno];
 NSString *rec10c = [opLog beginPhase:OperationPhasePermission operation:@"stat verification" target:destExe input:@"permission postcondition" transactionID:txnID];
 [opLog endPhase:rec10c exitCode:permissionVerified ? 0 : 1 rawOutput:permissionVerified ? @"stat/postcondition passed" : @"" rawError:statFailure
 verification:[NSString stringWithFormat:@"statOk=%@ mode=%o uid=%d gid=%d appStatOk=%@ appMode=%o appUid=%d appGid=%d executableAccess=%@ bundleAccess=%@ secureMode=%@ ownershipMatchesBundle=%@", statOk ? @"YES" : @"NO", mode, uid, gid, appStatOk ? @"YES" : @"NO", appMode, appUID, appGID, executableAccess ? @"YES" : @"NO", bundleAccess ? @"YES" : @"NO", secureMode ? @"YES" : @"NO", ownershipMatchesBundle ? @"YES" : @"NO"]
 verified:permissionVerified duration:0];

 if (!permissionVerified) {
 // ROLLBACK
 [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
 [fm removeItemAtPath:tmp error:nil];
  // Emit diagnostics report even on failure
  [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultFailed];
 if (completion) completion([InstallationResult failureResult:[NSString stringWithFormat:@"Permission postcondition failed: statOk=%@ mode=%o uid=%d gid=%d appUid=%d appGid=%d executableAccess=%@ bundleAccess=%@ secureMode=%@ ownershipMatchesBundle=%@", statOk ? @"YES" : @"NO", mode, uid, gid, appUID, appGID, executableAccess ? @"YES" : @"NO", bundleAccess ? @"YES" : @"NO", secureMode ? @"YES" : @"NO", ownershipMatchesBundle ? @"YES" : @"NO"]
 provider:[self providerName] transaction:txnID error:nil evidence:nil]);
 return;
 }

 // PHASE 6: AUTHORITATIVE SMART SIGNING
 [transaction transitionTransaction:txnID toState:InstallationTransactionStateSigning reason:@"installation promotion complete; signing installed targets"];
 NSLog(@"[IPAInstallerPro] === PHASE 6: SIGNING ===");
 NSString *rec11 = [opLog beginPhase:OperationPhaseSign operation:@"sign-execute" target:destApp input:@"authoritative per-target plan" transactionID:txnID];
 NSUInteger smartSignedCount = 0;
 BOOL authoritativeSigning = NO;
 if (planGenerated && signingPlan && signingPlan.targets.count > 0) {
     BOOL remapped = [self remapSigningPlan:signingPlan toInstalledAppPath:destApp];
     if (remapped) {
         smartSignedCount = [self executeSigningPlan:signingPlan atAppPath:destApp hasHelper:hasH opLog:opLog txnID:txnID];
         authoritativeSigning = (smartSignedCount == signingPlan.targets.count);
         NSLog(@"[IPAInstallerPro] Smart signing completed: %lu/%lu targets", (unsigned long)smartSignedCount, (unsigned long)signingPlan.targets.count);
     } else {
         NSLog(@"[IPAInstallerPro] Smart signing plan could not be mapped to installed bundle");
     }
 }

 // Only use the old broad signer when no complete structural plan is available.
 // Never run it after a complete plan: that would overwrite preserved/minimal
 // entitlement policy and reintroduce launch regressions.
  if (!authoritativeSigning) {
      NSLog(@"[IPAInstallerPro] Structural plan unavailable/incomplete; using legacy fallback");
      [self signAllAt:destApp hasHelper:hasH opLog:opLog txnID:txnID];
      [self signExe:destExe hasHelper:hasH opLog:opLog txnID:txnID];
  } else {
      // TrollStore performs a final recursive -s pass after assigning
      // per-bundle entitlements. This signs CodeResources/nested code while
      // leaving the planned container identity on the bundle executables.
      BOOL recursiveOK = [self signTarget:destApp withEntitlements:nil hasHelper:hasH opLog:opLog txnID:txnID];
      if (!recursiveOK) {
          NSLog(@"[IPAInstallerPro] Recursive bundle signing failed — rollback");
          [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
          [fm removeItemAtPath:tmp error:nil];
          [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
          [opLog endTransaction:txnID finalResult:OperationResultFailed];
          if (completion) completion([InstallationResult failureResult:@"Recursive bundle signing failed — rollback" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
          return;
      }
  }
  [opLog endPhase:rec11 exitCode:0 rawOutput:@"" rawError:@"" verification:authoritativeSigning ? @"authoritative plan + recursive signing applied" : @"legacy fallback applied" verified:YES duration:0];

 BOOL sigOk = [self verifySignature:destExe opLog:opLog txnID:txnID];
 if (!sigOk) {
     if (authoritativeSigning) {
         // A complete plan must never be replaced by the legacy signer after a
         // failed verification. That would make the install report success with
         // different entitlements than the plan that was analyzed.
         NSLog(@"[IPAInstallerPro] Planned signature verification failed — refusing legacy entitlement overwrite");
         [opLog endPhase:rec11 exitCode:1 rawOutput:@"" rawError:@"Planned signature verification failed" verification:@"authoritative signing" verified:NO duration:0];
         [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
         [fm removeItemAtPath:tmp error:nil];
         [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
         [opLog endTransaction:txnID finalResult:OperationResultFailed];
         if (completion) completion([InstallationResult failureResult:@"Planned signature verification failed — rollback" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
         return;
     }
     NSLog(@"[IPAInstallerPro] Legacy signature weak, retrying with explicit entitlements...");
     [self signExeWithExplicitEntitlements:destExe hasHelper:hasH opLog:opLog txnID:txnID];
     sigOk = [self verifySignature:destExe opLog:opLog txnID:txnID];
     if (!sigOk) {
         [opLog endPhase:rec11 exitCode:1 rawOutput:@"" rawError:@"Signing failed" verification:@"signing" verified:NO duration:0];
         [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
         [fm removeItemAtPath:tmp error:nil];
         [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
         [opLog endTransaction:txnID finalResult:OperationResultFailed];
         if (completion) completion([InstallationResult failureResult:@"Signature failed — rollback" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
         return;
     }
 }
  // PHASE 7: FRAMEWORK (legacy fallback only)
  NSString *dbgBefore = [opLog beginPhase:OperationPhaseSign operation:@"[DEBUG] BEFORE fixFrameworks" target:@"" input:@"" transactionID:txnID];
  [opLog endPhase:dbgBefore exitCode:0 rawOutput:@"[DEBUG] BEFORE fixFrameworks" rawError:@"" verification:@"debug" verified:YES duration:0];

  if (!authoritativeSigning) {
      [self fixFrameworks:destApp hasHelper:hasH opLog:opLog txnID:txnID];
  } else {
      NSLog(@"[IPAInstallerPro] Skipping legacy fixFrameworks pass; authoritative plan already signed every target");
  }

  NSString *dbgAfter = [opLog beginPhase:OperationPhaseSign operation:@"[DEBUG] AFTER fixFrameworks" target:@"" input:@"" transactionID:txnID];
  [opLog endPhase:dbgAfter exitCode:0 rawOutput:@"[DEBUG] AFTER fixFrameworks" rawError:@"" verification:@"debug" verified:YES duration:0];

  NSString *dbgEnter = [opLog beginPhase:OperationPhaseSign operation:@"[DEBUG] ENTERING POST-SIGN VERIFICATION" target:@"" input:@"" transactionID:txnID];
  [opLog endPhase:dbgEnter exitCode:0 rawOutput:@"[DEBUG] ENTERING POST-SIGN VERIFICATION" rawError:@"" verification:@"debug" verified:YES duration:0];

  BOOL postSignOK = [self postSignVerification:destApp opLog:opLog txnID:txnID];
  if (!postSignOK) {
      NSLog(@"[IPAInstallerPro] Post-sign Mach-O verification failed — rollback");
      [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
      [fm removeItemAtPath:tmp error:nil];
      [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
      [opLog endTransaction:txnID finalResult:OperationResultFailed];
      if (completion) completion([InstallationResult failureResult:@"Post-sign Mach-O verification failed — rollback" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
      return;
  }
  if (authoritativeSigning && ![self verifyPlannedEntitlements:signingPlan opLog:opLog txnID:txnID]) {
      NSLog(@"[IPAInstallerPro] Final entitlement invariants failed — rollback");
      [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
      [fm removeItemAtPath:tmp error:nil];
      [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
      [opLog endTransaction:txnID finalResult:OperationResultFailed];
      if (completion) completion([InstallationResult failureResult:@"Final entitlement verification failed — rollback" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
      return;
  }

  NSString *dbgExit = [opLog beginPhase:OperationPhaseSign operation:@"[DEBUG] EXITING POST-SIGN VERIFICATION" target:@"" input:@"" transactionID:txnID];
  [opLog endPhase:dbgExit exitCode:0 rawOutput:@"[DEBUG] EXITING POST-SIGN VERIFICATION" rawError:@"" verification:@"debug" verified:YES duration:0];

  // INSTALLATION VERIFICATION MUST PRECEDE ANY REGISTRATION.
  [transaction transitionTransaction:txnID toState:InstallationTransactionStateVerifyingInstall reason:@"promotion, permissions, signatures and topology completed"];
  NSLog(@"[IPAInstallerPro] === VERIFY INSTALLATION BEFORE REGISTRATION ===");
  NSString *rec15 = [opLog beginPhase:OperationPhaseVerify operation:@"verify installation before registration" target:destApp input:bundleID transactionID:txnID];
  BOOL installVerified = [self verifyInstallation:destApp bundleID:bundleID exeName:exeName opLog:opLog txnID:txnID];
  [opLog endPhase:rec15 exitCode:installVerified ? 0 : 1 rawOutput:@"" rawError:installVerified ? @"" : @"Installation verification failed before registration"
  verification:[NSString stringWithFormat:@"bundleID=%@ exe=%@ registered_not_required=YES", bundleID, exeName] verified:installVerified duration:0];
  if (!installVerified) {
      [transaction beginRollbackForTransaction:txnID reason:@"installation verification failed before registration"];
      [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
      [fm removeItemAtPath:tmp error:nil];
      [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
      [transaction markFailedForTransaction:txnID reason:@"installation verification failed before registration"];
      [opLog endTransaction:txnID finalResult:OperationResultFailed];
      if (completion) completion([InstallationResult failureResult:@"Installation verification failed before registration — rollback executed" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
      return;
  }

  // REGISTRATION is a guarded transaction transition. A concurrent failure
  // cannot pass this check because the coordinator serializes the state.
  if (![transaction beginRegistrationForTransaction:txnID reason:@"installation verification passed"] ) {
      [transaction markFailedForTransaction:txnID reason:@"registration rejected by transaction state"];
      [fm removeItemAtPath:tmp error:nil];
      [opLog endTransaction:txnID finalResult:OperationResultFailed];
      if (completion) completion([InstallationResult failureResult:@"Registration rejected: transaction was not in VERIFYING_INSTALL state" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
      return;
  }

  // PHASE 8: UICACHE / REGISTRATION
  NSLog(@"[IPAInstallerPro] === PHASE 8: UICACHE REGISTRATION ===");
  NSString *rec14a = [opLog beginPhase:OperationPhaseUICache operation:@"uicache -p logical" target:logicalDest input:@"" transactionID:txnID];
  BOOL logicalRegistrationOK = [self runRoot:self.uicachePath args:@[@"-p", logicalDest] opLog:opLog recordID:rec14a];
  NSString *rec14b = [opLog beginPhase:OperationPhaseUICache operation:@"uicache -p resolved" target:destApp input:@"" transactionID:txnID];
  BOOL resolvedRegistrationOK = [self runRoot:self.uicachePath args:@[@"-p", destApp] opLog:opLog recordID:rec14b];
  NSString *rec14c = [opLog beginPhase:OperationPhaseUICache operation:@"uicache -a" target:@"" input:@"" transactionID:txnID];
  BOOL allRegistrationOK = [self runRoot:self.uicachePath args:@[@"-a"] opLog:opLog recordID:rec14c];
  BOOL registrationCommandsOK = logicalRegistrationOK && resolvedRegistrationOK && allRegistrationOK;
  BOOL registrationVerified = registrationCommandsOK && [self verifyRegistrationForBundleID:bundleID path:destApp opLog:opLog txnID:txnID];
  if (!registrationVerified || ![transaction markRegistrationVerifiedForTransaction:txnID reason:@"uicache completed and Bundle ID is registered"]) {
      NSLog(@"[IPAInstallerPro] Registration verification failed — rolling back registration and bundle");
      [transaction beginRollbackForTransaction:txnID reason:@"registration command or verification failed"];
      [self rollbackRegistrationForBundleID:bundleID path:destApp opLog:opLog txnID:txnID];
      [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
      [fm removeItemAtPath:tmp error:nil];
      [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
      [transaction markFailedForTransaction:txnID reason:@"registration verification failed; rollback completed"];
      [opLog endTransaction:txnID finalResult:OperationResultFailed];
      if (completion) completion([InstallationResult failureResult:@"Registration verification failed — rollback executed" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
      return;
  }

  [transaction transitionTransaction:txnID toState:InstallationTransactionStateLaunching reason:@"registration verified"];
  NSString *launchReadinessReason = nil;
  BOOL launchReady = [self verifyLaunchReadinessAtPath:destApp bundleID:bundleID exeName:exeName opLog:opLog txnID:txnID reason:&launchReadinessReason];
  if (!launchReady) {
      NSLog(@"[IPAInstallerPro] Launch readiness gate failed — rollback registration: %@", launchReadinessReason ?: @"unknown reason");
      [transaction beginRollbackForTransaction:txnID reason:launchReadinessReason ?: @"launch validation failed"];
      [self rollbackRegistrationForBundleID:bundleID path:destApp opLog:opLog txnID:txnID];
      [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
      [fm removeItemAtPath:tmp error:nil];
      [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
      [transaction markFailedForTransaction:txnID reason:launchReadinessReason ?: @"launch validation failed; rollback completed"];
      [opLog endTransaction:txnID finalResult:OperationResultFailed];
      if (completion) completion([InstallationResult failureResult:launchReadinessReason ?: @"Launch readiness verification failed — rollback executed" provider:[self providerName] transaction:txnID error:nil evidence:@{ @"launchReadiness": @"failed", @"registrationRollback": @YES }]);
      return;
  }

   if (![transaction markSuccessForTransaction:txnID reason:@"registration verified and launch validation passed"]) {
      NSLog(@"[IPAInstallerPro] Final success rejected by transaction coordinator — rollback");
      [transaction beginRollbackForTransaction:txnID reason:@"success transition rejected"];
      [self rollbackRegistrationForBundleID:bundleID path:destApp opLog:opLog txnID:txnID];
      [self restoreBackup:backupPath to:destApp opLog:opLog txnID:txnID];
      [fm removeItemAtPath:tmp error:nil];
      [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
      [transaction markFailedForTransaction:txnID reason:@"success transition rejected; rollback completed"];
      [opLog endTransaction:txnID finalResult:OperationResultFailed];
      if (completion) completion([InstallationResult failureResult:@"Transaction success transition rejected — rollback executed" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
      return;
  }

 // SUCCESS — cleanup backup and temp
 [self cleanupBackup:backupPath opLog:opLog txnID:txnID];

 // PHASE 10: CLEANUP
 NSLog(@"[IPAInstallerPro] === PHASE 10: CLEANUP ===");
 NSString *rec16 = [opLog beginPhase:OperationPhaseCleanup operation:@"remove temp" target:tmp input:@"" transactionID:txnID];
 [fm removeItemAtPath:tmp error:nil];
 BOOL tmpRemoved = ![fm fileExistsAtPath:tmp];
 [opLog endPhase:rec16 exitCode:tmpRemoved ? 0 : 1 rawOutput:@"" rawError:tmpRemoved ? @"" : @"Temp still exists"
 verification:[NSString stringWithFormat:@"removed=%@", tmpRemoved ? @"YES" : @"NO"] verified:tmpRemoved duration:0];

 // SUCCESS
 NSLog(@"[IPAInstallerPro] === INSTALLATION SUCCESS: %@ ===", bundleID);
 // Record in the authoritative Spider-installed-apps registry (Jailbreak Hiding reads this).
 [SpiderInstalledAppsStore.sharedStore noteInstalledAppWithBundleID:bundleID path:destApp];
  // Emit diagnostics report before completing
  [self emitDiagnosticsReport:opLog txnID:txnID bundleID:bundleID];
 [opLog endTransaction:txnID finalResult:OperationResultSuccess];
 InstallationResult *result = [InstallationResult successResult:[NSString stringWithFormat:@"Installed %@", appFolder]
 provider:[self providerName] transaction:txnID evidence:@{@"bundleID": bundleID, @"path": destApp, @"exe": exeName}];
 result.bundleID = bundleID;
 if (completion) completion(result);
}

- (BOOL)verifyPlannedEntitlements:(SigningPlan *)plan opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
    if (!plan || plan.targets.count == 0) return NO;
    NSMutableString *summary = [NSMutableString string];
    BOOL allOK = YES;
    for (SigningTarget *target in plan.targets) {
        if (!target.needsSigning) continue;
        BOOL containerBearing = (target.targetType == SigningTargetTypeMainExecutable ||
                                 target.targetType == SigningTargetTypeAppExtension ||
                                 target.targetType == SigningTargetTypeXPCService);
        if (!containerBearing) continue;

        NSDictionary *planned = target.plannedEntitlements.rawEntitlements;
        NSDictionary *finalEnts = [self extractEntitlementsFromExecutable:target.filePath];
        BOOL ok = (finalEnts != nil && finalEnts.count > 0);
        NSMutableArray *failures = [NSMutableArray array];

        id plannedContainer = planned[@"com.apple.private.security.container-required"];
        if ([plannedContainer isKindOfClass:[NSString class]] && [(NSString *)plannedContainer length] > 0) {
            if (![finalEnts[@"com.apple.private.security.container-required"] isEqual:plannedContainer]) {
                ok = NO;
                [failures addObject:@"container-required mismatch/missing"];
            }
            if ([finalEnts[@"com.apple.private.security.no-container"] boolValue] ||
                [finalEnts[@"com.apple.private.security.no-sandbox"] boolValue]) {
                ok = NO;
                [failures addObject:@"conflicting no-container/no-sandbox present"];
            }
        }

        if (target.targetType == SigningTargetTypeMainExecutable && !target.hasOriginalSignature) {
            id expectedAppID = planned[@"application-identifier"];
            id expectedTeamID = planned[@"com.apple.developer.team-identifier"];
            if ([expectedAppID isKindOfClass:[NSString class]] &&
                ![finalEnts[@"application-identifier"] isEqual:expectedAppID]) {
                ok = NO;
                [failures addObject:@"application-identifier mismatch/missing"];
            }
            if ([expectedTeamID isKindOfClass:[NSString class]] &&
                ![finalEnts[@"com.apple.developer.team-identifier"] isEqual:expectedTeamID]) {
                ok = NO;
                [failures addObject:@"team-identifier mismatch/missing"];
            }
            if ([planned[@"keychain-access-groups"] isKindOfClass:[NSArray class]] &&
                ![finalEnts[@"keychain-access-groups"] isKindOfClass:[NSArray class]]) {
                ok = NO;
                [failures addObject:@"keychain-access-groups missing"];
            }
        }

        [summary appendFormat:@"%@=%@%@; ", target.targetName ?: target.filePath, ok ? @"OK" : @"FAIL", failures.count ? [NSString stringWithFormat:@" (%@)", [failures componentsJoinedByString:@", "]] : @""];
        NSLog(@"[IPAInstallerPro] Final entitlement check %@: %@%@", target.targetName, ok ? @"OK" : @"FAIL", failures.count ? [NSString stringWithFormat:@" %@", [failures componentsJoinedByString:@", "]] : @"");
        if (!ok) allOK = NO;
    }

    NSString *recordID = [opLog beginPhase:OperationPhaseVerify operation:@"final entitlement invariants" target:@"main/appex" input:@"ldid -e" transactionID:txnID];
    [opLog endPhase:recordID exitCode:allOK ? 0 : 1 rawOutput:summary rawError:allOK ? @"" : @"Planned entitlement values were not present in final signatures" verification:@"planned versus final entitlements" verified:allOK duration:0];
    return allOK;
}

- (NSArray<NSString *> *)machOPathsAtPath:(NSString *)rootPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:rootPath];
    NSString *relative = nil;
    while ((relative = [enumerator nextObject])) {
        NSString *fullPath = [rootPath stringByAppendingPathComponent:relative];
        NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeDirectory] || [attrs[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) continue;
        NSData *header = [NSData dataWithContentsOfFile:fullPath options:NSDataReadingMappedIfSafe error:nil];
        if (header.length < sizeof(uint32_t)) continue;
        uint32_t magic = 0;
        [header getBytes:&magic length:sizeof(magic)];
        BOOL macho = (magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64 ||
                      magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64);
        if (macho) [paths addObject:fullPath];
    }
    return [paths copy];
}

- (BOOL)verifyAllMachOSignedAtPath:(NSString *)appPath opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
    NSArray<NSString *> *paths = [self machOPathsAtPath:appPath];
    BOOL allOK = (paths.count > 0);
    NSUInteger passedCount = 0;
    NSMutableString *details = [NSMutableString stringWithFormat:@"Mach-O targets=%lu\n", (unsigned long)paths.count];
    for (NSString *path in paths) {
        NSString *relativePath = path;
        NSString *rootPrefix = [appPath stringByAppendingString:@"/"];
        if ([path hasPrefix:rootPrefix]) relativePath = [path substringFromIndex:rootPrefix.length];

        struct stat st = {0};
        BOOL lstatOK = (lstat(path.fileSystemRepresentation, &st) == 0);
        NSString *fileType = lstatOK ? (S_ISREG(st.st_mode) ? @"regular" : (S_ISLNK(st.st_mode) ? @"symlink" : (S_ISDIR(st.st_mode) ? @"directory" : @"other"))) : @"lstat-failed";
        NSString *mode = lstatOK ? [NSString stringWithFormat:@"%04o", st.st_mode & 07777] : @"-";
        NSString *uid = lstatOK ? [NSString stringWithFormat:@"%u", st.st_uid] : @"-";
        NSString *gid = lstatOK ? [NSString stringWithFormat:@"%u", st.st_gid] : @"-";
        NSString *size = lstatOK ? [NSString stringWithFormat:@"%lld", (long long)st.st_size] : @"-";

        MachOAnalysisResult *analysis = [[MachOAnalyzer sharedAnalyzer] analyzeFileAtPath:path];
        NSString *parseStatus = analysis ? [NSString stringWithFormat:@"%ld", (long)analysis.parseStatus] : @"none";
        NSString *machOType = analysis.machOTypeName ?: @"unknown";
        NSUInteger slices = analysis.slices.count;
        BOOL hasEmbeddedCodeSignature = analysis && analysis.hasCodeSignature && analysis.codeSignatureSize > 0;

        SigningTarget *plannedTarget = nil;
        for (SigningTarget *candidate in self.activeSigningPlan.targets) {
            if ([candidate.filePath isEqualToString:path]) { plannedTarget = candidate; break; }
        }
        NSString *planState = plannedTarget ? @"IN_SIGNING_PLAN" : @"OUTSIDE_SIGNING_PLAN";
        NSString *planType = plannedTarget.targetTypeName ?: (plannedTarget ? [plannedTarget typeName] : @"-");
        NSString *strategy = plannedTarget.strategyName ?: (plannedTarget ? [plannedTarget strategyNameString] : @"-");
        NSString *needsSigning = plannedTarget ? (plannedTarget.needsSigning ? @"YES" : @"NO") : @"-";

        NSString *metaRecord = [opLog beginPhase:OperationPhaseVerify operation:@"Mach-O forensic metadata" target:path input:relativePath transactionID:txnID];
        BOOL metadataOK = lstatOK && analysis && analysis.parseStatus == MachOParseSuccess && analysis.machOType != 0;
        NSString *metadataError = metadataOK ? @"" : [NSString stringWithFormat:@"metadata validation failed: lstat=%@ parseStatus=%@ machOType=%@", lstatOK ? @"OK" : @"FAIL", parseStatus, machOType];
        [opLog endPhase:metaRecord exitCode:metadataOK ? 0 : 1 rawOutput:@"" rawError:metadataError verification:[NSString stringWithFormat:@"relative=%@ type=%@ mode=%@ uid=%@ gid=%@ size=%@ macho=%@ slices=%lu codeSignature=%@ plan=%@ type=%@ strategy=%@ needsSigning=%@", relativePath, fileType, mode, uid, gid, size, machOType, (unsigned long)slices, hasEmbeddedCodeSignature ? @"YES" : @"NO", planState, planType, strategy, needsSigning] verified:metadataOK duration:0 context:@{@"path": path ?: @"", @"relativePath": relativePath ?: @"", @"fileType": fileType, @"mode": mode, @"uid": uid, @"gid": gid, @"size": size, @"parseStatus": parseStatus, @"machOType": machOType, @"slices": @(slices), @"hasCodeSignatureLoadCommand": @(hasEmbeddedCodeSignature), @"codeSignatureOffset": @(analysis.codeSignatureOffset), @"codeSignatureSize": @(analysis.codeSignatureSize), @"planState": planState, @"plannedType": planType, @"strategy": strategy, @"needsSigning": needsSigning}];

        NSString *recordID = [opLog beginPhase:OperationPhaseVerify operation:@"verify every Mach-O code signature" target:path input:@"ldid -h" transactionID:txnID];
        BOOL ldidOK = [self runCmdCapture:self.ldidPath args:@[@"-h", path] opLog:opLog recordID:recordID operation:@"Mach-O ldid -h verification"];
        BOOL targetOK = metadataOK && hasEmbeddedCodeSignature && ldidOK;
        if (targetOK) passedCount++;
        else allOK = NO;
        [details appendFormat:@"%@ | relative=%@ | full=%@ | type=%@ | mode=%@ uid=%@ gid=%@ size=%@ | parse=%@ macho=%@ slices=%lu | embeddedCodeSignature=%@ offset=%u size=%u | plan=%@ type=%@ strategy=%@ needsSigning=%@ | ldid-h=%@\n", targetOK ? @"PASS" : @"FAIL", relativePath, path, fileType, mode, uid, gid, size, parseStatus, machOType, (unsigned long)slices, hasEmbeddedCodeSignature ? @"YES" : @"NO", analysis.codeSignatureOffset, analysis.codeSignatureSize, planState, planType, strategy, needsSigning, ldidOK ? @"PASS" : @"FAIL"];
    }
    [details appendFormat:@"Summary: passed=%lu failed=%lu total=%lu\n", (unsigned long)passedCount, (unsigned long)(paths.count - passedCount), (unsigned long)paths.count];
    self.lastMachOVerificationDetail = details;
    NSLog(@"[IPAInstallerPro] Nested Mach-O signature coverage: %lu/%lu", (unsigned long)passedCount, (unsigned long)paths.count);
    return allOK;
}

- (BOOL)postSignVerification:(NSString *)destApp opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
    NSDate *started = [NSDate date];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *rec = [opLog beginPhase:OperationPhaseVerify operation:@"POST-SIGN VERIFICATION" target:destApp input:@"" transactionID:txnID];
    NSMutableString *r = [NSMutableString string];

    [r appendString:@"\n═══════════════════════════════════════════════════════════════\n"];
    [r appendString:@"POST-SIGN VERIFICATION\n"];
    [r appendString:@"═══════════════════════════════════════════════════════════════\n"];

    // ─── [INFO.PLST] ───
    [r appendString:@"\n[INFO.PLST]\n"];
    NSString *infoPath = [destApp stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    if (info) {
        [r appendFormat:@"  UIMainStoryboardFile:      %@\n", info[@"UIMainStoryboardFile"] ?: @"(not set)"];
        [r appendFormat:@"  UILaunchStoryboardName:    %@\n", info[@"UILaunchStoryboardName"] ?: @"(not set)"];
        [r appendFormat:@"  NSMainNibFile:             %@\n", info[@"NSMainNibFile"] ?: @"(not set)"];
        [r appendFormat:@"  NSMainNibFile~ipad:        %@\n", info[@"NSMainNibFile~ipad"] ?: @"(not set)"];
        [r appendFormat:@"  UIApplicationSceneManifest: %@\n", info[@"UIApplicationSceneManifest"] ? @"FOUND" : @"MISSING"];
        [r appendFormat:@"  UISceneConfigurations:     %@\n", info[@"UISceneConfigurations"] ? @"FOUND" : @"MISSING"];
        [r appendFormat:@"  CFBundleExecutable:        %@\n", info[@"CFBundleExecutable"] ?: @"MISSING"];
    } else {
        [r appendString:@"  ❌ Info.plist NOT READABLE\n"];
    }

    // ─── [FILES] ───
    [r appendString:@"\n[FILES]\n"];
    NSString *exeName = info[@"CFBundleExecutable"] ?: [[destApp lastPathComponent] stringByDeletingPathExtension];
    NSString *mainExe = [destApp stringByAppendingPathComponent:exeName];
    [r appendFormat:@"  Runner:                    %@\n", [fm fileExistsAtPath:mainExe] ? @"FOUND" : @"MISSING"];

    NSString *flutterAssets = [destApp stringByAppendingPathComponent:@"flutter_assets"];
    [r appendFormat:@"  flutter_assets:            %@\n", [fm fileExistsAtPath:flutterAssets] ? @"FOUND" : @"MISSING"];

    NSString *mainSb = [destApp stringByAppendingPathComponent:@"Main.storyboardc"];
    [r appendFormat:@"  Main.storyboardc:          %@\n", [fm fileExistsAtPath:mainSb] ? @"FOUND" : @"MISSING"];

    NSString *launchSb = [destApp stringByAppendingPathComponent:@"LaunchScreen.storyboardc"];
    [r appendFormat:@"  LaunchScreen.storyboardc:  %@\n", [fm fileExistsAtPath:launchSb] ? @"FOUND" : @"MISSING"];

    // ─── [SIGNATURE] ───
    [r appendString:@"\n[SIGNATURE]\n"];

    // Runner signature
    NSString *runnerSig = [self runCmdOutput:self.ldidPath args:@[@"-h", mainExe]];
    BOOL runnerSigned = (runnerSig && runnerSig.length > 0);
    [r appendFormat:@"  Runner signature:          %@\n", runnerSigned ? @"VALID" : @"INVALID"];
    if (runnerSigned) {
        NSString *runnerEnt = [self runCmdOutput:self.ldidPath args:@[@"-e", mainExe]];
        [r appendFormat:@"  Runner entitlements:       %@\n", (runnerEnt && runnerEnt.length > 10) ? @"FOUND" : @"MISSING"];
    }

    // Frameworks count
    NSString *fwDir = [destApp stringByAppendingPathComponent:@"Frameworks"];
    NSUInteger fwTotal = 0, fwSigned = 0, fwFailed = 0;
    if ([fm fileExistsAtPath:fwDir]) {
        for (NSString *item in [fm contentsOfDirectoryAtPath:fwDir error:nil]) {
            if ([item hasSuffix:@".framework"]) {
                fwTotal++;
                NSString *fwExe = [fwDir stringByAppendingPathComponent:[item stringByAppendingPathComponent:[item stringByDeletingPathExtension]]];
                if ([fm fileExistsAtPath:fwExe]) {
                    NSString *sig = [self runCmdOutput:self.ldidPath args:@[@"-h", fwExe]];
                    if (sig && sig.length > 0) {
                        fwSigned++;
                    } else {
                        fwFailed++;
                    }
                } else {
                    fwFailed++;
                }
            }
        }
    }
    [r appendFormat:@"  Frameworks total:          %lu\n", (unsigned long)fwTotal];
    [r appendFormat:@"  Frameworks signed:         %lu\n", (unsigned long)fwSigned];
    [r appendFormat:@"  Frameworks failed:         %lu\n", (unsigned long)fwFailed];

    [r appendString:@"\n[MACH-O TARGET RESULTS]\n"];
    BOOL nestedMachOOk = [self verifyAllMachOSignedAtPath:destApp opLog:opLog txnID:txnID];
    [r appendString:self.lastMachOVerificationDetail ?: @"Mach-O scan produced no targets\n"];
    [r appendFormat:@"  Runner signed:             %@\n", runnerSigned ? @"YES" : @"NO"];
    [r appendFormat:@"  Nested Mach-O verification: %@\n", nestedMachOOk ? @"PASS" : @"FAIL"];
    [r appendString:@"═══════════════════════════════════════════════════════════════\n"];

    BOOL allOk = runnerSigned && nestedMachOOk;
    NSTimeInterval elapsed = -[started timeIntervalSinceNow];
    [opLog endPhase:rec exitCode:allOk ? 0 : 1 rawOutput:r rawError:allOk ? @"" : @"Post-sign Mach-O verification failed; see MACH-O TARGET RESULTS for exact target" verification:@"post-sign verification complete" verified:allOk duration:elapsed context:@{@"runnerSigned": @(runnerSigned), @"nestedMachOTargets": @(nestedMachOOk), @"machOVerification": self.lastMachOVerificationDetail ?: @"", @"wallClockSeconds": @(elapsed)}];
    return allOk;
}


#pragma mark - Mach-O permission normalization

- (BOOL)ensureExecutablePermissionsForMachOAtPath:(NSString *)appPath hasHelper:(BOOL)hasH opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:appPath];
    NSString *relativePath = nil;
    BOOL allOK = YES;
    NSUInteger changed = 0;
    while ((relativePath = [enumerator nextObject])) {
        NSString *fullPath = [appPath stringByAppendingPathComponent:relativePath];
        NSDictionary *attributes = [fm attributesOfItemAtPath:fullPath error:nil];
        if ([attributes[NSFileType] isEqualToString:NSFileTypeDirectory] || [attributes[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) continue;
        NSData *header = [NSData dataWithContentsOfFile:fullPath options:NSDataReadingMappedIfSafe error:nil];
        if (header.length < 4) continue;
        uint32_t magic = 0;
        [header getBytes:&magic length:sizeof(magic)];
        BOOL isMachO = (magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64 || magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64);
        if (!isMachO) continue;
        NSNumber *permissions = attributes[NSFilePosixPermissions];
        mode_t mode = permissions ? permissions.unsignedShortValue : 0;
        BOOL alreadyAccessible = ((mode & (S_IRUSR | S_IXUSR)) == (S_IRUSR | S_IXUSR)) &&
            (access([fullPath UTF8String], R_OK | X_OK) == 0);
        if (alreadyAccessible) continue;

        // chmod uses additive symbolic bits: it preserves existing write bits but
        // makes every Mach-O readable and executable by the principals that must
        // load/launch it. Non-Mach-O resources are never touched here.
        BOOL commandOK = [self runRoot:self.chmodPath args:@[@"a+rx", fullPath] opLog:opLog recordID:nil];
        struct stat after = {0};
        BOOL statAfter = (lstat([fullPath UTF8String], &after) == 0);
        BOOL modeAfter = statAfter && ((after.st_mode & (S_IRUSR | S_IXUSR)) == (S_IRUSR | S_IXUSR));
        BOOL accessAfter = (access([fullPath UTF8String], R_OK | X_OK) == 0);
        BOOL ok = commandOK && statAfter && modeAfter && accessAfter;
        if (!ok) {
            allOK = NO;
            NSLog(@"[IPAInstallerPro] Failed to establish Mach-O executable access: %@ command=%@ stat=%@ mode=%o access=%@ errno=%d", fullPath, commandOK ? @"YES" : @"NO", statAfter ? @"YES" : @"NO", statAfter ? (after.st_mode & 0777) : 0, accessAfter ? @"YES" : @"NO", errno);
        } else {
            changed++;
        }
    }
    NSLog(@"[IPAInstallerPro] Mach-O executable permission normalization: %lu files changed (postcondition checked)", (unsigned long)changed);
    return allOK;
}

#pragma mark - Signing

- (void)signAllAt:(NSString *)path hasHelper:(BOOL)hasH opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 NSFileManager *fm = [NSFileManager defaultManager];
 NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:path];
 NSString *relativePath = nil;
 while ((relativePath = [enumerator nextObject])) {
 NSString *fullPath = [path stringByAppendingPathComponent:relativePath];
 NSString *item = [relativePath lastPathComponent];
 BOOL isDir = NO;
 [fm fileExistsAtPath:fullPath isDirectory:&isDir];

 if (isDir) {
 if ([item hasSuffix:@".app"]) {
 NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[fullPath stringByAppendingPathComponent:@"Info.plist"]];
 NSString *en = info[@"CFBundleExecutable"];
 if (en) [self signBin:[fullPath stringByAppendingPathComponent:en] hasHelper:hasH label:[@"app:" stringByAppendingString:en] opLog:opLog txnID:txnID];
 } else if ([item hasSuffix:@".framework"]) {
 NSString *fn = [item stringByDeletingPathExtension];
 [self signBin:[fullPath stringByAppendingPathComponent:fn] hasHelper:hasH label:[@"fw:" stringByAppendingString:fn] opLog:opLog txnID:txnID];
 // Skip descending into framework bundles to avoid double-signing
 [enumerator skipDescendants];
 } else if ([item hasSuffix:@".appex"] || [item hasSuffix:@".xpc"]) {
 [self signBundleExecutableAtPath:fullPath
 label:[NSString stringWithFormat:@"%@:%@", [item.pathExtension lowercaseString], item]
 hasHelper:hasH opLog:opLog txnID:txnID];
 [enumerator skipDescendants];
 }
 } else if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
 [self signBin:fullPath hasHelper:hasH label:[@"dylib:" stringByAppendingString:item] opLog:opLog txnID:txnID];
 }
 }
}

- (NSDictionary *)extractEntitlementsFromExecutable:(NSString *)path {
    NSDictionary *ents = [[SignatureAnalyzer sharedAnalyzer] extractEntitlementsAtPath:path];
    if (ents.count > 0) return ents;
    return nil;
}


- (NSDictionary *)extractEntitlementsFromAppBundle:(NSString *)appPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!appPath || ![fm fileExistsAtPath:appPath]) return nil;

    // 1. Try archived-expanded-entitlements.xcent (most common in IPAs)
    NSString *xcentPath = [appPath stringByAppendingPathComponent:@"archived-expanded-entitlements.xcent"];
    if ([fm fileExistsAtPath:xcentPath]) {
        NSDictionary *ents = [NSDictionary dictionaryWithContentsOfFile:xcentPath];
        if (ents && ents.count > 0) {
            NSLog(@"[IPAInstallerPro] Found entitlements in archived-expanded-entitlements.xcent (%lu keys)", (unsigned long)ents.count);
            return ents;
        }
    }

    // 2. Try embedded.mobileprovision (extract entitlements from provisioning profile)
    NSString *provPath = [appPath stringByAppendingPathComponent:@"embedded.mobileprovision"];
    if ([fm fileExistsAtPath:provPath]) {
        NSData *provData = [NSData dataWithContentsOfFile:provPath];
        if (provData && provData.length > 0) {
            NSString *provStr = [[NSString alloc] initWithData:provData encoding:NSASCIIStringEncoding];
            if (provStr && provStr.length > 0) {
                // Find Entitlements dict in the plist portion of .mobileprovision
                NSRange entRange = [provStr rangeOfString:@"<key>Entitlements</key>"];
                if (entRange.location != NSNotFound) {
                    NSString *sub = [provStr substringFromIndex:entRange.location];
                    if (sub && sub.length > 0) {
                        NSRange dictEnd = [sub rangeOfString:@"</dict>"];
                        if (dictEnd.location != NSNotFound) {
                            NSString *entXml = [sub substringToIndex:dictEnd.location + 7];
                            if (entXml && entXml.length > 0) {
                                NSString *wrapped = [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\">%@</plist>", entXml];
                                NSData *xmlData = [wrapped dataUsingEncoding:NSUTF8StringEncoding];
                                if (xmlData && xmlData.length > 0) {
                                    NSError *err = nil;
                                    id plist = [NSPropertyListSerialization propertyListWithData:xmlData options:NSPropertyListImmutable format:NULL error:&err];
                                    if ([plist isKindOfClass:[NSDictionary class]]) {
                                        NSLog(@"[IPAInstallerPro] Found entitlements in embedded.mobileprovision (%lu keys)", (unsigned long)[(NSDictionary *)plist count]);
                                        return (NSDictionary *)plist;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return nil;
}

- (BOOL)signBundleExecutableAtPath:(NSString *)bundlePath label:(NSString *)label hasHelper:(BOOL)hasH opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 NSFileManager *fm = [NSFileManager defaultManager];
 if (bundlePath.length == 0 || ![fm fileExistsAtPath:bundlePath]) return NO;
 NSString *infoPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
 NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
 NSString *executable = [info[@"CFBundleExecutable"] isKindOfClass:[NSString class]] ? info[@"CFBundleExecutable"] : nil;
 if (executable.length == 0) return NO;
 NSString *executablePath = [bundlePath stringByAppendingPathComponent:executable];
 if (![fm fileExistsAtPath:executablePath]) return NO;
 NSString *rec = [opLog beginPhase:OperationPhaseSign operation:[NSString stringWithFormat:@"sign extension (%@)", label ?: @"bundle"] target:executablePath input:@"preserve-entitlements" transactionID:txnID];
 NSDictionary *origEnts = [self extractEntitlementsFromExecutable:executablePath];
 BOOL signedOK = NO;
 NSMutableDictionary *merged = origEnts ? [origEnts mutableCopy] : [NSMutableDictionary dictionary];
 NSString *ep = nil;
 if (merged.count > 0) {
     ep = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"appex_%@.ent", [NSUUID UUID].UUIDString]];
     [merged writeToFile:ep atomically:YES];
     NSString *sf = [NSString stringWithFormat:@"-S%@", ep];
     signedOK = hasH ? [self runRoot:self.ldidPath args:@[sf, executablePath] opLog:opLog recordID:rec] : [self runCmd:self.ldidPath args:@[sf, executablePath] opLog:opLog recordID:rec];
     [fm removeItemAtPath:ep error:nil];
 } else {
     signedOK = hasH ? [self runRoot:self.ldidPath args:@[@"-s", executablePath] opLog:opLog recordID:rec] : [self runCmd:self.ldidPath args:@[@"-s", executablePath] opLog:opLog recordID:rec];
 }
 if (!signedOK) { signedOK = hasH ? [self runRoot:self.ldidPath args:@[@"-S", executablePath] opLog:opLog recordID:rec] : [self runCmd:self.ldidPath args:@[@"-S", executablePath] opLog:opLog recordID:rec]; }
 // DIAGNOSTICS: log extension signing result
 BOOL hasGTA = merged[@"get-task-allow"] != nil;
 BOOL hasPlatform = merged[@"platform-application"] != nil;
 BOOL hasNoSandbox = merged[@"com.apple.private.security.no-sandbox"] != nil;
 [self diagLog:@"[DIAG] signBundle | label:%@ | hasGTA:%@ | hasPlatform:%@ | hasNoSandbox:%@ | result:%@", label, hasGTA?@"YES":@"NO", hasPlatform?@"YES":@"NO", hasNoSandbox?@"YES":@"NO", signedOK?@"OK":@"FAIL"];
 if ([label containsString:@"appex"]) self.diagAppexSigned++;
 return signedOK;
}

- (void)signBin:(NSString *)path hasHelper:(BOOL)hasH label:(NSString *)label opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
  if ([label hasPrefix:@"fw:"]) self.diagFrameworksSigned++;
  else if ([label hasPrefix:@"dylib:"]) self.diagDylibsSigned++;
 NSString *rec = [opLog beginPhase:OperationPhaseSign operation:[NSString stringWithFormat:@"ldid -S (%@)", label] target:path input:@"" transactionID:txnID];
 if (hasH) [self runRoot:self.chmodPath args:@[@"755", path] opLog:opLog recordID:nil];
 else [self runCmd:self.chmodPath args:@[@"755", path] opLog:opLog recordID:nil];

 // Extract original entitlements (for frameworks/dylibs)
 NSDictionary *origEnts = nil;
 if ([label hasPrefix:@"fw:"] || [label hasPrefix:@"dylib:"]) {
 origEnts = [self extractEntitlementsFromExecutable:path];
 }

 // Preserve source entitlements for nested code; otherwise use ldid's clean signing path.
 NSMutableDictionary *merged = origEnts ? [origEnts mutableCopy] : [NSMutableDictionary dictionary];

 NSString *ep = nil;
 BOOL ok = NO;
 if (merged.count > 0) {
     ep = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"bin_%@.ent", [[NSUUID UUID] UUIDString]]];
     [merged writeToFile:ep atomically:YES];
     NSString *sf = [NSString stringWithFormat:@"-S%@", ep];
     ok = hasH ? [self runRoot:self.ldidPath args:@[sf, path] opLog:opLog recordID:rec]
               : [self runCmd:self.ldidPath args:@[sf, path] opLog:opLog recordID:rec];
     [[NSFileManager defaultManager] removeItemAtPath:ep error:nil];
 } else {
     ok = hasH ? [self runRoot:self.ldidPath args:@[@"-s", path] opLog:opLog recordID:rec]
               : [self runCmd:self.ldidPath args:@[@"-s", path] opLog:opLog recordID:rec];
 }

 if (!ok) {
 // Fallback: blank signing
 ok = hasH ? [self runRoot:self.ldidPath args:@[@"-S", path] opLog:opLog recordID:rec]
 : [self runCmd:self.ldidPath args:@[@"-S", path] opLog:opLog recordID:rec];
 }

 if (!ok) {
 // Last resort: minimal entitlements
 NSString *ep2 = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"min_%@.ent", [NSUUID UUID].UUIDString]];
 NSDictionary *minimal = [EntitlementSet minimalEntitlements];
 [minimal writeToFile:ep2 atomically:YES];
 NSString *sf2 = [NSString stringWithFormat:@"-S%@", ep2];
 ok = hasH ? [self runRoot:self.ldidPath args:@[sf2, path] opLog:opLog recordID:rec]
           : [self runCmd:self.ldidPath args:@[sf2, path] opLog:opLog recordID:rec];
 [[NSFileManager defaultManager] removeItemAtPath:ep2 error:nil];
 }

 // DIAGNOSTICS: log framework/dylib signing result
 BOOL hasGTA = merged[@"get-task-allow"] != nil;
 BOOL hasPlatform = merged[@"platform-application"] != nil;
 BOOL hasNoSandbox = merged[@"com.apple.private.security.no-sandbox"] != nil;
 [self diagLog:@"[DIAG] signBin | label:%@ | hasGTA:%@ | hasPlatform:%@ | hasNoSandbox:%@ | result:%@", label, hasGTA?@"YES":@"NO", hasPlatform?@"YES":@"NO", hasNoSandbox?@"YES":@"NO", ok?@"OK":@"FAIL"];
}

- (void)signExe:(NSString *)path hasHelper:(BOOL)hasH opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
 NSString *rec = [opLog beginPhase:OperationPhaseSign operation:@"signExe (main)" target:path input:@"" transactionID:txnID];
 NSDictionary *origEnts = [self extractEntitlementsFromExecutable:path];
 NSString *source = @"executable";
 if (!origEnts || origEnts.count == 0) { NSString *appBundle = [path stringByDeletingLastPathComponent]; origEnts = [self extractEntitlementsFromAppBundle:appBundle]; if (origEnts && origEnts.count > 0) source = @"app-bundle"; }
 NSMutableDictionary *merged = origEnts ? [origEnts mutableCopy] : [[EntitlementSet genericJailbreakEntitlements] mutableCopy];
 if (!origEnts || origEnts.count == 0) {
     NSDictionary *appInfo = [NSDictionary dictionaryWithContentsOfFile:[[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Info.plist"]];
     NSString *bundleID = [appInfo[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? appInfo[@"CFBundleIdentifier"] : nil;
     if (bundleID.length > 0) {
         NSString *appIdentifier = [NSString stringWithFormat:@"IPAINSTALLERPRO.%@", bundleID];
         merged[@"application-identifier"] = appIdentifier;
         merged[@"com.apple.developer.team-identifier"] = @"IPAINSTALLERPRO";
         merged[@"keychain-access-groups"] = @[appIdentifier, @"com.apple.token"];
         merged[@"com.apple.private.security.container-required"] = bundleID;
     }
 }
 BOOL hasAppID = merged[@"application-identifier"] != nil;
 BOOL hasTeamID = merged[@"com.apple.developer.team-identifier"] != nil || merged[@"team-identifier"] != nil;
 BOOL hasGTA = merged[@"get-task-allow"] != nil;
 BOOL hasPlatform = merged[@"platform-application"] != nil;
 BOOL hasNoSandbox = merged[@"com.apple.private.security.no-sandbox"] != nil;
 NSString *ep = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"merged_%@.ent", [[NSUUID UUID] UUIDString]]];
 [merged writeToFile:ep atomically:YES];
 NSString *sf = [NSString stringWithFormat:@"-S%@", ep];
 BOOL ok = hasH ? [self runRoot:self.ldidPath args:@[sf, path] opLog:opLog recordID:rec] : [self runCmd:self.ldidPath args:@[sf, path] opLog:opLog recordID:rec];
 [[NSFileManager defaultManager] removeItemAtPath:ep error:nil];
 if (ok) { NSLog(@"[IPAInstallerPro] Main exe signed with merged entitlements (%lu keys)", (unsigned long)merged.count); [self diagLog:@"[DIAG] signExe | entitlements:%lu | source:%@ | hasAppID:%@ | hasTeamID:%@ | hasGTA:%@ | hasPlatform:%@ | hasNoSandbox:%@ | result:OK", (unsigned long)merged.count, source, hasAppID?@"YES":@"NO", hasTeamID?@"YES":@"NO", hasGTA?@"YES":@"NO", hasPlatform?@"YES":@"NO", hasNoSandbox?@"YES":@"NO"]; return; }
 ok = hasH ? [self runRoot:self.ldidPath args:@[@"-S", path] opLog:opLog recordID:rec] : [self runCmd:self.ldidPath args:@[@"-S", path] opLog:opLog recordID:rec];
 if (ok) { NSLog(@"[IPAInstallerPro] Main exe signed blank (fallback)"); [self diagLog:@"[DIAG] signExe | entitlements:0 | source:blank | hasAppID:NO | hasTeamID:NO | hasGTA:NO | hasPlatform:NO | hasNoSandbox:NO | result:OK"]; return; }
 NSString *ep2 = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"min_%@.ent", [NSUUID UUID].UUIDString]]; NSDictionary *minimal = [EntitlementSet minimalEntitlements]; [minimal writeToFile:ep2 atomically:YES]; NSString *sf2 = [NSString stringWithFormat:@"-S%@", ep2]; BOOL fallbackOK = hasH ? [self runRoot:self.ldidPath args:@[sf2, path] opLog:opLog recordID:rec] : [self runCmd:self.ldidPath args:@[sf2, path] opLog:opLog recordID:rec]; [[NSFileManager defaultManager] removeItemAtPath:ep2 error:nil]; [self diagLog:@"[DIAG] signExe | entitlements:%lu | source:fallback | hasAppID:NO | hasTeamID:NO | hasGTA:%@ | hasPlatform:%@ | hasNoSandbox:NO | result:%@", (unsigned long)minimal.count, minimal[@"get-task-allow"] ? @"YES" : @"NO", minimal[@"platform-application"] ? @"YES" : @"NO", fallbackOK ? @"OK" : @"FAIL"];
}

- (void)signExeWithExplicitEntitlements:(NSString *)path hasHelper:(BOOL)hasH opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
 NSString *rec = [opLog beginPhase:OperationPhaseSign operation:@"signExe (explicit entitlements retry)" target:path input:@"" transactionID:txnID];
 NSString *ep = [NSTemporaryDirectory() stringByAppendingPathComponent:@"explicit.ent"];
 NSDictionary *ents = [EntitlementSet genericJailbreakEntitlements];
 [ents writeToFile:ep atomically:YES];
 NSString *sf = [NSString stringWithFormat:@"-S%@", ep];
 BOOL ok = hasH ? [self runRoot:self.ldidPath args:@[sf, path] opLog:opLog recordID:rec]
              : [self runCmd:self.ldidPath args:@[sf, path] opLog:opLog recordID:rec];
 [[NSFileManager defaultManager] removeItemAtPath:ep error:nil];
 if (!ok) NSLog(@"[IPAInstallerPro] Explicit entitlement signing failed for %@", path);
}

- (NSArray *)embeddedExecutablePathsAtPath:(NSString *)appPath {
 NSFileManager *fm = [NSFileManager defaultManager];
 NSMutableArray *paths = [NSMutableArray array];
 NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:appPath];
 NSString *relativePath = nil;
 while ((relativePath = [enumerator nextObject])) {
 NSString *lower = relativePath.lowercaseString;
 if (![lower hasSuffix:@".appex"] && ![lower hasSuffix:@".xpc"]) continue;
 NSString *bundlePath = [appPath stringByAppendingPathComponent:relativePath];
 BOOL isDirectory = NO;
 if (![fm fileExistsAtPath:bundlePath isDirectory:&isDirectory] || !isDirectory) continue;
 NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"Info.plist"]];
 NSString *executable = [info[@"CFBundleExecutable"] isKindOfClass:[NSString class]] ? info[@"CFBundleExecutable"] : nil;
 NSString *executablePath = executable.length > 0 ? [bundlePath stringByAppendingPathComponent:executable] : nil;
 if (executablePath.length > 0 && [fm fileExistsAtPath:executablePath]) [paths addObject:executablePath];
 [enumerator skipDescendants];
 }
 return [paths copy];
}

- (BOOL)verifyEmbeddedBundleSignaturesAtPath:(NSString *)appPath opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 NSArray *paths = [self embeddedExecutablePathsAtPath:appPath];
 BOOL allValid = YES;
 for (NSString *path in paths) {
 BOOL valid = [self runCmd:self.ldidPath args:@[@"-h", path] opLog:nil recordID:nil];
 NSString *rec = [opLog beginPhase:OperationPhaseVerify operation:@"verify embedded executable signature" target:path input:@"ldid -h" transactionID:txnID];
 [opLog endPhase:rec exitCode:valid ? 0 : 1 rawOutput:@"" rawError:valid ? @"" : @"Embedded executable signature check failed"
 verification:[NSString stringWithFormat:@"path=%@ signed=%@", path, valid ? @"YES" : @"NO"] verified:valid duration:0];
 if (!valid) allValid = NO;
 }
 return allValid;
}

- (void)fixFrameworks:(NSString *)appPath hasHelper:(BOOL)hasH opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
  NSString *traceRec = [opLog beginPhase:OperationPhaseSign operation:@"[TRACE] ENTER fixFrameworks" target:appPath input:@"" transactionID:txnID];
  [opLog endPhase:traceRec exitCode:0 rawOutput:@"[TRACE] ENTER fixFrameworks" rawError:@"" verification:@"trace" verified:YES duration:0];

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *fw = [appPath stringByAppendingPathComponent:@"Frameworks"];
  if (![fm fileExistsAtPath:fw]) {
    NSString *missRec = [opLog beginPhase:OperationPhaseSign operation:@"[TRACE] RETURN FROM fixFrameworks" target:appPath input:@"reason=Frameworks_dir_missing" transactionID:txnID];
    [opLog endPhase:missRec exitCode:0 rawOutput:@"[TRACE] RETURN FROM fixFrameworks | reason=Frameworks_dir_missing" rawError:@"" verification:@"trace" verified:YES duration:0];
    return;
  }

  NSArray *items = [fm contentsOfDirectoryAtPath:fw error:nil];
  NSString *itemsRec = [opLog beginPhase:OperationPhaseSign operation:@"[TRACE] fixFrameworks items" target:appPath input:@"" transactionID:txnID];
  [opLog endPhase:itemsRec exitCode:0 rawOutput:[NSString stringWithFormat:@"[TRACE] fixFrameworks found %lu items", (unsigned long)items.count] rawError:@"" verification:@"trace" verified:YES duration:0];

  for (NSString *item in items) {
    NSString *ip = [fw stringByAppendingPathComponent:item];
    BOOL isDir = NO;
    [fm fileExistsAtPath:ip isDirectory:&isDir];

    if (isDir && [item hasSuffix:@".framework"]) {
      NSString *fn = [item stringByDeletingPathExtension];
      NSString *beforeFw = [opLog beginPhase:OperationPhaseSign operation:[NSString stringWithFormat:@"[TRACE] BEFORE SIGN framework: %@", fn] target:ip input:@"" transactionID:txnID];
      [opLog endPhase:beforeFw exitCode:0 rawOutput:[NSString stringWithFormat:@"[TRACE] BEFORE SIGN framework: %@", fn] rawError:@"" verification:@"trace" verified:YES duration:0];

      [self signBin:[ip stringByAppendingPathComponent:fn] hasHelper:hasH label:[@"fw:" stringByAppendingString:fn] opLog:opLog txnID:txnID];

      NSString *afterFw = [opLog beginPhase:OperationPhaseSign operation:[NSString stringWithFormat:@"[TRACE] AFTER SIGN framework: %@", fn] target:ip input:@"" transactionID:txnID];
      [opLog endPhase:afterFw exitCode:0 rawOutput:[NSString stringWithFormat:@"[TRACE] AFTER SIGN framework: %@", fn] rawError:@"" verification:@"trace" verified:YES duration:0];

      [self signAllAt:ip hasHelper:hasH opLog:opLog txnID:txnID];

      NSString *afterAll = [opLog beginPhase:OperationPhaseSign operation:[NSString stringWithFormat:@"[TRACE] AFTER signAllAt: %@", fn] target:ip input:@"" transactionID:txnID];
      [opLog endPhase:afterAll exitCode:0 rawOutput:[NSString stringWithFormat:@"[TRACE] AFTER signAllAt: %@", fn] rawError:@"" verification:@"trace" verified:YES duration:0];

    } else if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
      NSString *beforeDy = [opLog beginPhase:OperationPhaseSign operation:[NSString stringWithFormat:@"[TRACE] BEFORE SIGN dylib: %@", item] target:ip input:@"" transactionID:txnID];
      [opLog endPhase:beforeDy exitCode:0 rawOutput:[NSString stringWithFormat:@"[TRACE] BEFORE SIGN dylib: %@", item] rawError:@"" verification:@"trace" verified:YES duration:0];

      [self signBin:ip hasHelper:hasH label:[@"dylib:" stringByAppendingString:item] opLog:opLog txnID:txnID];

      NSString *afterDy = [opLog beginPhase:OperationPhaseSign operation:[NSString stringWithFormat:@"[TRACE] AFTER SIGN dylib: %@", item] target:ip input:@"" transactionID:txnID];
      [opLog endPhase:afterDy exitCode:0 rawOutput:[NSString stringWithFormat:@"[TRACE] AFTER SIGN dylib: %@", item] rawError:@"" verification:@"trace" verified:YES duration:0];

      if (hasH) {
        [self runRoot:self.chmodPath args:@[@"755", ip] opLog:opLog recordID:nil];
        [self runRoot:self.chownPath args:@[@"root:wheel", ip] opLog:opLog recordID:nil];
      }
    }
  }

  NSString *exitRec = [opLog beginPhase:OperationPhaseSign operation:@"[TRACE] EXIT fixFrameworks" target:appPath input:@"" transactionID:txnID];
  [opLog endPhase:exitRec exitCode:0 rawOutput:@"[TRACE] EXIT fixFrameworks" rawError:@"" verification:@"trace" verified:YES duration:0];
}


#pragma mark - Launch Readiness Gate

#pragma mark - Bundle-scoped dependency index (v3.2.2)

// FIX(v3.2.2): Non-standard layouts in modded IPAs (e.g. FFmpeg-style dylib
// trees referencing "@rpath/libavutil_sci.framework/libavutil" from a custom
// subdirectory) defeat the fixed candidate list. This builds a one-time,
// cached index of every file inside the app bundle and is consulted ONLY
// after every standard candidate fails. Purely additive — no existing
// candidate, gate, or special case is altered.
- (NSSet<NSString *> *)bundlePathIndexForApp:(NSString *)appPath {
    static NSCache<NSString *, NSSet<NSString *> *> *indexCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        indexCache = [NSCache new];
        indexCache.totalCostLimit = 32 * 1024 * 1024;
    });
    NSSet<NSString *> *cached = [indexCache objectForKey:appPath];
    if (cached) return cached;

    NSMutableSet<NSString *> *paths = [NSMutableSet set];
    const NSUInteger kIndexCap = 50000;
    NSUInteger count = 0;
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager]
        enumeratorAtURL:[NSURL fileURLWithPath:appPath]
        includingPropertiesForKeys:nil
        options:0
        errorHandler:nil];
    // Note: no SkipsPackageDescendants — we must descend into .framework
    // bundles because the dependency leaf itself is "X.framework/X".
    for (NSURL *url in enumerator) {
        if (++count > kIndexCap) break;
        [paths addObject:url.path];
    }
    [indexCache setObject:paths forKey:appPath cost:paths.count * 64];
    return paths;
}

- (BOOL)dependency:(NSString *)dependency resolvesForBinary:(NSString *)binaryPath appPath:(NSString *)appPath rpaths:(NSArray<MachORPath *> *)rpaths {
    if (!dependency.length || !binaryPath.length || !appPath.length) return NO;

    // Mach-O install names cannot contain formatting whitespace. Some tools
    // emit a wrapped name such as "@rpath/ WebKit.framework/ WebKit"; remove
    // only whitespace characters, preserving the original validation policy.
    NSString *originalDependency = dependency;
    NSString *normalizedDependency = [[dependency componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    BOOL normalizedLooksSystem = [normalizedDependency hasPrefix:@"@rpath/"] ||
        [normalizedDependency hasPrefix:@"/System/Library/"] ||
        [normalizedDependency hasPrefix:@"/usr/lib/"] ||
        [normalizedDependency hasPrefix:@"/us/lib/"];
    // Preserve legitimate app-local install names containing spaces. Only
    // use the whitespace-stripped spelling for a malformed system/rpath name.
    if (normalizedLooksSystem && normalizedDependency.length) dependency = normalizedDependency;
    else dependency = originalDependency;

    // FIX(v3.0.49): System prefixes are trusted unconditionally (see below).

    // A malformed diagnostic may print /us/lib/ instead of /usr/lib/;
    // normalize only this unambiguous system-prefix typo.
    if ([dependency hasPrefix:@"/us/lib/"]) {
        dependency = [@"/usr/lib" stringByAppendingString:[dependency substringFromIndex:[@"/us/lib" length]]];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    static NSSet<NSString *> *systemFrameworks;
    static dispatch_once_t frameworkOnceToken;
    dispatch_once(&frameworkOnceToken, ^{
        systemFrameworks = [NSSet setWithArray:@[
            @"WebKit.framework", @"Foundation.framework", @"UIKit.framework",
            @"IOKit.framework", @"SpringBoardServices.framework", @"WebCore.framework",
            @"CoreFoundation.framework", @"CoreGraphics.framework", @"Security.framework",
            @"QuartzCore.framework", @"AVFoundation.framework", @"CoreTelephony.framework",
            @"MobileCoreServices.framework", @"UniformTypeIdentifiers.framework",
            @"SystemConfiguration.framework", @"Network.framework", @"CFNetwork.framework"
        ]];
    });
    NSString *frameworkComponent = nil;
    NSArray<NSString *> *dependencyComponents = [dependency componentsSeparatedByString:@"/"];
    for (NSString *component in dependencyComponents) {
        if ([component hasSuffix:@".framework"]) { frameworkComponent = component; break; }
    }
    BOOL isKnownSystemFramework = frameworkComponent.length && [systemFrameworks containsObject:frameworkComponent];
    if (isKnownSystemFramework && ([dependency hasPrefix:@"@rpath/"] || [dependency hasPrefix:@"/System/Library/"] || [dependency hasPrefix:@"/System/Library/PrivateFrameworks/"])) {
        return YES;
    }
    // FIX(v3.0.49): Restore unconditional trust for system prefixes.
    // System frameworks and libraries are resolved by dyld at launch through
    // the dyld shared cache. On device they are frequently NOT present as
    // readable regular files: cache-only frameworks (SwiftUI, CryptoKit,
    // AdSupport, UserNotifications, Combine...), sandboxed file-exists checks
    // returning NO for valid system paths, and rootless layouts. v3.0.43
    // trusted these prefixes and installed every standard app reliably; the
    // existence gate added later broke them all. Runtime resolution is dyld's
    // job — the static gate must not second-guess it. App-local and jailbreak
    // libraries are still fully verified through the candidate logic below.
    if ([dependency hasPrefix:@"/System/Library/"] || [dependency hasPrefix:@"/usr/lib/"] || [dependency hasPrefix:@"/usr/lib/swift/"]) {
        return YES;
    }

    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSString *binaryDir = [binaryPath stringByDeletingLastPathComponent];
    NSString *frameworksDir = [appPath stringByAppendingPathComponent:@"Frameworks"];
    NSString *libDir = [appPath stringByAppendingPathComponent:@"lib"];
    NSString *(^expandBase)(NSString *, NSString *) = ^NSString *(NSString *base, NSString *fallback) {
        if ([base hasPrefix:@"@loader_path"]) return [binaryDir stringByAppendingPathComponent:[base substringFromIndex:[@"@loader_path" length]]];
        if ([base hasPrefix:@"@executable_path"]) return [appPath stringByAppendingPathComponent:[base substringFromIndex:[@"@executable_path" length]]];
        if ([base hasPrefix:@"/"]) return base;
        return [fallback stringByAppendingPathComponent:base ?: @""];
    };

    if ([dependency hasPrefix:@"@rpath/"]) {
        NSString *leaf = [dependency substringFromIndex:[@"@rpath/" length]];
        for (MachORPath *rpath in rpaths) {
            NSString *raw = rpath.rawPath;
            if (!raw.length) continue;
            NSString *base = expandBase(raw, frameworksDir);
            [candidates addObject:[[base stringByAppendingPathComponent:leaf] stringByStandardizingPath]];
            if ([raw containsString:@".."] || [raw hasPrefix:@"@loader_path"]) {
                [candidates addObject:[[frameworksDir stringByAppendingPathComponent:raw] stringByStandardizingPath]];
            }
        }
        [candidates addObject:[[frameworksDir stringByAppendingPathComponent:leaf] stringByStandardizingPath]];
        [candidates addObject:[[libDir stringByAppendingPathComponent:leaf] stringByStandardizingPath]];
        // FIX(v3.0.50): Jailbreak bootstrap locations (see @loader_path branch).
        [candidates addObject:[[ @"/usr/lib" stringByAppendingPathComponent:leaf] stringByStandardizingPath]];
        [candidates addObject:[[ @"/var/jb/usr/lib" stringByAppendingPathComponent:leaf] stringByStandardizingPath]];
        [candidates addObject:[[ @"/private/var/jb/usr/lib" stringByAppendingPathComponent:leaf] stringByStandardizingPath]];
        [candidates addObject:[[ @"/var/jb/basebin" stringByAppendingPathComponent:leaf] stringByStandardizingPath]];
        [candidates addObject:[[ @"/private/var/jb/basebin" stringByAppendingPathComponent:leaf] stringByStandardizingPath]];
        // FIX(v3.0.49): Swift runtime libraries ship with the system and are
        // satisfied from the dyld shared cache even when no on-disk candidate
        // exists inside the bundle (v3.0.43 behavior, restored).
        if ([leaf hasPrefix:@"libswift"] && ![leaf containsString:@"/"]) return YES;
    } else if ([dependency hasPrefix:@"@loader_path"]) {
        NSString *relative = [dependency substringFromIndex:[@"@loader_path" length]];
        [candidates addObject:[[binaryDir stringByAppendingPathComponent:relative] stringByStandardizingPath]];
        [candidates addObject:[[frameworksDir stringByAppendingPathComponent:relative] stringByStandardizingPath]];
        [candidates addObject:[[libDir stringByAppendingPathComponent:relative] stringByStandardizingPath]];
        // FIX(v3.0.50): Jailbreak-provided libraries (e.g. Dopamine's
        // basebin/libchoma.dylib referenced as @loader_path/libchoma.dylib by
        // libjailbreak.dylib) are frequently NOT bundled — dyld resolves them
        // from the bootstrap at runtime. Verify against bootstrap locations so
        // such apps are not rejected. Purely additive; no existing candidate
        // or behavior is altered.
        [candidates addObject:[[ @"/usr/lib" stringByAppendingPathComponent:relative] stringByStandardizingPath]];
        [candidates addObject:[[ @"/var/jb/usr/lib" stringByAppendingPathComponent:relative] stringByStandardizingPath]];
        [candidates addObject:[[ @"/private/var/jb/usr/lib" stringByAppendingPathComponent:relative] stringByStandardizingPath]];
        [candidates addObject:[[ @"/var/jb/basebin" stringByAppendingPathComponent:relative] stringByStandardizingPath]];
        [candidates addObject:[[ @"/private/var/jb/basebin" stringByAppendingPathComponent:relative] stringByStandardizingPath]];
    } else if ([dependency hasPrefix:@"@executable_path"]) {
        NSString *relative = [dependency substringFromIndex:[@"@executable_path" length]];
        [candidates addObject:[[appPath stringByAppendingPathComponent:relative] stringByStandardizingPath]];
        [candidates addObject:[[frameworksDir stringByAppendingPathComponent:[relative lastPathComponent]] stringByStandardizingPath]];
    } else if ([dependency hasPrefix:@"/"]) {
        [candidates addObject:dependency];
        [candidates addObject:[[ @"/var/jb" stringByAppendingPathComponent:dependency] stringByStandardizingPath]];
        [candidates addObject:[[ @"/private/var/jb" stringByAppendingPathComponent:dependency] stringByStandardizingPath]];
    } else {
        [candidates addObject:[[binaryDir stringByAppendingPathComponent:dependency] stringByStandardizingPath]];
        [candidates addObject:[[appPath stringByAppendingPathComponent:dependency] stringByStandardizingPath]];
        [candidates addObject:[[frameworksDir stringByAppendingPathComponent:dependency] stringByStandardizingPath]];
        [candidates addObject:[[libDir stringByAppendingPathComponent:dependency] stringByStandardizingPath]];
    }

    for (NSString *candidate in candidates) {
        if (candidate.length && [fm fileExistsAtPath:candidate]) return YES;
    }

    // FIX(v3.2.2): Last-resort bundle-scoped lookup for non-standard layouts.
    // Only reached when every standard candidate failed. Absolute-path
    // dependencies are intentionally excluded — if the file is truly absent
    // from disk there is nothing an in-bundle search could satisfy.
    BOOL isAppRelativeRef = [dependency hasPrefix:@"@rpath/"] ||
                            [dependency hasPrefix:@"@loader_path"] ||
                            [dependency hasPrefix:@"@executable_path"] ||
                            ![dependency hasPrefix:@"/"];
    if (isAppRelativeRef) {
        NSString *leaf = nil;
        if ([dependency hasPrefix:@"@rpath/"]) leaf = [dependency substringFromIndex:[@"@rpath/" length]];
        else if ([dependency hasPrefix:@"@loader_path"]) leaf = [dependency substringFromIndex:[@"@loader_path" length]];
        else if ([dependency hasPrefix:@"@executable_path"]) leaf = [dependency substringFromIndex:[@"@executable_path" length]];
        else leaf = dependency;
        leaf = [leaf stringByStandardizingPath];
        if (leaf.length && ![leaf hasPrefix:@".."]) {
            NSString *suffix = [@"/" stringByAppendingString:leaf];
            NSSet<NSString *> *index = [self bundlePathIndexForApp:appPath];
            for (NSString *indexedPath in index) {
                if ([indexedPath hasSuffix:suffix]) return YES;
            }
        }
    }
    return NO;
}

- (BOOL)verifyLaunchReadinessAtPath:(NSString *)appPath bundleID:(NSString *)bundleID exeName:(NSString *)exeName opLog:(OperationLog *)opLog txnID:(NSString *)txnID reason:(NSString **)reason {
    // This is a strict static gate. It proves that the installed bundle is
    // structurally launchable; it cannot prove behavior inside the app process.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *failures = [NSMutableArray array];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"]];
    if (![info isKindOfClass:[NSDictionary class]]) [failures addObject:@"Info.plist is unreadable"];
    if (![info[@"CFBundleIdentifier"] isEqual:bundleID]) [failures addObject:@"CFBundleIdentifier does not match the installation identity"];
    // FIX(v3.0.19): Removed CFBundlePackageType check — not all valid apps have APPL
    if (!exeName.length || [exeName containsString:@"/"] || [exeName containsString:@".."] || [exeName containsString:@"~"]) [failures addObject:@"invalid CFBundleExecutable name"];

    NSString *mainBinary = [appPath stringByAppendingPathComponent:exeName ?: @""];
    // FIX(v3.0.19): Relaxed X_OK check. On iOS 16+ with certain jailbreaks, access(X_OK)
    // may fail due to sandbox restrictions even though the binary IS executable.
    BOOL mainExists = exeName.length > 0 && [fm fileExistsAtPath:mainBinary] && [fm isReadableFileAtPath:mainBinary];
    if (!mainExists) {
        [failures addObject:@"main executable is missing or unreadable"];
    } else if (access(mainBinary.fileSystemRepresentation, X_OK) != 0 && access(mainBinary.fileSystemRepresentation, R_OK) != 0) {
        [failures addObject:@"main binary is not accessible"];
    }

    NSArray<NSString *> *machOPaths = [self machOPathsAtPath:appPath];
    if (![machOPaths containsObject:mainBinary]) [failures addObject:@"main executable is not a recognizable Mach-O"];
    // FIX(v3.0.19): Accept arm64, arm64e, armv7, armv7s, x86_64, i386
    for (NSString *binaryPath in machOPaths) {
        MachOAnalysisResult *analysis = [[MachOAnalyzer sharedAnalyzer] analyzeFileAtPath:binaryPath];
        if (!analysis || (analysis.parseStatus == MachOParseFailed && !analysis.hasEncryptedSlice) || analysis.slices.count == 0) {
            [failures addObject:[NSString stringWithFormat:@"Mach-O analysis failed: %@", binaryPath.lastPathComponent]];
            continue;
        }
        BOOL hasValidArch = NO;
        for (MachOSlice *slice in analysis.slices) {
            if (slice.cputype == 0x0100000c || slice.cputype == 0x0000000c || slice.cputype == 0x01000007 || slice.cputype == 0x00000007) {
                hasValidArch = YES; break;
            }
        }
        if (!hasValidArch) [failures addObject:[NSString stringWithFormat:@"no compatible architecture slice: %@", binaryPath.lastPathComponent]];
        for (MachODependency *dep in analysis.dependencies) {
            if (dep.isWeak) continue;
            if (![self dependency:dep.rawInstallName resolvesForBinary:binaryPath appPath:appPath rpaths:analysis.rpaths]) {
                [failures addObject:[NSString stringWithFormat:@"unresolved dependency %@ in %@", dep.rawInstallName ?: @"(empty)", binaryPath.lastPathComponent]];
            }
        }
    }
    if (machOPaths.count == 0) [failures addObject:@"bundle contains no Mach-O executable"];

    // Every executable-bearing bundle must have a valid identity and executable.
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:appPath];
    NSString *relative = nil;
    while ((relative = [enumerator nextObject])) {
        if (![relative hasSuffix:@"/Info.plist"]) continue;
        NSString *bundlePath = [[appPath stringByAppendingPathComponent:relative] stringByDeletingLastPathComponent];
        NSString *lower = bundlePath.lowercaseString;
        if (![lower hasSuffix:@".app"] && ![lower hasSuffix:@".appex"] && ![lower hasSuffix:@".xpc"] && ![lower hasSuffix:@".framework"]) continue;
        NSDictionary *bundleInfo = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:relative]];
        NSString *bundleExecutable = [bundleInfo[@"CFBundleExecutable"] isKindOfClass:[NSString class]] ? bundleInfo[@"CFBundleExecutable"] : nil;
        NSString *bundleIdentifier = [bundleInfo[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? bundleInfo[@"CFBundleIdentifier"] : nil;
        if (!bundleIdentifier.length || !bundleExecutable.length || [bundleExecutable containsString:@"/"]) {
            [failures addObject:[NSString stringWithFormat:@"invalid nested bundle metadata: %@", bundlePath.lastPathComponent]];
            continue;
        }
        NSString *nestedExecutable = [bundlePath stringByAppendingPathComponent:bundleExecutable];
        BOOL isHostBundle = [lower hasSuffix:@".app"] && [bundlePath isEqualToString:appPath];
        BOOL nestedExists = [fm fileExistsAtPath:nestedExecutable] && [fm isReadableFileAtPath:nestedExecutable];
        BOOL nestedMachO = [machOPaths containsObject:nestedExecutable];
        BOOL nestedExecutableBit = nestedExists && access(nestedExecutable.fileSystemRepresentation, X_OK) == 0;
        if (!nestedExists) {
            [failures addObject:[NSString stringWithFormat:@"nested executable is missing or unreadable: %@", nestedExecutable.lastPathComponent]];
        } else if (!nestedMachO) {
            [failures addObject:[NSString stringWithFormat:@"nested executable is not a recognized Mach-O: %@", nestedExecutable.lastPathComponent]];
        } else if (isHostBundle && !nestedExecutableBit) {
            // The host application's executable is the launch-critical contract.
            [failures addObject:[NSString stringWithFormat:@"main executable is not runnable: %@", nestedExecutable.lastPathComponent]];
        } else if (!nestedExecutableBit) {
            // FIX(v3.0.19): All nested binaries lacking X_OK are warnings only.
            // On iOS 16/17/18 with different jailbreaks, file permissions vary.
            // ldid + uicache handle permission correction automatically.
            NSLog(@"[IPAInstallerPro] Nested executable lacks X_OK; retaining as warning: %@", nestedExecutable);
            NSString *warningRecord = [opLog beginPhase:OperationPhaseVerify operation:@"nested executable permission warning" target:nestedExecutable input:@"role-aware check" transactionID:txnID];
            [opLog endPhase:warningRecord exitCode:0 rawOutput:@"" rawError:@"" verification:@"child executable: permission warning only" verified:YES duration:0 context:@{ @"role": [lower hasSuffix:@".appex"] ? @"appex" : ([lower hasSuffix:@".xpc"] ? @"xpc" : @"nested") }];
        }
    }

    NSString *recordID = [opLog beginPhase:OperationPhaseVerify operation:@"launch-readiness-gate" target:appPath input:@"static launch contract" transactionID:txnID];
    NSString *summary = failures.count ? [failures componentsJoinedByString:@"; "] : @"bundle identity, Mach-O, arm64 slices, dependencies, nested metadata and executable permissions passed";
    BOOL ready = failures.count == 0;
    [opLog endPhase:recordID exitCode:ready ? 0 : 1 rawOutput:summary rawError:ready ? @"" : @"Launch readiness gate rejected installation" verification:@"strict static launch readiness" verified:ready duration:0];
    if (!ready && reason) *reason = [NSString stringWithFormat:@"Launch readiness failed: %@", summary];
    return ready;
}

#pragma mark - Verification

- (BOOL)verifyInstallation:(NSString *)appPath bundleID:(NSString *)bid exeName:(NSString *)en opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 NSFileManager *fm = [NSFileManager defaultManager];
 BOOL ok = YES;
 NSString *ep = [appPath stringByAppendingPathComponent:en];

 // exe exists + readable + executable
 BOOL exeExists = [fm fileExistsAtPath:ep];
 BOOL exeReadable = [fm isReadableFileAtPath:ep];
 BOOL exeX_OK = (access([ep UTF8String], X_OK) == 0);

 NSString *recExe = [opLog beginPhase:OperationPhaseVerify operation:@"verify executable" target:ep input:@"" transactionID:txnID];
 [opLog endPhase:recExe exitCode:(exeExists && exeReadable && exeX_OK) ? 0 : 1 rawOutput:@"" rawError:(exeExists && exeReadable && exeX_OK) ? @"" : [NSString stringWithFormat:@"exists=%d readable=%d xok=%d", exeExists, exeReadable, exeX_OK]
 verification:[NSString stringWithFormat:@"exists=%@ readable=%@ xok=%@", exeExists ? @"YES" : @"NO", exeReadable ? @"YES" : @"NO", exeX_OK ? @"YES" : @"NO"]
 verified:(exeExists && exeReadable && exeX_OK) duration:0];
 if (!exeExists || !exeReadable || !exeX_OK) ok = NO;

 // Info.plist
 NSString *ip = [appPath stringByAppendingPathComponent:@"Info.plist"];
 BOOL infoExists = [fm fileExistsAtPath:ip];
 NSString *recInfo = [opLog beginPhase:OperationPhaseVerify operation:@"verify Info.plist" target:ip input:@"" transactionID:txnID];
 [opLog endPhase:recInfo exitCode:infoExists ? 0 : 1 rawOutput:@"" rawError:infoExists ? @"" : @"Missing"
 verification:[NSString stringWithFormat:@"exists=%@", infoExists ? @"YES" : @"NO"] verified:infoExists duration:0];
 if (!infoExists) ok = NO;

 // Verify signature on main executable
 BOOL exeSigned = [self verifySignature:ep opLog:opLog txnID:txnID];
 if (!exeSigned) ok = NO;

 // Frameworks
 NSString *fwp = [appPath stringByAppendingPathComponent:@"Frameworks"];
 if ([fm fileExistsAtPath:fwp]) {
 for (NSString *item in [fm contentsOfDirectoryAtPath:fwp error:nil]) {
 NSString *p = [fwp stringByAppendingPathComponent:item];
 if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
 BOOL dylibReadable = [fm isReadableFileAtPath:p];
 BOOL dylibExecutableBit = (access([p UTF8String], X_OK) == 0);
 MachOAnalysisResult *dylibAnalysis = [[MachOAnalyzer sharedAnalyzer] analyzeFileAtPath:p];
 BOOL dylibMachOValid = (dylibAnalysis && dylibAnalysis.parseStatus == MachOParseSuccess && dylibAnalysis.machOType != 0);
 // Shared libraries are loaded by the host process and are not main
 // executables. Their X_OK bit is recorded as evidence but is not a failure
 // condition; readability and valid Mach-O metadata remain mandatory.
 BOOL dylibValid = dylibReadable && dylibMachOValid;
 NSString *recFw = [opLog beginPhase:OperationPhaseVerify operation:[NSString stringWithFormat:@"verify dylib %@", item] target:p input:@"" transactionID:txnID];
 [opLog endPhase:recFw exitCode:dylibValid ? 0 : 1 rawOutput:@"" rawError:dylibValid ? @"" : [NSString stringWithFormat:@"readable=%@ machoValid=%@", dylibReadable ? @"YES" : @"NO", dylibMachOValid ? @"YES" : @"NO"]
 verification:[NSString stringWithFormat:@"readable=%@ executableBit=%@ machoValid=%@ signatureCheckedByPostSign=YES", dylibReadable ? @"YES" : @"NO", dylibExecutableBit ? @"YES" : @"NO", dylibMachOValid ? @"YES" : @"NO"]
 verified:dylibValid duration:0 context:@{ @"path": p ?: @"", @"readable": @(dylibReadable), @"executableBit": @(dylibExecutableBit), @"machoValid": @(dylibMachOValid), @"signatureCheckedByPostSign": @YES }];
 if (!dylibValid) ok = NO;
 }
 }
 }

 // Embedded extensions are separate code bundles. A main executable can pass
 // verification while an unsigned appex/xpc crashes the host at launch.
 BOOL embeddedSignaturesOK = [self verifyEmbeddedBundleSignaturesAtPath:appPath opLog:opLog txnID:txnID];
 if (!embeddedSignaturesOK) ok = NO;

 // Check if app is registered in LSApplicationWorkspace (best effort, non-blocking)
 Class LS = objc_getClass("LSApplicationWorkspace");
 if (LS) {
 id ws = [LS performSelector:@selector(defaultWorkspace)];
 if ([ws respondsToSelector:@selector(applicationForIdentifier:)]) {
 id a = [ws performSelector:@selector(applicationForIdentifier:) withObject:bid];
 BOOL registered = (a != nil);
 NSString *recLS = [opLog beginPhase:OperationPhaseVerify operation:@"LSApplicationWorkspace check" target:bid input:@"" transactionID:txnID];
 [opLog endPhase:recLS exitCode:0 rawOutput:@"" rawError:@""
 verification:[NSString stringWithFormat:@"registered=%@", registered ? @"YES" : @"NO"] verified:YES duration:0];
 if (!registered) {
 NSLog(@"[IPAInstallerPro] App not yet registered in LS — uicache may need time");
 }
 }
 }

 // Dopamine-specific: verify app is in correct rootless path (warning only)
  // FIX(Palera1n): Use dynamic bootstrapPath instead of hardcoded /var/jb
  RuntimeEnvironment *rtEnv2 = [RuntimeEnvironment sharedEnvironment];
  NSString *expectedPrefix = rtEnv2.bootstrapPath ? [rtEnv2.bootstrapPath stringByAppendingPathComponent:@"Applications/"] : @"/var/jb/Applications/";
  if (![appPath hasPrefix:expectedPrefix] && ![appPath hasPrefix:@"/Applications/"]) {
  NSString *recPath = [opLog beginPhase:OperationPhaseVerify operation:@"rootlessPathCheck" target:appPath input:@"" transactionID:txnID];
 [opLog endPhase:recPath exitCode:0 rawOutput:@"" rawError:@""
 verification:[NSString stringWithFormat:@"path=%@ (non-standard but allowed)", appPath] verified:YES duration:0];
 NSLog(@"[IPAInstallerPro] WARNING: App not in standard Applications path: %@", appPath);
 }

 return ok;
}

- (BOOL)isBundleIDRegistered:(NSString *)bundleID {
    if (!bundleID.length) return NO;
    NSDictionary *facts = [[ForensicRegistrationProbe sharedProbe] launchServicesFactsForBundleID:bundleID];
    return [facts[@"registered"] boolValue];
}

- (BOOL)verifyRegistrationForBundleID:(NSString *)bundleID path:(NSString *)appPath opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
    NSDictionary *facts = [[ForensicRegistrationProbe sharedProbe] launchServicesFactsForBundleID:bundleID];
    BOOL registered = [facts[@"registered"] boolValue];
    NSString *recordID = [opLog beginPhase:OperationPhaseVerify operation:@"verify registration" target:bundleID input:appPath ?: @"" transactionID:txnID];
    [opLog endPhase:recordID exitCode:registered ? 0 : 1 rawOutput:@"" rawError:registered ? @"" : @"Bundle ID is not registered by any supported LaunchServices source"
    verification:[NSString stringWithFormat:@"registered=%@ path=%@ workspaceEnumeration=%@ proxyLookup=%@", registered ? @"YES" : @"NO", appPath ?: @"-", [facts[@"workspaceEnumerationSupported"] boolValue] ? @"YES" : @"NO", [facts[@"proxyLookupSupported"] boolValue] ? @"YES" : @"NO"] verified:registered duration:0 context:@{ @"bundleID": bundleID ?: @"", @"path": appPath ?: @"", @"registered": @(registered), @"launchServicesFacts": facts ?: @{} }];
    return registered;
}

- (BOOL)rollbackRegistrationForBundleID:(NSString *)bundleID path:(NSString *)appPath opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
    NSString *recordID = [opLog beginPhase:OperationPhaseCleanup operation:@"uicache -u registration rollback" target:appPath ?: @"" input:bundleID ?: @"" transactionID:txnID];
    BOOL commandOK = [self runRoot:self.uicachePath args:@[@"-u", appPath ?: @""] opLog:opLog recordID:recordID];
    BOOL unregistered = ![self isBundleIDRegistered:bundleID];
    BOOL rollbackSafe = unregistered;
    NSString *rollbackError = rollbackSafe ? (commandOK ? @"" : @"uicache -u failed, but registration absence was independently verified") : @"Registration rollback could not prove unregistered state";
    [opLog endPhase:recordID exitCode:rollbackSafe ? 0 : 1 rawOutput:@"" rawError:rollbackError
    verification:[NSString stringWithFormat:@"command=%@ unregistered=%@ bundleID=%@ path=%@", commandOK ? @"SUCCESS" : @"WARNING", unregistered ? @"YES" : @"NO", bundleID ?: @"-", appPath ?: @"-"] verified:rollbackSafe duration:0 context:@{ @"bundleID": bundleID ?: @"", @"path": appPath ?: @"", @"commandOK": @(commandOK), @"unregistered": @(unregistered), @"bestEffort": @YES }];
    return rollbackSafe;
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
 if (!bundleID || bundleID.length == 0) {
 if (completion) completion(NO, @"Bundle ID is empty");
 return;
 }

 NSFileManager *fm = [NSFileManager defaultManager];
 NSString *appPath = nil;

 // ─── PHASE 1: Resolve app path via LSApplicationWorkspace ───
 Class LS = objc_getClass("LSApplicationWorkspace");
 if (LS) {
 id ws = [LS performSelector:@selector(defaultWorkspace)];
 if (ws && [ws respondsToSelector:@selector(allApplications)]) {
 NSArray *apps = [ws performSelector:@selector(allApplications)];
 for (id app in apps) {
 NSString *bid = nil;
 if ([app respondsToSelector:@selector(bundleIdentifier)]) {
 bid = [app performSelector:@selector(bundleIdentifier)];
 }
 if ([bid isEqualToString:bundleID]) {
 if ([app respondsToSelector:@selector(bundleURL)]) {
 appPath = [[app performSelector:@selector(bundleURL)] path];
 } else if ([app respondsToSelector:@selector(containerURL)]) {
 appPath = [[app performSelector:@selector(containerURL)] path];
 }
 break;
 }
 }
 }
 }

 // ─── PHASE 2: Scan Applications directories for matching Info.plist ───
  // FIX(Palera1n): Use dynamic bootstrapPath for Applications directory
  RuntimeEnvironment *rtEnv3 = [RuntimeEnvironment sharedEnvironment];
  NSMutableArray *searchDirs = [NSMutableArray arrayWithObjects:@"/Applications", @"/var/mobile/Applications", nil];
  if (rtEnv3.bootstrapPath) {
      [searchDirs insertObject:[rtEnv3.bootstrapPath stringByAppendingPathComponent:@"Applications"] atIndex:0];
  } else {
      [searchDirs insertObject:@"/var/jb/Applications" atIndex:0];
  }
  if (!appPath || appPath.length == 0) {
  for (NSString *dir in searchDirs) {
 if (![fm fileExistsAtPath:dir]) continue;
 NSArray *items = [fm contentsOfDirectoryAtPath:dir error:nil];
 for (NSString *item in items) {
 if ([item hasSuffix:@".app"]) {
 NSString *infoPath = [dir stringByAppendingPathComponent:[item stringByAppendingPathComponent:@"Info.plist"]];
 NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
 NSString *bid = info[@"CFBundleIdentifier"];
 if ([bid isEqualToString:bundleID]) {
 appPath = [dir stringByAppendingPathComponent:item];
 break;
 }
 }
 }
 if (appPath) break;
 }
 }

 if (!appPath || appPath.length == 0) {
 if (completion) completion(NO, @"App not found on device");
 return;
 }

 NSLog(@"[IPAInstallerPro] Resolved app path for %@: %@", bundleID, appPath);

 // ─── PHASE 3: Try LSApplicationWorkspace uninstall API (but verify!) ───
 if (LS) {
 id ws = [LS performSelector:@selector(defaultWorkspace)];
 if (ws) {
 BOOL apiCalled = NO;
 if ([ws respondsToSelector:@selector(uninstallApplication:withOptions:)]) {
 (void)[ws performSelector:@selector(uninstallApplication:withOptions:) withObject:bundleID withObject:@{}];
 apiCalled = YES;
 } else if ([ws respondsToSelector:@selector(uninstallApplication:)]) {
 (void)[ws performSelector:@selector(uninstallApplication:) withObject:bundleID];
 apiCalled = YES;
 }
 if (apiCalled && ![fm fileExistsAtPath:appPath]) {
 [self runRoot:self.uicachePath args:@[@"-a"] opLog:nil recordID:nil];
 if (completion) completion(YES, nil);
 return;
 }
 }
 }

 // ─── PHASE 4: Force remove via root helper ───
 // Unregister from SpringBoard first
 [self runRoot:self.uicachePath args:@[@"-p", appPath] opLog:nil recordID:nil];

 // Delete the app bundle
 BOOL removed = NO;
 if ([self hasRootHelper]) {
 removed = [self runRoot:self.rmPath args:@[@"-rf", appPath] opLog:nil recordID:nil];
 } else {
 NSError *err = nil;
 removed = [fm removeItemAtPath:appPath error:&err];
 if (!removed) {
 removed = [self runRoot:self.rmPath args:@[@"-rf", appPath] opLog:nil recordID:nil];
 }
 }

 // ─── PHASE 5: Verify deletion actually happened ───
 if (removed && [fm fileExistsAtPath:appPath]) {
 // Still there — try once more with helper
 removed = [self runRoot:self.rmPath args:@[@"-rf", appPath] opLog:nil recordID:nil];
 }

 if (removed && ![fm fileExistsAtPath:appPath]) {
 [self runRoot:self.uicachePath args:@[@"-a"] opLog:nil recordID:nil];
 if (completion) completion(YES, nil);
 } else {
 if (completion) completion(NO, @"Failed to remove application files — path still exists");
 }
}

#pragma mark - App Icon Extraction

- (NSString *)iconPathForAppAtPath:(NSString *)appPath {
 NSFileManager *fm = [NSFileManager defaultManager];
 NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
 NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
 if (!info) return nil;

 // Try CFBundleIcons (iOS 5+)
 NSDictionary *iconsDict = info[@"CFBundleIcons"];
 if (!iconsDict) iconsDict = info[@"CFBundleIcons~ipad"];

 NSArray *iconFiles = nil;
 if (iconsDict) {
 NSDictionary *primary = iconsDict[@"CFBundlePrimaryIcon"];
 if (primary) iconFiles = primary[@"CFBundleIconFiles"];
 }

 // Fallback to CFBundleIconFiles
 if (!iconFiles || iconFiles.count == 0) {
 iconFiles = info[@"CFBundleIconFiles"];
 }

 // Fallback to CFBundleIconFile (single)
 if (!iconFiles || iconFiles.count == 0) {
 NSString *singleIcon = info[@"CFBundleIconFile"];
 if (singleIcon) iconFiles = @[singleIcon];
 }

 if (!iconFiles || iconFiles.count == 0) return nil;

 // Find the best icon (largest, @2x or @3x preferred)
 NSString *bestIcon = nil;
 for (NSString *iconName in iconFiles) {
 NSString *baseName = [iconName stringByDeletingPathExtension];
 NSString *ext = [iconName pathExtension];
 if (ext.length == 0) ext = @"png";

 // Try @3x first
 NSString *icon3x = [appPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@@3x.%@", baseName, ext]];
 if ([fm fileExistsAtPath:icon3x]) { bestIcon = icon3x; break; }

 // Try @2x
 NSString *icon2x = [appPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@@2x.%@", baseName, ext]];
 if ([fm fileExistsAtPath:icon2x]) { bestIcon = icon2x; break; }

 // Try base
 NSString *iconBase = [appPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", baseName, ext]];
 if ([fm fileExistsAtPath:iconBase]) { bestIcon = iconBase; break; }
 }

 return bestIcon;
}

- (BOOL)remapSigningPlan:(SigningPlan *)plan toInstalledAppPath:(NSString *)installedAppPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!plan || !installedAppPath.length || ![fm fileExistsAtPath:installedAppPath]) return NO;

    NSUInteger validTargets = 0;
    for (SigningTarget *target in plan.targets) {
        if (!target.filePath.length) return NO;
        NSString *relative = target.filePath;
        while ([relative hasPrefix:@"/"]) relative = [relative substringFromIndex:1];
        NSString *installedPath = [installedAppPath stringByAppendingPathComponent:relative];
        if (![fm fileExistsAtPath:installedPath]) {
            NSLog(@"[SmartSign] Missing mapped target: %@ -> %@", relative, installedPath);
            return NO;
        }
        target.filePath = installedPath;
        validTargets++;
    }
    return (validTargets == plan.targets.count && validTargets > 0);
}

#pragma mark - Uninstall

- (void)uninstallAppAtPath:(NSString *)appPath bundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
 if (!appPath || appPath.length == 0 || !bundleID || bundleID.length == 0) {
 [self uninstallAppWithBundleID:bundleID completion:completion];
 return;
 }

 // Unregister from SpringBoard first
 [self runRoot:self.uicachePath args:@[@"-p", appPath] opLog:nil recordID:nil];

 // Delete via root helper
 BOOL removed = [self runRoot:self.rmPath args:@[@"-rf", appPath] opLog:nil recordID:nil];

 // Verify actually gone
 if (removed && ![[NSFileManager defaultManager] fileExistsAtPath:appPath]) {
 [self runRoot:self.uicachePath args:@[@"-a"] opLog:nil recordID:nil];
 if (completion) completion(YES, nil);
 } else {
 if (completion) completion(NO, @"Failed to remove application files");
 }
}
#pragma mark - Smart Signing Plan Execution

- (NSUInteger)executeSigningPlan:(SigningPlan *)plan atAppPath:(NSString *)appPath hasHelper:(BOOL)hasH opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 if (!plan || !plan.isViable || plan.targets.count == 0) {
 NSLog(@"[SmartSign] Invalid plan");
 return 0;
 }
 NSArray *ordered = [plan targetsOrderedForSigning];
 NSUInteger signedCount = 0;
 for (SigningTarget *target in ordered) {
 if (!target.needsSigning) continue;
  NSLog(@"[SmartSign] Signing [%@] %@ with strategy: %@",
        target.targetTypeName, target.targetName, target.strategyNameString);

  BOOL ok = NO;
  switch (target.strategy) {
      case SigningStrategyPreserveOriginal: {
          NSDictionary *ents = target.plannedEntitlements.rawEntitlements;
          if (!ents || ents.count == 0) {
              NSString *entOutput = [self runCmdOutput:self.ldidPath args:@[@"-e", target.filePath]];
              if (entOutput && entOutput.length > 10) {
                  NSString *tmpEnt = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"pres_%@.plist", [[NSUUID UUID] UUIDString]]];
                  [entOutput writeToFile:tmpEnt atomically:YES encoding:NSUTF8StringEncoding error:nil];
                  ents = [NSDictionary dictionaryWithContentsOfFile:tmpEnt];
              }
          }
          ok = [self signTarget:target.filePath withEntitlements:ents hasHelper:hasH opLog:opLog txnID:txnID];
          break;
      }
      case SigningStrategyGeneric: {
          NSDictionary *ents = target.plannedEntitlements.rawEntitlements ?: [EntitlementSet genericJailbreakEntitlements];
          ok = [self signTarget:target.filePath withEntitlements:ents hasHelper:hasH opLog:opLog txnID:txnID];
          break;
      }
      case SigningStrategyMinimal: {
          NSDictionary *ents = target.plannedEntitlements.rawEntitlements ?: [EntitlementSet minimalEntitlements];
          ok = [self signTarget:target.filePath withEntitlements:ents hasHelper:hasH opLog:opLog txnID:txnID];
          break;
      }
      case SigningStrategySkip:
          ok = YES;
          break;
      default: {
          NSDictionary *ents = target.plannedEntitlements.rawEntitlements ?: [EntitlementSet genericJailbreakEntitlements];
          ok = [self signTarget:target.filePath withEntitlements:ents hasHelper:hasH opLog:opLog txnID:txnID];
          break;
      }
  }

  if (!ok) {
      NSLog(@"[SmartSign] FAILED to sign: %@", target.targetName);
  } else {
      signedCount++;
  }

 }
 NSLog(@"[SmartSign] Total signed: %lu / %lu targets", (unsigned long)signedCount, (unsigned long)ordered.count);
 return signedCount;
}

- (BOOL)signTarget:(NSString *)path withEntitlements:(NSDictionary *)entitlements hasHelper:(BOOL)hasH opLog:(OperationLog *)opLog txnID:(NSString *)txnID {
 NSFileManager *fm = [NSFileManager defaultManager];
 if (![fm fileExistsAtPath:path]) return NO;
 NSString *recordID = [opLog beginPhase:OperationPhaseSign operation:@"smart-ldid" target:path input:@"" transactionID:txnID];
 NSString *entPath = nil;
 if (entitlements && entitlements.count > 0) {
 NSString *tmpDir = NSTemporaryDirectory();
 NSString *uuid = [[NSUUID UUID] UUIDString];
 entPath = [tmpDir stringByAppendingPathComponent:[NSString stringWithFormat:@"ent_%@.plist", uuid]];
 [entitlements writeToFile:entPath atomically:YES];
 }
 BOOL ok = NO;
 if (entPath) {
 NSString *sf = [NSString stringWithFormat:@"-S%@", entPath];
 ok = hasH ? [self runRoot:self.ldidPath args:@[sf, path] opLog:opLog recordID:recordID]
             : [self runCmd:self.ldidPath args:@[sf, path] opLog:opLog recordID:recordID];
 [fm removeItemAtPath:entPath error:nil];
 } else {
  // Match TrollStore's no-entitlement path: -s recursively signs the
  // bundle without fabricating an empty -S argument.
  ok = hasH ? [self runRoot:self.ldidPath args:@[@"-s", path] opLog:opLog recordID:recordID]
             : [self runCmd:self.ldidPath args:@[@"-s", path] opLog:opLog recordID:recordID];
 }
 [opLog endPhase:recordID exitCode:ok ? 0 : 1 rawOutput:@"" rawError:ok ? @"" : @"Smart sign failed" verification:@"smart ldid" verified:ok duration:0];
 return ok;
}


@end