#import "RuntimeDiagnostics.h"
#import "SPRootHide.h"
#import "OperationLog.h"
#import "RootlessManager.h"
#import "ExecutableValidator.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/types.h>
#import <signal.h>
#import <spawn.h>
#import <UIKit/UIKit.h>
#import <sys/wait.h>
#import <sys/sysctl.h>
#import "RuntimeEnvironment.h"

@implementation ProcessInfo
@end

@implementation RuntimeDiagnosticsResult

- (NSString *)detailedReport {
    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"\n=== Runtime Diagnostics Report ===\n"];
    [r appendFormat:@"Bundle ID: %@\n", self.bundleID ?: @"N/A"];
    [r appendFormat:@"State: %@\n", self.state ?: @"N/A"];
    [r appendFormat:@"\n--- Timing ---\n"];
    [r appendFormat:@"Launch requested: %@\n", self.launchRequestedAt ?: @"N/A"];
    [r appendFormat:@"Process detected: %@\n", self.processDetectedAt ?: @"N/A"];
    [r appendFormat:@"Process exit: %@\n", self.processExitAt ?: @"N/A"];
    [r appendFormat:@"Launch detection time: %.0f ms\n", self.launchDetectionTimeMs];
    [r appendFormat:@"Process lifetime: %.0f ms\n", self.processLifetimeMs];
    [r appendFormat:@"Monitoring window: %.0f ms\n", self.monitoringWindowMs];
    [r appendFormat:@"\n--- Process ---\n"];
    [r appendFormat:@"Detected: %@\n", self.processDetected ? @"YES" : @"NO"];
    [r appendFormat:@"PID: %d\n", self.pid];
    [r appendFormat:@"UID: %d\n", self.uid];
    [r appendFormat:@"GID: %d\n", self.gid];
    [r appendFormat:@"Remained alive: %@\n", self.processRemainedAlive ? @"YES" : @"NO"];
    [r appendFormat:@"\n--- Crash ---\n"];
    [r appendFormat:@"Crash detected: %@\n", self.crashDetected ? @"YES" : @"NO"];
    [r appendFormat:@"Termination reason: %@\n", self.terminationReason ?: @"N/A"];
    [r appendFormat:@"Crash report path: %@\n", self.crashReportPath ?: @"unavailable"];
    if (self.diagnosticOutput && self.diagnosticOutput.length > 0) {
        [r appendFormat:@"\n--- Diagnostic Output ---\n%@\n", self.diagnosticOutput];
    }
    [r appendFormat:@"\n=== End Report ===\n"];
    return r;
}

@end

@interface RuntimeDiagnostics ()
- (NSString *)findCrashReportForBundleID:(NSString *)bundleID processName:(NSString *)processName afterDate:(NSDate *)afterDate;
@end

@implementation RuntimeDiagnostics

+ (instancetype)sharedDiagnostics {
    static RuntimeDiagnostics *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _processDetectionTimeout = 5.0;
        _monitoringWindow = 10.0;
        _pollInterval = 0.5;
    }
    return self;
}

- (void)diagnoseAppLaunch:(NSString *)bundleID
           transactionID:(NSString *)txnID
            operationLog:(OperationLog *)opLog
              completion:(void (^)(RuntimeDiagnosticsResult *result))completion {
    NSDate *overallStart = [NSDate date];
    RuntimeDiagnosticsResult *result = [[RuntimeDiagnosticsResult alloc] init];
    result.bundleID = bundleID;
    result.state = @"NOT_STARTED";
    result.launchRequestedAt = [NSDate date];
    result.monitoringWindowMs = self.monitoringWindow * 1000.0;

    NSLog(@"[RuntimeDiagnostics] Starting diagnosis for %@", bundleID);

    NSString *recLaunch = [opLog beginPhase:OperationPhaseLaunch
                                  operation:@"launchApp"
                                     target:bundleID
                                      input:@""
                              transactionID:txnID];

    result.state = @"LAUNCH_REQUESTED";
    BOOL launched = [self launchAppWithBundleID:bundleID];
    NSTimeInterval launchDuration = [[NSDate date] timeIntervalSinceDate:result.launchRequestedAt] * 1000.0;

    [opLog endPhase:recLaunch
           exitCode:launched ? 0 : 1
          rawOutput:@""
           rawError:launched ? @"" : @"LSApplicationWorkspace openApplicationWithBundleID failed"
       verification:launched ? @"Launch request dispatched" : @"Launch request failed"
           verified:launched
           duration:launchDuration / 1000.0];

    if (!launched) {
        result.success = NO;
        result.state = @"LAUNCH_FAILED";
        result.summary = @"Launch request failed";
        if (completion) completion(result);
        return;
    }

    NSString *recDetect = [opLog beginPhase:OperationPhaseLaunch
                                  operation:@"processDetection"
                                     target:bundleID
                                      input:[NSString stringWithFormat:@"timeout=%.1fs", self.processDetectionTimeout]
                              transactionID:txnID];

    NSDate *detectStart = [NSDate date];
    ProcessInfo *proc = [self detectProcessForBundleID:bundleID timeout:self.processDetectionTimeout];
    result.launchDetectionTimeMs = [[NSDate date] timeIntervalSinceDate:detectStart] * 1000.0;
    result.processDetectedAt = proc ? [NSDate date] : nil;

    if (proc) {
        result.processDetected = YES;
        result.pid = proc.pid;
        result.uid = proc.uid;
        result.gid = proc.gid;
        result.appName = proc.name;
        result.executablePath = proc.executablePath;
        result.state = @"PROCESS_DETECTED";

        NSString *procInfo = [NSString stringWithFormat:@"PID=%d name=%@ UID=%d GID=%d path=%@",
                              proc.pid, proc.name, proc.uid, proc.gid, proc.executablePath ?: @"N/A"];

        [opLog endPhase:recDetect
               exitCode:0
              rawOutput:procInfo
               rawError:@""
           verification:[NSString stringWithFormat:@"Process detected in %.0f ms", result.launchDetectionTimeMs]
               verified:YES
               duration:result.launchDetectionTimeMs / 1000.0];

        NSLog(@"[RuntimeDiagnostics] Process detected: %@", procInfo);
    } else {
        result.processDetected = NO;
        result.state = @"PROCESS_NOT_DETECTED";
        result.success = NO;
        result.summary = [NSString stringWithFormat:@"Process not detected within %.1fs", self.processDetectionTimeout];

        [opLog endPhase:recDetect
               exitCode:1
              rawOutput:@""
               rawError:[NSString stringWithFormat:@"No process matching %@ found after %.1fs", bundleID, self.processDetectionTimeout]
           verification:@"Process detection timeout"
               verified:NO
               duration:result.launchDetectionTimeMs / 1000.0];

        if (completion) completion(result);
        return;
    }

    NSString *recMonitor = [opLog beginPhase:OperationPhaseRuntimeMonitor
                                   operation:@"runtimeMonitor"
                                      target:bundleID
                                       input:[NSString stringWithFormat:@"PID=%d window=%.1fs poll=%.1fs",
                                              result.pid, self.monitoringWindow, self.pollInterval]
                               transactionID:txnID];

    NSDate *monitorStart = [NSDate date];
    int exitStatus = 0;
    int signalNum = 0;
    BOOL stillAlive = [self monitorProcess:result.pid duration:self.monitoringWindow exitStatus:&exitStatus signalNum:&signalNum];
    NSTimeInterval monitorDuration = [[NSDate date] timeIntervalSinceDate:monitorStart] * 1000.0;

    if (!stillAlive) {
        result.processRemainedAlive = NO;
        result.processExitAt = [NSDate date];
        result.processLifetimeMs = monitorDuration;

        NSString *terminationReason = [self determineTerminationReason:result.pid
                                                               bundleID:bundleID
                                                              processName:proc.name
                                                              exitStatus:exitStatus
                                                               signalNum:signalNum];
        result.terminationReason = terminationReason;
        NSString *crashEvidencePath = [self findCrashReportForBundleID:bundleID processName:proc.name afterDate:result.launchRequestedAt];
        BOOL crashEvidenceFound = (crashEvidencePath.length > 0);
        if (crashEvidenceFound) result.crashReportPath = crashEvidencePath;
        
        NSString *state;
        NSString *terminationType;
        BOOL crashDetected = NO;
        int exitCodeForLog = 1;
        
        if (signalNum == SIGKILL) {
            state = @"KILLED_JETSAM";
            terminationType = @"Killed by SIGKILL";
            exitCodeForLog = 3;
            NSString *jetsam = [self findJetsamEventForProcessName:proc.name bundleID:bundleID];
            if (jetsam) {
                terminationType = @"Killed by Jetsam (out-of-memory)";
            }
        } else if (signalNum == SIGTERM) {
            state = @"KILLED";
            terminationType = @"Terminated by SIGTERM";
            exitCodeForLog = 3;
        } else if (signalNum != 0) {
            state = @"CRASHED";
            terminationType = [NSString stringWithFormat:@"Crashed by %@ (%d)", [self signalName:signalNum], signalNum];
            crashDetected = YES;
            exitCodeForLog = 2;
        } else if (crashEvidenceFound) {
            state = @"CRASHED";
            terminationType = [NSString stringWithFormat:@"Crash report found after process disappearance: %@", crashEvidencePath.lastPathComponent ?: @"unknown report"];
            crashDetected = YES;
            exitCodeForLog = 2;
        } else if (exitStatus == 0) {
            state = @"EXITED_NORMAL";
            terminationType = @"Exited normally (status 0)";
            exitCodeForLog = 1;
        } else if (exitStatus > 0) {
            state = @"EXITED_WITH_ERROR";
            terminationType = [NSString stringWithFormat:@"Exited with error status %d", exitStatus];
            exitCodeForLog = 1;
        } else {
            state = @"EXITED_NORMAL";
            terminationType = @"Exited (no crash signal detected)";
            exitCodeForLog = 1;
        }
        
        result.crashDetected = crashDetected;
        result.state = state;
        result.terminationReason = terminationType;
        result.success = NO;
        result.summary = [NSString stringWithFormat:@"%@ after %.0f ms", terminationType, monitorDuration];
        
        [opLog endPhase:recMonitor
               exitCode:exitCodeForLog
              rawOutput:[NSString stringWithFormat:@"lifetime=%.0fms exitStatus=%d signal=%d state=%@", monitorDuration, exitStatus, signalNum, state]
               rawError:terminationType
           verification:[NSString stringWithFormat:@"Process %@ after %.0f ms", state, monitorDuration]
               verified:NO
               duration:monitorDuration / 1000.0];
        
        NSLog(@"[RuntimeDiagnostics] Process %@ after %.0f ms (exit=%d signal=%d)", state, monitorDuration, exitStatus, signalNum);

        NSString *recCrash = [opLog beginPhase:OperationPhaseCrashDiagnostics
                                      operation:@"crashDiagnostics"
                                         target:bundleID
                                          input:[NSString stringWithFormat:@"PID=%d exitStatus=%d signal=%d", result.pid, exitStatus, signalNum]
                                  transactionID:txnID];

        NSMutableString *diagnosticOutput = [NSMutableString string];

        NSString *crashPath = [self findCrashReportForBundleID:bundleID processName:proc.name afterDate:result.launchRequestedAt];
        if (crashPath) {
            result.crashReportPath = crashPath;
            NSString *crashContent = [NSString stringWithContentsOfFile:crashPath encoding:NSUTF8StringEncoding error:nil];
            if (crashContent) {
                [diagnosticOutput appendFormat:@"=== Crash Report (%@) ===\n%@\n\n", crashPath, crashContent];
            }
        }

        NSString *jetsamInfo = [self findJetsamEventForProcessName:proc.name bundleID:bundleID];
        if (jetsamInfo) {
            [diagnosticOutput appendFormat:@"=== Jetsam Event ===\n%@\n\n", jetsamInfo];
        }

        NSString *syslogEntries = [self getSyslogForProcess:proc.name pid:result.pid bundleID:bundleID];
        if (syslogEntries) {
            [diagnosticOutput appendFormat:@"=== Syslog Entries ===\n%@\n\n", syslogEntries];
        }

        NSString *launchdLog = [self getLaunchdLogForBundleID:bundleID];
        if (launchdLog) {
            [diagnosticOutput appendFormat:@"=== Launchd Log ===\n%@\n\n", launchdLog];
        }

        NSString *unifiedLog = [self getUnifiedLogForBundleID:bundleID processName:proc.name];
        if (unifiedLog) {
            [diagnosticOutput appendFormat:@"=== Unified Log ===\n%@\n\n", unifiedLog];
        }

        NSString *exitAnalysis = [self analyzeExitStatus:exitStatus signalNum:signalNum];
        [diagnosticOutput appendFormat:@"=== Exit Status Analysis ===\n%@\n", exitAnalysis];

        result.diagnosticOutput = diagnosticOutput;

        BOOL hasAnyDiagnostic = (diagnosticOutput.length > 0);
        [opLog endPhase:recCrash
               exitCode:hasAnyDiagnostic ? 0 : 1
              rawOutput:diagnosticOutput
               rawError:hasAnyDiagnostic ? @"" : @"No diagnostic sources produced output"
           verification:[NSString stringWithFormat:@"Checked: CrashReporter, Jetsam, Syslog, Launchd, UnifiedLogs. Found: %@", hasAnyDiagnostic ? @"YES" : @"NO"]
               verified:hasAnyDiagnostic
               duration:0];

        NSLog(@"[RuntimeDiagnostics] Crash diagnostics complete. Sources found: %@", hasAnyDiagnostic ? @"YES" : @"NO");
    } else {
        result.processRemainedAlive = YES;
        result.processLifetimeMs = monitorDuration;
        result.state = @"RUNNING";
        result.success = YES;
        result.terminationReason = @"";
        result.summary = [NSString stringWithFormat:@"Process remained alive for full %.0f ms window", monitorDuration];

        [opLog endPhase:recMonitor
               exitCode:0
              rawOutput:[NSString stringWithFormat:@"alive_after=%.0fms", monitorDuration]
               rawError:@""
           verification:[NSString stringWithFormat:@"Process remained alive for full %.0f ms monitoring window", monitorDuration]
               verified:YES
               duration:monitorDuration / 1000.0];

        NSLog(@"[RuntimeDiagnostics] Process remained alive for %.0f ms", monitorDuration);
    }

    NSTimeInterval overallDuration = [[NSDate date] timeIntervalSinceDate:overallStart] * 1000.0;
    NSLog(@"[RuntimeDiagnostics] Complete for %@ in %.0f ms — State: %@", bundleID, overallDuration, result.state);

    if (completion) completion(result);
}

- (BOOL)launchAppWithBundleID:(NSString *)bundleID {
    @try {
        Class LSClass = objc_getClass([@"LSApplicationWorkspace" UTF8String]);
        if (!LSClass) {
            NSLog(@"[RuntimeDiagnostics] LSApplicationWorkspace not available");
            return NO;
        }
        id workspace = ((id (*)(Class, SEL))objc_msgSend)(LSClass, NSSelectorFromString(@"defaultWorkspace"));
        if (!workspace) {
            NSLog(@"[RuntimeDiagnostics] defaultWorkspace returned nil");
            return NO;
        }
        SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
        if ([workspace respondsToSelector:openSel]) {
            BOOL opened = ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(workspace, openSel, bundleID);
            NSLog(@"[RuntimeDiagnostics] openApplicationWithBundleID:%@ returned %d", bundleID, opened);
            return opened;
        }
        NSString *urlScheme = [NSString stringWithFormat:@"%@://", bundleID];
        NSURL *url = [NSURL URLWithString:urlScheme];
        if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            NSLog(@"[RuntimeDiagnostics] Launched via URL scheme: %@", urlScheme);
            return YES;
        }
        NSLog(@"[RuntimeDiagnostics] No launch method available for %@", bundleID);
        return NO;
    } @catch (NSException *e) {
        NSLog(@"[RuntimeDiagnostics] Launch exception: %@", e.reason);
        return NO;
    }
}

- (ProcessInfo *)detectProcessForBundleID:(NSString *)bundleID timeout:(NSTimeInterval)timeout {
    NSDate *start = [NSDate date];
    NSString *exeName = [self extractExecutableNameFromBundleID:bundleID];
    while ([[NSDate date] timeIntervalSinceDate:start] < timeout) {
        ProcessInfo *proc = [self findProcessMatchingBundleID:bundleID exeName:exeName];
        if (proc) return proc;
        [NSThread sleepForTimeInterval:self.pollInterval];
    }
    return nil;
}

- (NSString *)extractExecutableNameFromBundleID:(NSString *)bundleID {
    NSString *appPath = [self findAppPathForBundleID:bundleID];
    if (appPath) {
        NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        NSString *exeName = info[@"CFBundleExecutable"];
        if (exeName) return exeName;
    }
    NSArray *parts = [bundleID componentsSeparatedByString:@"."];
    return parts.lastObject ?: bundleID;
}

- (NSString *)findAppPathForBundleID:(NSString *)bundleID {
    RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];
    NSMutableArray *searchPaths = [NSMutableArray arrayWithObject:@"/Applications"];
    if (rt.bootstrapPath) {
        [searchPaths insertObject:[rt.bootstrapPath stringByAppendingPathComponent:@"Applications"] atIndex:0];
    } else {
        [searchPaths insertObject:@"/var/jb/Applications" atIndex:0];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *base in searchPaths) {
        NSArray *items = [fm contentsOfDirectoryAtPath:base error:nil];
        for (NSString *item in items) {
            if ([item hasSuffix:@".app"]) {
                NSString *appPath = [base stringByAppendingPathComponent:item];
                NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
                if ([info[@"CFBundleIdentifier"] isEqualToString:bundleID]) {
                    return appPath;
                }
            }
        }
    }
    return nil;
}

- (ProcessInfo *)findProcessMatchingBundleID:(NSString *)bundleID exeName:(NSString *)exeName {
    NSString *psPath = [[ExecutableValidator sharedValidator] findExecutableNamed:@"ps"];
    NSString *psOutput = nil;
    if (psPath) psOutput = [self runCmdOutput:psPath args:@[@"-eo", @"pid,uid,gid,comm"]];
    if (!psOutput) psOutput = [self runCmdOutput:@"/bin/ps" args:@[@"-eo", @"pid,uid,gid,comm"]];
    if (!psOutput) return nil;

    NSArray *lines = [psOutput componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;
        NSArray *parts = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *cleanParts = [NSMutableArray array];
        for (NSString *p in parts) {
            if (p.length > 0) [cleanParts addObject:p];
        }
        if (cleanParts.count >= 4) {
            NSString *pidStr = cleanParts[0];
            NSString *uidStr = cleanParts[1];
            NSString *gidStr = cleanParts[2];
            NSString *comm = cleanParts[3];
            if ([comm isEqualToString:exeName] || [comm isEqualToString:bundleID] || [comm containsString:exeName]) {
                pid_t pid = [pidStr intValue];
                if (pid > 0 && [self isProcessAlive:pid]) {
                    ProcessInfo *info = [[ProcessInfo alloc] init];
                    info.pid = pid;
                    info.uid = [uidStr intValue];
                    info.gid = [gidStr intValue];
                    info.name = comm;
                    info.startTime = [NSDate date];
                    return info;
                }
            }
        }
    }
    return nil;
}

- (BOOL)monitorProcess:(pid_t)pid duration:(NSTimeInterval)duration exitStatus:(int *)exitStatus signalNum:(int *)signalNum {
    NSDate *start = [NSDate date];
    *exitStatus = 0;
    *signalNum = 0;

    while ([[NSDate date] timeIntervalSinceDate:start] < duration) {
        if (![self isProcessAlive:pid]) {
            int status;
            pid_t result = waitpid(pid, &status, WNOHANG);
            if (result == pid) {
                if (WIFEXITED(status)) {
                    *exitStatus = WEXITSTATUS(status);
                }
                if (WIFSIGNALED(status)) {
                    *signalNum = WTERMSIG(status);
                }
            }
            return NO;
        }
        [NSThread sleepForTimeInterval:self.pollInterval];
    }
    return [self isProcessAlive:pid];
}

- (BOOL)isProcessAlive:(pid_t)pid {
    return (kill(pid, 0) == 0);
}

- (NSString *)determineTerminationReason:(pid_t)pid bundleID:(NSString *)bundleID processName:(NSString *)processName exitStatus:(int)exitStatus signalNum:(int)signalNum {
    NSMutableString *reason = [NSMutableString string];

    if (signalNum != 0) {
        NSString *signalName = [self signalName:signalNum];
        [reason appendFormat:@"Terminated by signal %d (%@). ", signalNum, signalName];

        if (signalNum == SIGKILL) {
            NSString *jetsam = [self findJetsamEventForProcessName:processName bundleID:bundleID];
            if (jetsam) {
                [reason appendFormat:@"SIGKILL detected — possible Jetsam/OOM kill. %@", jetsam];
            } else {
                [reason appendString:@"SIGKILL detected — could be Jetsam (out-of-memory), manual kill, or system termination."];
            }
        } else if (signalNum == SIGABRT) {
            [reason appendString:@"SIGABRT — assertion failure or abort() called."];
        } else if (signalNum == SIGSEGV) {
            [reason appendString:@"SIGSEGV — segmentation fault (memory access violation)."];
        } else if (signalNum == SIGBUS) {
            [reason appendString:@"SIGBUS — bus error (misaligned memory access)."];
        } else if (signalNum == SIGILL) {
            [reason appendString:@"SIGILL — illegal instruction (corrupted binary or architecture mismatch)."];
        } else if (signalNum == SIGTRAP) {
            [reason appendString:@"SIGTRAP — breakpoint/trap (debugger or runtime check)."];
        }
    } else if (exitStatus != 0) {
        [reason appendFormat:@"Exited with status %d. ", exitStatus];
        if (exitStatus == 1) {
            [reason appendString:@"General error exit."];
        } else if (exitStatus == 255) {
            [reason appendString:@"Exit code 255 — typically indicates launch failure or dylib loading issue."];
        }
    } else {
        [reason appendString:@"Exited with status 0 (normal exit) — but process terminated unexpectedly during monitoring."];
    }

    NSString *crashPath = [self findCrashReportForBundleID:bundleID processName:processName];
    if (crashPath) {
        [reason appendFormat:@" Crash report found at: %@", crashPath];
    } else {
        [reason appendString:@" No crash report found in standard locations."];
    }

    return reason;
}

- (NSString *)signalName:(int)signalNum {
    switch (signalNum) {
        case SIGHUP: return @"SIGHUP";
        case SIGINT: return @"SIGINT";
        case SIGQUIT: return @"SIGQUIT";
        case SIGILL: return @"SIGILL";
        case SIGTRAP: return @"SIGTRAP";
        case SIGABRT: return @"SIGABRT";
        case SIGBUS: return @"SIGBUS";
        case SIGFPE: return @"SIGFPE";
        case SIGKILL: return @"SIGKILL";
        case SIGSEGV: return @"SIGSEGV";
        case SIGTERM: return @"SIGTERM";
        default: return @"UNKNOWN";
    }
}

- (NSString *)findCrashReportForBundleID:(NSString *)bundleID processName:(NSString *)processName {
    return [self findCrashReportForBundleID:bundleID processName:processName afterDate:nil];
}

- (NSString *)findCrashReportForBundleID:(NSString *)bundleID processName:(NSString *)processName afterDate:(NSDate *)afterDate {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSArray *searchPaths = @[
        @"/var/mobile/Library/Logs/CrashReporter",
        @"/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs",
        @"/var/mobile/Library/Logs/CrashReporter/Panics",
        @"/var/mobile/Library/Logs/CrashReporter/CoreCapture"
    ];

    NSDate *now = [NSDate date];
    NSString *latestPath = nil;
    NSDate *latestDate = nil;

    for (NSString *basePath in searchPaths) {
        if (![fm fileExistsAtPath:basePath]) continue;

        NSArray *items = [fm contentsOfDirectoryAtPath:basePath error:nil];
        for (NSString *item in items) {
            BOOL matches = NO;
            if (bundleID && [item containsString:bundleID]) matches = YES;
            if (processName && [item containsString:processName]) matches = YES;

            if (matches && ([item hasSuffix:@".ips"] || [item hasSuffix:@".crash"])) {
                NSString *fullPath = [basePath stringByAppendingPathComponent:item];
                NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
                NSDate *modDate = attrs[NSFileModificationDate];

                if (modDate && [now timeIntervalSinceDate:modDate] < 300 &&
                    (!afterDate || [modDate compare:afterDate] != NSOrderedAscending)) {
                    if (!latestDate || [modDate compare:latestDate] == NSOrderedDescending) {
                        latestDate = modDate;
                        latestPath = fullPath;
                    }
                }
            }
        }
    }

    return latestPath;
}

- (NSString *)findJetsamEventForProcessName:(NSString *)processName bundleID:(NSString *)bundleID {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *jetsamPath = @"/var/mobile/Library/Logs/CrashReporter/JetsamEvent";

    if (![fm fileExistsAtPath:jetsamPath]) {
        return nil;
    }

    NSArray *items = [fm contentsOfDirectoryAtPath:jetsamPath error:nil];
    NSDate *now = [NSDate date];
    NSString *latestMatch = nil;
    NSDate *latestDate = nil;

    for (NSString *item in items) {
        if ([item hasSuffix:@".ips"]) {
            NSString *fullPath = [jetsamPath stringByAppendingPathComponent:item];
            NSString *content = [NSString stringWithContentsOfFile:fullPath encoding:NSUTF8StringEncoding error:nil];

            if (content && processName && [content containsString:processName]) {
                NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
                NSDate *modDate = attrs[NSFileModificationDate];
                if (modDate && [now timeIntervalSinceDate:modDate] < 300) {
                    if (!latestDate || [modDate compare:latestDate] == NSOrderedDescending) {
                        latestDate = modDate;
                        latestMatch = fullPath;
                    }
                }
            }
        }
    }

    if (latestMatch) {
        NSString *content = [NSString stringWithContentsOfFile:latestMatch encoding:NSUTF8StringEncoding error:nil];
        if (content) {
            NSArray *lines = [content componentsSeparatedByString:@"\n"];
            NSMutableString *relevant = [NSMutableString string];
            for (NSString *line in lines) {
                if (processName && [line containsString:processName]) {
                    [relevant appendFormat:@"%@\n", line];
                }
            }
            if (relevant.length > 0) {
                return [NSString stringWithFormat:@"Jetsam report: %@\nRelevant entries:\n%@", latestMatch, relevant];
            }
        }
    }

    return nil;
}

- (NSString *)getSyslogForProcess:(NSString *)processName pid:(pid_t)pid bundleID:(NSString *)bundleID {
    NSString *syslogPath = @"/var/log/syslog";
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:syslogPath]) {
        RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];
        if (rt.bootstrapPath) {
            syslogPath = [rt.bootstrapPath stringByAppendingPathComponent:@"var/log/syslog"];
        } else {
            syslogPath = @"/var/jb/var/log/syslog";
        }
        if (![fm fileExistsAtPath:syslogPath]) {
            return nil;
        }
    }

    NSString *tailPath = [[ExecutableValidator sharedValidator] findExecutableNamed:@"tail"];
    if (!tailPath) tailPath = @"/usr/bin/tail";
    NSString *tailOutput = [self runCmdOutput:tailPath args:@[@"-n", @"50", syslogPath]];
    if (!tailOutput) return nil;

    NSArray *lines = [tailOutput componentsSeparatedByString:@"\n"];
    NSMutableString *relevant = [NSMutableString string];

    for (NSString *line in lines) {
        if ((processName && [line containsString:processName]) ||
            (bundleID && [line containsString:bundleID]) ||
            [line containsString:[NSString stringWithFormat:@"[%d]", pid]]) {
            [relevant appendFormat:@"%@\n", line];
        }
    }

    return relevant.length > 0 ? relevant : nil;
}

- (NSString *)getLaunchdLogForBundleID:(NSString *)bundleID {
    NSString *launchdLog = @"/var/log/launchd.log";
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:launchdLog]) {
        return nil;
    }

    NSString *tailPath2 = [[ExecutableValidator sharedValidator] findExecutableNamed:@"tail"];
    if (!tailPath2) tailPath2 = @"/usr/bin/tail";
    NSString *tailOutput = [self runCmdOutput:tailPath2 args:@[@"-n", @"30", launchdLog]];
    if (!tailOutput) return nil;

    NSArray *lines = [tailOutput componentsSeparatedByString:@"\n"];
    NSMutableString *relevant = [NSMutableString string];

    for (NSString *line in lines) {
        if ([line containsString:bundleID]) {
            [relevant appendFormat:@"%@\n", line];
        }
    }

    return relevant.length > 0 ? relevant : nil;
}

- (NSString *)getUnifiedLogForBundleID:(NSString *)bundleID processName:(NSString *)processName {
    NSString *logOutput = [self runCmdOutput:@"/usr/bin/log" args:@[@"show", @"--last", @"2m", @"--predicate", [NSString stringWithFormat:@"subsystem == \"%@\" OR process == \"%@\"", bundleID, processName ?: bundleID]]];

    if (!logOutput || logOutput.length == 0) {
        logOutput = [self runCmdOutput:@"/usr/bin/log" args:@[@"show", @"--last", @"1m"]];
    }

    if (!logOutput || logOutput.length == 0) {
        return nil;
    }

    NSArray *lines = [logOutput componentsSeparatedByString:@"\n"];
    NSMutableString *relevant = [NSMutableString string];

    for (NSString *line in lines) {
        if ([line containsString:bundleID] || (processName && [line containsString:processName])) {
            [relevant appendFormat:@"%@\n", line];
        }
    }

    return relevant.length > 0 ? relevant : nil;
}

- (NSString *)analyzeExitStatus:(int)exitStatus signalNum:(int)signalNum {
    NSMutableString *analysis = [NSMutableString string];

    [analysis appendFormat:@"Exit status: %d\n", exitStatus];
    [analysis appendFormat:@"Signal: %d (%@)\n", signalNum, [self signalName:signalNum]];

    if (signalNum == SIGKILL) {
        [analysis appendString:@"\nSIGKILL analysis:\n"];
        [analysis appendString:@"- Jetsam (out-of-memory): Check JetsamEvent logs\n"];
        [analysis appendString:@"- Manual kill: User or another process sent SIGKILL\n"];
        [analysis appendString:@"- System termination: launchd or watchdog terminated the process\n"];
    } else if (signalNum == SIGABRT) {
        [analysis appendString:@"\nSIGABRT analysis:\n"];
        [analysis appendString:@"- Assertion failure (NSAssert, assert())\n"];
        [analysis appendString:@"- Uncaught exception\n"];
        [analysis appendString:@"- abort() called intentionally\n"];
    } else if (signalNum == SIGSEGV) {
        [analysis appendString:@"\nSIGSEGV analysis:\n"];
        [analysis appendString:@"- Dereferencing null pointer\n"];
        [analysis appendString:@"- Buffer overflow\n"];
        [analysis appendString:@"- Use-after-free\n"];
        [analysis appendString:@"- Stack overflow\n"];
    } else if (exitStatus == 255) {
        [analysis appendString:@"\nExit 255 analysis:\n"];
        [analysis appendString:@"- Dylib loading failure (injection tool incompatibility)\n"];
        [analysis appendString:@"- Launchd failed to start the process\n"];
        [analysis appendString:@"- Missing or corrupted executable\n"];
    }

    return analysis;
}

- (NSString *)runCmdOutput:(NSString *)cmd args:(NSArray *)args {
    if (!cmd || cmd.length == 0) return nil;
    args = SPToolArguments(cmd, args);

    int outPipe[2];
    if (pipe(outPipe) != 0) return nil;

    pid_t pid;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outPipe[1]);

    const char *c = [cmd UTF8String];
    char **argv = malloc((args.count + 2) * sizeof(char*));
    argv[0] = (char*)c;
    for (NSUInteger i = 0; i < args.count; i++) argv[i+1] = (char*)[args[i] UTF8String];
    argv[args.count + 1] = NULL;

    extern char **environ;
    int st = posix_spawn(&pid, c, &actions, NULL, argv, environ);
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    close(outPipe[1]);

    if (st != 0) { close(outPipe[0]); return nil; }

    NSMutableString *output = [NSMutableString string];
    char buf[4096];
    ssize_t n;
    while ((n = read(outPipe[0], buf, sizeof(buf) - 1)) > 0) {
        buf[n] = '\0';
        [output appendString:[NSString stringWithUTF8String:buf]];
    }
    close(outPipe[0]);

    int ws;
    waitpid(pid, &ws, 0);

    return output;
}

@end
