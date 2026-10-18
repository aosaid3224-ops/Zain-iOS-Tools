//
//  UQMCrash.hpp
//  Version: 4.3.9(1073)
//  Created by joyfyzhang on 2020/9/3.
//  Copyright © 2020 joyfyzhang. All rights reserved.
//

#ifndef UQMCrash_h
#define UQMCrash_h

#include "UQMDefine.h"
#include "CrashSightMobileAgent.h"

NS_UQM_BEGIN

    typedef enum {
        CRASH_TYPE_NATIVE = 2,
        CRASH_TYPE_U3D = 3,
        CRASH_TYPE_ANR = 4,
        CRASH_TYPE_JS = 5,
        CRASH_TYPE_LUA = 6,
    }UQMCrashType;

    class UQM_EXPORT UQMCrashRet : public UQMBaseRet {
    public:
        int maxDataLen;
        char* data;
    };

    class UQM_EXPORT UQMCrashObserver
    {
    public:
        //新增一个虚析构函数 不然 UE4 报错
        virtual ~UQMCrashObserver() {};

        virtual long OnCrashExtraDataNotify(const UQMInnerCrashRet& crashRet) {
            return 0;
        };

        virtual const char* OnCrashExtraMessageNotify(int crashType) {
            return NULL;
        };
    };

    class UQM_EXPORT UQMCrashLogObserver
    {
    public:
        //新增一个虚析构函数 不然 UE4 报错
        virtual ~UQMCrashLogObserver() {};

        // 设置日志路径回调
        virtual const char* OnCrashSetLogPathNotify(int crashType) {
            return NULL;
        };

        // 通知日志上传结果回调
        virtual void OnCrashLogUploadResultNotify(int crashType, int result) {
        };
    };

    class UQM_EXPORT UQMCrash : public GCloud::CrashSight::CrashSightMobileAgent
    {
    private:
        static std::map<int, char*> retMsg;
#if !UQM_PLATFORM_WINDOWS
        static pthread_mutex_t mutex;
#endif
        
        static void CrashDataObserver(const UQMInnerCrashRet& crashRet, const char* seqID);

        static void CrashMessageObserver(const UQMInnerCrashRet& crashRet, const char* seqID);

        static void CrashSetLogPathObserver(const UQMInnerCrashRet& crashRet, const char* seqID);

        static void CrashLogUploadResultObserver(const UQMInnerCrashRet& crashRet, const char* seqID);

        static UQMCrashObserver* mCrashObserver;
        static UQMCrashLogObserver* mCrashLogObserver;

        ~UQMCrash();

        static void SetPRVCrashObserver(UQMInnerRetCallbackClass<UQMInnerCrashRet>::UQMInnerRetCallback crashObserver);
        static void SetExtraMessageCrashObserver(UQMInnerRetCallbackClass<UQMInnerCrashRet>::UQMInnerRetCallback crashObserver);
        static void SetLogPathObserver(UQMInnerRetCallbackClass<UQMInnerCrashRet>::UQMInnerRetCallback crashObserver);
        static void SetLogUploadResultObserver(UQMInnerRetCallbackClass<UQMInnerCrashRet>::UQMInnerRetCallback crashObserver);

    public:
        static void SetCrashObserver(UQMCrashObserver* crashObserver);

        static void SetCrashLogObserver(UQMCrashLogObserver* crashObserver);

        /**
         * 配置回调类型
         * @param callbackType 目前是5种类型，用5位表示。第一位表示crash，第二位表示anr，第三位表示u3d c# error，第四位表示js，第五位表示lua
         * 示例：关闭u3d c# error上报(type=4)的回调, callbackType=0b11011
         */
        static void ConfigCallbackTypeBeforeInit(int32_t callbackType);

        /**
         * 崩溃处理函数处理超时限制
         * @param timeout <=0 表示不限制
         */
        static void ConfigCrashHandleTimeout(int32_t timeout);

        static void Init(const UQMString& appId, bool unexpectedTerminatingDetectionEnable, bool debugMode, const UQMString& serverUrl);
        /**
         *  自定义日志打印接口,用于记录一些关键的业务调试信息, 可以更全面地反应APP发生崩溃或异常的上下文环境.
         *
         *  @param level  日志级别，0-silent, 1-error,2-warning，3-info，4-debug，5-verbose
         *  @param tag    日志模块分类
         *  @param log 日志内容
         */
        static void LogInfo(int level, const UQMString& tag, const UQMString& log);

        /**
         * 设置关键数据，随崩溃信息上报
         * @param key 键值
         * @param value 键值对
         */
        static void SetUserValue(const UQMString& key, const UQMString& value);

        /**
         * 设置用户 ID
         * @param userId   用户ID
         */
        static void SetUserId(const UQMString& userId);

        /**
         * 设置App ID
         * @param appId  项目ID
         */
        static void SetAppId(const UQMString& appId);

        /**
         * 进入子地图
         * @param appId  项目ID
         */
        static void EntrySubMap(const UQMString& appId);

        /**
         * 设置场景
         * @param userSceneTag  场景标签
         */
        static void SetUserSceneTag(const UQMString& userSceneTag, bool upload = false);

        static void SetCurrentScene(int sceneId);

        static void ReportExceptionPRV(int type, const UQMString& exceptionName, const UQMString& exceptionMsg, const UQMString& exceptionStack, const UQMVector<UQMKVPair>& extInfo, const UQMString& extInfoJsonStr, bool quit = false, int dumpNativeType = 0);

        /**
         * 设置UQM的上报异常堆栈
         * @param type 3-cocoa 4-c# 5-JS 6-Lua, 7-统计信息上报
         * 当type=7时,exceptionName是统计的字段,exceptionMsg是统计字段的值
         * @param exceptionName 异常名称
         * @param exceptionMsg 异常消息
         * @param exceptionStack 异常堆栈内容
         * @param extInfo 异常的附加额外信息
         * @param dumpNativeType 0：关闭，1：调用系统接口dump，3：minidump
         */
        static void ReportException(int type, const UQMString& exceptionName, const UQMString& exceptionMsg, const UQMString& exceptionStack, std::map<std::string, std::string>& extInfo, int dumpNativeType = 0)
        {
            UQMVector<UQMKVPair> tmp;
            std::map<std::string, std::string>::iterator it = extInfo.begin();
            for (; it != extInfo.end(); it++)
            {
                UQMKVPair kvPair;
                kvPair.key = (*it).first;
                kvPair.value = (*it).second;
                tmp.push_back(kvPair);
            }
            ReportExceptionPRV(type, exceptionName, exceptionMsg, exceptionStack, tmp,
                               nullptr, false, dumpNativeType);
        }

        /**
         * 设置UQM的上报异常堆栈: c接口版本，不支持map
         * @param type 3-cocoa 4-c# 5-JS 6-Lua
         * @param exceptionName 异常名称
         * @param exceptionMsg 异常消息
         * @param exceptionStack 异常堆栈内容
         * @param dumpNativeType 0：关闭，1：调用系统接口dump，3：minidump
         */
        static void ReportException(int type, const UQMString& exceptionName, const UQMString& exceptionMsg, const UQMString& exceptionStack, int dumpNativeType = 0)
        {
            UQMVector<UQMKVPair> extInfo;
            ReportExceptionPRV(type, exceptionName, exceptionMsg, exceptionStack, extInfo, nullptr, false, dumpNativeType);
        }

        /**
         * 设置前后台
         * @param isAppForeground 是否前台
         */
        static void SetIsAppForeground(bool isAppForeground);

        static void SetAppVersion(const UQMString& appVersion);

        static void SetCallBackMsg(const UQMString &data);

        // GameAgent
        static void InitWithAppId(const UQMString& appId);

        static void ConfigDefaultBeforeInit(const UQMString& channel, const UQMString& version, const UQMString& user, long delay);

        static void ConfigCrashServerUrlBeforeInit(const UQMString& crashServerUrl);

        static void ConfigCrashReporterLogLevelBeforeInit(int logLevel);

        static void ConfigDebugModeBeforeInit(bool enable);

        static void SetDeviceId(const UQMString& deviceId);

        static void SetCustomizedDeviceID(const UQMString& deviceId);

        static void SetCustomizedMatchID(const UQMString& matchId);

        static void SetDeviceModel(const UQMString& deviceModel);

        static void SetLogPath(const UQMString& logPath);

        static void ReportException(int type, const UQMString& name, const UQMString& reason, const UQMString& stackTrace, const UQMString& extras, bool quit, int dumpNativeType = 0)
        {
            UQMVector<UQMKVPair> tmp;
            UQMKVPair kvPair;
            kvPair.key = "Extra";
            kvPair.value = extras;
            tmp.push_back(kvPair);
            ReportExceptionPRV(type, name, reason, stackTrace, tmp, nullptr, quit, dumpNativeType);
        }

        static void ReportExceptionJson(int type, const UQMString& exceptionName, const UQMString& exceptionMsg, const UQMString& exceptionStack, const UQMString& paramsJson, int dumpNativeType = 0)
        {
            UQMVector<UQMKVPair> tmp;
            ReportExceptionPRV(type, exceptionName, exceptionMsg, exceptionStack, tmp, paramsJson,
                               false, dumpNativeType);
        }

        static void LogRecord(int level, const UQMString& message);

    };

NS_UQM_END

#endif /* UQMCrash_h */
