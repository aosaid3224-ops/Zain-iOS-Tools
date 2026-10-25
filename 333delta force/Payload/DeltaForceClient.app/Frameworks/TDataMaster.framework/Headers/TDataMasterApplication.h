//
//  TDataMasterApplication.h
//  TDM
//
//  Created by vforkk on 4/7/14.
//  Copyright (c) 2014 TSF4G. All rights reserved.
//
#ifndef TDataMasterApplication_h
#define TDataMasterApplication_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface TDataMasterApplication : NSObject

+ (TDataMasterApplication*)sharedInstance;

- (void)setLogLevel:(int)level;
//- (const char *) GetTDMSDKVersion;
- (void)reportBinaryWithSrcID:(int)srcID eventName:(const char*)eventName data:(const char*)data andLen:(int)len;

- (void)reportEventWithSrcID:(NSNumber*)srcID eventName:(NSString*)eventName AndEventKVArray:(NSArray*)eventKVArray;

- (void)reportAppleASAEvent;

- (BOOL)handleOpenURL:(NSURL *)url;

- (void)registerLifeCycle;

- (void)applicationDidEnterBackground:(UIApplication *)application;

- (void)applicationWillEnterForeground:(UIApplication *)application;

- (void)applicationDidBecomeActive:(UIApplication*)application;

- (void)applicationWillResignActive:(UIApplication*)application;

- (void)applicationWillTerminate:(UIApplication*)application;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error;

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo;


@property(nonatomic, strong) UIViewController* rootVC;
@property(nonatomic, strong) NSMutableArray* observers;
@end
#endif
