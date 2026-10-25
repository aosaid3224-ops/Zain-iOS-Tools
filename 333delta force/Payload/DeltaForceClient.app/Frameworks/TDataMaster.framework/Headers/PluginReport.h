//
//  PluginReport.h
//  PluginReport
//
//  Created by v_yanyanqin on 2018/8/7.
//  Copyright © 2018年 tdatamaster. All rights reserved.
//

#ifndef PluginReport_h
#define PluginReport_h

#ifdef ANDROID
#include "GCloudPluginManager/PluginBase/PluginBase.h"
#endif

#ifdef __APPLE__
#include "PluginBase.h"
#endif

#if defined(__OPENHARMONY__) || defined(_WIN32) || defined(_WIN64)
#include "PluginBase.h"
#endif

#include "ITDataMaster.h"
#include "TDataMasterVersion.h"

GCLOUD_PLUGIN_NAMESPACE

class PUBLIC_API PluginReport : public Singleton<PluginReport> , public PluginBase
{
public:
    virtual const char* GetName() const
    {
        return PLUGIN_NAME_TDM;
    };
    virtual const char* GetVersion() const
    {
        return TDataMaster_Version_String;
    };
    
public:
    virtual void OnStartup(IServiceRegister* serviceRegister)
    {
        if(serviceRegister){
            serviceRegister->Register(PLUGIN_SERVICE_NAME_REPORT);
        }
    };
    virtual void OnPostStartup(){};
    virtual void OnPreShutdown(){};
    virtual void OnShutdown(){};
    
public:
    virtual IPluginService* GetServiceByName(const char* serviceName);
};

GCLOUD_PLUGIN_NAMESPACE_END

#endif /* PluginReport_h */
