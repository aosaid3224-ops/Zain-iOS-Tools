//
//  UQM.h
//  CrashSight
//
//  Created by joyfyzhang on 2020/9/4.
//  Copyright © 2020 joyfyzhang. All rights reserved.
//

#ifndef UQM_h
#define UQM_h

#include "UQMMacros.h"
#include "UQMSingleton.h"

#ifdef ANDROID
#include <jni.h>
#endif

NS_UQM_BEGIN

//暂未弄清楚此处的具体用途，故不做替换修改
#ifdef _WIN32
#define UQM_ITOP_DEPRECATED(_version)
#else
#define UQM_ITOP_DEPRECATED(_version) __attribute__((deprecated))
#endif


class UQM : public UQMSingleton<UQM>
{
    friend class UQMSingleton<UQM>;
    
private:
    UQM() {
        initialized = false;
    };
    virtual ~UQM();
public:
    //JavaVM 是Android JNI使用，iOS这里定义一个，保证编译通过
#if UQM_PLATFORM_WINDOWS
#define JavaVM void
#else
#ifdef __APPLE__
#define JavaVM void
#endif
#endif
    
    void Initialize(JavaVM *vm);

private:
        bool initialized;
};

NS_UQM_END
// #include "UQMRename.h"

#endif /* UQM_h */
