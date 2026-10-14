#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MachORPathRepair : NSObject

+ (instancetype)sharedRepair;

- (BOOL)repairAppAtPath:(NSString *)appPath
          changedPaths:(NSArray<NSString *> * _Nullable * _Nullable)changedPaths
                 error:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
