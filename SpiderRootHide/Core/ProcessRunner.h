#import <Foundation/Foundation.h>
@class CommandResult;

@interface ProcessRunner : NSObject

+ (instancetype)sharedRunner;

- (CommandResult *)runCommand:(NSString *)path
                    arguments:(NSArray<NSString *> *)arguments
                      timeout:(NSTimeInterval)timeout;

- (void)runCommand:(NSString *)path
         arguments:(NSArray<NSString *> *)arguments
           timeout:(NSTimeInterval)timeout
        completion:(void (^)(CommandResult *result))completion;

@end
