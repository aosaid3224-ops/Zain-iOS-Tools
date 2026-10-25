#pragma once

#ifndef GCLOUD_VERSION_CRASHSIGHT
#define GCLOUD_VERSION_CRASHSIGHT "GCLOUD_VERSION_CRASHSIGHT_4.3.9.1073" //用于编译时传入
#endif

#include "UQMMacros.h"

//using namespace UQM;

namespace GCloud {
    namespace CrashSight {

        enum LogSeverity
        {
            LogSilent,
            LogError,
            LogWarning,
            LogInfo,
            LogDebug,
            LogVerbose
        };

        class UQM_EXPORT CrashSightMobileAgent
        {
        public:

            /// Set game type for Android
            /// @param gameType COCOS=1, UNITY=2, UNREAL=3
            static void SetGameType(int gameType);

            /// configs callback type.
            /// @param callbackType 目前是5种类型，用5位表示。第一位表示crash，第二位表示anr，第三位表示u3d c# error，第四位表示js，第五位表示lua
            static void ConfigCallbackType(int32_t callbackType);

            /// Configs the default.
            /// @param channel channel
            /// @param version version
            /// @param user user
            /// @param delay delay
            static void ConfigDefault(const char* channel, const char* version, const char* user, long delay);

            /// Configs the crashServerUrl.
            /// @param crashServerUrl crashServerUrl
            static void ConfigCrashServerUrl(const char* crashServerUrl);

            /// Configs the type of the crash reporter and customized log level to upload
            /// @param logLevel Off=0,Error=1,Warn=2,Info=3,Debug=4
            static void ConfigCrashReporter(int logLevel);

            /// configs the debug mode.
            /// @param enable If set to true< debug mode.
            static void ConfigDebugMode(bool enable);

            /// Set deviceId.
            /// @param deviceId 设备唯一标识
            static void SetDeviceId(const char* deviceId);

            /// Set app deviceId.
            /// @param deviceId
            static void SetCustomizedDeviceID(const char* deviceId);

            static void GetSDKDefinedDeviceID(void* data, int len);

            static void SetCustomizedMatchID(const char* matchId);

            static void GetSDKSessionID(void* data, int len);

            /// Set deviceModel.
            /// @param deviceModel 手机型号
            static void SetDeviceModel(const char* deviceModel);

            /// 设置日志绝对路径.
            /// @param logPath 日志路径
            static void SetLogPath(const char* logPath);

            /// Init sdk with the specified appId.
            /// @param appId App identifier.
            static void InitWithAppId(const char* appId, bool forceOnUiThread);

            static void ReportExceptionPRV(int type, const char* exceptionName, const char* exceptionMsg, const char* exceptionStack, const char *extInfo, const char* extInfoJsonStr, bool quit = false, int dumpNativeType = 0, const char* errorAttachmentPath = "");

            /// Report Exception
            /// @param type type
            /// @param name name
            /// @param reason reason
            /// @param stackTrace stackTrace
            /// @param extras extras, json对象序列化字符串
            /// @param quit quit
            /// @param dumpNativeType 0：关闭，1：调用系统接口dump，3：minidump
            static void ReportException(int type, const char* name, const char* reason, const char* stackTrace, const char* extras, bool quit, int dumpNativeType = 0, const char* errorAttachmentPath = "");

            /// Report Exception
            /// @param type
            /// @param exceptionName
            /// @param exceptionMsg
            /// @param exceptionStack
            /// @param paramsJson map序列化后的JSON字符串
            /// @param dumpNativeType 0：关闭，1：调用系统接口dump，3：minidump
            static void ReportExceptionJson(int type, const char* exceptionName, const char* exceptionMsg, const char* exceptionStack, const char* paramsJson, int dumpNativeType = 0, const char* errorAttachmentPath = "");

            /// Report log statistics
            /// @msgType 消息类型
            /// @msg 消息详情
            static void ReportLogInfo(const char* msgType, const char* msg);

            /// Sets the user identifier.
            /// @param userId User identifier.
            static void SetUserId(const char* userId);

            /// Sets the scene.
            /// @param sceneId Scene identifier.
            static void SetScene(const char *sceneId, bool upload = false);

            /// Adds the scene data.
            /// @param key Key
            /// @param value Value
            static void AddSceneData(const char* key, const char* value);

            /// Prints the log.
            /// @param level level
            /// @param format format
            static void PrintLog(LogSeverity level, const char* format, ...);

            // unity android
            static void CloseCrashReport();

            // unity android
            static void StartCrashReport();

            // unity android
            static void RestartCrashReport();

            /// Set app version.
            /// @param appVersion app version
            static void SetAppVersion(const char* appVersion);


            /// Catch multiple signal from different thread, and upload information of first signal.
            /// @param SetCatchMultiSignal enable
            static void SetCatchMultiSignal(bool enable);

            /// Unwind at most 256 stack frame, and report last frame even if stack string is full.
            /// @param SetUnwindExtraStack enable
            static void SetUnwindExtraStack(bool enable);

            /// Get crash thread id when crash happens. Return -1 while failed.
            static long GetCrashThreadId();

            static bool IsLastSessionCrash();

            static void GetLastSessionUserId(void* data, int len);

            /// Set upload thread num, default 3
            static void SetUploadThreadNum(int num);

            static void TestOomCrash();

            static void TestJavaCrash();

            static void TestOcCrash();

            static void TestNativeCrash();

            static void TestANR();

            static void GetCrashUuid(void* data, int len);

            static void SetLogcatBufferSize(int size);

            static void startDumpRoutine(int dumpMode, int startTimeMode, long startTime, long dumpInterval,
                                         int dumpTimes, bool saveLocal, const char *savePath);

            static void startMonitorFdCount(int interval, int limit, int dumpType);

            static int getExceptionType(const char *name);
            
            static void testUseAfterFree();
            
            static void setEnableGetPackageInfo(bool enable);

            static void setServerEnv(const char *serverEnv);

            static void setEngineInfo(const char *version, const char *buildConfig, const char *language, const char *locale);

            static void setGpuInfo(const char *version, const char *vendor, const char *renderer);

            static void setIsOpengles(bool isOpengles);

            static void enableDetailedPageTracing(bool enable);

            static void useSavedUserId(bool enable);

            static bool checkFdCount(int limit, int dumpType, bool upload);

            static void SetOomLogPath(const char *logPath);

            static void ReportJank(int type, const char* exceptionName,
                                   const char* exceptionMsg, const char* exceptionStack,
                                   const char* extInfoJsonStr, int reportInfoOption, const char* jankAttachmentPath = nullptr);

            static void setEngineMainThread();

            static void ReportStuck(int threadId, int maxChecks, long checkInterval,
                                    const char *name, const char *message, const char *extraInfo,
                                    int dumpNativeType, const char *attachPath);

        private:
            static bool mIsInitialized;

            static const char* GetCsVersion();
        };


    }
}





