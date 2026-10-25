#ifndef CSLogger_hpp
#define CSLogger_hpp

#include "UQMMacros.h"
#include <stdarg.h>

#ifndef CS_LOG_TAG
#define CS_LOG_TAG "[CrashSightPlugin-Native]"
#endif

// your convenient logger macro
#define CSLoggerDebug(fmt, ...) CSLogger::log(CSLoggerLevel::CSLoggerLevelDebug, CS_LOG_TAG, fmt, ##__VA_ARGS__);
#define UQM_LOG_DEBUG(fmt, ...) CSLogger::log(CSLoggerLevel::CSLoggerLevelDebug, CS_LOG_TAG, fmt, ##__VA_ARGS__)

#define CSLoggerInfo(fmt, ...)  CSLogger::log(CSLoggerLevel::CSLoggerLevelInfo, CS_LOG_TAG, fmt, ##__VA_ARGS__);
#define CSLoggerWarn(fmt, ...)  CSLogger::log(CSLoggerLevel::CSLoggerLevelWarn, CS_LOG_TAG, fmt, ##__VA_ARGS__);
#define CSLoggerError(fmt, ...) CSLogger::log(CSLoggerLevel::CSLoggerLevelError, CS_LOG_TAG, fmt, ##__VA_ARGS__);
#define UQM_LOG_ERROR(fmt, ...) CSLogger::log(CSLoggerLevel::CSLoggerLevelError, CS_LOG_TAG, fmt, ##__VA_ARGS__)

NS_UQM_BEGIN

typedef enum
{
    CSLoggerLevelDebug = 0,
    CSLoggerLevelInfo,
    CSLoggerLevelWarn,
    CSLoggerLevelError,
    CSLoggerLevelSilent
} CSLoggerLevel;

class UQM_EXPORT CSLogger
{
private:
    static CSLoggerLevel _loggerLevel;

public:
    static void setLoggerLevel(CSLoggerLevel loggerLevel);

    static void log(CSLoggerLevel loggerLevel, const char *tag, const char *fmt, ...);

    static void logv(CSLoggerLevel loggerLevel, const char *tag, const char *fmt, va_list args);
};

NS_UQM_END

#endif /* CSLogger_hpp */
