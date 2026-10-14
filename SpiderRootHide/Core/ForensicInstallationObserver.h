#import <Foundation/Foundation.h>
@class ForensicTransactionReport;
@class OperationLog;

@interface ForensicInstallationObserver : NSObject

- (void)beginObservingTransaction:(NSString *)transactionID
                          ipaPath:(NSString *)ipaPath
                         bundleID:(NSString *)bundleID
                         operationLog:(OperationLog *)operationLog;

- (ForensicTransactionReport *)finishObservation;

@property (nonatomic, assign, readonly, getter=isObserving) BOOL observing;
@property (nonatomic, strong, readonly) ForensicTransactionReport *currentReport;
@end
