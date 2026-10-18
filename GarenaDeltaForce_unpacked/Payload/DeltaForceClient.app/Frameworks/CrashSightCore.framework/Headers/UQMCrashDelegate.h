//
//  UQMCrashDelegate.h
//  UQMCore
//
//  Created by joyfyzhang on 2021/1/8.
//  Copyright © 2021 joyfyzhang. All rights reserved.
//

#ifndef UQMCrashDelegate_h
#define UQMCrashDelegate_h

#import <Foundation/Foundation.h>

@protocol UQMCrashDelegate <NSObject>

@required

- (void)configCallbackTypeBeforeInit: (int32_t)callbackType;

- (void)configCrashHandleTimeout: (int32_t)timeout;

- (void)initCrashReport:(NSString *)appId unexpectedTerminatingDetectionEnable:(bool)unexpectedTerminatingDetectionEnable debugMode:(bool)debugMode serverUrl:(NSString *)serverUrl;

@optional

- (void)reportLog:(int)level tag:(NSString *)tag log:(NSString *)log;

- (void)setUserData:(NSString *)key value:(NSString *)value;

- (void)setUserId: (NSString *)userId;

- (void)setAppId: (NSString *)appId;

- (void)setUserSceneTag: (NSString *)userSceneTag isUpload:(bool)upload;

- (void)reportException:(int)type exceptionName:(NSString *)exceptionName
        exceptionMsg:(NSString *)exceptionMsg
        exceptionStack:(NSString *)exceptionStack
        extInfo:(NSDictionary *)extInfo
        extInfoJsonStr:(NSString *)extInfoJsonStr
        quit:(bool)quit
        dumpNativeType:(int)dumpNativeType
        errorAttachmentPath:(NSString *)errorAttachmentPath;

-(void)reportLogInfo:(NSString*)msgType msg:(NSString*)msg;

- (void)setIsAppForeground: (bool)isAppForeground;

- (void)setAppVersion: (NSString *)appVersion;

// agent
- (void)initWithAppId:(NSString *) appId;

- (void)configCrashServerUrlBeforeInit: (NSString *)serverUrl;

- (void)configDefaultBeforeInit: (NSString *)channel version:(NSString *)version user:(NSString *)user delay:(long)delay;

- (void)configCrashReporterLogLevelBeforeInit: (int)logLevel;

- (void)configDebugModeBeforeInit: (bool) enable;

- (void)logRecord: (int)level message: (NSString *)message;

- (void)setLogPath: (NSString *)logPath;

-(void)closeCrashReport;

-(void)reregisterCrashHandler;

- (long)getCrashThreadId;

- (void)setAppDeviceId: (NSString *)deviceId;

-(NSString*)getBackendDeviceId;

- (void)setCustomizedMatchID: (NSString *)matchId;

-(NSString*)getSDKSessionID;

-(BOOL)isLastSessionCrash;

-(NSString*)getLastSessionUserId;

-(int)getExceptionType:(NSString *)name;

-(void)setServerEnv:(NSString *)serverEnv;

-(void)setEngineInfo:(NSString *)version buildConfig:(NSString *)buildConfig language:(NSString *)language locale:(NSString *)locale;

- (void)enableDetailedPageTracing: (bool) enable;

- (void)useSavedUserId: (bool) enable;

- (void)setOomLogPath: (NSString *)logPath;

-(void)reportJank:(int)type exceptionName:(NSString *)name exceptionMsg:(NSString *) msg exceptionStack:(NSString *)stack extInfoJsonStr:(NSString *)extra reportInfoOption:(int)reportInfoOption jankAttachmentPath:(NSString *)attachPath;

-(void)reportStuckWithThreadIndex:(int)threadIndex
                        maxChecks:(int)maxChecks
                    checkInterval:(NSTimeInterval)checkInterval
                             name:(NSString *)name
                          message:(NSString *)message
                        extraInfo:(NSString *)extraInfo
                   dumpNativeType:(int)dumpNativeType
                       attachPath:(NSString *)attachPath;

-(void)setEngineMainThread;

@end

#endif /* UQMCrashDelegate_h */
