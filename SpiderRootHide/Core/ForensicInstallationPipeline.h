#import <Foundation/Foundation.h>
@class ForensicTransactionReport;
@class InstallationResult;
@class RuntimeDiagnosticsResult;

@interface ForensicInstallationPipeline : NSObject
+ (instancetype)sharedPipeline;

- (void)runIPAAtPath:(NSString *)ipaPath
   launchAfterInstall:(BOOL)launchAfterInstall
           completion:(void (^)(ForensicTransactionReport *report,
                                InstallationResult *installationResult,
                                RuntimeDiagnosticsResult *runtimeResult))completion;
@end
