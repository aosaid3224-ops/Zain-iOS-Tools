//
//  UQMDefine.hpp
//  CrashSight
//
//  Created by joyfyzhang on 2020/9/3.
//  Copyright © 2020 joyfyzhang. All rights reserved.
//

#ifndef UQMDefine_hpp
#define UQMDefine_hpp

#include <stdio.h>
#include <string>
#include <vector>
#include <ostream>
#include "UQMMacros.h"
#include "UQMMacroExpand.h"
#include "UQMCompatLayer.h"
#include "CSLogger.h"

#define CS_SDK_DEVICE_ID_LEN 64
#define CS_SDK_USER_ID_LEN 64

NS_UQM_BEGIN

typedef enum UQMMethodName {
    kUQMMethodNameUndefine = 000,
    kUQMMethodNameCrashExtraData = 1011,
    kUQMMethodNameCrashExtraMessage = 1012,
    kUQMMethodNameCrashSetLogPath = 1013,
    kUQMMethodNameCrashLogUploadResult = 1014,
} UQMMethodName;

typedef enum UQMObserverID
{
    kUQMObserverIDWakeUp                 = 107,
}UQMObserverID;

class UQM_EXPORT UQMBaseRet {
public:
    // 标记是从哪个方法过来
    int methodNameID;
    // UQM 返回码，详情可参考 UQMError.h
    int retCode;
    // UQM 描述信息
    std::string retMsg;
    // 第三方渠道返回码
    int thirdCode;
    // 第三方渠道描述信息
    std::string thirdMsg;
    // 扩展字段，保留
    std::string extraJson;

    // 构造函数对外使用，必须包含在外部调用，否则会 crash
    UQMBaseRet();

    // 构造函数对外使用，必须包含在外部调用，否则会 crash
    UQMBaseRet(int code);

    // 构造函数对外使用，必须包含在外部调用，否则会 crash
    UQMBaseRet(int code, int tCode, std::string tMsg);

#if UQM_PLATFORM_WINDOWS
#else
UQM_AutoParser("com.uqm.crashsight.core.api.UQMRet", A(thirdCode, "ret"), A(thirdMsg, "msg"),
               O(methodNameID, retCode, retMsg, extraJson));
#endif

};

/**
 * 基础结构类
 */
class UQM_EXPORT UQMInnerBaseRet
{
public:

    // 标记是从哪个方法过来
    int methodNameID;

    // UQM 返回码，详情可参考 UQMError.h
    int retCode;

    // UQM 描述信息
    UQMString retMsg;

    // 第三方渠道返回码
    int thirdCode;

    // 第三方渠道描述信息
    UQMString thirdMsg;

    // 扩展字段，保留
    UQMString extraJson;

    // 回调类型
    int crashType{};

    // 构造函数
    UQMInnerBaseRet();

    UQMInnerBaseRet(int retCode);

    UQMInnerBaseRet(int retCode, int methodID);

    UQMInnerBaseRet(int retCode, int thirdCode, const UQMString& thirdMsg);

    UQMInnerBaseRet(int retCode, UQMString retMsg, int thirdCode, const UQMString& thirdMsg);
#if UQM_PLATFORM_WINDOWS
#else
        UQM_AutoParser("com.uqm.crashsight.core.api.UQMRet", A(thirdCode, "ret"),
                       A(thirdMsg, "msg"), O(methodNameID, retCode, retMsg, extraJson));
#endif

};

class UQMInnerCrashRet : public UQMInnerBaseRet
{
public:
    char *data{};
    int maxDataLen{};
    int *dataLen{};
    UQMInnerCrashRet();
#if UQM_PLATFORM_WINDOWS
#else
UQM_AutoParser("com.uqm.crashsight.core.api.crash.UQMCrashRet",
               A(thirdCode, "ret"), A(thirdMsg, "msg"),
               A(extraJson, "extra"), O(retCode, retMsg, methodNameID),
               O(methodNameID));
#endif
};

template<typename RetType>
class UQMInnerRetCallbackClass
{
public:
    typedef void (*UQMInnerRetCallback)(const RetType &ret, const char *seqID);
};

template<typename RetType>
class UQMCallBackParams
{
public:
    RetType mRet;
    unsigned int mObserverID;
    UQMString mSeqID;
    UQMCallBackParams(const RetType &ret, unsigned int observerID, UQMString seqID): mRet(ret), mObserverID(observerID), mSeqID(seqID){};
};

void UQMInnerObserverHolderDispatch(void (*callback)(int result, void *args), void *context);


template<typename RetType>
class UQMInnerObserverHolder
{
private :
    static std::map<int, typename UQMInnerRetCallbackClass<RetType>::UQMInnerRetCallback> mObserverHolder;
    static std::map<std::string, UQMCallBackParams<RetType> > mTaskParamsHolder;
    static void cacheTask(std::string mSeqID, UQMCallBackParams<RetType> taskParams)
    {
        if (mSeqID.empty()){
            UQM_LOG_DEBUG("cacheTask failed for mSeqID is empty");
            return;
        }
        mTaskParamsHolder.insert(std::make_pair(mSeqID, taskParams));
        UQM_LOG_DEBUG("mTaskParamsHolder after insert %s", mSeqID.c_str());
    }
    static void commitCacheTask()
    {
        typename std::map<std::string, UQMCallBackParams<RetType> >::iterator iter;
        for (iter = mTaskParamsHolder.begin(); iter != mTaskParamsHolder.end(); ){
            UQMCallBackParams<RetType> taskParam = iter->second;
            if(CommitCacheToTaskQueue(taskParam.mRet, taskParam.mObserverID, taskParam.mSeqID)){
                mTaskParamsHolder.erase(iter++);
                UQM_LOG_DEBUG("mTaskParamsHolder size: %lu, after erase %s", (unsigned long)mTaskParamsHolder.size(), taskParam.mSeqID.c_str());
            } else {
                ++iter;
            }
        }
        // UQM_LOG_DEBUG("mTaskParamsHolder size: %lu, after commitCacheTask", (unsigned long)mTaskParamsHolder.size());
    }
public:
    static void CacheObserver(const unsigned int mObserverID, typename UQMInnerRetCallbackClass<RetType>::UQMInnerRetCallback observer)
    {
        if (mObserverHolder.find(mObserverID) != mObserverHolder.end())
        {
            // 如果已经存在就删除原来的 key，保证 key 对应的 value 是最新
            mObserverHolder.erase(mObserverID);
        }

        mObserverHolder.insert(std::make_pair(mObserverID, observer));
        commitCacheTask();
    }

    static void CommitToTaskQueueBackRet(const RetType &ret, const unsigned int observerID, const UQMString &seqID)
    {
        if (mObserverHolder.find(observerID) != mObserverHolder.end())
        {
            UQMInnerCrashRet innerCrashRet = static_cast<UQMInnerCrashRet>(ret);

            //UQM_LOG_DEBUG("innerCrashRet %d %s %p %d", observerID, seqID.c_str(), innerCrashRet.data, innerCrashRet.maxDataLen);

            mObserverHolder[observerID](ret, seqID.c_str());
        }
    }

    static void CommitToTaskQueue(const RetType &ret, const unsigned int observerID, const UQMString &seqID)
    {
        UQMCallBackParams<RetType> *params = new UQMCallBackParams<RetType>(ret, observerID, seqID);

        if(mObserverHolder.find(params->mObserverID) == mObserverHolder.end()){ // 当前没有setObserver，缓存回调
            UQM_LOG_DEBUG("Cache ObserverID %d", observerID);
            UQMCallBackParams<RetType> taskParams(params->mRet, params->mObserverID, params->mSeqID);
            cacheTask(params->mSeqID.toString(), taskParams);
            UQM_SAFE_DELETE(params);
        } else if (kUQMObserverIDWakeUp == observerID){ //wakeup 回调直接回调
            UQM_LOG_DEBUG("CallbackOnMainThread %d", observerID);
            CallbackOnMainThread(-1, params);
        } else {
            UQM_LOG_DEBUG("DispatchAsyncMainThread %d", observerID);
            UQMInnerObserverHolderDispatch(CallbackOnMainThread, params);
        }
    }

    static bool CommitCacheToTaskQueue(const RetType &ret, const unsigned int observerID, const UQMString &seqID){
        UQMCallBackParams<RetType> *params = new UQMCallBackParams<RetType>(ret, observerID, seqID);
        if(mObserverHolder.find(params->mObserverID) != mObserverHolder.end()){
            UQM_LOG_DEBUG("DispatchAsyncMainThread %d", observerID);
            UQMInnerObserverHolderDispatch(CallbackOnMainThread, params);
            return true;
        }
        UQM_SAFE_DELETE(params);
        return false;
    }


    static void CallbackOnMainThread(int ret, void *args)
    {
        UQMCallBackParams<RetType> *params = (UQMCallBackParams<RetType> *)args;

        if (mObserverHolder.find(params->mObserverID) != mObserverHolder.end())
        {
            UQM_LOG_DEBUG("observer address %p of observerID : %d", mObserverHolder[params->mObserverID], params->mObserverID);
            mObserverHolder[params->mObserverID](params->mRet, params->mSeqID.c_str());
        }
        else
        {
            UQM_LOG_DEBUG("can not get inner callback for %u, make sure you have define", params->mObserverID);
        }

        UQM_SAFE_DELETE(params);
    }

};


template<class RetType> std::map<int, typename UQMInnerRetCallbackClass<RetType>::UQMInnerRetCallback> UQMInnerObserverHolder<RetType>::mObserverHolder;
template<class RetType> std::map<std::string, UQMCallBackParams<RetType> > UQMInnerObserverHolder<RetType>::mTaskParamsHolder;

#ifdef ANDROID

typedef void (*FuncRunOnUIDelegate)(void *args);

#endif


NS_UQM_END

#endif /* UQMDefine_hpp */
