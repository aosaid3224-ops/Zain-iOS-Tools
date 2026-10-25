//
//  PluginCrosCurl.h
//  CrosCurl
//  Query and Call Curl Functions base by CrosCurl
//
//  Created by kiddpeng on 2022/5/19.
//  Copyright © 2022年 gcloud. All rights reserved.
//

#ifndef PLUGINCROSCURL_SOURCE_PLUGINCROSCURL_H_
#define PLUGINCROSCURL_SOURCE_PLUGINCROSCURL_H_

#include "GCloudPluginManager/PluginBase/PluginBase.h"
#include "crosCurl.h"
#ifdef ANDROID
#include <android/log.h>
#endif

#ifdef __OHOS__
#include "hilog/log.h"
#endif

#ifdef __APPLE__
#import <Foundation/Foundation.h>
#endif

#ifndef PLUGINCROSCURL_DLL_EXPORT
#ifdef _WIN32
#define PLUGINCROSCURL_DLL_EXPORT __declspec(dllexport)
#else
#define PLUGINCROSCURL_DLL_EXPORT __attribute__((visibility("default")))
#endif
#endif

GCLOUD_PLUGIN_NAMESPACE

class PluginCrosCurl : public GCloud::Plugin::Singleton<PluginCrosCurl>,
                       public GCloud::Plugin::PluginBase {
 public:
  virtual const char *GetName() const { return "PluginCrosCurl"; }
  virtual const char *GetVersion() const { return "1.0.000.1107"; }

 public:
  virtual void OnStartup(GCloud::Plugin::IServiceRegister *serviceRegister) {
#ifdef ANDROID
    __android_log_print(ANDROID_LOG_INFO, "", "PluginCrosCurl OnStartup");
#endif

#ifdef __APPLE__
    NSLog(@"PluginCrosCurl OnStartup");
#endif

#ifdef __OHOS__
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, "PluginCrosCurl", "OnStartup");
#endif
    cros_curl_global_init(CROS_CURL_GLOBAL_ALL);

    if (serviceRegister) {
      serviceRegister->Register("CurlFuncQuery");
    }
  }
  virtual void OnPostStartup() {}
  virtual void OnPreShutdown() {}
  virtual void OnShutdown() {
    cros_curl_global_cleanup();
  }

 public:
  virtual GCloud::Plugin::IPluginService *
  GetServiceByName(const char *serviceName);
};

GCLOUD_PLUGIN_NAMESPACE_END

#endif  // PLUGINCROSCURL_SOURCE_PLUGINCROSCURL_H_
