//
//  CrashSightConfig.h
//  CrashSight
//
//  Copyright (c) 2016年 
//

#pragma once

#define CS_UNAVAILABLE(x) __attribute__((unavailable(x)))

#if __has_feature(nullability)
#define CS_NONNULL __nonnull
#define CS_NULLABLE __nullable
#define CS_START_NONNULL _Pragma("clang assume_nonnull begin")
#define CS_END_NONNULL _Pragma("clang assume_nonnull end")
#else
#define CS_NONNULL
#define CS_NULLABLE
#define CS_START_NONNULL
#define CS_END_NONNULL
#endif

#import <Foundation/Foundation.h>

#import "CrashSightLog.h"

#define CS_CALLBACK_FLAGS_LUA     0x1
#define CS_CALLBACK_FLAGS_JS      (0x1 << 1)
#define CS_CALLBACK_FLAGS_CSHARP  (0x1 << 2)
#define CS_CALLBACK_FLAGS_CRASH   (0x1 << 4)
#define CS_CALLBACK_FLAGS_CUSTOM  (0x1 << 5)


typedef NS_ENUM(NSInteger, CSCallbackType) {
    CSCallbackTypeNone = 0,
    CSCallbackTypeCrash = 2,
    CSCallbackTypeCShap = 3,
    CSCallbackTypeJS = 5,
    CSCallbackTypeLua = 6,
    CSCallbackTypeCustom = 8,
    CSCallbackTypeJank = 9,
    CSCallbackTypeStuck = 10,
};
typedef CSCallbackType CSExceptionType;

@protocol CrashSightDelegate <NSObject>

@optional
/**
 *  发生异常时回调
 *
 *  @param exception 异常信息
 *
 *  @return 返回需上报记录，随异常上报一起上报
 */
- (NSString * CS_NULLABLE)attachmentForException:(NSException * CS_NULLABLE)exception callbackType:(CSCallbackType)callbackType;

/**
     * 设置UQM的崩溃时触发回调的方法
     * @return 返回崩溃时需要上报的日志路径
     */
- (NSString * CS_NULLABLE)attachmentLogPathForExceptionType:(CSExceptionType)exceptionType;

    /**
     * 设置UQM的崩溃时触发回调的方法
     * 通知日志上报结果
     */
- (void)attachmentLogUploadResultForExceptionType:(CSExceptionType)exceptionType result:(int) result;


/**
 *  策略激活时回调
 *
 *  @param tacticInfo
 *
 *  @return app是否弹框展示
 */
- (BOOL) h5AlertForTactic:(NSDictionary *)tacticInfo;

@end

@interface CrashSightConfig : NSObject

/**
 *  SDK Debug信息开关, 默认关闭
 */
@property (nonatomic, assign) BOOL debugMode;

/**
 *  设置自定义渠道标识
 */
@property (nonatomic, copy) NSString *channel;

/**
 *  设置自定义版本号
 */
@property (nonatomic, copy) NSString *version;

/**
 *  设置自定义设备唯一标识
 */
@property (nonatomic, copy) NSString *deviceIdentifier;

/**
 *  卡顿监控开关，默认关闭
 */
@property (nonatomic) BOOL blockMonitorEnable;

/**
 *  卡顿监控判断间隔，单位为秒
 */
@property (nonatomic) NSTimeInterval blockMonitorTimeout;

/**
 *  设置 App Groups Id (如有使用 CrashSight iOS Extension SDK，请设置该值)
 */
@property (nonatomic, copy) NSString *applicationGroupIdentifier;

/**
 *  进程内还原开关，默认开启
 */
@property (nonatomic) BOOL symbolicateInProcessEnable;

/**
 *  @deprecate
 *  已经改为云控控制，用户配置无效
 *  非正常退出事件记录开关，默认关闭
 */
@property (nonatomic) BOOL unexpectedTerminatingDetectionEnable;

/**
 *  页面信息记录开关，默认开启
 */
@property (nonatomic) BOOL viewControllerTrackingEnable;

/**
 *  CrashSight Delegate
 */
@property (nonatomic, assign) id<CrashSightDelegate> delegate;

/**
 * 控制自定义日志上报，默认值为CrashSightLogLevelSilent，即关闭日志记录功能。
 * 如果设置为CrashSightLogLevelWarn，则在崩溃时会上报Warn、Error接口打印的日志
 */
@property (nonatomic, assign) CrashSightLogLevel reportLogLevel;

/**
 *  崩溃数据过滤器，如果崩溃堆栈的模块名包含过滤器中设置的关键字，则崩溃数据不会进行上报
 *  例如，过滤崩溃堆栈中包含搜狗输入法的数据，可以添加过滤器关键字SogouInputIPhone.dylib等
 */
@property (nonatomic, copy) NSArray *excludeModuleFilter;

/**
 * 控制台日志上报开关，默认开启
 */
@property (nonatomic, assign) BOOL consolelogEnable;

/**
 * @deprecate
 * 崩溃退出超时，如果监听到崩溃后，App一直没有退出，则到达超时时间后会自动abort进程退出
 * 默认值 5s， 单位 秒
 * 当赋值为0时，则不会自动abort进程退出
 */
@property (nonatomic, assign) NSUInteger crashAbortTimeout;

/**
 *  设置自定义联网、crash上报域名
 */
@property (nonatomic, copy) NSString *crashServerUrl;



/// CS_CALLBACK_FLAGS_LUA(0x1) | CS_CALLBACK_FLAGS_JA(0x1 << 1) | CS_CALLBACK_FLAGS_CSHARP(0x1 << 2) | CS_CALLBACK_FLAGS_CRASH(0x1 << 4), default: 0xFFFF
@property (nonatomic, assign) uint32_t callbackFlags;

/**
 *  崩溃处理超时时间，单位秒
 *  defalut：2秒, 小于等于0：不限制（20秒）
 *
 */
@property (nonatomic, assign) int crashProcessTimeout;

/**
 *  配置崩溃上报COS文件绝对路径，必须是文件路径，不支持文件夹路径， 文件最大10MB， 超过部分忽略。
 *
 */
@property (nonatomic, copy) NSString *uploadUserAttchmentFilePath;

@property (nonatomic, copy) NSString *oomAttchmentFilePath;


@property (nonatomic, assign) BOOL ignoreCallSigaltstackFunctionFailed;


@end
