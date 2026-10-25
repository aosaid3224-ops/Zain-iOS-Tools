//
// Created by joyfyzhang on 2021/10/19.
//

#ifndef ANDROID_UQMUNITYEXTRA_H
#define ANDROID_UQMUNITYEXTRA_H

#include "UQMUnityBridge.h"

extern "C"
{
    ///----- UQMCrash
    void UQM_EXPORT cs_configCallbackTypeAdapter(int32_t callbackType);

    void UQM_EXPORT cs_configGameTypeAdapter(int gameType);

    void UQM_EXPORT cs_configAutoReportLogLevelAdapter(int level);

    void UQM_EXPORT cs_configDefaultAdapter(const char *channel, const char *version, const char *user, int64_t delay);

    void UQM_EXPORT cs_configCrashServerUrlAdapter(const char *serverUrl);

    void UQM_EXPORT cs_configDebugModeAdapter(bool enable);

    void UQM_EXPORT cs_setDeviceIdAdapter(const char *deviceId);

    /**
     * 设置业务的deviceId，仅用于页面搜索，不影响后台统计
     * @param deviceId
     */
    void UQM_EXPORT cs_setCustomizedDeviceIDAdapter(const char *deviceId);

    const char* UQM_EXPORT cs_getSDKDefinedDeviceIDAdapter();

    void UQM_EXPORT cs_setCustomizedMatchIDAdapter(const char *matchId);

    const char* UQM_EXPORT cs_getSDKSessionIDAdapter();
    
    const char* UQM_EXPORT cs_getCrashUuidAdapter();

    void UQM_EXPORT cs_setDeviceModelAdapter(const char *deviceModel);

    void UQM_EXPORT cs_setCallbackMsgAdapter(const char *msg);

    void UQM_EXPORT cs_initWithAppIdAdapter(const char *appId, bool forceOnUiThread);

    void UQM_EXPORT cs_logRecordAdapter(int level, const char *message);

    void UQM_EXPORT cs_addSceneDataAdapter(const char *key, const char *value);

    void UQM_EXPORT cs_reportExceptionAdapter(int type, const char *exceptionName, const char *exceptionMsg,
                               const char *exceptionStack, const char *extras, const char *paramsJson,
                               bool quitProgram, int dumpNativeType, const char* errorAttachmentPath);

    void UQM_EXPORT cs_setUserIdAdapter(const char *userId);

    void UQM_EXPORT cs_setSceneAdapter(const char *sceneId, bool upload);

    void UQM_EXPORT cs_setLogPathAdapter(const char *logPath);

    void UQM_EXPORT cs_reRegistAllMonitorsAdapter();

    void UQM_EXPORT cs_closeAllMonitorsAdapter();

    void UQM_EXPORT cs_setAppVersionAdapter(const char *appVersion);

    void UQM_EXPORT cs_crashObserverAdapter();

    void UQM_EXPORT cs_unregisterCrashObserverAdapter();

    void UQM_EXPORT cs_crashLogObserverAdapter();

    void UQM_EXPORT cs_reportLogInfo(const char *msgType, const char *msg);

    // test api
    void UQM_EXPORT cs_testOomCrashAdapter();

    void UQM_EXPORT cs_testJavaCrashAdapter();

    void UQM_EXPORT cs_testOcCrashAdapter();

    void UQM_EXPORT cs_testNativeCrashAdapter();

    void UQM_EXPORT cs_testANRAdapter();

    void UQM_EXPORT cs_setCatchMultiSignal(bool enable);

    void UQM_EXPORT cs_setUnwindExtraStack(bool enable);

    long UQM_EXPORT cs_getCrashThreadId();

    void UQM_EXPORT cs_setLogcatBufferSize(int size);

    void UQM_EXPORT cs_startDumpRoutine(int dumpMode, int startTimeMode, long startTime, long dumpInterval,
                                        int dumpTimes, bool saveLocal, const char *savePath);

    void UQM_EXPORT cs_startMonitorFdCount(int interval, int limit, int dumpType);

    int UQM_EXPORT cs_getExceptionType(const char *name);
    
    void UQM_EXPORT cs_testUseAfterFreeAdapter();
    
    void UQM_EXPORT cs_setEnableGetPackageInfo(bool enable);

    void UQM_EXPORT cs_setServerEnv(const char *serverEnv);

    void UQM_EXPORT cs_setEngineInfo(const char *version, const char *buildConfig, const char *language, const char *locale);

    void UQM_EXPORT cs_setGpuInfo(const char *version, const char *vendor, const char *renderer);

    void UQM_EXPORT cs_enableDetailedPageTracing(bool enable);

    void UQM_EXPORT cs_useSavedUserId(bool enable);
    
    bool UQM_EXPORT cs_isLastSessionCrash();

    const char* UQM_EXPORT cs_getLastSessionUserId();

    bool UQM_EXPORT cs_checkFdCount(int limit, int dumpType, bool upload);

    void UQM_EXPORT cs_setOomLogPath(const char *logPath);

    void UQM_EXPORT cs_reportJank(int type, const char* exceptionName,
                              const char* exceptionMsg, const char* exceptionStack,
                              const char* extInfoJsonStr, int reportInfoOption, const char* jankAttachmentPath);

    void UQM_EXPORT cs_setEngineMainThread();

    void UQM_EXPORT cs_reportStuck(int threadId, int maxChecks, int checkInterval,
                            const char *name, const char *message, const char *extraInfo,
                            int dumpNativeType, const char *attachPath);


#if __APPLE__
    bool cs_showRatingAlertAdapter();
    void cs_showAppStoreProductViewAdapter(const char* appid);
    #endif
}

#endif //ANDROID_UQMUNITYEXTRA_H
