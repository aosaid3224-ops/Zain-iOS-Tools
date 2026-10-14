#import <Foundation/Foundation.h>

@class InstallationResult;
@class OperationLog;

@protocol InstallationProvider <NSObject>
@required
- (NSString *)providerName;
- (NSString *)providerDescription;
- (BOOL)isAvailable;
- (NSInteger)priority;

- (void)installIPA:(NSString *)ipaPath
      transactionID:(NSString *)txnID
       operationLog:(OperationLog *)opLog
         completion:(void (^)(InstallationResult *result))completion;

- (void)uninstallAppWithBundleID:(NSString *)bundleID
                      completion:(void (^)(BOOL success, NSString *error))completion;
- (void)uninstallAppAtPath:(NSString *)appPath bundleID:(NSString *)bundleID
                      completion:(void (^)(BOOL success, NSString *error))completion;
@end

@interface InstallationResult : NSObject
@property (nonatomic, assign) BOOL success;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) NSString *detailedOutput;
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) NSString *providerName;
@property (nonatomic, strong) NSString *transactionID;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) NSDictionary *evidence;

+ (InstallationResult *)successResult:(NSString *)msg
                           provider:(NSString *)provider
                        transaction:(NSString *)txnID
                           evidence:(NSDictionary *)evidence;

+ (InstallationResult *)failureResult:(NSString *)msg
                             provider:(NSString *)provider
                          transaction:(NSString *)txnID
                                error:(NSError *)error
                             evidence:(NSDictionary *)evidence;
@end
