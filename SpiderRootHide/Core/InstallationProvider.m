#import "InstallationProvider.h"

@implementation InstallationResult

+ (InstallationResult *)successResult:(NSString *)msg
                             provider:(NSString *)provider
                          transaction:(NSString *)txnID
                             evidence:(NSDictionary *)evidence {
    InstallationResult *result = [[InstallationResult alloc] init];
    result.success = YES;
    result.message = msg ?: @"Success";
    result.detailedOutput = msg ?: @"Success";
    result.providerName = provider ?: @"Unknown";
    result.transactionID = txnID ?: @"";
    result.bundleID = nil;
    result.error = nil;
    result.evidence = evidence ?: @{};
    return result;
}

+ (InstallationResult *)failureResult:(NSString *)msg
                             provider:(NSString *)provider
                          transaction:(NSString *)txnID
                                error:(NSError *)error
                             evidence:(NSDictionary *)evidence {
    InstallationResult *result = [[InstallationResult alloc] init];
    result.success = NO;
    result.message = msg ?: @"Unknown error";
    result.detailedOutput = msg ?: @"Unknown error";
    result.providerName = provider ?: @"Unknown";
    result.transactionID = txnID ?: @"";
    result.bundleID = nil;
    result.error = error;
    result.evidence = evidence ?: @{};
    return result;
}

@end
