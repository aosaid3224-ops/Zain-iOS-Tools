#import "InstallationTransactionCoordinator.h"

static BOOL InstallationTransactionTransitionAllowed(InstallationTransactionState from, InstallationTransactionState to) {
    if (from == InstallationTransactionStatePending && (to == InstallationTransactionStateAnalyzing || to == InstallationTransactionStatePreparing || to == InstallationTransactionStateFailed)) return YES;
    if (from == InstallationTransactionStateAnalyzing && (to == InstallationTransactionStatePreparing || to == InstallationTransactionStateFailed)) return YES;
    if (from == InstallationTransactionStatePreparing && (to == InstallationTransactionStateInstalling || to == InstallationTransactionStateSigning || to == InstallationTransactionStateFailed)) return YES;
    if (from == InstallationTransactionStateInstalling && (to == InstallationTransactionStateSigning || to == InstallationTransactionStateVerifyingInstall || to == InstallationTransactionStateFailed || to == InstallationTransactionStateRollback)) return YES;
    if (from == InstallationTransactionStateSigning && (to == InstallationTransactionStateVerifyingInstall || to == InstallationTransactionStateFailed || to == InstallationTransactionStateRollback)) return YES;
    if (from == InstallationTransactionStateVerifyingInstall && (to == InstallationTransactionStateRegistering || to == InstallationTransactionStateFailed || to == InstallationTransactionStateRollback)) return YES;
    if (from == InstallationTransactionStateRegistering && (to == InstallationTransactionStateVerifyingRegistration || to == InstallationTransactionStateRollback || to == InstallationTransactionStateFailed)) return YES;
    if (from == InstallationTransactionStateVerifyingRegistration && (to == InstallationTransactionStateLaunching || to == InstallationTransactionStateRollback || to == InstallationTransactionStateFailed)) return YES;
    if (from == InstallationTransactionStateLaunching && (to == InstallationTransactionStateSuccess || to == InstallationTransactionStateRollback || to == InstallationTransactionStateFailed)) return YES;
    if (from == InstallationTransactionStateRollback && to == InstallationTransactionStateFailed) return YES;
    return NO;
}

NSString *InstallationTransactionStateName(InstallationTransactionState state) {
    switch (state) {
        case InstallationTransactionStatePending: return @"PENDING";
        case InstallationTransactionStateAnalyzing: return @"ANALYZING";
        case InstallationTransactionStatePreparing: return @"PREPARING";
        case InstallationTransactionStateSigning: return @"SIGNING";
        case InstallationTransactionStateInstalling: return @"INSTALLING";
        case InstallationTransactionStateVerifyingInstall: return @"VERIFYING_INSTALL";
        case InstallationTransactionStateRegistering: return @"REGISTERING";
        case InstallationTransactionStateVerifyingRegistration: return @"VERIFYING_REGISTRATION";
        case InstallationTransactionStateLaunching: return @"LAUNCHING";
        case InstallationTransactionStateSuccess: return @"SUCCESS";
        case InstallationTransactionStateFailed: return @"FAILED";
        case InstallationTransactionStateRollback: return @"ROLLBACK";
    }
    return @"UNKNOWN";
}

@interface InstallationTransactionCoordinator ()
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *states;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *reasons;
@end

@implementation InstallationTransactionCoordinator

+ (instancetype)sharedCoordinator {
    static InstallationTransactionCoordinator *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _stateQueue = dispatch_queue_create("com.aosaid.ipainstallerpro.transaction-state", DISPATCH_QUEUE_SERIAL);
        _states = [NSMutableDictionary dictionary];
        _reasons = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)beginTransaction:(NSString *)transactionID {
    if (!transactionID.length) return NO;
    __block BOOL accepted = NO;
    dispatch_sync(self.stateQueue, ^{
        NSNumber *existing = self.states[transactionID];
        if (!existing) {
            self.states[transactionID] = @(InstallationTransactionStatePending);
            accepted = YES;
        } else if (existing.integerValue == InstallationTransactionStatePending) {
            accepted = YES;
        }
    });
    return accepted;
}

- (InstallationTransactionState)stateForTransaction:(NSString *)transactionID {
    __block InstallationTransactionState state = InstallationTransactionStateFailed;
    dispatch_sync(self.stateQueue, ^{
        NSNumber *value = self.states[transactionID];
        if (value) state = value.integerValue;
    });
    return state;
}

- (BOOL)transitionTransaction:(NSString *)transactionID toState:(InstallationTransactionState)state reason:(NSString *)reason {
    if (!transactionID.length) return NO;
    __block BOOL accepted = NO;
    dispatch_sync(self.stateQueue, ^{
        NSNumber *currentValue = self.states[transactionID];
        if (!currentValue) return;
        InstallationTransactionState current = currentValue.integerValue;
        if (current == state && current == InstallationTransactionStateFailed) return;
        if (current == InstallationTransactionStateFailed || current == InstallationTransactionStateSuccess) return;
        if (!InstallationTransactionTransitionAllowed(current, state)) return;
        self.states[transactionID] = @(state);
        self.reasons[transactionID] = reason ?: @"";
        accepted = YES;
    });
    if (!accepted) NSLog(@"[Transaction] rejected %@ -> %@ (%@)", transactionID, InstallationTransactionStateName(state), reason ?: @"invalid transition");
    return accepted;
}

- (BOOL)beginRegistrationForTransaction:(NSString *)transactionID reason:(NSString *)reason {
    __block BOOL accepted = NO;
    dispatch_sync(self.stateQueue, ^{
        NSNumber *value = self.states[transactionID];
        if (!value || value.integerValue != InstallationTransactionStateVerifyingInstall) return;
        self.states[transactionID] = @(InstallationTransactionStateRegistering);
        self.reasons[transactionID] = reason ?: @"install verification passed";
        accepted = YES;
    });
    if (!accepted) NSLog(@"[Transaction] registration rejected before VERIFYING_INSTALL_SUCCESS: %@", transactionID);
    return accepted;
}

- (BOOL)markRegistrationVerifiedForTransaction:(NSString *)transactionID reason:(NSString *)reason {
    return [self transitionTransaction:transactionID toState:InstallationTransactionStateVerifyingRegistration reason:reason ?: @"registration command completed"];
}

- (BOOL)beginRollbackForTransaction:(NSString *)transactionID reason:(NSString *)reason {
    __block BOOL accepted = NO;
    dispatch_sync(self.stateQueue, ^{
        NSNumber *value = self.states[transactionID];
        if (!value) return;
        InstallationTransactionState current = value.integerValue;
        if (current == InstallationTransactionStateSuccess || current == InstallationTransactionStateFailed || current == InstallationTransactionStateRollback) return;
        self.states[transactionID] = @(InstallationTransactionStateRollback);
        self.reasons[transactionID] = reason ?: @"rollback requested";
        accepted = YES;
    });
    return accepted;
}

- (void)markFailedForTransaction:(NSString *)transactionID reason:(NSString *)reason {
    if (!transactionID.length) return;
    dispatch_sync(self.stateQueue, ^{
        if (self.states[transactionID]) {
            self.states[transactionID] = @(InstallationTransactionStateFailed);
            self.reasons[transactionID] = reason ?: @"transaction failed";
        }
    });
}

- (BOOL)markSuccessForTransaction:(NSString *)transactionID reason:(NSString *)reason {
    return [self transitionTransaction:transactionID toState:InstallationTransactionStateSuccess reason:reason ?: @"transaction completed successfully"];
}

- (BOOL)isRegistrationAllowedForTransaction:(NSString *)transactionID {
    return [self stateForTransaction:transactionID] == InstallationTransactionStateVerifyingInstall;
}

- (BOOL)isTerminalForTransaction:(NSString *)transactionID {
    InstallationTransactionState state = [self stateForTransaction:transactionID];
    return state == InstallationTransactionStateSuccess || state == InstallationTransactionStateFailed;
}

@end
