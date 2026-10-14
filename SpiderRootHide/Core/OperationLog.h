#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, OperationResult) {
    OperationResultPending = 0,
    OperationResultSuccess = 1,
    OperationResultFailed = 2,
    OperationResultSkipped = 3,
    OperationResultPartial = 4
};

typedef NS_ENUM(NSInteger, OperationPhase) {
    OperationPhaseStart = 0,
    OperationPhaseIPAOpen = 1,
    OperationPhaseIPAExtract = 2,
    OperationPhaseAppIdentify = 3,
    OperationPhaseFileCopy = 4,
    OperationPhaseFramework = 5,
    OperationPhaseDylib = 6,
    OperationPhaseSign = 7,
    OperationPhasePermission = 8,
    OperationPhaseUICache = 9,
    OperationPhaseVerify = 10,
    OperationPhaseCleanup = 11,
    OperationPhaseComplete = 12,
    OperationPhaseUnknown = 13,
    OperationPhaseLaunch = 14,
    OperationPhaseRuntimeMonitor = 15,
    OperationPhaseCrashDiagnostics = 16
};

@interface OperationRecord : NSObject
@property (nonatomic, strong, readwrite) NSString *recordID;
@property (nonatomic, strong, readwrite) NSString *transactionID;
@property (nonatomic, strong, readwrite) NSDate *timestamp;
@property (nonatomic, assign, readwrite) OperationPhase phase;
@property (nonatomic, strong, readwrite) NSString *operation;
@property (nonatomic, strong, readwrite) NSString *target;
@property (nonatomic, strong, readwrite) NSString *input;
@property (nonatomic, assign, readwrite) int exitCode;
@property (nonatomic, strong, readwrite) NSString *rawOutput;
@property (nonatomic, strong, readwrite) NSString *rawError;
@property (nonatomic, strong, readwrite) NSString *verification;
@property (nonatomic, assign, readwrite) BOOL verified;
@property (nonatomic, assign, readwrite) OperationResult result;
@property (nonatomic, assign, readwrite) NSTimeInterval duration;
@property (nonatomic, strong, readwrite) NSDictionary *context;
- (NSString *)phaseName;
- (NSString *)resultSymbol;
- (NSString *)resultName;
- (NSString *)logLine;
- (NSString *)detailDump;
- (NSDictionary *)dictionaryRepresentation;
@end

typedef void (^OperationLogLiveHandler)(OperationRecord *record, BOOL isUpdate);

@interface OperationLog : NSObject
+ (instancetype)sharedLog;
- (NSString *)subscribeLiveToTransactionID:(NSString *)transactionID handler:(OperationLogLiveHandler)handler;
- (void)unsubscribeLiveSubscription:(NSString *)subscriptionID;
- (NSString *)beginTransactionForIPA:(NSString *)ipaPath;
- (void)endTransaction:(NSString *)transactionID finalResult:(OperationResult)result;
- (NSString *)beginPhase:(OperationPhase)phase
               operation:(NSString *)operation
                  target:(NSString *)target
                   input:(NSString *)input
           transactionID:(NSString *)transactionID;
- (void)endPhase:(NSString *)recordID
        exitCode:(int)exitCode
       rawOutput:(NSString *)rawOutput
        rawError:(NSString *)rawError
    verification:(NSString *)verification
        verified:(BOOL)verified
        duration:(NSTimeInterval)duration
         context:(NSDictionary *)context;
- (void)endPhase:(NSString *)recordID
        exitCode:(int)exitCode
       rawOutput:(NSString *)rawOutput
        rawError:(NSString *)rawError
    verification:(NSString *)verification
        verified:(BOOL)verified
        duration:(NSTimeInterval)duration;
- (NSArray<OperationRecord *> *)recordsForTransaction:(NSString *)transactionID;
- (OperationRecord *)recordByID:(NSString *)recordID;
- (NSArray<OperationRecord *> *)failedRecordsInTransaction:(NSString *)transactionID;
- (OperationRecord *)firstFailureInTransaction:(NSString *)transactionID;
- (BOOL)transactionHasFailures:(NSString *)transactionID;
- (NSString *)transactionReport:(NSString *)transactionID;
- (NSString *)transactionSummary:(NSString *)transactionID;
- (NSDictionary *)transactionStats:(NSString *)transactionID;
- (NSString *)exportTransactionAsJSON:(NSString *)transactionID;
- (void)clearTransaction:(NSString *)transactionID;
- (void)clearAll;
@property (nonatomic, strong, readonly) NSString *activeTransactionID;
@property (nonatomic, strong, readonly) NSArray<NSString *> *allTransactionIDs;
@end
