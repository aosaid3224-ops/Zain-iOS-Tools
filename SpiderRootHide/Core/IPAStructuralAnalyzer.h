#import <Foundation/Foundation.h>
@class IPAStructuralResult;

@interface IPAStructuralAnalyzer : NSObject

+ (instancetype)sharedAnalyzer;

- (IPAStructuralResult *)analyzeIPAAtPath:(NSString *)ipaPath;

- (IPAStructuralResult *)analyzeIPAAtPath:(NSString *)ipaPath keepExtracted:(BOOL)keep;

- (IPAStructuralResult *)analyzeExtractedPayloadAtPath:(NSString *)payloadPath sourceIPAPath:(NSString *)ipaPath;

@end
