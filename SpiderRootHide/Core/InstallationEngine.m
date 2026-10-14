#import "InstallationEngine.h"
#import "DirectInstallationProvider.h"
#import "OperationLog.h"
#import "RuntimeDiagnostics.h"
#import "InstallationTransactionCoordinator.h"

@interface InstallationEngine ()
@property (nonatomic, strong) NSMutableArray<id<InstallationProvider>> *providers;
@property (nonatomic, strong) NSLock *installLock;
@property (nonatomic, assign) BOOL isInstalling;
@property (nonatomic, strong, readwrite) NSString *activeTxnID;
@property (nonatomic, strong, readwrite) OperationLog *operationLog;
@property (nonatomic, assign) InstallationStage currentStage;
@end

@implementation InstallationEngine

+ (instancetype)sharedEngine {
    static InstallationEngine *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _providers = [NSMutableArray array];
        _installLock = [[NSLock alloc] init];
        _operationLog = [OperationLog sharedLog];
        DirectInstallationProvider *direct = [[DirectInstallationProvider alloc] init];
        [_providers addObject:direct];
    }
    return self;
}

- (NSArray<id<InstallationProvider>> *)availableProviders {
    NSMutableArray *a = [NSMutableArray array];
    for (id<InstallationProvider> p in self.providers) {
        if ([p isAvailable]) [a addObject:p];
    }
    return a;
}

- (id<InstallationProvider>)bestProvider {
    NSArray *a = [self availableProviders];
    if (a.count == 0) return nil;
    id<InstallationProvider> best = a.firstObject;
    for (id<InstallationProvider> p in a) {
        if ([p priority] > [best priority]) best = p;
    }
    return best;
}

- (NSString *)currentProviderName {
    id<InstallationProvider> p = [self bestProvider];
    return p ? [p providerName] : @"None";
}

- (NSString *)stageDescription:(InstallationStage)stage {
    switch (stage) {
        case InstallationStageIdle: return @"Idle";
        case InstallationStagePreparing: return @"Preparing";
        case InstallationStageValidating: return @"Validating";
        case InstallationStageInstalling: return @"Installing";
        case InstallationStageRegistering: return @"Registering";
        case InstallationStageCompleted: return @"Completed";
        case InstallationStageFailed: return @"Failed";
        default: return @"Unknown";
    }
}

- (NSString *)activeTransactionID { return self.activeTxnID; }
- (NSString *)transactionReport:(NSString *)txnID { return [self.operationLog transactionReport:txnID]; }
- (OperationLog *)operationLog { return _operationLog; }

- (void)prepareTransactionWithID:(NSString *)txnID {
    if (txnID.length == 0) return;
    [self.installLock lock];
    if (!self.isInstalling) {
        self.activeTxnID = txnID;
        [[InstallationTransactionCoordinator sharedCoordinator] beginTransaction:txnID];
        self.currentStage = InstallationStagePreparing;
    }
    [self.installLock unlock];
}

- (BOOL)resetFailedInstallationState {
    [self.installLock lock];
    if (self.isInstalling) {
        [self.installLock unlock];
        return NO;
    }
    BOOL hadStaleState = (self.activeTxnID.length > 0 || self.currentStage != InstallationStageIdle);
    self.activeTxnID = nil;
    self.currentStage = InstallationStageIdle;
    [self.installLock unlock];
    if (hadStaleState) {
        NSLog(@"[IPAInstallerPro] Cleared stale failed transaction state");
    }
    return YES;
}

- (void)installIPA:(NSString *)ipaPath
     progressBlock:(void (^)(InstallationStage stage, NSString *statusMessage, float progress))progressBlock
        completion:(void (^)(InstallationResult *result))completion {
    [self.installLock lock];
    if (self.isInstalling) {
        [self.installLock unlock];
        NSString *err = @"Another installation is already in progress. Please wait.";
        if (progressBlock) progressBlock(InstallationStageFailed, err, 1.0);
        if (completion) completion([InstallationResult failureResult:err provider:@"Engine" transaction:@"" error:nil evidence:nil]);
        return;
    }
    self.isInstalling = YES;
    NSString *transactionID = self.activeTxnID.length > 0 ? [self.activeTxnID copy] : [[NSUUID UUID] UUIDString];
    self.activeTxnID = transactionID;
    [self.installLock unlock];

    __weak typeof(self) weakSelf = self;
    __block BOOL didFinalize = NO;
    NSObject *completionGate = [NSObject new];
    void (^finalize)(InstallationResult *) = ^(InstallationResult *result) {
        @synchronized (completionGate) {
            if (didFinalize) {
                NSLog(@"[IPAInstallerPro] Ignoring duplicate completion for transaction %@", transactionID);
                return;
            }
            didFinalize = YES;
        }
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        InstallationTransactionCoordinator *transactionCoordinator = [InstallationTransactionCoordinator sharedCoordinator];
        if (result && result.success && [transactionCoordinator stateForTransaction:transactionID] != InstallationTransactionStateSuccess) {
            NSLog(@"[IPAInstallerPro] Provider reported success without FINAL_SUCCESS state; converting to failure");
            [transactionCoordinator markFailedForTransaction:transactionID reason:@"provider success did not match transaction SUCCESS state"];
            result = [InstallationResult failureResult:@"Transaction success state was not proven" provider:result.providerName ?: @"Provider" transaction:transactionID error:nil evidence:@{ @"transactionState": InstallationTransactionStateName([transactionCoordinator stateForTransaction:transactionID]) }];
        } else if (!result || !result.success) {
            [transactionCoordinator markFailedForTransaction:transactionID reason:result.message ?: @"provider failed"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (result && result.success) {
                strongSelf.currentStage = InstallationStageCompleted;
                if (progressBlock) progressBlock(strongSelf.currentStage, @"Installation complete!", 1.0);
                NSLog(@"[IPAInstallerPro] Installation succeeded via %@", result.providerName ?: @"Provider");
                NSLog(@"[IPAInstallerPro] RuntimeDiagnostics disabled — app will NOT auto-launch");
            } else {
                NSString *message = result.message ?: @"Unknown installation error";
                strongSelf.currentStage = InstallationStageFailed;
                if (progressBlock) progressBlock(strongSelf.currentStage, message, 1.0);
                NSLog(@"[IPAInstallerPro] Installation failed for transaction %@: %@", transactionID, message);
            }
            [strongSelf finishInstallation];
            if (completion) completion(result);
        });
    };

    self.currentStage = InstallationStagePreparing;
    if (progressBlock) progressBlock(self.currentStage, @"Preparing installation...", 0.05);
    if (!ipaPath || ipaPath.length == 0) {
        finalize([InstallationResult failureResult:@"IPA path is empty" provider:@"Engine" transaction:transactionID error:nil evidence:nil]);
        return;
    }

    NSLog(@"[IPAInstallerPro] Starting installation for %@", [ipaPath lastPathComponent]);
    NSArray *available = [self availableProviders];
    if (available.count == 0) {
        NSString *err = @"No installation provider available. Ensure ldid, uicache, and unzip are installed.";
        finalize([InstallationResult failureResult:err provider:@"Engine" transaction:transactionID error:nil evidence:nil]);
        return;
    }

    self.currentStage = InstallationStageValidating;
    if (progressBlock) progressBlock(self.currentStage, @"Validating IPA...", 0.15);
    id<InstallationProvider> provider = available.firstObject;
    NSLog(@"[IPAInstallerPro] Using provider: %@", [provider providerName]);
    self.currentStage = InstallationStageInstalling;
    if (progressBlock) progressBlock(self.currentStage, @"Installing files...", 0.3);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * 60 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @synchronized (completionGate) {
            if (didFinalize) return;
        }
        NSError *timeoutError = [NSError errorWithDomain:@"IPAInstallerPro.InstallationEngine" code:408 userInfo:@{NSLocalizedDescriptionKey: @"انتهت مهلة التثبيت؛ أوقف المحرك العملية لتحرير أداة التثبيت."}];
        NSLog(@"[IPAInstallerPro] Installation watchdog fired for transaction %@", transactionID);
        finalize([InstallationResult failureResult:timeoutError.localizedDescription provider:provider.providerName ?: @"Provider" transaction:transactionID error:timeoutError evidence:@{ @"watchdog": @YES, @"timeoutSeconds": @600 }]);
    });

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __strong typeof(weakSelf) providerOwner = weakSelf;
        if (!providerOwner) return;
        @try {
            [provider installIPA:ipaPath transactionID:transactionID operationLog:providerOwner.operationLog completion:^(InstallationResult *result) {
                finalize(result ?: [InstallationResult failureResult:@"لم يُرجع مزود التثبيت نتيجة" provider:provider.providerName ?: @"Provider" transaction:transactionID error:nil evidence:nil]);
            }];
        } @catch (NSException *exception) {
            NSError *exceptionError = [NSError errorWithDomain:@"IPAInstallerPro.InstallationEngine" code:500 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"استثناء غير متوقع من مزود التثبيت"}];
            finalize([InstallationResult failureResult:exceptionError.localizedDescription provider:provider.providerName ?: @"Provider" transaction:transactionID error:exceptionError evidence:@{ @"exception": @YES }]);
        }
    });
}

- (void)finishInstallation {
    [self.installLock lock];
    self.isInstalling = NO;
    self.activeTxnID = nil;
    self.currentStage = InstallationStageIdle;
    [self.installLock unlock];
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    if (!bundleID || bundleID.length == 0) {
        if (completion) completion(NO, @"Bundle ID is empty");
        return;
    }
    for (id<InstallationProvider> p in self.providers) {
        if ([p isAvailable] && [p respondsToSelector:@selector(uninstallAppWithBundleID:completion:)]) {
            [p uninstallAppWithBundleID:bundleID completion:completion];
            return;
        }
    }
    if (completion) completion(NO, @"No provider available for uninstall");
}

- (void)uninstallAppAtPath:(NSString *)appPath bundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    if (!bundleID || bundleID.length == 0) {
        if (completion) completion(NO, @"Bundle ID is empty");
        return;
    }
    for (id<InstallationProvider> p in self.providers) {
        if ([p isAvailable] && [p respondsToSelector:@selector(uninstallAppAtPath:bundleID:completion:)]) {
            [p uninstallAppAtPath:appPath bundleID:bundleID completion:completion];
            return;
        }
    }
    [self uninstallAppWithBundleID:bundleID completion:completion];
}

@end
