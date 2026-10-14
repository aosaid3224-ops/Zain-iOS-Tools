#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, InstallationTransactionState) {
    InstallationTransactionStatePending = 0,
    InstallationTransactionStateAnalyzing,
    InstallationTransactionStatePreparing,
    InstallationTransactionStateSigning,
    InstallationTransactionStateInstalling,
    InstallationTransactionStateVerifyingInstall,
    InstallationTransactionStateRegistering,
    InstallationTransactionStateVerifyingRegistration,
    InstallationTransactionStateLaunching,
    InstallationTransactionStateSuccess,
    InstallationTransactionStateFailed,
    InstallationTransactionStateRollback
};

FOUNDATION_EXPORT NSString *InstallationTransactionStateName(InstallationTransactionState state);

@interface InstallationTransactionCoordinator : NSObject
+ (instancetype)sharedCoordinator;
- (BOOL)beginTransaction:(NSString *)transactionID;
- (BOOL)transitionTransaction:(NSString *)transactionID toState:(InstallationTransactionState)state reason:(NSString *)reason;
- (InstallationTransactionState)stateForTransaction:(NSString *)transactionID;
- (BOOL)beginRegistrationForTransaction:(NSString *)transactionID reason:(NSString *)reason;
- (BOOL)markRegistrationVerifiedForTransaction:(NSString *)transactionID reason:(NSString *)reason;
- (BOOL)beginRollbackForTransaction:(NSString *)transactionID reason:(NSString *)reason;
- (void)markFailedForTransaction:(NSString *)transactionID reason:(NSString *)reason;
- (BOOL)markSuccessForTransaction:(NSString *)transactionID reason:(NSString *)reason;
- (BOOL)isRegistrationAllowedForTransaction:(NSString *)transactionID;
- (BOOL)isTerminalForTransaction:(NSString *)transactionID;
@end
