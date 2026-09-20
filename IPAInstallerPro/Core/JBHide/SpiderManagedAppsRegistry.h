//
//  SpiderManagedAppsRegistry.h
//  Lists apps installed/managed by Spider for the Jailbreak Hiding screen.
//
//  Source of truth: SpiderInstalledAppsStore (written at install success).
//  Legacy entries are migrated once from the OperationLog so previously
//  installed apps appear too. Entries whose bundle is currently absent from
//  the device are KEPT in the list (flagged), never silently dropped.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface SpiderManagedApp : NSObject
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *bundlePath;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, assign) BOOL currentlyInstalled; // NO = recorded but not on device now
@end

@interface SpiderManagedAppsRegistry : NSObject
+ (instancetype)sharedRegistry;
- (NSArray<SpiderManagedApp *> *)managedApps;
- (void)refresh;
@end
