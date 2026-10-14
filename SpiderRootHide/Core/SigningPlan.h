#import <Foundation/Foundation.h>
@class SigningTarget;

@interface SigningPlan : NSObject

@property (nonatomic, strong) NSString *ipaPath;
@property (nonatomic, strong) NSArray<SigningTarget *> *targets;
@property (nonatomic, strong) NSMutableArray<NSString *> *warnings;
@property (nonatomic, strong) NSMutableArray<NSString *> *recommendations;
@property (nonatomic, assign) BOOL isViable;
@property (nonatomic, strong) NSString *viabilityReason;
@property (nonatomic, assign) NSInteger totalTargets;
@property (nonatomic, assign) NSInteger preserveCount;
@property (nonatomic, assign) NSInteger genericCount;
@property (nonatomic, assign) NSInteger minimalCount;
@property (nonatomic, assign) NSInteger skipCount;
@property (nonatomic, assign) NSInteger complexTargetsCount;
@property (nonatomic, strong) NSDate *planCreatedAt;
@property (nonatomic, strong) NSString *plannerVersion;

- (instancetype)init;
- (NSArray<SigningTarget *> *)targetsOrderedForSigning;
- (NSString *)detailedReport;
- (NSDictionary *)dictionaryRepresentation;

@end
