#import "ForensicTypes.h"

static NSString *ForensicDateString(NSDate *date) {
    if (!date) return @"";
    return [NSString stringWithFormat:@"%.6f", date.timeIntervalSince1970];
}

NSString *ForensicInstallStateName(ForensicInstallState state) {
    switch (state) {
        case ForensicInstallStateBegun: return @"BEGIN";
        case ForensicInstallStateInputInspected: return @"INPUT_INSPECTED";
        case ForensicInstallStateExtracted: return @"EXTRACTED";
        case ForensicInstallStateBundleDiscovered: return @"BUNDLE_DISCOVERED";
        case ForensicInstallStateFilesystemMutated: return @"FILESYSTEM_MUTATED";
        case ForensicInstallStateMachOAnalyzed: return @"MACHO_ANALYZED";
        case ForensicInstallStateInstalled: return @"INSTALLED";
        case ForensicInstallStateContainerDiscovered: return @"CONTAINER_DISCOVERED";
        case ForensicInstallStateRegistered: return @"REGISTERED";
        case ForensicInstallStateLaunchable: return @"LAUNCHABLE";
        case ForensicInstallStateRunning: return @"RUNNING";
        case ForensicInstallStateExited: return @"EXITED";
        case ForensicInstallStateCrashed: return @"CRASHED";
        case ForensicInstallStateFailed: return @"FAILED";
        case ForensicInstallStateRolledBack: return @"ROLLED_BACK";
        case ForensicInstallStateCompleted: return @"COMPLETED";
        default: return @"UNKNOWN";
    }
}

NSString *ForensicEventResultName(ForensicEventResult result) {
    switch (result) {
        case ForensicEventResultObserved: return @"OBSERVED";
        case ForensicEventResultSuccess: return @"SUCCESS";
        case ForensicEventResultFailure: return @"FAILURE";
        case ForensicEventResultPartial: return @"PARTIAL";
        default: return @"PENDING";
    }
}

@implementation ForensicEvent

+ (instancetype)eventWithTransactionID:(NSString *)transactionID operation:(NSString *)operation {
    ForensicEvent *event = [[self alloc] init];
    event.eventID = [[NSUUID UUID] UUIDString];
    event.transactionID = transactionID ?: @"";
    event.startedAt = [NSDate date];
    event.stateBefore = ForensicInstallStateUnknown;
    event.stateAfter = ForensicInstallStateUnknown;
    event.result = ForensicEventResultPending;
    event.operation = operation ?: @"";
    event.phase = @"FORENSIC";
    event.target = @"";
    event.logicalPath = @"";
    event.resolvedPath = @"";
    event.bundleID = @"";
    event.responsibleProcess = @"";
    event.pid = 0;
    event.uid = -1;
    event.gid = -1;
    event.exitStatus = -1;
    event.signalNumber = 0;
    event.stdoutText = @"";
    event.stderrText = @"";
    event.createdPaths = @[];
    event.changedPaths = @[];
    event.removedPaths = @[];
    event.failureReason = @"";
    event.context = @{};
    return event;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"eventID": self.eventID ?: @"",
        @"transactionID": self.transactionID ?: @"",
        @"startedAt": ForensicDateString(self.startedAt),
        @"endedAt": ForensicDateString(self.endedAt),
        @"stateBefore": ForensicInstallStateName(self.stateBefore),
        @"stateAfter": ForensicInstallStateName(self.stateAfter),
        @"result": ForensicEventResultName(self.result),
        @"operation": self.operation ?: @"",
        @"phase": self.phase ?: @"",
        @"target": self.target ?: @"",
        @"logicalPath": self.logicalPath ?: @"",
        @"resolvedPath": self.resolvedPath ?: @"",
        @"bundleID": self.bundleID ?: @"",
        @"responsibleProcess": self.responsibleProcess ?: @"",
        @"pid": @(self.pid),
        @"uid": @(self.uid),
        @"gid": @(self.gid),
        @"exitStatus": @(self.exitStatus),
        @"signalNumber": @(self.signalNumber),
        @"stdout": self.stdoutText ?: @"",
        @"stderr": self.stderrText ?: @"",
        @"createdPaths": self.createdPaths ?: @[],
        @"changedPaths": self.changedPaths ?: @[],
        @"removedPaths": self.removedPaths ?: @[],
        @"failureReason": self.failureReason ?: @"",
        @"context": self.context ?: @{}
    };
}

@end

@implementation ForensicTransactionReport

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *eventDicts = [NSMutableArray array];
    for (ForensicEvent *event in self.events ?: @[]) {
        [eventDicts addObject:[event dictionaryRepresentation]];
    }
    return @{
        @"transactionID": self.transactionID ?: @"",
        @"ipaPath": self.ipaPath ?: @"",
        @"bundleID": self.bundleID ?: @"",
        @"finalState": ForensicInstallStateName(self.finalState),
        @"productionPathTouched": @(self.productionPathTouched),
        @"events": eventDicts,
        @"evidence": self.evidence ?: @{},
        @"failureReason": self.failureReason ?: @""
    };
}

- (NSString *)jsonRepresentation {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self dictionaryRepresentation] options:NSJSONWritingPrettyPrinted error:&error];
    if (!data) return [NSString stringWithFormat:@"{\"error\":\"%@\"}", error.localizedDescription ?: @"serialization failed"];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSString *)summaryReport {
    NSMutableString *report = [NSMutableString stringWithFormat:@"Forensic Transaction %@\n", self.transactionID ?: @""];
    [report appendFormat:@"IPA: %@\nBundle ID: %@\nFinal state: %@\nProduction path touched: %@\n",
     self.ipaPath ?: @"", self.bundleID ?: @"", ForensicInstallStateName(self.finalState), self.productionPathTouched ? @"YES" : @"NO"];
    if (self.failureReason.length > 0) [report appendFormat:@"Failure: %@\n", self.failureReason];
    [report appendFormat:@"Events: %lu\n", (unsigned long)self.events.count];
    for (ForensicEvent *event in self.events ?: @[]) {
        [report appendFormat:@"%@ %@ %@ -> %@ result=%@ exit=%d pid=%d target=%@\n",
         ForensicDateString(event.startedAt), event.phase ?: @"FORENSIC", event.operation ?: @"",
         ForensicInstallStateName(event.stateAfter), ForensicEventResultName(event.result), event.exitStatus,
         event.pid, event.target ?: @""];
        if (event.failureReason.length > 0) [report appendFormat:@"  reason: %@\n", event.failureReason];
    }
    return report;
}

@end
