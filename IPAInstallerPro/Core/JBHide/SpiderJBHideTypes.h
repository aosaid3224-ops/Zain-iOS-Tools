//
//  SpiderJBHideTypes.h
//  IPAInstallerPro — Jailbreak Hiding
//
//  Per-app jailbreak-detection mitigation states.
//  Principle: Configured != Applied != Verified. Never assume.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SpiderJBHideStatus) {
    SpiderJBHideStatusOff = 0,        // mechanism absent
    SpiderJBHideStatusConfigured = 1, // toggle saved, mechanism not confirmed
    SpiderJBHideStatusApplied = 2,    // mechanism files in place + static verify
    SpiderJBHideStatusVerified = 3    // proven by real launch probe
};

@interface SpiderJBHideResult : NSObject
@property (nonatomic, assign) BOOL success;
@property (nonatomic, assign) SpiderJBHideStatus status;
@property (nonatomic, strong) NSString *errorMessage;   // nil on success
@property (nonatomic, strong) NSString *detailReport;   // human-readable report
@property (nonatomic, strong) NSDate *completedAt;
+ (instancetype)resultWithSuccess:(BOOL)success status:(SpiderJBHideStatus)status error:(NSString *)error report:(NSString *)report;
@end
