#import "ForensicInstallationPipeline.h"
#import "ForensicInstallationObserver.h"
#import "ForensicRegistrationProbe.h"
#import "ForensicTypes.h"
#import "DirectInstallationProvider.h"
#import "IPAExtractor.h"
#import "OperationLog.h"
#import "RuntimeDiagnostics.h"
#import "InstallationProvider.h"
#import "RootlessManager.h"

@interface ForensicInstallationPipeline ()
@property (nonatomic, strong) ForensicInstallationObserver *activeObserver;
@end

@implementation ForensicInstallationPipeline

+ (instancetype)sharedPipeline {
    static ForensicInstallationPipeline *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (NSDictionary *)inputFactsAtPath:(NSString *)ipaPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!ipaPath || ipaPath.length == 0) {
        return @{
            @"path": @"",
            @"exists": @NO,
            @"regularFile": @NO,
            @"size": @0,
            @"modifiedAt": @"",
            @"readable": @NO,
            @"extension": @""
        };
    }
    NSDictionary *attrs = [fm attributesOfItemAtPath:ipaPath error:nil];
    BOOL regular = [attrs[NSFileType] isEqualToString:NSFileTypeRegular];
    return @{
        @"path": ipaPath,
        @"exists": @([fm fileExistsAtPath:ipaPath]),
        @"regularFile": @(regular),
        @"size": attrs[NSFileSize] ?: @0,
        @"modifiedAt": attrs[NSFileModificationDate] ?: @"",
        @"readable": @([fm isReadableFileAtPath:ipaPath]),
        @"extension": ipaPath.pathExtension.lowercaseString ?: @""
    };
}

- (void)finishWithObserver:(ForensicInstallationObserver *)observer
                   evidence:(NSDictionary *)evidence
                  finalState:(ForensicInstallState)finalState
             failureReason:(NSString *)failureReason
                  completion:(void (^)(ForensicTransactionReport *, InstallationResult *, RuntimeDiagnosticsResult *))completion
       installationResult:(InstallationResult *)installationResult
             runtimeResult:(RuntimeDiagnosticsResult *)runtimeResult {
    OperationLog *log = [OperationLog sharedLog];
    NSString *txnID = observer.currentReport.transactionID;
    [log recordsForTransaction:txnID];
    ForensicTransactionReport *report = [observer finishObservation];
    if (!report) return;
    NSMutableDictionary *mergedEvidence = [report.evidence mutableCopy] ?: [NSMutableDictionary dictionary];
    [mergedEvidence addEntriesFromDictionary:evidence ?: @{}];
    report.evidence = [mergedEvidence copy];
    report.finalState = finalState;
    report.failureReason = failureReason ?: @"";
    if (completion) completion(report, installationResult, runtimeResult);
}

- (void)runIPAAtPath:(NSString *)ipaPath
   launchAfterInstall:(BOOL)launchAfterInstall
           completion:(void (^)(ForensicTransactionReport *report,
                                InstallationResult *installationResult,
                                RuntimeDiagnosticsResult *runtimeResult))completion {
    OperationLog *log = [OperationLog sharedLog];
    NSString *transactionID = [log beginTransactionForIPA:ipaPath ?: @""];
    IPAExtractedInfo *info = ipaPath.length ? [[IPAExtractor sharedExtractor] extractInfoFromIPA:ipaPath] : nil;
    NSString *bundleID = info.bundleID ?: @"";

    ForensicInstallationObserver *observer = [[ForensicInstallationObserver alloc] init];
    self.activeObserver = observer;
    [observer beginObservingTransaction:transactionID ipaPath:ipaPath bundleID:bundleID operationLog:log];

    NSString *inputRecord = [log beginPhase:OperationPhaseIPAOpen operation:@"forensic live input inspection" target:ipaPath ?: @"" input:@"NSFileManager attributes/readability" transactionID:transactionID];
    NSDictionary *inputFacts = [self inputFactsAtPath:ipaPath];
    BOOL inputOK = inputFacts && [inputFacts[@"exists"] boolValue] && [inputFacts[@"regularFile"] boolValue] && [inputFacts[@"readable"] boolValue] && [inputFacts[@"extension"] isEqualToString:@"ipa"];
    [log endPhase:inputRecord exitCode:inputOK ? 0 : 1 rawOutput:@"" rawError:inputOK ? @"" : @"Input is not a readable regular IPA file" verification:inputOK ? @"Input facts captured" : @"Input inspection failed" verified:inputOK duration:0 context:inputFacts];

    if (!inputOK || !bundleID.length) {
        NSString *reason = !inputOK ? @"Forensic input inspection failed" : @"Bundle ID was not discovered before installation";
        [log endTransaction:transactionID finalResult:OperationResultFailed];
        [self finishWithObserver:observer evidence:@{@"inputFacts": inputFacts, @"bundleIDDiscovery": info ? @"returned-no-bundle-id" : @"no-extractor-result"} finalState:ForensicInstallStateFailed failureReason:reason completion:completion installationResult:nil runtimeResult:nil];
        self.activeObserver = nil;
        return;
    }

    DirectInstallationProvider *provider = [[DirectInstallationProvider alloc] init];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __weak typeof(self) weakSelf = self;
        [provider installIPA:ipaPath transactionID:transactionID operationLog:log completion:^(InstallationResult *installationResult) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            NSString *logicalPath = @"";
            NSString *resolvedPath = @"";
            ForensicRegistrationProbe *probe = [ForensicRegistrationProbe sharedProbe];
            NSDictionary *registration = [probe probeBundleID:bundleID transactionID:transactionID operationLog:log logicalPath:logicalPath resolvedPath:resolvedPath];
            BOOL registered = [registration[@"registeredByAllSources"] boolValue];
            NSMutableDictionary *evidence = [NSMutableDictionary dictionaryWithDictionary:@{
                @"inputFacts": inputFacts,
                @"bundleID": bundleID,
                @"installationSuccessFlag": @(installationResult.success),
                @"installationMessage": installationResult.message ?: @"",
                @"registrationProbe": registration ?: @{},
                @"strictStateRule": @"registration is not launchability; launch is proven only by RuntimeDiagnostics"
            }];
            if (installationResult.evidence) evidence[@"providerEvidence"] = installationResult.evidence;

            if (!installationResult.success) {
                NSString *reason = installationResult.message ?: @"Provider installation failed";
                [strongSelf finishWithObserver:observer evidence:evidence finalState:ForensicInstallStateFailed failureReason:reason completion:completion installationResult:installationResult runtimeResult:nil];
                strongSelf.activeObserver = nil;
                return;
            }

            if (!registered) {
                NSString *reason = @"Provider reported success, but exact Bundle ID registration was not proven by both uicache -l and LaunchServices";
                [strongSelf finishWithObserver:observer evidence:evidence finalState:ForensicInstallStateInstalled failureReason:reason completion:completion installationResult:installationResult runtimeResult:nil];
                strongSelf.activeObserver = nil;
                return;
            }

            if (!launchAfterInstall) {
                [strongSelf finishWithObserver:observer evidence:evidence finalState:ForensicInstallStateRegistered failureReason:@"" completion:completion installationResult:installationResult runtimeResult:nil];
                strongSelf.activeObserver = nil;
                return;
            }

            [[RuntimeDiagnostics sharedDiagnostics] diagnoseAppLaunch:bundleID transactionID:transactionID operationLog:log completion:^(RuntimeDiagnosticsResult *runtimeResult) {
                NSMutableDictionary *runtimeEvidence = [evidence mutableCopy];
                runtimeEvidence[@"runtimeState"] = runtimeResult.state ?: @"UNKNOWN";
                runtimeEvidence[@"runtimeSummary"] = runtimeResult.summary ?: @"";
                runtimeEvidence[@"runtimeCrashDetected"] = @(runtimeResult.crashDetected);
                runtimeEvidence[@"runtimeCrashReportPath"] = runtimeResult.crashReportPath ?: @"";
                ForensicInstallState state = runtimeResult.crashDetected ? ForensicInstallStateCrashed : (runtimeResult.success ? ForensicInstallStateRunning : ForensicInstallStateExited);
                NSString *reason = runtimeResult.success ? @"" : (runtimeResult.terminationReason ?: runtimeResult.summary ?: @"Runtime did not prove a running process");
                [strongSelf finishWithObserver:observer evidence:runtimeEvidence finalState:state failureReason:reason completion:completion installationResult:installationResult runtimeResult:runtimeResult];
                strongSelf.activeObserver = nil;
            }];
        }];
    });
}

@end
