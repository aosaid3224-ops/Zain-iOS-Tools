#import <Foundation/Foundation.h>

@class OperationLog;

@interface ProcessInfo : NSObject
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *executablePath;
@property (nonatomic, assign) uid_t uid;
@property (nonatomic, assign) gid_t gid;
@property (nonatomic, strong) NSDate *startTime;
@end

@interface RuntimeDiagnosticsResult : NSObject
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) NSString *appName;
@property (nonatomic, strong) NSString *executablePath;
@property (nonatomic, strong) NSString *state;
@property (nonatomic, strong) NSDate *launchRequestedAt;
@property (nonatomic, strong) NSDate *processDetectedAt;
@property (nonatomic, strong) NSDate *processExitAt;
@property (nonatomic, assign) NSTimeInterval launchDetectionTimeMs;
@property (nonatomic, assign) NSTimeInterval processLifetimeMs;
@property (nonatomic, assign) NSTimeInterval monitoringWindowMs;
@property (nonatomic, assign) BOOL processDetected;
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) uid_t uid;
@property (nonatomic, assign) gid_t gid;
@property (nonatomic, assign) BOOL processRemainedAlive;
@property (nonatomic, assign) BOOL crashDetected;
@property (nonatomic, strong) NSString *terminationReason;
@property (nonatomic, strong) NSString *crashReportPath;
@property (nonatomic, strong) NSString *diagnosticOutput;
@property (nonatomic, assign) BOOL success;
@property (nonatomic, strong) NSString *summary;
- (NSString *)detailedReport;
@end

@interface RuntimeDiagnostics : NSObject
+ (instancetype)sharedDiagnostics;
- (void)diagnoseAppLaunch:(NSString *)bundleID
           transactionID:(NSString *)txnID
            operationLog:(OperationLog *)opLog
              completion:(void (^)(RuntimeDiagnosticsResult *result))completion;
@property (nonatomic, assign) NSTimeInterval processDetectionTimeout;
@property (nonatomic, assign) NSTimeInterval monitoringWindow;
@property (nonatomic, assign) NSTimeInterval pollInterval;
@end
