//
//  UQMMacros.hpp
//  UQM
//
//  Created by joyfyzhang on 2020/9/3.
//  Copyright © 2020 joyfyzhang. All rights reserved.
//

#ifndef UQMMacros_hpp
#define UQMMacros_hpp

#include <set>
#include <map>
#include <list>
#include <string>
#include <string.h>
#include <stdlib.h>
#include <vector>
#include <cwchar>
#include <iostream>

#ifdef __cplusplus
    #define NS_UQM_BEGIN namespace UQM \
        {
    #define NS_UQM_END }
    #define USING_NS_UQM using namespace UQM;
#else
    #define NS_UQM_BEGIN
    #define NS_UQM_END
    #define USING_NS_UQM
#endif


#define UQM_UUID_KEY_NAME "uqm_uuid"
#define UQM_CONFIG_DEFAULT_GAME_ID "11"
#define UQM_SEQ_ID_PRIMARY_KEY_NAME "uqm_seq_id_primary_key"

//适配 UE4 以及 Cocos 系统定义

#if PLATFORM_WINDOWS
    #undef UQM_PLATFORM_WINDOWS
    #define UQM_PLATFORM_WINDOWS 1
#else
    #if defined(_WIN32) || defined(_WIN64)
        #undef UQM_PLATFORM_WINDOWS
        #define UQM_PLATFORM_WINDOWS 1
    #elif defined(__APPLE__)
        #include <TargetConditionals.h>
        #undef UQM_PLATFORM_WINDOWS
        #define UQM_PLATFORM_WINDOWS 0
        #if TARGET_OS_IOS || TARGET_OS_IPHONE
            #undef UQM_PLATFORM_MAC
            #define UQM_PLATFORM_MAC 0
        #else
            #undef UQM_PLATFORM_MAC
            #define UQM_PLATFORM_MAC 1
        #endif
    #else
        #undef UQM_PLATFORM_WINDOWS
        #define UQM_PLATFORM_WINDOWS 0
        #undef UQM_PLATFORM_MAC
        #define UQM_PLATFORM_MAC 0
    #endif
#endif

//UE4 环境
#if PLATFORM_WINDOWS || PLATFORM_MAC || PLATFORM_IOS || PLATFORM_ANDROID
#undef UQM_UE4
    #define UQM_UE4 1
#endif


////UE4 windows 游客登录需要做dll 函数导出的特殊处理
#if UQM_PLATFORM_WINDOWS
    #ifdef UQM_CORE
        #define UQM_EXPORT_UE __declspec(dllexport)
    #else
        #define UQM_EXPORT_UE __declspec(dllimport)
    #endif
    #define UQM_EXPORT
    #define UQM_HIDDEN
#else
    #define UQM_EXPORT_UE
    #if __GNUC__ >= 4
        #if defined(__APPLE__)
            #ifdef UQM_UE4
//                #define UQM_EXPORT UQMCORE_API
//                #define UQM_HIDDEN UQMCORE_API
                #define UQM_EXPORT
                #define UQM_HIDDEN
            #else
                #define UQM_EXPORT
                #define UQM_HIDDEN
            #endif
        #elif defined(CRASHSIGHT_PS4) || defined(CRASHSIGHT_PS5)
            #define UQM_EXPORT  __declspec(dllimport)
            #define UQM_HIDDEN
        #else
            #define UQM_EXPORT __attribute__ ((visibility ("default")))
            #define UQM_HIDDEN  __attribute__ ((visibility ("hidden")))
        #endif
    #else
        #define UQM_EXPORT
        #define UQM_HIDDEN
    #endif
#endif

//UE4 Mac/Windows

#if UQM_PLATFORM_WINDOWS
#else
    #ifdef ANDROID
        #define UQM_VERSION "5.4.000.5057"
        #define UQM_CUR_OS 1
    #elif defined(__APPLE__)
        #define UQM_CUR_OS 2
        #define UQM_VERSION "5.4.000.5057"
    #endif
#endif

#if UQM_PLATFORM_WINDOWS
#else
    #ifdef __APPLE__
        #define UQM_LABEL_KEYCHAIN_ENABLE               "UQM_KEYCHAIN_ENABLE"
    #endif
#endif

// 删除单个指针和删除多个指针
#define UQM_SAFE_DELETE(ptr) \
    do                   \
    {                    \
        if (ptr != NULL) \
        {                \
            delete ptr;  \
            ptr = NULL;  \
        }                \
} while (0)

#define UQM_SAFE_DELETE_ARR(ptr) \
    do                       \
    {                        \
        if (ptr != NULL)     \
        {                    \
            delete[] ptr;    \
            ptr = NULL;      \
        }                    \
    } while (0)

// 分配内存和释放内存
#define UQM_SAFE_MALLOC(num, type) (type *) calloc((num) , sizeof(type))
#define UQM_SAFE_FREE(ptr)   \
    do                   \
    {                    \
        if (ptr != NULL) \
        {                \
            free(ptr);   \
            ptr = NULL;  \
        }                \
    } while (0)

#if defined(__has_cpp_attribute)
#  if __has_cpp_attribute(deprecated)
#    define CS_DEPRECATED(msg) [[deprecated(msg)]]
#  else
#    define CS_DEPRECATED(msg)
#  endif
#else
#  define CS_DEPRECATED(msg)
#endif

#endif /* UQMMacros_hpp */
