//
//  SpiderJBHideStateStore.h
//  Persistent per-bundleID state for Jailbreak Hiding.
//

#import <Foundation/Foundation.h>
#import "SpiderJBHideTypes.h"

@interface SpiderJBHideAppState : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) SpiderJBHideStatus status;
@property (nonatomic, strong) NSString *lastError;
@property (nonatomic, strong) NSDate *lastAppliedAt;
@property (nonatomic, strong) NSDate *lastVerifiedAt;
@end

@interface SpiderJBHideStateStore : NSObject
+ (instancetype)sharedStore;
- (SpiderJBHideAppState *)stateForBundleID:(NSString *)bundleID;
- (void)setEnabled:(BOOL)enabled forBundleID:(NSString *)bundleID;
- (void)updateStatus:(SpiderJBHideStatus)status error:(NSString *)error forBundleID:(NSString *)bundleID;
- (void)markVerifiedForBundleID:(NSString *)bundleID;
- (NSDictionary<NSString *, SpiderJBHideAppState *> *)allStates;
@end
