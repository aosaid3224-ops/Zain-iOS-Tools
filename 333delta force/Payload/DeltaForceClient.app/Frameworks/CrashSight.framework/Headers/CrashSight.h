//
//  CrashSight.h
//
//  Version: 4.3.9(1073)
//
//  Copyright (c) 2017年 
//

#import <Foundation/Foundation.h>

#import "CrashSightConfig.h"
#import "CrashSightLog.h"

#define GCLOUD_VERSION_CRASHSIGHT  "GCLOUD_VERSION_CRASHSIGHT_4.3.9.1073.sgprod"



typedef NS_OPTIONS(uint32_t, CSExceptionReprotOption) {
    CSExceptionReprotOptionNone            = 0,
    CSExceptionReprotOptionSystemLog = 1 << 0,
    CSExceptionReprotOptionCustomLog = 1 << 1,
    CSExceptionReprotOptionKV = 1 << 2,
    CSExceptionReprotOptionCallback = 1 << 3,
    CSExceptionReprotOptionDumpStack = 1 << 4,
};

@interface CrashSight : NSObject

/**
 *  初始化CrashSight,使用默认CrashSightConfigs
 *
 *  @param appId 注册CrashSight分配的应用唯一标识
 */
+ (void)startWithAppId:(NSString * CS_NULLABLE)appId;

/**
 *  使用指定配置初始化CrashSight
 *
 *  @param appId 注册CrashSight分配的应用唯一标识
 *  @param config 传入配置的 CrashSightConfig
 */
+ (void)startWithAppId:(NSString * CS_NULLABLE)appId
                config:(CrashSightConfig * CS_NULLABLE)config;

/**
 *  使用指定配置初始化CrashSight
 *
 *  @param appId 注册CrashSight分配的应用唯一标识
 *  @param development 是否开发设备
 *  @param config 传入配置的 CrashSightConfig
 */
+ (void)startWithAppId:(NSString * CS_NULLABLE)appId
     developmentDevice:(BOOL)development
                config:(CrashSightConfig * CS_NULLABLE)config;

/**
 *  设置用户标识
 *
 *  @param userId 用户标识
 */
+ (void)setUserIdentifier:(NSString *)userId;

/**
 *  更新版本信息
 *
 *  @param version 应用版本信息
 */
+ (void)updateAppVersion:(NSString *)version;

/**
 *  设置关键数据，随崩溃信息上报
 *
 *  @param value KEY
 *  @param key VALUE
 */
+ (void)setUserValue:(NSString *)value
              forKey:(NSString *)key;

/**
 *  获取USER ID
 *
 *  @return USER ID
 */
+ (NSString *)crashSightUserIdentifier;

/**
 *  获取关键数据
 *
 *  @return 关键数据
 */
+ (NSDictionary * CS_NULLABLE)allUserValues;


+ (void)setUserSceneTag:(NSString *)userSceneTag isUpload:(bool)upload;


+ (NSString *)currentUserSceneTag;

/**
 *  获取设备ID
 *
 *  @return 设备ID
 */
+ (NSString *)crashSightDeviceId;

/**
 *  上报自定义Objective-C异常
 *
 *  @param exception 异常信息
 */
+ (void)reportException:(NSException *)exception;

/**
 *  上报错误
 *
 *  @param error 错误信息
 */
+ (void)reportError:(NSError *)error;

/**
 *    @brief 上报自定义错误
 *
 *    @param category    类型(Cocoa=3,CSharp=4,JS=5,Lua=6)
 *    @param aName       名称
 *    @param aReason     错误原因
 *    @param aStackArray 堆栈
 *    @param info        附加数据
 *    @param terminate   上报后是否退出应用进程
 */
+ (void)reportExceptionWithCategory:(NSUInteger)category
                               name:(NSString *)aName
                             reason:(NSString *)aReason
                          callStack:(NSArray *)aStackArray
                          extraInfo:(NSDictionary *)info
                       terminateApp:(BOOL)terminate
                       dumpDataType:(int) dumpDataType
                errorAttachmentPath:(NSString *)errorAttachmentPath;


/**
 *    @brief 上报自定义错误
 *
 *    @param category    类型(Cocoa=3,CSharp=4,JS=5,Lua=6)
 *    @param aName       名称
 *    @param aReason     错误原因
 *    @param aStackArray 堆栈
 *    @param info        附加数据
 *    @param terminate   上报后是否退出应用进程
 */
+ (void)reportExceptionWithCategory:(NSUInteger)category
                               name:(NSString *)aName
                             reason:(NSString *)aReason
                          callStack:(NSArray *)aStackArray
                          extraInfoJSONString:(NSString *)info
                       terminateApp:(BOOL)terminate
                       dumpDataType:(int) dumpDataType
                errorAttachmentPath:(NSString *)errorAttachmentPath;


+ (void) reportLogInfo:(NSString *)messageType message:(NSString *)message;


+ (void)reportJankWithName:(NSString *)name message:(NSString *)message stack:(NSArray *)stack extraInfo:(NSDictionary *)extraInfo  option:(CSExceptionReprotOption)option attachmentPath:(nullable NSString *)attachmentPath;

/**
 *  SDK 版本信息
 *
 *  @return SDK版本号
 */
+ (NSString *)sdkVersion;

/**
 *  APP 版本信息
 *
 *  @return SDK版本号
 */
+ (NSString *)appVersion;

/**
 *  App 是否发生了连续闪退
 *  如果 启动SDK 且 5秒内 闪退，且次数达到 3次 则判定为连续闪退
 *
 *  @return 是否连续闪退
 */
+ (BOOL)isAppCrashedOnStartUpExceedTheLimit;

/**
 *  关闭crashSight监控
 */
+ (void)closeCrashReport;

/**
 *  再次注册CrashSight对Crash监听
 */
+ (void)reregisterCrashHandler;

/**
 *  设置上报URL，可在初始化CrashSight后动态设置
 */
+ (void)setServerUrl:(NSString *)url;

/**
 *  设置上报附件的绝对路径
 */
+ (void)setAttachmentPath:(NSString *)path;

+ (int)getCrashThreadId;


+ (NSString *)crashSightSessionId;

+ (BOOL)isLastSessionCrash;

+ (NSString *)getLastSessionUserId;

+ (NSDictionary *)ccConifg;

+ (int)getExceptionType:(NSString *)name;

+ (void)setServerEnv:(NSString *)serverEnv;

+ (void)setEngineInfo:(NSString *)version buildConfig:(NSString *)buildConfig language:(NSString *)language locale:(NSString *)locale;

+ (void)enableDetailedPageTracing:(bool)enable;

+ (void)useSavedUserId:(bool)enable;

+ (void)reportStuckWithThreadIndex:(int)threadIndex
                         maxChecks:(int)maxChecks
                     checkInterval:(NSTimeInterval)checkInterval
                              name:(NSString *)name
                           message:(NSString *)message
                         extraInfo:(NSString *)extraInfo
                    dumpNativeType:(int)dumpNativeType
                        attachPath:(NSString *)attachPath;




// 必须在lua线程调用， 否则捕获lua堆栈时会崩溃
+ (void)setLuaState:(nonnull void*)lua;

+ (void)setLuaFuncGetglobal:(nonnull void *)getglobal getfield:(nonnull void *)getfield pushstring:(nonnull void *)pushstring pushinteger:(nonnull void *)pushinteger pcallk:(nonnull void *)pcallk tolstring:(nonnull void *)tolstring settop:(nonnull void *)settop;

+ (void)setEngineMainThread;

@end
