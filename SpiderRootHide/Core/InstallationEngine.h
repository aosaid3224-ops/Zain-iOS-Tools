#import <Foundation/Foundation.h>
#import "InstallationProvider.h"

typedef NS_ENUM(NSInteger, InstallationStage) {
    InstallationStageIdle = 0,
    InstallationStagePreparing = 1,
    InstallationStageValidating = 2,
    InstallationStageInstalling = 3,
    InstallationStageRegistering = 4,
    InstallationStageCompleted = 5,
    InstallationStageFailed = 6
};

@interface InstallationEngine : NSObject
+ (instancetype)sharedEngine;

- (NSArray<id<InstallationProvider>> *)availableProviders;
- (id<InstallationProvider>)bestProvider;
- (NSString *)currentProviderName;
- (NSString *)stageDescription:(InstallationStage)stage;

- (void)installIPA:(NSString *)ipaPath
     progressBlock:(void (^)(InstallationStage stage, NSString *statusMessage, float progress))progressBlock
        completion:(void (^)(InstallationResult *result))completion;

- (void)uninstallAppWithBundleID:(NSString *)bundleID
                      completion:(void (^)(BOOL success, NSString *error))completion;
- (void)uninstallAppAtPath:(NSString *)appPath bundleID:(NSString *)bundleID
                    completion:(void (^)(BOOL success, NSString *error))completion;

@property (nonatomic, readonly, assign) BOOL isInstalling;

- (NSString *)activeTransactionID;
- (NSString *)transactionReport:(NSString *)txnID;
- (OperationLog *)operationLog;

- (void)prepareTransactionWithID:(NSString *)txnID;

- (BOOL)resetFailedInstallationState;
@end
