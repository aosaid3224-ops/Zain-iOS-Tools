//
//  SpiderManagedAppsRegistry.h
//  Lists apps installed by Spider (from OperationLog), validated via LaunchServices.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface SpiderManagedApp : NSObject
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *bundlePath;
@property (nonatomic, strong) UIImage *icon;
@end

@interface SpiderManagedAppsRegistry : NSObject
+ (instancetype)sharedRegistry;
- (NSArray<SpiderManagedApp *> *)managedApps;
- (void)refresh;
@end
