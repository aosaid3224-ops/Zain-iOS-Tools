//
//  UQMLog.hpp
//  CrashSight
//
//  Created by joyfyzhang on 2020/9/3.
//  Copyright © 2020 joyfyzhang. All rights reserved.
//

#ifndef UQMLog_hpp
#define UQMLog_hpp

#include <string>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "UQMMacros.h"
#include "UQMCompatLayer.h"
#include "CSLogger.h"
#if UQM_PLATFORM_WINDOWS || PLATFORM_LINUX
#else
#include <sys/cdefs.h>
#include <sys/time.h>
#include <unistd.h>
#include "zlib.h"
#endif


// 定义此宏 会在 release 日志宏中打印日志到控制台
#ifndef DEBUG
#define DEBUG
#endif

#ifndef UQM_LOG_TAG
#define UQM_LOG_TAG "[CrashSightPlugin-Native]"
#endif

#ifdef ANDROID
#define UQM_LOG_MAX_LENGTH 1023 //冗余一位，用于解决最后一个是汉字导致被截断的问题
#elif defined(__APPLE__)
#define UQM_LOG_MAX_LENGTH 4096
#endif


//#define __UQM_FILENAME1__ (strrchr(__FILE__, '/') ? (strrchr(__FILE__, '/') + 1):__FILE__)
//#define __UQM_FILENAME2__ (strrchr(__FILE__, '\\') ? (strrchr(__FILE__, '\\') + 1):__FILE__)
//#define __UQM_FILENAME__ (strrchr(__FILE__, '/') ? (__UQM_FILENAME1__):(__UQM_FILENAME2__))

//#ifdef UQM_NO_LOG_DEBUG
//#define UQM_LOG_DEBUG(...)
//#define UQM_LOG_ERROR(...)
//#define UQM_LOG_JSON(level, ...)
//#else
//#define UQM_LOG_DEBUG(...)          UQMLogger(kUQMLevelDebug, UQM_LOG_TAG, __UQM_FILENAME__, __FUNCTION__, __LINE__).console().writeLog(__VA_ARGS__)
//#define UQM_LOG_ERROR(...)          UQMLogger(kUQMLevelError, UQM_LOG_TAG, __UQM_FILENAME__, __FUNCTION__, __LINE__).console().writeLog(__VA_ARGS__)
//#endif


NS_UQM_BEGIN

    typedef enum {
        kUQMLevelDebug = 0,  // 调试使用日志  精简日志，kLevelVerbose、kLevelInfo、kLevelWarn 都合并成Debug
        kUQMLevelError,  // 错误日志
    } UQMLogLevel;

    typedef struct {
        UQMLogLevel level;
        const char *tag;
        const char *fileName;
        const char *funcName;
        int line;
#if UQM_PLATFORM_WINDOWS || PLATFORM_LINUX
#else
        struct timeval timeval;
#endif
        long long pid;
        long long tid;
        long long mainTid;
    } UQMLogInfo;





    class UQM_EXPORT UQMLogger {
    public:

        UQMLogger(UQMLogLevel level, const char *tag, const char *fileName, const char *funcName, int line);

        ~UQMLogger();

        // 是否打印日志到控制台
        UQMLogger &console();

#if UQM_PLATFORM_WINDOWS || PLATFORM_LINUX
        UQMLogger &writeLog(const char *fmt, ...);
#else
        // 此接口独立出来 - 方便后续格式化
        UQMLogger &writeLog(const char *fmt, ...)__attribute__((format(printf, 2, 3)));
#endif

        static void consoleFormatLogVA(const UQMLogInfo *info, const char *message);
        static void consoleFormatLog(const UQMLogInfo *info, const char *format);
        static void consoleLog(const int level, const char *resultLog, ...);

        static long long getPid() {
#if UQM_PLATFORM_WINDOWS || PLATFORM_LINUX
            return -1;
#else
            return getpid();
#endif
        }

        static long long getTid() {
#if UQM_PLATFORM_WINDOWS || PLATFORM_LINUX
            return -1;
#else
#ifdef __APPLE__
            return -1;
#else
            return pthread_self();
#endif
#endif
        }

        static long long getMainTid() {
#if UQM_PLATFORM_WINDOWS || PLATFORM_LINUX
            return -1;
#else
#ifdef __APPLE__
            return -1;
#else
            return gettid();
#endif
#endif
        }

    private:
        UQMLogInfo info;
        bool isConsole;
        UQMString curLogMsg;
    };

NS_UQM_END

#endif /* UQMLog_hpp */
