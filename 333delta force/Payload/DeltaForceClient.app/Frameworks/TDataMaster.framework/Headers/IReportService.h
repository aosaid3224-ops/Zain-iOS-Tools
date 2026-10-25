//
//  IReportService.h
//  GCloudPluginManager
//
//  Created by cedar on 2018/8/3.
//  Copyright © 2018年 tdatamaster. All rights reserved.
//

#ifndef IReportService_h
#define IReportService_h

#include <stdlib.h>
#include <stdint.h>
#include "string.h"
#include "DeviceInfoDefine.h"
#include "ITDataMasterV5.h"

#include "GCloudPluginManager/IPluginService.h"
#include "GCloudPluginManager/IPluginManager.h"

GCLOUD_PLUGIN_NAMESPACE

#define GCLOUDCORE_REPORT_ENV_TEST         0x01
#define GCLOUDCORE_REPORT_ENV_RELEASE      0x02

#define GCLOUDCORE_REPORT_INTERFACE_INFO   0x01
#define GCLOUDCORE_REPORT_QUALITY_INFO     0x02

#if defined(_WIN32) || defined(_WIN64)
typedef long long int64_t;
#endif

#define TDM_PLUGIN_SAFE_MALLOC(num, type) (type *) calloc((num) , sizeof(type))
#define TDM_PLUGIN_SAFE_FREE(ptr)   \
do                   \
{                    \
if (ptr != NULL) \
{                \
free(ptr);   \
ptr = NULL;  \
}                \
} while (0)

enum GCLoudCoreEventKeys
{
    kIntKeyAccountType = 100000,
    kIntKeyDataType = 100001,
    kIntKeyInterfaceDataType = 100002,
    
    kIntKeyResultCode = 100100,
    kIntKeyErrorCode,
    KIntKeySecondErrorCode,
    KIntKeyMethodType,
    KIntKeySessionID,
    KIntKeyDuration,
    
    KStrKeyGCloudVersion = 110000,
    KStrKeyGCloudCoreVersion,
    KStrKeyAccountID,
    
    KStrKeyComponentName = 110100,
    KStrKeyComponentVersion,
    KStrKeyMethodName,
    KStrKeyMethodParams,
    KStrKeyResultData,
    KStrKeyErrorMsg,
    KStrKeySecondErrorMsg,
};

#define TDM_REPORT_STANDARD_MODE 0
#define TDM_REPORT_SIMPLE_MODE 1

class IEvent
{
public:
    virtual ~IEvent(){}
    
public:
    virtual void Add(const char* key, const char* value, const int valueLen) = 0;
    virtual void Add(int key, const char* value, const int valueLen) = 0;
    virtual void Add(int key, int64_t value) = 0;
    
public:
    virtual void Report() = 0;
    virtual void Report(int mode) = 0;
};


class IReportService : public IPluginService
{
protected:
    ~IReportService(){}
    
public:
    virtual IEvent* CreateEvent(int srcID, const char* eventName) = 0;
    virtual void DestroyEvent(GCloud::Plugin::IEvent** ppEvent) = 0;
    virtual void ReportBinary(int srcID, const char * eventName, const char* data, int len) = 0;
    virtual const char* GetSessionID() = 0;
    virtual const char* GetTDMUID() = 0;
    
    bool CheckSupportCollectDeviceInfo(GCloud::Plugin::IPluginManager* pluginManager)
    {
        if(NULL == pluginManager)
        {
            return false;
        }
        GCloud::Plugin::IPlugin* plugin = (GCloud::Plugin::IPlugin*)pluginManager->GetPluginByName(PLUGIN_NAME_TDM);
        if(NULL == plugin)
        {
            return false;
        }
        
        const char* tdmVersion = plugin->GetVersion();
        
        if(NULL == tdmVersion || strlen(tdmVersion) <= 0)
        {
            return false;
        }
        
        int curMajorVersion = -1;
        int curFeatureVersion = -1;
        
        const int supportMajorVersion = 1;
        const int supportFeatureVersion = 6;
        
        int count = 0;
        int start = 0;
        
        for(int i = 0; i < strlen(tdmVersion); i++)
        {
            if(tdmVersion[i] == '.')
            {
                int tempLen = i - start;
                if(tempLen > 0)
                {
                    char* tempVersion = TDM_PLUGIN_SAFE_MALLOC(tempLen+1, char);
                    strncpy(tempVersion, tdmVersion+start, tempLen);
                    if(count == 0)
                    {
                        curMajorVersion = atoi(tempVersion);
                    }
                    else if(count == 1)
                    {
                        curFeatureVersion = atoi(tempVersion);
                    }
                    else if(count == 2){}
                    else
                    {
                        TDM_PLUGIN_SAFE_FREE(tempVersion);
                        return false;
                    }
                    TDM_PLUGIN_SAFE_FREE(tempVersion);
                }
                count++;
                // jump the separator .
                start = i+1;
            }
        }
        
        if(count != 3)
        {
            return false;
        }
        
        return (supportMajorVersion < curMajorVersion || (supportMajorVersion == curMajorVersion && supportFeatureVersion <= curFeatureVersion));
    }
    
    virtual void AddDeviceInfoObserver(IDeviceInfoObserver *pObserver, const char *deviceInfoName = COLLECT_DEVICE_INFO_ALL_STRING) = 0;
    

    virtual DeviceInfoStatus GetDeviceInfo(const char* deviceInfoName, int64_t* deviceInfoValue) = 0;
    virtual DeviceInfoStatus GetDeviceInfo(const char* deviceInfoName, bool* deviceInfoValue) = 0;
    virtual DeviceInfoStatus GetDeviceInfo(const char* deviceInfoName, char** deviceInfoValue, size_t valueLen) = 0;
    
    virtual DeviceInfoStatus GetDeviceInfoValueLen(const char* deviceInfoName, size_t* valueLen) = 0;
    
    virtual DeviceInfoStatus SetDeviceInfo(const char* deviceInfoName, const int64_t deviceInfoValue) = 0;
    virtual DeviceInfoStatus SetDeviceInfo(const char* deviceInfoName, const bool deviceInfoValue) = 0;
    virtual DeviceInfoStatus SetDeviceInfo(const char* deviceInfoName, const char* deviceInfoValue) = 0;
    virtual void EnableReport(bool enable) = 0;
    
    virtual void EnableDeviceInfo(bool enable) = 0;
    virtual void ReportLogin(int platform, const char* openid) = 0;

};

_USE_TDM_Name_Space
class IReportServiceV2 : public IReportService
{
protected:
    virtual ~IReportServiceV2(){}

public:
    virtual int GetVersion() { return 2; }

public:
    virtual IEventData* CreateEventData() = 0;
    virtual void DestroyEventData(IEventData*& eventData) = 0;
    virtual void ReportLoginV2(int platform, const char* openid, const TDM::IEventData *evnetData) = 0;
};

class IReportServiceV3 : public IReportServiceV2
{
protected:
    virtual ~IReportServiceV3(){}

public:
    virtual int GetVersion() { return 3; }

public:
    //ITDataMasterV3
    virtual int UploadFileByCOS(int srcID, const char* eventName, const char* fileName,
                                    const char* filePath, ITDMUploadFileObserver *observer) = 0;
    virtual int UploadBinaryByCOS(int srcID, const char* eventName, const char* fileName,
                const unsigned char* fileData, long fileLength, ITDMUploadFileObserver *observer) = 0;
    
    //ITDataMasterV4
    virtual int SetUserAgent(const char *value) = 0;

    //ITDataMasterV5
    virtual int EnableDeviceInfoCollect(const char *deviceName, bool enable) = 0;
};

class IReportServiceV4 : public IReportServiceV3
{
protected:
    virtual ~IReportServiceV4(){}

public:
    virtual int GetVersion() { return 4; }

public:
    //ITDataMasterV6
    virtual int ReportEventV2(int srcID, const char* eventName, const IEventData* eventData, int host, uint32_t devInfoOpt) = 0;
};

class IReportServiceV5 : public IReportServiceV4
{
protected:
    virtual ~IReportServiceV5(){}

public:
    virtual int GetVersion() { return 5; }

public:
    //ITDataMasterV7
    virtual PUBLIC_API void FlushCacheData() = 0;
    virtual PUBLIC_API void AgileReport(bool agile) = 0;
    virtual PUBLIC_API bool IsEventEmpty() = 0;
};

class IReportServiceV6 : public IReportServiceV5
{
    protected:
    virtual ~IReportServiceV6(){}

public:
    virtual int GetVersion() { return 6; }

public:
    //ITDataMaster
    virtual void ReportBinary(int srcID, const char *eventName, const char *data, const int len, const char *dstFileName, const bool forceSaveCOS) = 0;
};

//Inner use only
class ICoreReportService : public IPluginService
{
protected:
    ~ICoreReportService(){}
    
public:
    virtual IEvent* CreateEvent(int env, int srcID, const char* eventName) = 0;
    virtual void DestroyEvent(GCloud::Plugin::IEvent** ppEvent) = 0;
};


GCLOUD_PLUGIN_NAMESPACE_END


#endif /* IReportService_h */
