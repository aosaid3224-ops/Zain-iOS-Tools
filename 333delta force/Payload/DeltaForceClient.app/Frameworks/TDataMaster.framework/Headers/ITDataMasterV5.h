
#ifndef ITDataMasterV5_h
#define ITDataMasterV5_h

#include "ITDataMasterV4.h"
_TDM_Name_Space
{
    #define TDM_REPORT_PRIVACY_KV_URL 0
    #define TDM_REPORT_COMMON_KV_URL  1

    #define TDM_REPORT_DEVICE_INFO_NONE         0x00000000
    #define TDM_REPORT_DEVICE_INFO_ALL          0xffffffff
    #define TDM_REPORT_DEVICE_INFO_QIMEI        0x00000001
    #define TDM_REPORT_DEVICE_INFO_IDFA         0x00000002
    #define TDM_REPORT_DEVICE_INFO_IDFV         0x00000004
    #define TDM_REPORT_DEVICE_INFO_TGTOKEN      0x00000008
    #define TDM_REPORT_DEVICE_INFO_ANDROIDID    0x00000010
    #define TDM_REPORT_DEVICE_INFO_OAID         0x00000020
    #define TDM_REPORT_DEVICE_INFO_XID          0x00000040

    class ITDataMasterV5 : public ITDataMasterV4
    {
    protected:
        ITDataMasterV5(){}
        virtual ~ITDataMasterV5(){}

    public:
        static PUBLIC_API ITDataMasterV5* GetInstance();
        virtual int GetVersion() { return 5; }
        
        /**
        * 设置设备信息采集与否
        */
        virtual PUBLIC_API int EnableDeviceInfoCollect(const char* deviceName, bool enable) = 0;
    };

    class ITDataMasterV6 : public ITDataMasterV5
    {
    protected:
        ITDataMasterV6(){}
        virtual ~ITDataMasterV6(){}

    public:
        static PUBLIC_API ITDataMasterV6* GetInstance();
        virtual int GetVersion() { return 6; }
        /**
        * 隐私数据上报接口
        */
        virtual PUBLIC_API int ReportEventV2(int srcID, const char* eventName, const IEventData* eventData, int host, uint32_t devInfoOpt) = 0;
    };

    class ITDataMasterV7 : public ITDataMasterV6
    {
    protected:
        ITDataMasterV7(){}
        virtual ~ITDataMasterV7(){}

    public:
        static PUBLIC_API ITDataMasterV7* GetInstance();
        virtual int GetVersion() { return 7; }
        /**
        * 刷新当前上报队列缓存接口
        */
       virtual PUBLIC_API void FlushCacheData() = 0;
       /**
        * 上报灵敏度设置接口
        */
       virtual PUBLIC_API void AgileReport(bool agile) = 0;
       /**
        * KV上报队列是否为空
        */
       virtual PUBLIC_API bool IsEventEmpty() = 0;
    };

    PUBLIC_API void IdleTDMReport(bool idle);
    PUBLIC_API int SetZTSDKCallBackFunc(void *callback_func);
}

#endif /* ITDataMasterV5_h */
