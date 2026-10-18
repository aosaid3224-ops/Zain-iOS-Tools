//
//  UQMCrashIMPL.h
//  CrashSight
//
//  Created by joyfyzhang on 2020/9/4.
//  Copyright © 2020 joyfyzhang. All rights reserved.
//

#ifndef UQMCrashIMPL_h
#define UQMCrashIMPL_h

#include "UQMDefine.h"
#include "UQMSingleton.h"

NS_UQM_BEGIN

class UQMCrashIMPL : public UQMSingleton<UQMCrashIMPL>
{
    friend class UQMSingleton<UQMCrashIMPL>;
    
public:

    static void ConfigCallbackTypeBeforeInit(const std::string& channel, int32_t callbackType);
    
    static void ConfigCrashHandleTimeout(const std::string& channel, int32_t timeout);

    static bool Init(const std::string& channel, const std::string& appId, bool unexpectedTerminatingDetectionEnable, bool debugMode, const std::string& serverUrl);
    
    static void LogInfo(const std::string& channel, int level, const std::string& tag, const std::string& log);
    
    static void SetUserValue(const std::string& channel, const std::string& key, const std::string& value);
    
    static void SetUserId(const std::string& channel, const std::string& userId);

    static void SetAppId(const std::string& channel, const std::string& appId);

    static void SetUserSceneTag(const std::string& channel, const std::string& userSceneTag, bool upload);
    
    static void ReportException(const std::string& channel, int type, const std::string& exceptionName, const std::string& exceptionMsg, const std::string& exceptionStack, const UQMVector<UQMKVPair> &extInfo, const std::string& extInfoJsonStr, bool quit= false, int dumpNativeType= 0, const std::string& errorAttachmentPath = "");

    static void ReportLogInfo(const std::string& msgType, const std::string& msg);

#ifdef ANDROID
    static jobject convert(const std::map<std::string, std::string> &data);
#endif

    static void SetIsAppForeground(const std::string& channel, bool isAppForeground);

    static void SetAppVersion(const std::string& channel, const std::string& appVersion);

    //测试接口
    static void TestOomCrash(const std::string& channel);
    static void TestJavaCrash(const std::string& channel);
    static void TestOcCrash(const std::string& channel);
    static void TestNativeCrash(std::string channel) {
        UQM_LOG_DEBUG("TestNativeCrash channel = %s", channel.c_str());
        abort();
    }
    static void TestANR(const std::string& channel);

    //agent
    static bool InitWithAppId (const std::string& channel, const std::string& appId, bool forceOnUiThread);

    static void SetGameType(const std::string& channel, int gameType);

    static void ConfigDefaultBeforeInit(const std::string& channel, const std::string& appChannel, const std::string& version, const std::string& user, long delay);
    
    static void ConfigCrashServerUrlBeforeInit(const std::string& channel, const std::string& serverUrl);

    static void ConfigCrashReporterLogLevelBeforeInit(const std::string& channel, int logLevel);

    static void ConfigDebugModeBeforeInit(const std::string& channel, bool enable);

    static void SetDeviceId(const std::string& channel, const std::string& deviceId);

    static void SetAppDeviceId(const std::string& channel, const std::string& deviceId);

    static std::string GetBackendDeviceId(const std::string& channel);

    static void SetCustomizedMatchID(const std::string& channel, const std::string& matchId);

    static std::string GetSDKSessionID(const std::string& channel);

    static void SetDeviceModel(const std::string& channel, const std::string& deviceModel);

    static void SetLogPath(const std::string& channel, const std::string& logPath);

    static void LogRecord (const std::string& channel, int level, const std::string& message);

    static void CloseCrashReport(const std::string& channel);

    static void StartCrashReport(const std::string& channel);

    static void SetCatchMultiSignal(const std::string& channel, bool enable);

    static void SetUnwindExtraStack(const std::string& channel, bool enable);

    static long GetCrashThreadId(const std::string& channel);

    static std::string GetCrashUuid(const std::string &channel);

    static bool IsLastSessionCrash(const std::string& channel);

    static std::string GetLastSessionUserId(const std::string& channel);

    static void SetUploadThreadNum(const std::string& channel, int num);
    
    static void SetLogcatBufferSize(const std::string &channel, int size);

    static void startDumpRoutine(const std::string& channel, int dumpMode, int startTimeMode, long startTime,
                                 long dumpInterval, int dumpTimes, bool saveLocal, const std::string& savePath);

    static void startMonitorFdCount(const std::string& channel, int interval, int limit, int dumpType);

    static int getExceptionType(const std::string& channel, const std::string& name);
    
    static void testUseAfterFree(const std::string &channel);
    
    static void setEnableGetPackageInfo(const std::string& channel, bool enable);

    static void setServerEnv(const std::string& channel, const std::string& serverEnv);

    static void setEngineInfo(const std::string& channel, const std::string& version, const std::string& buildConfig, const std::string& language, const std::string& locale);

    static void setGpuInfo(const std::string& channel, const std::string& version, const std::string& vendor, const std::string& renderer);

    static void setIsOpengles(const std::string& channel, bool isOpengles);

    static void enableDetailedPageTracing(const std::string& channel, bool enable);

    static void useSavedUserId(const std::string& channel, bool enable);

    static bool checkFdCount(const std::string& channel, int limit, int dumpType, bool upload);

    static void SetOomLogPath(const std::string& channel, const std::string& logPath);

    static void ReportJank(const std::string& channel, int type, const std::string& exceptionName,
                           const std::string& exceptionMsg, const std::string& exceptionStack,
                           const std::string& extInfoJsonStr, int reportInfoOption, const std::string& jankAttachmentPath);

    static void setEngineMainThread(const std::string& channel);

    static void ReportStuck(const std::string& channel, int threadId, int maxChecks, long checkInterval,
                           const std::string& name, const std::string& message, const std::string& extraInfo,
                           int dumpNativeType, const std::string& attachPath);

    private:
    UQMCrashIMPL() {}
    static void CallFunction(const std::string& channel, const std::string& functionName, bool enable);
    static long CallLongFunction(const std::string& channel, const std::string& functionName);

    };

NS_UQM_END

#endif /* UQMCrashIMPL_h */
