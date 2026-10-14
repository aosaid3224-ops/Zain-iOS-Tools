#import "CommandResult.h"

@implementation CommandResult

- (instancetype)initWithCommandPath:(NSString *)path
                          arguments:(NSArray<NSString *> *)arguments
                           exitCode:(int)exitCode
                       signalNumber:(int)signalNumber
                         spawnError:(int)spawnError
                         stdoutText:(NSString *)stdoutText
                         stderrText:(NSString *)stderrText
                         stdoutData:(NSData *)stdoutData
                         stderrData:(NSData *)stderrData
                           duration:(NSTimeInterval)duration
                           timedOut:(BOOL)timedOut {
    self = [super init];
    if (self) {
        _commandPath = [path copy];
        _arguments = [arguments copy];
        _exitCode = exitCode;
        _signalNumber = signalNumber;
        _spawnError = spawnError;
        _stdoutText = [stdoutText copy] ?: @"";
        _stderrText = [stderrText copy] ?: @"";
        _stdoutData = [stdoutData copy] ?: [NSData data];
        _stderrData = [stderrData copy] ?: [NSData data];
        _duration = duration;
        _timedOut = timedOut;
        _success = (spawnError == 0 && !timedOut && exitCode == 0);
    }
    return self;
}

- (NSDictionary *)diagnosticDictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"command"] = self.commandPath ?: @"";
    d[@"arguments"] = self.arguments ?: @[];
    d[@"success"] = @(self.success);
    d[@"exitCode"] = @(self.exitCode);
    d[@"signal"] = @(self.signalNumber);
    d[@"spawnError"] = @(self.spawnError);
    d[@"timedOut"] = @(self.timedOut);
    d[@"durationMs"] = @(round(self.duration * 1000.0));
    d[@"stdoutBytes"] = @(self.stdoutData.length);
    d[@"stderrBytes"] = @(self.stderrData.length);
    return d;
}

- (NSString *)failureCategory {
    if (self.timedOut) return @"TIMEOUT";
    if (self.spawnError != 0) {
        switch (self.spawnError) {
            case ENOENT: return @"NOT_FOUND";
            case EACCES: return @"PERMISSION_DENIED";
            case EPERM:  return @"PERMISSION_DENIED";
            default:     return @"SPAWN_FAILED";
        }
    }
    if (self.signalNumber != 0) return @"SIGNALLED";
    if (self.exitCode != 0) return @"EXIT_FAILURE";
    return @"NONE";
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<CommandResult: %@ | exit=%d signal=%d spawnErr=%d timedOut=%@ duration=%.3fs success=%@ stdoutBytes=%lu stderrBytes=%lu>",
            self.commandPath.lastPathComponent, self.exitCode, self.signalNumber, self.spawnError,
            self.timedOut ? @"YES" : @"NO", self.duration, self.success ? @"YES" : @"NO",
            (unsigned long)self.stdoutData.length, (unsigned long)self.stderrData.length];
}

@end
