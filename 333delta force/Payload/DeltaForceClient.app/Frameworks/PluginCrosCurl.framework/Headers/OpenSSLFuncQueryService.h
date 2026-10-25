//
//  OpenSSLFuncQueryService.h
//  CrosCurl
//  Query and Call OpenSSL Functions base by CrosCurl
//
//  Created by kiddpeng on 2022/5/19.
//  Copyright © 2022年 gcloud. All rights reserved.
//

#ifndef PLUGINCROSCURL_SOURCE_OPENSSLFUNCQUERYSERVICE_H_
#define PLUGINCROSCURL_SOURCE_OPENSSLFUNCQUERYSERVICE_H_

#include "GCloudPluginManager/PluginBase/PluginBase.h"
#include "IOpenSSLFuncQueryService.h"

GCLOUD_PLUGIN_NAMESPACE

class OpenSSLFuncQueryService : public IOpenSSLFuncQueryService {
 private:
  OpenSSLFuncQueryService() {}
  ~OpenSSLFuncQueryService() {}

 public:
  static OpenSSLFuncQueryService *GetInstance();
  void ReleaseInstance();

  virtual const char *GetName() const { return "OpenSSLFuncQueryService"; }
  virtual const char *GetPluginName() const { return "PluginCrosCurl"; }

 public:
  int QueryOpenSSLFuncs(OpenSSLFuncs *pOpenSSLFuncs);
};

GCLOUD_PLUGIN_NAMESPACE_END

#endif  // PLUGINCROSCURL_SOURCE_OPENSSLFUNCQUERYSERVICE_H_
