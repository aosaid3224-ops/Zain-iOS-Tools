//
//  kgvmp.h
//  kgvmp
//
//  Created by zohnzliu(刘专) on 2018/7/10.
//  Copyright © 2018年 tgpa. All rights reserved.
//

#import <UIKit/UIKit.h>

// In this header, you should import all the public headers of your framework using statements like #import <kgvmp/PublicHeader.h>

typedef void (*VmpCallbackDelegate)(const char* json);

#if defined(__cplusplus)
extern "C"
{
#endif
    // 获取SDK的版本号
    int _GetVersionCode(void);
    // 获取SDK的版本名称
    char* _GetVersionName(void);
    // 开启debug模式，直接访问测试服务器
    void _EnableDebugMode(void);
    // 打开日志输出
    void _SetLogAble(bool enable);
    // Deprecated; 检测sdk功能是否开启
    bool _CheckSdkCanWork(void);
    // 初始化TGPA，需要在MSDK初始化之后/登录之前调用
    void _InitTGPA(void);
    // 注册回调函数，需要在登录之后调用
    void _RegisterVmpCallback(VmpCallbackDelegate callback);
    // 发送游戏数据1
    void _UpdateGameInfoII(int key, int value);
    // 发送游戏数据2
    void _UpdateGameInfoIS(int key, const char* value);
    // 发送游戏数据3
    void _UpdateGameInfoSS(const char* key, const char* value);
    // 发送游戏数据4
    void _UpdateGameInfoIF(int key, float value);
    // 发送游戏对局FPS数据
    void _PostMatchFPSData(int size, float* fpsArr);

    // 从TGPA侧获取数据
    char* _GetDataFromTGPA(const char* key, const char* value);

    int TGPA_HapticSupport();

    int TGPA_HapticAmplitudeSupport();

    void TGPA_HapticPlay(const char* heJson, int loop, int interval, int amplitude);

    void TGPA_HapticPlayWithFile(const char* heFilePath, int loop, int interval, int amplitude);

    void TGPA_HapticStop();
    
#if defined(__cplusplus)
}
#endif
