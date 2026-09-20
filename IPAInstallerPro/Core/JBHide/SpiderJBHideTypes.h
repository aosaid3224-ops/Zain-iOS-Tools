//
//  SpiderJBHideTypes.h
//  IPAInstallerPro — Jailbreak Hiding
//
//  Strict state machine. Toggle ON never equals "protection active".
//   Off        — mechanism absent
//   Configured — requested, saved, not yet applied
//   Applied    — mechanism files in place + static checks pass
//   Verified   — proven by a real launch + in-process load marker
//   Failed     — operation did not complete or could not be proven
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SpiderJBHideStatus) {
    SpiderJBHideStatusOff = 0,
    SpiderJBHideStatusConfigured = 1,
    SpiderJBHideStatusApplied = 2,
    SpiderJBHideStatusVerified = 3,
    SpiderJBHideStatusFailed = 4
};

@interface SpiderJBHideResult : NSObject
@property (nonatomic, assign) BOOL success;
@property (nonatomic, assign) SpiderJBHideStatus status;
@property (nonatomic, strong) NSString *errorMessage;   // nil on success
@property (nonatomic, strong) NSString *detailReport;   // human-readable report
@property (nonatomic, strong) NSDate *completedAt;
+ (instancetype)resultWithSuccess:(BOOL)success status:(SpiderJBHideStatus)status error:(NSString *)error report:(NSString *)report;
@end
