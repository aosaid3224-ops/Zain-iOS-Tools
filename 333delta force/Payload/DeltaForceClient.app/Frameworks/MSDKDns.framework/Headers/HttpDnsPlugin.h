//
// HttpDNSPlugin.h
// ./
//
// Created by zefengwang on 2019-10-23.
// Copyright © 2019 OneSDK. All rights reserved.

#ifndef ONESDK_HTTPDNS_COMMON_HTTPDNSPLUGIN_SOURCE_EXPORT_HTTPDNSPLUGIN_H_
#define ONESDK_HTTPDNS_COMMON_HTTPDNSPLUGIN_SOURCE_EXPORT_HTTPDNSPLUGIN_H_

#include "GCloudPluginManager/PluginBase/PluginBase.h"

#ifdef ANDROID
#include <android/log.h>
#endif

#if defined(__OHOS__) || (_WIN32)
#include "third_party/log/DnsLog.h"
#endif

#ifndef DLL_EXPORT
#ifdef _WIN32
#define DLL_EXPORT __declspec(dllexport)
#else
#define DLL_EXPORT __attribute__((visibility("default")))
#endif
#endif

#define HttpDnsVersion "2.1.01.183"

#define GCLOUD_VERSION_HttpDNS "GCLOUD_VERSION_HttpDNS_2.1.01.183"

namespace GCloud {
namespace HttpDNS {

class DLL_EXPORT HttpDnsPlugin
    : public GCloud::Plugin::Singleton<HttpDnsPlugin>,
      public GCloud::Plugin::PluginBase {
 public:
  virtual const char *GetName() const;

  virtual const char *GetVersion() const;

  static HttpDnsPlugin *GetInstance();

  void ReleaseInstance();

 public:
  virtual void OnStartup(GCloud::Plugin::IServiceRegister *serviceRegister);

  virtual void OnPostStartup();

  virtual void OnPreShutdown();
  virtual void OnShutdown();

 public:
  virtual GCloud::Plugin::IPluginService *GetServiceByName(const char *serviceName);
};

}  // namespace HttpDNS
}  // namespace GCloud

#endif  // ONESDK_HTTPDNS_COMMON_HTTPDNSPLUGIN_SOURCE_EXPORT_HTTPDNSPLUGIN_H_
