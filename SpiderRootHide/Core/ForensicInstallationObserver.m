#import "ForensicInstallationObserver.h"
#import "ForensicTypes.h"
#import "OperationLog.h"
#include <sys/stat.h>
#include <unistd.h>
#include <limits.h>
#include <stdlib.h>
#import "RuntimeEnvironment.h"

@interface ForensicInstallationObserver ()
@property (nonatomic, assign, readwrite, getter=isObserving) BOOL observing;
@property (nonatomic, strong, readwrite) ForensicTransactionReport *currentReport;
@property (nonatomic, strong) OperationLog *operationLog;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ForensicEvent *> *eventsByRecordID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *lastFactsByPath;
@property (nonatomic, assign) ForensicInstallState currentState;
@end

@implementation ForensicInstallationObserver

- (instancetype)init {
    self = [super init];
    if (self) {
        _eventsByRecordID = [NSMutableDictionary dictionary];
        _lastFactsByPath = [NSMutableDictionary dictionary];
        _currentState = ForensicInstallStateUnknown;
    }
    return self;
}

- (void)beginObservingTransaction:(NSString *)transactionID
                          ipaPath:(NSString *)ipaPath
                         bundleID:(NSString *)bundleID
                         operationLog:(OperationLog *)operationLog {
    [self finishObservation];
    if (!transactionID.length || !operationLog) return;

    self.operationLog = operationLog;
    self.eventsByRecordID = [NSMutableDictionary dictionary];
    self.lastFactsByPath = [NSMutableDictionary dictionary];
    self.currentState = ForensicInstallStateBegun;

    ForensicTransactionReport *report = [[ForensicTransactionReport alloc] init];
    report.transactionID = transactionID;
    report.ipaPath = ipaPath ?: @"";
    report.bundleID = bundleID ?: @"";
    report.finalState = ForensicInstallStateBegun;
    report.productionPathTouched = NO;
    report.events = @[];
    report.evidence = @{
        @"mode": @"passive-observer",
        @"mutatesFilesystem": @NO,
        @"invokesInstaller": @NO,
        @"invokesSigning": @NO,
        @"invokesUICache": @NO,
        @"stateContract": @[@"EXTRACTED", @"INSTALLED", @"REGISTERED", @"LAUNCHABLE", @"RUNNING"]
    };
    self.currentReport = report;
    self.observing = YES;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(recordAdded:) name:@"OperationRecordAdded" object:nil];
    [center addObserver:self selector:@selector(recordUpdated:) name:@"OperationRecordUpdated" object:nil];

    NSArray<OperationRecord *> *existing = [operationLog recordsForTransaction:transactionID];
    for (OperationRecord *record in existing) [self consumeRecord:record];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (ForensicTransactionReport *)finishObservation {
    if (self.observing && self.operationLog && self.currentReport.transactionID.length > 0) {
        NSArray<OperationRecord *> *finalRecords = [self.operationLog recordsForTransaction:self.currentReport.transactionID];
        for (OperationRecord *record in finalRecords) [self consumeRecord:record];
    }
    if (self.observing) [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.observing = NO;
    if (!self.currentReport) return nil;
    self.currentReport.events = [[self.eventsByRecordID.allValues sortedArrayUsingComparator:^NSComparisonResult(ForensicEvent *a, ForensicEvent *b) {
        return [a.startedAt compare:b.startedAt];
    }] copy];
    self.currentReport.finalState = self.currentState;
    self.currentReport = self.currentReport;
    return self.currentReport;
}

- (void)recordAdded:(NSNotification *)notification {
    OperationRecord *record = notification.object;
    if ([record isKindOfClass:[OperationRecord class]]) [self consumeRecord:record];
}

- (void)recordUpdated:(NSNotification *)notification {
    OperationRecord *record = notification.object;
    if ([record isKindOfClass:[OperationRecord class]]) [self consumeRecord:record];
}

- (BOOL)recordBelongsToCurrentTransaction:(OperationRecord *)record {
    return self.observing && record.transactionID.length > 0 && [record.transactionID isEqualToString:self.currentReport.transactionID];
}

- (ForensicInstallState)stateForRecord:(OperationRecord *)record result:(ForensicEventResult *)resultOut {
    BOOL isStalePending = NO;
    if (record.result == OperationResultPending && record.timestamp) {
        if ([[NSDate date] timeIntervalSinceDate:record.timestamp] > 600) isStalePending = YES;
        if (record.phase == OperationPhaseComplete && record.exitCode == -1) isStalePending = YES;
    }
    BOOL isPendingBegin = ((record.result == OperationResultPending || record.exitCode == -1) && record.rawOutput.length == 0 && record.rawError.length == 0) && !isStalePending;
    BOOL successful = record.verified && record.exitCode == 0 && record.result != OperationResultFailed;
    ForensicEventResult result = isPendingBegin ? ForensicEventResultPending : (successful ? ForensicEventResultSuccess : (record.result == OperationResultPartial ? ForensicEventResultPartial : ForensicEventResultFailure));
    ForensicInstallState state = isPendingBegin ? self.currentState : self.currentState;
    NSString *op = record.operation.lowercaseString ?: @"";
    if (isPendingBegin) {
        if (state == ForensicInstallStateUnknown) state = ForensicInstallStateBegun;
        if (resultOut) *resultOut = ForensicEventResultPending;
        return state;
    }

    if (record.phase == OperationPhaseIPAOpen) state = successful ? ForensicInstallStateInputInspected : ForensicInstallStateFailed;
    else if (record.phase == OperationPhaseIPAExtract) state = successful ? ForensicInstallStateExtracted : ForensicInstallStateFailed;
    else if (record.phase == OperationPhaseAppIdentify) state = successful ? ForensicInstallStateBundleDiscovered : ForensicInstallStateFailed;
    else if (record.phase == OperationPhaseFileCopy) {
        if ([op containsString:@"promote"] && successful) state = ForensicInstallStateInstalled;
        else if (!successful) state = ForensicInstallStateFailed;
    } else if (record.phase == OperationPhaseFramework || record.phase == OperationPhaseDylib) {
        if (!successful) state = ForensicInstallStateFailed;
    } else if (record.phase == OperationPhaseSign || record.phase == OperationPhasePermission) {
        if (!successful) state = ForensicInstallStateFailed;
        else if (state < ForensicInstallStateMachOAnalyzed) state = ForensicInstallStateMachOAnalyzed;
    } else if (record.phase == OperationPhaseUICache) {
        if ([op hasPrefix:@"forensic "]) state = self.currentState;
        else state = successful ? ForensicInstallStateRegistered : ForensicInstallStateFailed;
    } else if (record.phase == OperationPhaseVerify) {
        if ([op containsString:@"launch readiness"] || [op containsString:@"launchable"]) state = successful ? ForensicInstallStateLaunchable : ForensicInstallStateFailed;
        else if ([op containsString:@"rollback"] && successful) state = ForensicInstallStateRolledBack;
    } else if (record.phase == OperationPhaseLaunch) {
        if ([op containsString:@"process"] && successful) state = ForensicInstallStateRunning;
        else state = successful ? ForensicInstallStateLaunchable : ForensicInstallStateFailed;
    } else if (record.phase == OperationPhaseRuntimeMonitor) {
        if ([record.verification.lowercaseString containsString:@"crashed"] || [record.rawOutput.lowercaseString containsString:@"state=crashed"]) state = ForensicInstallStateCrashed;
        else if (successful) state = ForensicInstallStateRunning;
        else state = ForensicInstallStateExited;
    } else if (record.phase == OperationPhaseCrashDiagnostics) {
        if (record.verified && record.rawOutput.length > 0) result = ForensicEventResultObserved;
        if ([record.rawOutput.lowercaseString containsString:@"crash report"] || [record.rawOutput.lowercaseString containsString:@"exception"]) state = ForensicInstallStateCrashed;
    } else if (record.phase == OperationPhaseCleanup && successful && [op containsString:@"rollback"]) {
        state = ForensicInstallStateRolledBack;
    }

    if (!successful && record.exitCode != -1 && record.phase != OperationPhaseCrashDiagnostics) result = ForensicEventResultFailure;
    if (resultOut) *resultOut = result;
    return state;
}

- (NSString *)resolvedPathForTarget:(NSString *)target {
    if (!target.length) return @"";
    char resolved[PATH_MAX] = {0};
    if (realpath(target.fileSystemRepresentation, resolved)) return [NSString stringWithUTF8String:resolved] ?: target;
    return target;
}

- (NSDictionary *)factForPath:(NSString *)path {
    if (!path.length) return nil;
    struct stat st = {0};
    if (lstat(path.fileSystemRepresentation, &st) != 0) return nil;
    NSString *type = S_ISDIR(st.st_mode) ? @"directory" : (S_ISREG(st.st_mode) ? @"file" : (S_ISLNK(st.st_mode) ? @"symlink" : @"other"));
    return @{
        @"path": path,
        @"type": type,
        @"mode": @(st.st_mode & 07777),
        @"uid": @(st.st_uid),
        @"gid": @(st.st_gid),
        @"size": @((unsigned long long)st.st_size),
        @"inode": @((unsigned long long)st.st_ino),
        @"mtime": @((double)st.st_mtimespec.tv_sec + ((double)st.st_mtimespec.tv_nsec / 1000000000.0))
    };
}

- (NSDictionary<NSString *, NSDictionary *> *)factsUnderTarget:(NSString *)target {
    if (!target.length) return @{};
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableDictionary *facts = [NSMutableDictionary dictionary];
    NSDictionary *rootFact = [self factForPath:target];
    if (rootFact) facts[target] = rootFact;
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:target isDirectory:&isDirectory] || !isDirectory) return facts;

    NSArray<NSString *> *subpaths = [fm subpathsAtPath:target] ?: @[];
    NSUInteger limit = MIN(subpaths.count, 10000);
    for (NSUInteger i = 0; i < limit; i++) {
        NSString *full = [target stringByAppendingPathComponent:subpaths[i]];
        NSDictionary *fact = [self factForPath:full];
        if (fact) facts[full] = fact;
    }
    if (subpaths.count > limit) facts[[target stringByAppendingPathComponent:@".__FORENSIC_TRUNCATED__"]] = @{@"count": @(subpaths.count - limit)};
    return facts;
}

- (void)diffFactsBefore:(NSDictionary<NSString *, NSDictionary *> *)before
                  after:(NSDictionary<NSString *, NSDictionary *> *)after
                created:(NSArray<NSString *> **)created
                changed:(NSArray<NSString *> **)changed
                removed:(NSArray<NSString *> **)removed {
    NSMutableArray *newPaths = [NSMutableArray array];
    NSMutableArray *changedPaths = [NSMutableArray array];
    NSMutableArray *removedPaths = [NSMutableArray array];
    NSMutableSet *keys = [NSMutableSet setWithArray:before.allKeys];
    [keys addObjectsFromArray:after.allKeys];
    for (NSString *path in keys) {
        NSDictionary *oldFact = before[path];
        NSDictionary *newFact = after[path];
        if (!oldFact && newFact) [newPaths addObject:path];
        else if (oldFact && !newFact) [removedPaths addObject:path];
        else if (oldFact && newFact && ![oldFact isEqual:newFact]) [changedPaths addObject:path];
    }
    [newPaths sortUsingSelector:@selector(compare:)];
    [changedPaths sortUsingSelector:@selector(compare:)];
    [removedPaths sortUsingSelector:@selector(compare:)];
    if (created) *created = newPaths;
    if (changed) *changed = changedPaths;
    if (removed) *removed = removedPaths;
}

- (void)consumeRecord:(OperationRecord *)record {
    if (![self recordBelongsToCurrentTransaction:record]) return;
    ForensicEvent *event = self.eventsByRecordID[record.recordID];
    BOOL firstObservation = (event == nil);
    if (firstObservation) {
        event = [ForensicEvent eventWithTransactionID:record.transactionID operation:record.operation];
        event.phase = [record phaseName];
        event.startedAt = record.timestamp ?: [NSDate date];
        event.stateBefore = self.currentState;
        self.eventsByRecordID[record.recordID] = event;
    }

    ForensicEventResult eventResult = ForensicEventResultPending;
    ForensicInstallState nextState = [self stateForRecord:record result:&eventResult];
    NSString *target = record.target ?: @"";
    NSDictionary *beforeFacts = self.lastFactsByPath[target] ?: @{};
    NSDictionary *afterFacts = [self factsUnderTarget:target];
    NSArray *created = nil, *changed = nil, *removed = nil;
    [self diffFactsBefore:beforeFacts after:afterFacts created:&created changed:&changed removed:&removed];
    if (target.length) self.lastFactsByPath[target] = afterFacts;

    event.operation = record.operation ?: @"";
    event.phase = [record phaseName];
    event.target = target;
    RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];
    NSString *appsPath = rt.bootstrapPath ? [rt.bootstrapPath stringByAppendingPathComponent:@"Applications"] : @"/var/jb/Applications";
    event.logicalPath = ([target hasPrefix:@"/Applications"] || [target hasPrefix:appsPath]) ? target : @"";
    event.resolvedPath = [self resolvedPathForTarget:target];
    event.bundleID = self.currentReport.bundleID ?: @"";
    event.startedAt = record.timestamp ?: event.startedAt;
    event.endedAt = [event.startedAt dateByAddingTimeInterval:MAX(0, record.duration)];
    event.stateAfter = nextState;
    event.result = eventResult;
    event.exitStatus = record.exitCode;
    event.stdoutText = record.rawOutput ?: @"";
    event.stderrText = record.rawError ?: @"";
    event.createdPaths = created ?: @[];
    event.changedPaths = changed ?: @[];
    event.removedPaths = removed ?: @[];
    event.failureReason = (eventResult == ForensicEventResultFailure) ? (record.rawError.length ? record.rawError : record.verification) : @"";
    event.context = record.context ?: @{};
    NSNumber *pid = record.context[@"pid"];
    if ([pid isKindOfClass:[NSNumber class]]) event.pid = pid.intValue;
    NSNumber *uid = afterFacts[target][@"uid"];
    NSNumber *gid = afterFacts[target][@"gid"];
    event.uid = uid ? uid.intValue : (uid_t)getuid();
    event.gid = gid ? gid.intValue : (gid_t)getgid();
    event.responsibleProcess = record.context[@"command"] ?: record.operation ?: @"";

    if (event.createdPaths.count > 0 || event.changedPaths.count > 0 || event.removedPaths.count > 0) {
        if ([target containsString:@"/Applications"] || [target containsString:@"/var/containers/Bundle/Application"]) self.currentReport.productionPathTouched = YES;
    }
    if (nextState == ForensicInstallStateFailed || nextState == ForensicInstallStateCrashed || nextState == ForensicInstallStateRolledBack) {
        self.currentState = nextState;
    } else if (nextState > self.currentState) {
        self.currentState = nextState;
    }

    NSMutableArray *events = [self.eventsByRecordID.allValues mutableCopy];
    [events sortUsingComparator:^NSComparisonResult(ForensicEvent *a, ForensicEvent *b) { return [a.startedAt compare:b.startedAt]; }];
    self.currentReport.events = [events copy];
    self.currentReport.finalState = self.currentState;
    ForensicEvent *publishedEvent = event;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ForensicEventUpdated" object:publishedEvent userInfo:@{@"event": [publishedEvent dictionaryRepresentation]}];
}

@end
