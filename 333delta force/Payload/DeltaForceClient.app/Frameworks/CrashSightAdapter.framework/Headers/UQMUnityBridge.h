//
// Created by joyfyzhang on 2021/10/18.
//

#ifndef ANDROID_UQMUNITYBRIDGE_H
#define ANDROID_UQMUNITYBRIDGE_H

#ifdef ANDROID
#include "UQMDefine.h"
#include "UQM.h"
#include "UQMUtils.h"
#include "CSLogger.h"
#include <string>
#endif

#ifdef __APPLE__
#include <CrashSightCore/CrashSightCore.h>
#endif

NS_UQM_BEGIN

typedef char* (*UQMRetJsonCallback)(int methodId, int callbackType, int logUploadResult);

class UQMUnityBridge {
public:
    static UQMRetJsonCallback SendToUnity;
    static void SetBridge(UQMRetJsonCallback bridge);
    static char *pInvokeHandleCallback(int methodId, int callbackType, int logUploadResult = 0) {
        if (UQMUnityBridge::SendToUnity == NULL) {
            UQM_LOG_DEBUG("No callback for unity, please do UQM.Init(); first !");
            return NULL;
        } else {
            return UQMUnityBridge::SendToUnity(methodId, callbackType, logUploadResult);
        }
    }
};

extern "C" {
void UQM_EXPORT cs_setUnityCallback(UQMRetJsonCallback bridge);
int UQM_EXPORT cs_unityForceCrash();
int UQM_EXPORT cs_unityCrashCallback();
int UQM_EXPORT cs_unityCrashLogCallback();
int UQM_EXPORT cs_unregisterUnityCrashCallback();
}

NS_UQM_END

#endif //ANDROID_UQMUNITYBRIDGE_H
