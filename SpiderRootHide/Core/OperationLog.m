#import "OperationLog.h"
#import "Logger.h"

static NSString * const kLogFileName = @"IPAInstallerPro_OperationLog.plist";

@interface OperationLogLiveSubscription : NSObject
@property (nonatomic, copy) NSString *transactionID;
@property (nonatomic, copy) OperationLogLiveHandler handler;
@end

@implementation OperationLogLiveSubscription
@end

@interface OperationLog ()
@property (nonatomic, strong) NSMutableArray<OperationRecord *> *records;
@property (nonatomic, strong) dispatch_queue_t logQueue;
@property (nonatomic, strong) dispatch_queue_t persistenceQueue;
@property (nonatomic, strong) NSString *logFilePath;
@property (nonatomic, strong) NSString *activeTxnID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, OperationLogLiveSubscription *> *liveSubscriptions;
@end

@implementation OperationLog

+ (instancetype)sharedLog {
    static OperationLog *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logQueue = dispatch_queue_create("com.aosaid.ipainstallerpro.oplog", DISPATCH_QUEUE_SERIAL);
        _persistenceQueue = dispatch_queue_create("com.aosaid.ipainstallerpro.oplog.persistence", DISPATCH_QUEUE_SERIAL);
        _records = [NSMutableArray array];
        _liveSubscriptions = [NSMutableDictionary dictionary];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docs = paths.firstObject;
        _logFilePath = [docs stringByAppendingPathComponent:kLogFileName];
        [self loadLog];
    }
    return self;
}

- (NSString *)subscribeLiveToTransactionID:(NSString *)transactionID handler:(OperationLogLiveHandler)handler {
    if (!transactionID.length || !handler) return @"";
    NSString *subscriptionID = [[NSUUID UUID] UUIDString];
    OperationLogLiveSubscription *subscription = [[OperationLogLiveSubscription alloc] init];
    subscription.transactionID = [transactionID copy];
    subscription.handler = [handler copy];
    dispatch_sync(self.logQueue, ^{
        self.liveSubscriptions[subscriptionID] = subscription;
    });
    return subscriptionID;
}

- (void)unsubscribeLiveSubscription:(NSString *)subscriptionID {
    if (!subscriptionID.length) return;
    dispatch_async(self.logQueue, ^{
        [self.liveSubscriptions removeObjectForKey:subscriptionID];
    });
}

- (void)publishLiveRecord:(OperationRecord *)record update:(BOOL)update {
    if (!record.transactionID.length || self.liveSubscriptions.count == 0) return;
    NSArray<OperationLogLiveSubscription *> *subscriptions = [self.liveSubscriptions.allValues copy];
    for (OperationLogLiveSubscription *subscription in subscriptions) {
        if ([subscription.transactionID isEqualToString:record.transactionID] && subscription.handler) {
            subscription.handler(record, update);
        }
    }
}

- (NSString *)beginTransactionForIPA:(NSString *)ipaPath {
    NSString *txnID = [[NSUUID UUID] UUIDString];
    self.activeTxnID = txnID;

    OperationRecord *rec = [[OperationRecord alloc] init];
    rec.recordID = [[NSUUID UUID] UUIDString];
    rec.transactionID = txnID;
    rec.timestamp = [NSDate date];
    rec.phase = OperationPhaseStart;
    rec.operation = @"beginTransaction";
    rec.target = [ipaPath lastPathComponent];
    rec.input = ipaPath ?: @"";
    rec.exitCode = 0;
    rec.rawOutput = @"";
    rec.rawError = @"";
    rec.verification = @"Transaction started";
    rec.verified = YES;
    rec.result = OperationResultPending;
    rec.duration = 0;
    rec.context = @{};

    [self addRecord:rec];
    return txnID;
}

- (void)endTransaction:(NSString *)transactionID finalResult:(OperationResult)result {
    self.activeTxnID = nil;

    OperationRecord *rec = [[OperationRecord alloc] init];
    rec.recordID = [[NSUUID UUID] UUIDString];
    rec.transactionID = transactionID;
    rec.timestamp = [NSDate date];
    rec.phase = OperationPhaseComplete;
    rec.operation = @"endTransaction";
    rec.target = @"";
    rec.input = @"";
    rec.exitCode = (result == OperationResultSuccess) ? 0 : 1;
    rec.rawOutput = @"";
    rec.rawError = @"";
    rec.verification = [NSString stringWithFormat:@"Transaction ended with result: %@", [self resultName:result]];
    rec.verified = (result == OperationResultSuccess);
    rec.result = result;
    rec.duration = 0;
    rec.context = @{};

    [self addRecord:rec];
}

- (NSString *)beginPhase:(OperationPhase)phase operation:(NSString *)operation target:(NSString *)target input:(NSString *)input transactionID:(NSString *)transactionID {
    NSString *recID = [[NSUUID UUID] UUIDString];

    OperationRecord *rec = [[OperationRecord alloc] init];
    rec.recordID = recID;
    rec.transactionID = transactionID ?: @"";
    rec.timestamp = [NSDate date];
    rec.phase = phase;
    rec.operation = operation ?: @"";
    rec.target = target ?: @"";
    rec.input = input ?: @"";
    rec.exitCode = -1;
    rec.rawOutput = @"";
    rec.rawError = @"";
    rec.verification = @"Phase started";
    rec.verified = NO;
    rec.result = OperationResultPending;
    rec.duration = 0;
    rec.context = @{};

    [self addRecord:rec];
    return recID;
}

- (void)endPhase:(NSString *)recordID exitCode:(int)exitCode rawOutput:(NSString *)rawOutput rawError:(NSString *)rawError verification:(NSString *)verification verified:(BOOL)verified duration:(NSTimeInterval)duration {
    [self endPhase:recordID exitCode:exitCode rawOutput:rawOutput rawError:rawError verification:verification verified:verified duration:duration context:@{}];
}

- (void)endPhase:(NSString *)recordID exitCode:(int)exitCode rawOutput:(NSString *)rawOutput rawError:(NSString *)rawError verification:(NSString *)verification verified:(BOOL)verified duration:(NSTimeInterval)duration context:(NSDictionary *)context {
    dispatch_async(self.logQueue, ^{
        for (NSUInteger i = 0; i < self.records.count; i++) {
            OperationRecord *rec = self.records[i];
            if ([rec.recordID isEqualToString:recordID]) {
                OperationRecord *updated = [[OperationRecord alloc] init];
                updated.recordID = rec.recordID;
                updated.transactionID = rec.transactionID;
                updated.timestamp = rec.timestamp;
                updated.phase = rec.phase;
                updated.operation = rec.operation;
                updated.target = rec.target;
                updated.input = rec.input;
                updated.exitCode = exitCode;
                updated.rawOutput = rawOutput ?: @"";
                updated.rawError = rawError ?: @"";
                updated.verification = verification ?: @"";
                updated.verified = verified;
                updated.result = verified ? (exitCode == 0 ? OperationResultSuccess : OperationResultPartial) : OperationResultFailed;
                updated.duration = duration;
                updated.context = context ?: @{};
                self.records[i] = updated;
                [self saveLog];
                [self publishLiveRecord:updated update:YES];
                [self broadcastRecordUpdated:updated];
                break;
            }
        }
    });
}

- (void)addRecord:(OperationRecord *)record {
    dispatch_async(self.logQueue, ^{
        [self.records addObject:record];
        [self saveLog];
        [self publishLiveRecord:record update:NO];
        [self broadcastRecordAdded:record];
    });
}

- (OperationRecord *)recordByID:(NSString *)recordID {
    __block OperationRecord *result = nil;
    dispatch_sync(self.logQueue, ^{
        for (OperationRecord *rec in self.records) {
            if ([rec.recordID isEqualToString:recordID]) {
                result = rec;
                break;
            }
        }
    });
    return result;
}

- (NSArray<OperationRecord *> *)recordsForTransaction:(NSString *)transactionID {
    __block NSArray *result = nil;
    dispatch_sync(self.logQueue, ^{
        NSMutableArray *filtered = [NSMutableArray array];
        for (OperationRecord *rec in self.records) {
            if ([rec.transactionID isEqualToString:transactionID]) [filtered addObject:rec];
        }
        result = [filtered copy];
    });
    return result;
}

- (NSArray<OperationRecord *> *)failedRecordsInTransaction:(NSString *)transactionID {
    NSMutableArray *failed = [NSMutableArray array];
    for (OperationRecord *rec in [self recordsForTransaction:transactionID]) {
        if (rec.result == OperationResultFailed) [failed addObject:rec];
    }
    return failed;
}

- (OperationRecord *)firstFailureInTransaction:(NSString *)transactionID {
    for (OperationRecord *rec in [self recordsForTransaction:transactionID]) {
        if (rec.result == OperationResultFailed) return rec;
    }
    return nil;
}

- (BOOL)transactionHasFailures:(NSString *)transactionID {
    return [self firstFailureInTransaction:transactionID] != nil;
}

- (NSArray<OperationRecord *> *)allRecords {
    __block NSArray *result = nil;
    dispatch_sync(self.logQueue, ^{ result = [self.records copy]; });
    return result;
}

- (NSArray<NSString *> *)allTransactionIDs {
    NSMutableSet *txns = [NSMutableSet set];
    for (OperationRecord *rec in self.records) {
        if (rec.transactionID.length > 0) [txns addObject:rec.transactionID];
    }
    return [txns allObjects];
}

- (void)clearTransaction:(NSString *)transactionID {
    dispatch_async(self.logQueue, ^{
        NSMutableIndexSet *toRemove = [NSMutableIndexSet indexSet];
        for (NSUInteger i = 0; i < self.records.count; i++) {
            if ([self.records[i].transactionID isEqualToString:transactionID]) {
                [toRemove addIndex:i];
            }
        }
        [self.records removeObjectsAtIndexes:toRemove];
        [self saveLog];
    });
}

- (void)clearAll {
    dispatch_async(self.logQueue, ^{
        [self.records removeAllObjects];
        [self saveLog];
    });
}

- (NSString *)transactionReport:(NSString *)txnID {
    if (!txnID) return @"";
    NSArray *records = [self recordsForTransaction:txnID];
    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"Transaction Report: %@\n", txnID];
    [report appendFormat:@"Total records: %lu\n\n", (unsigned long)records.count];
    for (OperationRecord *rec in records) {
        [report appendFormat:@"%@ [%@] %@ — %@ (exit=%d)\n",
         [rec resultSymbol], [rec phaseName], rec.operation, rec.target, rec.exitCode];
        if (rec.rawError.length > 0) [report appendFormat:@"   ⚠️ %@\n", rec.rawError];
    }
    return report;
}

- (NSString *)transactionSummary:(NSString *)txnID {
    NSArray *records = [self recordsForTransaction:txnID];
    NSUInteger total = records.count;
    NSUInteger failed = 0;
    for (OperationRecord *rec in records) {
        if (rec.result == OperationResultFailed) failed++;
    }
    return [NSString stringWithFormat:@"%lu phases, %lu failed", (unsigned long)total, (unsigned long)failed];
}

- (NSDictionary *)transactionStats:(NSString *)txnID {
    NSArray *records = [self recordsForTransaction:txnID];
    NSUInteger total = records.count;
    NSUInteger failed = 0;
    NSTimeInterval totalDuration = 0;
    NSDate *firstTimestamp = nil;
    NSDate *lastTimestamp = nil;
    for (OperationRecord *rec in records) {
        if (rec.result == OperationResultFailed) failed++;
        totalDuration += rec.duration;
        if (!firstTimestamp || [rec.timestamp compare:firstTimestamp] == NSOrderedAscending) firstTimestamp = rec.timestamp;
        if (!lastTimestamp || [rec.timestamp compare:lastTimestamp] == NSOrderedDescending) lastTimestamp = rec.timestamp;
    }
    NSTimeInterval wallClockDuration = (firstTimestamp && lastTimestamp) ? [lastTimestamp timeIntervalSinceDate:firstTimestamp] : 0;
    return @{
        @"totalRecords": @(total),
        @"failedRecords": @(failed),
        @"successRate": @(total > 0 ? (total - failed) / (double)total : 0),
        @"totalDuration": @(totalDuration),
        @"wallClockDuration": @(wallClockDuration)
    };
}

- (NSString *)exportTransactionAsJSON:(NSString *)txnID {
    NSArray *records = [self recordsForTransaction:txnID];
    NSMutableArray *dicts = [NSMutableArray array];
    for (OperationRecord *rec in records) {
        [dicts addObject:[rec dictionaryRepresentation]];
    }
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dicts options:NSJSONWritingPrettyPrinted error:&error];
    return jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
}

- (NSString *)resultName:(OperationResult)result {
    switch (result) {
        case OperationResultSuccess: return @"SUCCESS";
        case OperationResultFailed: return @"FAILED";
        case OperationResultSkipped: return @"SKIPPED";
        case OperationResultPartial: return @"PARTIAL";
        default: return @"PENDING";
    }
}

- (void)saveLog {
    NSArray<OperationRecord *> *snapshot = [self.records copy];
    NSString *path = [self.logFilePath copy];
    dispatch_async(self.persistenceQueue, ^{
        NSMutableArray *dicts = [NSMutableArray arrayWithCapacity:snapshot.count];
        for (OperationRecord *rec in snapshot) [dicts addObject:[rec dictionaryRepresentation]];
        [dicts writeToFile:path atomically:YES];
    });
}

- (void)loadLog {
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.logFilePath]) {
        NSArray *loaded = [NSArray arrayWithContentsOfFile:self.logFilePath];
        if (loaded) {
            for (NSDictionary *dict in loaded) {
                OperationRecord *rec = [[OperationRecord alloc] init];
                rec.recordID = dict[@"recordID"] ?: @"";
                rec.transactionID = dict[@"transactionID"] ?: @"";
                rec.timestamp = dict[@"timestamp"] ?: [NSDate date];
                rec.phase = [dict[@"phase"] integerValue];
                rec.operation = dict[@"operation"] ?: @"";
                rec.target = dict[@"target"] ?: @"";
                rec.input = dict[@"input"] ?: @"";
                rec.exitCode = [dict[@"exitCode"] intValue];
                rec.rawOutput = dict[@"rawOutput"] ?: @"";
                rec.rawError = dict[@"rawError"] ?: @"";
                rec.verification = dict[@"verification"] ?: @"";
                rec.verified = [dict[@"verified"] boolValue];
                rec.result = [dict[@"result"] integerValue];
                rec.duration = [dict[@"duration"] doubleValue];
                rec.context = dict[@"context"] ?: @{};
                [self.records addObject:rec];
            }
        }
    }
}

- (void)broadcastRecordAdded:(OperationRecord *)record {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"OperationRecordAdded"
                                                            object:record
                                                          userInfo:@{@"record": [record dictionaryRepresentation]}];
    });
}

- (void)broadcastRecordUpdated:(OperationRecord *)record {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"OperationRecordUpdated"
                                                            object:record
                                                          userInfo:@{@"record": [record dictionaryRepresentation]}];
    });
}

@end
