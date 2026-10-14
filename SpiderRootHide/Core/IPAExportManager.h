#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^IPAExportCompletion)(NSURL * _Nullable ipaURL, NSError * _Nullable error);

@interface IPAExportManager : NSObject
+ (instancetype)sharedManager;
- (void)exportApplicationAtPath:(NSString *)bundlePath
                    suggestedName:(NSString *)suggestedName
                       completion:(IPAExportCompletion)completion;

- (void)cloneApplicationAtPath:(NSString *)bundlePath
                   suggestedName:(NSString *)suggestedName
                   bundleIdentifier:(NSString *)bundleIdentifier
                       completion:(IPAExportCompletion)completion;
@end

NS_ASSUME_NONNULL_END
