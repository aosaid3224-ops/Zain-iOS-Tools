#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ExecutableCapabilityStatus) {
    ExecutableCapabilityStatusNotFound,
    ExecutableCapabilityStatusNotExecutable,
    ExecutableCapabilityStatusPermissionDenied,
    ExecutableCapabilityStatusProcessFailed,
    ExecutableCapabilityStatusInvalidOutput,
    ExecutableCapabilityStatusTimeout,
    ExecutableCapabilityStatusUnknownError,
    ExecutableCapabilityStatusReady
};

@interface ExecutableCapability : NSObject

@property (nonatomic, copy, readonly) NSString *executableName;
@property (nonatomic, copy, readonly) NSString *resolvedPath;
@property (nonatomic, copy, readonly) NSArray<NSString *> *searchedPaths;
@property (nonatomic, assign, readonly) ExecutableCapabilityStatus status;
@property (nonatomic, assign, readonly) BOOL exists;
@property (nonatomic, assign, readonly) BOOL isAccessible;
@property (nonatomic, assign, readonly) BOOL isExecutable;
@property (nonatomic, assign, readonly) BOOL isInvocable;
@property (nonatomic, assign, readonly) BOOL outputValid;
@property (nonatomic, assign, readonly) int spawnError;
@property (nonatomic, assign, readonly) int exitCode;
@property (nonatomic, assign, readonly) int signalNumber;
@property (nonatomic, copy, readonly) NSString *testOutput;
@property (nonatomic, copy, readonly) NSString *lastErrorMessage;
@property (nonatomic, assign, readonly) NSTimeInterval duration;
@property (nonatomic, strong, readonly) NSDate *testTimestamp;

- (instancetype)initWithExecutableName:(NSString *)name
                          searchedPaths:(NSArray<NSString *> *)searchedPaths;

- (void)markFoundAtPath:(NSString *)path exists:(BOOL)exists executable:(BOOL)executable;

- (void)markInvocationResultWithSpawnError:(int)spawnError
                                  exitCode:(int)exitCode
                              signalNumber:(int)signalNumber
                                    output:(NSString *)output
                                  duration:(NSTimeInterval)duration;

- (void)markReadyWithPath:(NSString *)path output:(NSString *)output duration:(NSTimeInterval)duration;

- (void)markStatus:(ExecutableCapabilityStatus)status errorMessage:(NSString *)error;

- (NSString *)localizedStatusDescription;

- (NSDictionary *)diagnosticSnapshot;

- (NSDictionary *)fullDiagnosticDictionary;

@end
