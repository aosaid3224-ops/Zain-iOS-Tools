#import <Foundation/Foundation.h>
@class OperationLog;

@interface ForensicRegistrationProbe : NSObject
+ (instancetype)sharedProbe;

- (NSDictionary *)probeBundleID:(NSString *)bundleID
                   transactionID:(NSString *)transactionID
                    operationLog:(OperationLog *)operationLog
                    logicalPath:(NSString *)logicalPath
                   resolvedPath:(NSString *)resolvedPath;

- (NSDictionary *)launchServicesFactsForBundleID:(NSString *)bundleID;
@end
