//
//  GCloudAppLifecycle.h
//  GCloudPluginManager
//
//  Created by cedar on 2018/8/8.
//  Copyright © 2018年 GCloud. All rights reserved.
//

#ifndef GCloudAppLifecycle_h
#define GCloudAppLifecycle_h

#import "TargetConditionals.h"
#if TARGET_OS_IOS || TARGET_OS_IPHONE

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "GCloudAppLifecycleObserver.h"

NS_ASSUME_NONNULL_BEGIN

@interface GCloudAppLifecycle : NSObject

@property(atomic, assign) UIApplicationState innerAppState;

+ (GCloudAppLifecycle*) sharedInstance;

- (void) addObserver:(NSObject<GCloudAppLifecycleObserver>*) observer;

- (void) addObserverByName:(NSString *) observerName;

- (void) removeObserver:(NSObject<GCloudAppLifecycleObserver>*) observer;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;

- (BOOL)handleOpenURL:(NSURL *)url;

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options;

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation;

- (void)applicationDidEnterBackground:(UIApplication *)application;

- (void)applicationWillEnterForeground:(UIApplication *)application;

- (void)applicationDidBecomeActive:(UIApplication*)application;

- (void)applicationWillResignActive:(UIApplication*)application;

- (void)applicationWillTerminate:(UIApplication*)application;

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application;

- (void) application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error;

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler;

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo;

#pragma clang diagnostic push  
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#if defined(TARGET_OS_VISION) && (TARGET_OS_VISION)
#else
- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification;
#endif

#pragma clang diagnostic pop

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray * _Nullable))restorationHandler;

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(nullable UIWindow *)window  NS_AVAILABLE_IOS(6_0) __TVOS_PROHIBITED;

- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)(void))completionHandler;

//========================Lifecycle Utils start========================
- (Boolean) hasExtraSupportWindowImplementation;
//========================Lifecycle Utils end========================

#pragma mark - UIScene Delegate Application
- (NSObject *)application:(UIApplication *)application configurationForConnectingSceneSession:(NSObject *)connectingSceneSession options:(NSObject *)options;

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<NSObject *> *)sceneSessions;

#pragma mark - UIScene Delegate
- (void)scene:(NSObject *)scene willConnectToSession:(NSObject *)session options:(NSObject *)connectionOptions;

- (void)sceneDidDisconnect:(NSObject *)scene;

- (void)sceneDidBecomeActive:(NSObject *)scene;

- (void)sceneWillResignActive:(NSObject *)scene;

- (void)sceneWillEnterForeground:(NSObject *)scene;

- (void)sceneDidEnterBackground:(NSObject *)scene;

#pragma mark - UIScene Delegate System Integration
- (void)scene:(NSObject *)scene openURLContexts:(NSSet<NSObject *> *)URLContexts;

- (nullable NSUserActivity *)stateRestorationActivityForScene:(NSObject *)scene;

- (void)scene:(NSObject *)scene restoreInteractionStateWithUserActivity:(NSUserActivity *)stateRestorationActivity;

#pragma mark - UIScene Delegate User Activity Integration
- (void)scene:(NSObject *)scene willContinueUserActivityWithType:(NSString *)userActivityType;

- (void)scene:(NSObject *)scene continueUserActivity:(NSUserActivity *)userActivity;

- (void)scene:(NSObject *)scene didFailToContinueUserActivityWithType:(NSString *)userActivityType error:(NSError *)error;

- (void)scene:(NSObject *)scene didUpdateUserActivity:(NSUserActivity *)userActivity;


@property(nonatomic, strong) NSMutableArray* observers;

@end

NS_ASSUME_NONNULL_END

#endif/* #if TARGET_OS_IOS || TARGET_OS_IPHONE*/

#endif /* GCloudAppLifecycle_h */
