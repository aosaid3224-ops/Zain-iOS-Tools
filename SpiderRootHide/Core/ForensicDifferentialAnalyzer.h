#import <Foundation/Foundation.h>
@class IPAStructuralResult;

@interface ForensicDifferentialAnalyzer : NSObject
+ (instancetype)sharedAnalyzer;

- (NSDictionary *)compareWorkingIPA:(NSString *)workingIPA
                          crashIPA:(NSString *)crashIPA;

- (NSString *)reportForComparison:(NSDictionary *)comparison;
@end
