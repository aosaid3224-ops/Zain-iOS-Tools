#import <Foundation/Foundation.h>
#include <sys/types.h>

typedef NS_ENUM(NSInteger, ForensicInstallState) {
    ForensicInstallStateUnknown = 0,
    ForensicInstallStateBegun,
    ForensicInstallStateInputInspected,
    ForensicInstallStateExtracted,
    ForensicInstallStateBundleDiscovered,
    ForensicInstallStateFilesystemMutated,
    ForensicInstallStateMachOAnalyzed,
    ForensicInstallStateInstalled,
    ForensicInstallStateContainerDiscovered,
    ForensicInstallStateRegistered,
    ForensicInstallStateLaunchable,
    ForensicInstallStateRunning,
    ForensicInstallStateExited,
    ForensicInstallStateCrashed,
    ForensicInstallStateFailed,
    ForensicInstallStateRolledBack,
    ForensicInstallStateCompleted
};

typedef NS_ENUM(NSInteger, ForensicEventResult) {
    ForensicEventResultPending = 0,
    ForensicEventResultObserved,
    ForensicEventResultSuccess,
    ForensicEventResultFailure,
    ForensicEventResultPartial
};

FOUNDATION_EXPORT NSString *ForensicInstallStateName(ForensicInstallState state);
FOUNDATION_EXPORT NSString *ForensicEventResultName(ForensicEventResult result);

@interface ForensicEvent : NSObject
@property (nonatomic, copy) NSString *eventID;
@property (nonatomic, copy) NSString *transactionID;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, strong) NSDate *endedAt;
@property (nonatomic, assign) ForensicInstallState stateBefore;
@property (nonatomic, assign) ForensicInstallState stateAfter;
@property (nonatomic, assign) ForensicEventResult result;
@property (nonatomic, copy) NSString *operation;
@property (nonatomic, copy) NSString *phase;
@property (nonatomic, copy) NSString *target;
@property (nonatomic, copy) NSString *logicalPath;
@property (nonatomic, copy) NSString *resolvedPath;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *responsibleProcess;
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) NSInteger uid;
@property (nonatomic, assign) NSInteger gid;
@property (nonatomic, assign) int exitStatus;
@property (nonatomic, assign) int signalNumber;
@property (nonatomic, copy) NSString *stdoutText;
@property (nonatomic, copy) NSString *stderrText;
@property (nonatomic, copy) NSArray<NSString *> *createdPaths;
@property (nonatomic, copy) NSArray<NSString *> *changedPaths;
@property (nonatomic, copy) NSArray<NSString *> *removedPaths;
@property (nonatomic, copy) NSString *failureReason;
@property (nonatomic, copy) NSDictionary *context;

+ (instancetype)eventWithTransactionID:(NSString *)transactionID operation:(NSString *)operation;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface ForensicTransactionReport : NSObject
@property (nonatomic, copy) NSString *transactionID;
@property (nonatomic, copy) NSString *ipaPath;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, assign) ForensicInstallState finalState;
@property (nonatomic, assign) BOOL productionPathTouched;
@property (nonatomic, copy) NSArray<ForensicEvent *> *events;
@property (nonatomic, copy) NSDictionary *evidence;
@property (nonatomic, copy) NSString *failureReason;

- (NSDictionary *)dictionaryRepresentation;
- (NSString *)jsonRepresentation;
- (NSString *)summaryReport;
@end
