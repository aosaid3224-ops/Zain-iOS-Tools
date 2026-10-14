#import "OperationLog.h"

@implementation OperationRecord

- (NSString *)phaseName {
    switch (self.phase) {
        case OperationPhaseStart: return @"START";
        case OperationPhaseIPAOpen: return @"IPA_OPEN";
        case OperationPhaseIPAExtract: return @"IPA_EXTRACT";
        case OperationPhaseAppIdentify: return @"APP_IDENTIFY";
        case OperationPhaseFileCopy: return @"FILE_COPY";
        case OperationPhaseFramework: return @"FRAMEWORK";
        case OperationPhaseDylib: return @"DYLIB";
        case OperationPhaseSign: return @"SIGN";
        case OperationPhasePermission: return @"PERMISSION";
        case OperationPhaseUICache: return @"UICACHE";
        case OperationPhaseVerify: return @"VERIFY";
        case OperationPhaseCleanup: return @"CLEANUP";
        case OperationPhaseComplete: return @"COMPLETE";
        case OperationPhaseLaunch: return @"LAUNCH";
        case OperationPhaseRuntimeMonitor: return @"RUNTIME_MONITOR";
        case OperationPhaseCrashDiagnostics: return @"CRASH_DIAGNOSTICS";
        default: return @"UNKNOWN";
    }
}

- (NSString *)resultSymbol {
    switch (self.result) {
        case OperationResultSuccess: return @"✅";
        case OperationResultFailed: return @"❌";
        case OperationResultSkipped: return @"⏭️";
        case OperationResultPartial: return @"⚠️";
        default: return @"⏳";
    }
}

- (NSString *)resultName {
    switch (self.result) {
        case OperationResultSuccess: return @"SUCCESS";
        case OperationResultFailed: return @"FAILED";
        case OperationResultSkipped: return @"SKIPPED";
        case OperationResultPartial: return @"PARTIAL";
        default: return @"PENDING";
    }
}

- (NSString *)logLine {
    return [NSString stringWithFormat:@"%@ [%@] %@ — %@ | exit=%d | %@",
            [self resultSymbol], [self phaseName], self.operation, self.target, self.exitCode, self.verification];
}

- (NSString *)detailDump {
    return [NSString stringWithFormat:@"Phase: %@\nOperation: %@\nTarget: %@\nInput: %@\nExit: %d\nOutput: %@\nError: %@\nVerification: %@\nVerified: %@\nResult: %@\nDuration: %.3fs\nContext: %@",
            [self phaseName], self.operation, self.target, self.input, self.exitCode,
            self.rawOutput, self.rawError, self.verification,
            self.verified ? @"YES" : @"NO", [self resultName], self.duration, self.context ?: @{}];
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"recordID": self.recordID ?: @"",
        @"transactionID": self.transactionID ?: @"",
        @"timestamp": self.timestamp ?: [NSDate date],
        @"phase": @((NSInteger)self.phase),
        @"phaseName": [self phaseName],
        @"operation": self.operation ?: @"",
        @"target": self.target ?: @"",
        @"input": self.input ?: @"",
        @"exitCode": @(self.exitCode),
        @"rawOutput": self.rawOutput ?: @"",
        @"rawError": self.rawError ?: @"",
        @"verification": self.verification ?: @"",
        @"verified": @(self.verified),
        @"result": @((NSInteger)self.result),
        @"resultName": [self resultName],
        @"duration": @(self.duration),
        @"context": self.context ?: @{}
    };
}

@end
