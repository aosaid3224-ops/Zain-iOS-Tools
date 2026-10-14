#import <Foundation/Foundation.h>
@class IPAStructuralResult;
@class SigningPlan;

@interface SigningPlanner : NSObject

+ (instancetype)sharedPlanner;

- (SigningPlan *)createPlanForStructuralResult:(IPAStructuralResult *)result;

@end
