//
//  APM.h
//  APM
//
//  Created by vincentwgao on 2018/9/14.
//  Copyright © 2018年 xianglin. All rights reserved.
//
#ifndef ONESDK_TRI_IOS_GPM_PORTAL_GPMAPIINTERFACEOBJECT_H_
#define ONESDK_TRI_IOS_GPM_PORTAL_GPMAPIINTERFACEOBJECT_H_
//  #include <string>
//  #include <vector>
#include "GPMObserver.h"

//  typedef struct
//  {
//    std::string key;
//    std::string value;
//
//  } APMDictionary;


#define GCLOUD_VERSION_GPM_ANO "GCLOUD_VERSION_GPM_ANO_3.0.0202.686_ano"

#if defined(__cplusplus)
extern "C" {
#endif


typedef enum {
    GPMComponentDisableNone = 0,
    GPMComponentDisableAPM  = 0x01,
    GPMComponentDisableGEM  = 0x01 << 1,
    GPMComponentDisableGEMLocalNetwork  = 0x01 << 2,
} GPMComponentInitOption;

extern GPMComponentInitOption gpm_init_options;

/// 初始化SDK，调用其他API之前必须先做初始化操作
/// @param appId  appId
/// @param engine 上层使用引擎，如：UE4、Unity等
/// @param debug 是否为调试模式
int gpm_initContext(const char *appId, const char *engine, bool debug, int options);


/// 设置一个事件观察者
/// @param observer 事件观察者
void gpm_setObserver(GPMObserver *observer);


/// 是否允许为debug模式
void gpm_enableDebugMode();


/// 设置服务器信息
/// @param zoneId 大区Id
/// @param roomIp 房间服务器ip
void gpm_setServerInfo(const char *zoneId, const char *roomIp);


/// 进入游戏场景
/// @param sceneId 场景Id
void gpm_markLevelLoad(const char *sceneId);

/// 添加加载事件， 只能在gpm_markLevelLoad之后，且gpm_markLevelLoadCompleted之前调用。
/// @param eventName 事件名称
void gpm_addLoadingEvent(const char* eventName);

/// 结束游戏场景
void gpm_markLevelFin();

/// 游戏上报数据增加自定义字段（格式：key1:value1;key2:value2）,每次调用追加
void gpm_addCustomParamsInGame(const char *customParams);

/// 登录上报数据增加自定义字段
/// @param eventCategory 事件 名称
/// @param customParams 格式：key1:value1;key2:value2,每次调用追加
void gpm_addCustomParamsInStepEvent(const char *eventCategory, const char *customParams);

/// 保存FPS信息
/// @param favg 平均帧率
/// @param fmax 最大帧率
/// @param fmin 最小帧率
/// @param ftotal fps采集总次数
/// @param fheavy fps严重抖动次数
/// @param flight fps轻微抖动次数
/// @param fcntx0 fps自定义抖动次数
/// @param flfps1 fps小于lfps1的次数
/// @param flfps2 fps小于lfps2的次数
/// @param flfps3 fps小于lfps3的次数
/// @param fpsdots fps打点信息
void gpm_saveFps(float favg, int fmax, int fmin, int ftotal, int fheavy, int flight,
                 int fcntx0, int flfps1, int flfps2, int flfps3, const char * fpsdots);

/// 游戏进度条加载结束
void gpm_markLevelLoadCompleted();

/// 设置玩家登陆后的openid
/// @param openId  openID 玩家登陆后的openid
void gpm_setOpenId(const char *openId);


/// 设置游戏画质
/// @param quality 游戏画质, 默认为0
void gpm_setQulaity(int quality, int type);


/// 自定义事件上报接口
/// @param eventName 事件名称，最大长度128
/// @param eventList 事件内容 key最大长度64，value最大长度1024，key最大个数50
//  void gpm_postEvent(const char *eventName, std::vector<APMDictionary>& eventList);
void gpm_postEventSS(const char *eventName, const char* eventList);


/// 自定义数据流事件上报接口
/// @param eventCategory 事件名称
/// @param stepId 事件步骤
/// @param status 事件状态
/// @param code 事件状态码
/// @param msg 事件详细信息
/// @param extraKey 事件额外信息
void gpm_postStepEvent(const char *eventCategory, int stepId, int status, int code,
                       const char *msg, const char *extraKey, bool authorize, bool finish);

/// 当出现网络时延跳变/超时时，调用此方法进行网络质量诊断
void gpm_detectInTimeout();

    //  APM features
void gpm_postCoordinates(float x, float y, float z, float pitch, float yaw, float roll);

int gpm_checkDCLSByQcc(const char *absolutePath, const char *configName);

int gpm_checkDCLSByQccSync(const char *absolutePath, const char *configName);

int gpm_checkDCLSByString(const char* configName, const char* json);

void gpm_postFrame(float deltaTime, unsigned int frameIdx);

void gpm_postFrameWithSource(float deltaTime, unsigned int frameIdx, int source);

void gpm_postNetLatency(int latency, const char *ip, const char *serverInfo);

void gpm_beginTupleWrap(const char *category);

void gpm_endTupleWrap();

void gpm_postValueF1(const char *category, const char *key, float a, unsigned int frameIdx);

void gpm_postValueF2(const char *category, const char *key, float a, float b, unsigned int frameIdx);

void gpm_postValueF3(const char *category, const char *key, float a, float b, float c, unsigned int frameIdx);

void gpm_postValueI1(const char *category, const char *key, int a, unsigned int frameIdx);

void gpm_postValueI2(const char *category, const char *key, int a, int b, unsigned int frameIdx);

void gpm_postValueI3(const char *category, const char *key, int a, int b, int c, unsigned int frameIdx);

void gpm_postValueS(const char *category, const char *key, const char *value, unsigned int frameIdx);

void gpm_postValueCoordinate(const char *category, const char *key, float x, float y, float z, float pitch, float yaw, float roll, unsigned int frameIdx);

void gpm_setDefinedDeviceClass(int deviceClass);

void gpm_setTargetFramerate(int target);

void gpm_beginTag(const char *tagName);

void gpm_endTag();

void gpm_beginExtTag(const char *tagName);

void gpm_endExtTag(const char *tagName);

void gpm_setVersionIden(const char *versionName);

void gpm_setMatchId(const char *matchId);

void gpm_beignExclude();

void gpm_endExclude();

// 获取的错误信息字符串使用完毕后需要free操作
const char * gpm_getErrorMsg(int errorCode);

void gpm_linkSession(const char* eventName);

void gpm_initStepEventContext();

void gpm_releaseStepEventContext();

void gpm_postEventIS(int key, const char* value);

const char* gpm_getSDKVersion();

void gpm_log(const char * log);


void gpm_PostCpuTime(int x, int y);

int gpm_GetPostCpuFlag();

int gpm_GetPostGpuFlag();

void gpm_SetAppPauseState(int flag);

void gpm_setEngineMetaInfo(int engineType, const char *engineVersion, int grapohicsApi,
                           const char *vendor, const char *render, const char *version,
                           int gragraphicsMemSize, int graphicsMT, int supportRendertargetCount,
                           int isOpenGLES, int buildModel);

void gpm_blockDomesticCDNURL(void);

void gpm_postMemoryWarning();

void gpm_syncServerTime(unsigned int serverTime);

unsigned int gpm_getNativeFrameIdx(void);

void gpm_startUpFinish(void);

unsigned int gpm_getAvailableDiskSize(void);

bool gpm_setPostValueQueueLength(int postValueQueueLength);


void gpm_setCustomizedDeviceID(const char *deviceId);

// need free, if return result is no null
const char* gpm_getSDKDefinedDeviceID(void);

//enum ApmInfoType { Unknown, Pss, CurrentNow, Voltage, Status, BatteryTemperature, CpuTemperature  }

typedef enum {
    TAPMInfoTypeUnknow = 0,
    TAPMInfoTypeCurrentNow = 2,
    TAPMInfoTypeVoltage = 3,
    TAPMInfoTypeFootprint = 1,
    TAPMInfoTypeThermalState = 7,
    TAPMInfoTypeWifiFreqEnable5G = 8,
    TAPMInfoTypeMonoReserved = 10,
    TAPMInfoTypeCpuUsage = 11,
    TAPMInfoTypeNetState= 12,
    TAPMInfoTypeVPNState = 13,
    TAPMInfoTypeGPURenderer = 14,
    TAPMInfoTypeGPUDevice = 15,
    TAPMInfoTypeGPUTiler = 16,
}TAPMInfoType;

int gpm_getApmInfo(TAPMInfoType infoType, bool useCache);

bool gpm_isKvMsgFull();

void gpm_setMainFunctionExecuteTime(int timestamp);

int gpm_GetNetTrafficSinceBeginScene(int type);

void gpm_regularlyDumpThreadBacktrace(bool enable);

// 如果不设置取云控默认值
void gpm_setRegularlyDumpThreadBacktraceInterval(int interval);


void gpm_checkTickRefreshTimeDumpThreadBacktrace(bool enable);

// 如果不设置取云控默认值
void gpm_setCheckTickRefreshTimeDumpThreadBacktraceThresholdIntervalAndPrecision(int threshold, int precision);

void gpm_enablePerfSightStepEvent(void);

void gpm_enableLogger(bool enable);


void gpm_postResolution(int width, int height, int percentage);

void gpm_setResolutionFunc(void (*resolutionFunc)(void));


void gpm_traceRoute(const char *ipAddress);
void gpm_ping(const char *ipAddress);
void gpm_sendUdp(const char *ipAddress, int port);
void gpm_sendTcp(const char *ipAddress, int port);
void gpm_scanWifiDetail();

void gpm_flushData(void);

void gpm_SetLocalStrategy(int strategy_id, bool strategy_value);


void gpm_markLevelPause(void);

void gpm_markLevelContinue(void);

void gpm_setPerfSightUploadURL(const char *url);


void gpm_postValueBinary(const char *category, const char *key, const char *value, unsigned int len, bool localCache);

void gpm_setBinaryDataMaxSizeInMb(int size_in_mb);


void gpm_postCallGraph(int type, const char* caller, const char* callee, int
                                 call_count, int cost_time);


void gpm_setFlameGraphSize(int maxSize);

void gpm_enable_upload_cmd();

void gpm_setPostValueStrMaxLen(int maxLen);

void gpm_setFlameGraphDropThresholds(int flameGraphDropThresholds);

void gpm_setFlameGraphStrMapSize(int maxLen);

void gpm_setMaxReportSize(int);

void gpm_setGameLogPath(const char * gameLogPath);

void gpm_setThermalStateChangeCallBack(void (*callback)(int));

void gpm_reportData(const void *data, int len);

typedef enum   {
    TAPMDeviceInfoTypeDEVICE_NONE,
    TAPMDeviceInfoTypeOS_VERSION, //系统版本
    TAPMDeviceInfoTypeDISK_TYPE,
    TAPMDeviceInfoTypeAPP_ARCH,
    TAPMDeviceInfoTypeDEVICE_ARCH,
    TAPMDeviceInfoTypeGPU_VENDOR,
    TAPMDeviceInfoTypeGPU_RENDERER,
    TAPMDeviceInfoTypeGPU_VERSION,
    TAPMDeviceInfoTypeCPU_NAME,
    TAPMDeviceInfoTypeMAC_ADDRESS,
    TAPMDeviceInfoTypeMODEL_NAME //设备机型
}TAPMDeviceInfoType;

const char* gpm_getDeviceInfo(TAPMDeviceInfoType);

int gpm_getDeviceMemInMB();

void gpm_setLuaState(void* lua);

void gpm_setLuaFunc(void *getglobal, void *getfield, void *pushstring, void *pushinteger, void *pcallk, void *tolstring, void *settop);

#if defined(__cplusplus)
}
#endif
#endif  // ONESDK_TRI_IOS_GPM_PORTAL_GPMAPIINTERFACEOBJECT_H_

