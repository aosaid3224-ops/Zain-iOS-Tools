#import <Foundation/Foundation.h>
@class ExecutableCapability;

@interface ExecutableValidator : NSObject

+ (instancetype)sharedValidator;

- (ExecutableCapability *)validateExecutableNamed:(NSString *)name;

- (ExecutableCapability *)validateLDID;

- (ExecutableCapability *)validateUnzip;

- (ExecutableCapability *)validateUICache;

- (NSString *)findExecutableNamed:(NSString *)name;

- (NSArray<NSString *> *)currentSearchPaths;

@end
