#import "ExecutableCapability.h"

@implementation ExecutableCapability

- (instancetype)initWithExecutableName:(NSString *)name searchedPaths:(NSArray<NSString *> *)searchedPaths {
    self = [super init];
    if (self) {
        _executableName = [name copy];
        _searchedPaths = [searchedPaths copy] ?: @[];
        _status = ExecutableCapabilityStatusUnknownError;
        _testTimestamp = [NSDate date];
    }
    return self;
}

- (void)markFoundAtPath:(NSString *)path exists:(BOOL)exists executable:(BOOL)executable {
    _resolvedPath = [path copy];
    _exists = exists;
    _isAccessible = YES;
    _isExecutable = executable;
    if (!exists) {
        _status = ExecutableCapabilityStatusNotFound;
        _lastErrorMessage = [NSString stringWithFormat:@"لم يُعثر على %@ في المسارات المُفحصة", _executableName];
    } else if (!executable) {
        _status = ExecutableCapabilityStatusNotExecutable;
        _lastErrorMessage = [NSString stringWithFormat:@"%@ موجود لكنه غير قابل للتنفيذ", path];
    }
}

- (void)markInvocationResultWithSpawnError:(int)spawnError exitCode:(int)exitCode signalNumber:(int)signalNumber output:(NSString *)output duration:(NSTimeInterval)duration {
    _spawnError = spawnError;
    _exitCode = exitCode;
    _signalNumber = signalNumber;
    _testOutput = [output copy] ?: @"";
    _duration = duration;
    if (spawnError != 0) {
        if (spawnError == EACCES || spawnError == EPERM) {
            _status = ExecutableCapabilityStatusPermissionDenied;
            _lastErrorMessage = @"تم رفض الصلاحية عند محاولة التشغيل";
        } else if (spawnError == ENOENT) {
            _status = ExecutableCapabilityStatusNotFound;
            _lastErrorMessage = @"غير موجود في المسار المُحدد";
        } else {
            _status = ExecutableCapabilityStatusProcessFailed;
            _lastErrorMessage = [NSString stringWithFormat:@"فشل التشغيل (رمز الخطأ: %d)", spawnError];
        }
        return;
    }
    if (signalNumber != 0) {
        _status = ExecutableCapabilityStatusProcessFailed;
        _lastErrorMessage = [NSString stringWithFormat:@"تلقى إشارة إنهاء (%d)", signalNumber];
        return;
    }
}

- (void)markReadyWithPath:(NSString *)path output:(NSString *)output duration:(NSTimeInterval)duration {
    _resolvedPath = [path copy];
    _exists = YES;
    _isAccessible = YES;
    _isExecutable = YES;
    _isInvocable = YES;
    _outputValid = YES;
    _testOutput = [output copy] ?: @"";
    _duration = duration;
    _status = ExecutableCapabilityStatusReady;
    _lastErrorMessage = nil;
    _spawnError = 0;
    _exitCode = 0;
    _signalNumber = 0;
}

- (void)markStatus:(ExecutableCapabilityStatus)status errorMessage:(NSString *)error {
    _status = status;
    _lastErrorMessage = [error copy];
}

- (NSString *)localizedStatusDescription {
    switch (_status) {
        case ExecutableCapabilityStatusReady:      return @"مُفعّل";
        case ExecutableCapabilityStatusNotFound:   return @"غير موجود";
        case ExecutableCapabilityStatusNotExecutable: return @"غير قابل للتنفيذ";
        case ExecutableCapabilityStatusPermissionDenied: return @"تم رفض الصلاحية";
        case ExecutableCapabilityStatusProcessFailed: return @"فشل التشغيل";
        case ExecutableCapabilityStatusInvalidOutput: return @"خرج غير صالح";
        case ExecutableCapabilityStatusTimeout:    return @"انتهت المهلة";
        case ExecutableCapabilityStatusUnknownError: return @"خطأ غير معروف";
        default: return @"حالة غير معروفة";
    }
}

- (NSDictionary *)diagnosticSnapshot {
    return @{
        @"executable": _executableName ?: @"",
        @"resolvedPath": _resolvedPath ?: @"",
        @"status": @(_status),
        @"statusName": [self statusName],
        @"exists": @(_exists),
        @"isExecutable": @(_isExecutable),
        @"isInvocable": @(_isInvocable),
        @"outputValid": @(_outputValid),
        @"spawnError": @(_spawnError),
        @"exitCode": @(_exitCode),
        @"signal": @(_signalNumber),
        @"durationMs": @(round(_duration * 1000.0)),
        @"timestamp": _testTimestamp ?: [NSDate date],
        @"searchedPathsCount": @(_searchedPaths.count)
    };
}

- (NSDictionary *)fullDiagnosticDictionary {
    NSMutableDictionary *d = [[self diagnosticSnapshot] mutableCopy];
    d[@"searchedPaths"] = _searchedPaths ?: @[];
    d[@"testOutput"] = _testOutput ?: @"";
    d[@"errorMessage"] = _lastErrorMessage ?: @"";
    return d;
}

- (NSString *)statusName {
    switch (_status) {
        case ExecutableCapabilityStatusReady: return @"READY";
        case ExecutableCapabilityStatusNotFound: return @"NOT_FOUND";
        case ExecutableCapabilityStatusNotExecutable: return @"NOT_EXECUTABLE";
        case ExecutableCapabilityStatusPermissionDenied: return @"PERMISSION_DENIED";
        case ExecutableCapabilityStatusProcessFailed: return @"PROCESS_FAILED";
        case ExecutableCapabilityStatusInvalidOutput: return @"INVALID_OUTPUT";
        case ExecutableCapabilityStatusTimeout: return @"TIMEOUT";
        case ExecutableCapabilityStatusUnknownError: return @"UNKNOWN_ERROR";
        default: return @"UNKNOWN";
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<ExecutableCapability: %@ | status=%@ | path=%@ | duration=%.3fs>",
            _executableName, [self statusName], _resolvedPath.lastPathComponent, _duration];
}

@end
