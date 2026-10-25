//
//  CrashSightLog.h
//  CrashSight
//
//  Copyright (c) 2017年 
//

#import <Foundation/Foundation.h>

// Log level for CrashSight Log
typedef NS_ENUM(NSUInteger, CrashSightLogLevel) {
    CrashSightLogLevelSilent  = 0,
    CrashSightLogLevelError   = 1,
    CrashSightLogLevelWarn    = 2,
    CrashSightLogLevelInfo    = 3,
    CrashSightLogLevelDebug   = 4,
    CrashSightLogLevelVerbose = 5,
};
#pragma mark -

OBJC_EXTERN void CSLog(CrashSightLogLevel level, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);

OBJC_EXTERN void CSLogv(CrashSightLogLevel level, NSString *format, va_list args) NS_FORMAT_FUNCTION(2, 0);

#pragma mark -
#define CRASHSIGHT_LOG_MACRO(_level, fmt, ...) [CrashSightLog level:_level tag:nil log:fmt, ##__VA_ARGS__]

#define CSLogError(fmt, ...)   CRASHSIGHT_LOG_MACRO(CrashSightLogLevelError, fmt, ##__VA_ARGS__)
#define CSLogWarn(fmt, ...)    CRASHSIGHT_LOG_MACRO(CrashSightLogLevelWarn,  fmt, ##__VA_ARGS__)
#define CSLogInfo(fmt, ...)    CRASHSIGHT_LOG_MACRO(CrashSightLogLevelInfo, fmt, ##__VA_ARGS__)
#define CSLogDebug(fmt, ...)   CRASHSIGHT_LOG_MACRO(CrashSightLogLevelDebug, fmt, ##__VA_ARGS__)
#define CSLogVerbose(fmt, ...) CRASHSIGHT_LOG_MACRO(CrashSightLogLevelVerbose, fmt, ##__VA_ARGS__)

#pragma mark - Interface
@interface CrashSightLog : NSObject

/**
 *    @brief  初始化日志模块
 *
 *    @param level 设置默认日志级别，默认CSLogLevelSilent
 *
 *    @param printConsole 是否打印到控制台，默认NO
 */
+ (void)initLogger:(CrashSightLogLevel) level consolePrint:(BOOL)printConsole;

/**
 *    @brief 打印CSLogLevelInfo日志
 *
 *    @param format   日志内容 总日志大小限制为：字符串长度30k，条数200
 */
+ (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

/**
 *    @brief  打印日志
 *
 *    @param level 日志级别
 *    @param message   日志内容 总日志大小限制为：字符串长度30k，条数200
 */
+ (void)level:(CrashSightLogLevel) level logs:(NSString *)message;

/**
 *    @brief  打印日志
 *
 *    @param level 日志级别
 *    @param format   日志内容 总日志大小限制为：字符串长度30k，条数200
 */
+ (void)level:(CrashSightLogLevel) level log:(NSString *)format, ... NS_FORMAT_FUNCTION(2, 3);

/**
 *    @brief  打印日志
 *
 *    @param level  日志级别
 *    @param tag    日志模块分类
 *    @param format   日志内容 总日志大小限制为：字符串长度30k，条数200
 */
+ (void)level:(CrashSightLogLevel) level tag:(NSString *) tag log:(NSString *)format, ... NS_FORMAT_FUNCTION(3, 4);

@end
