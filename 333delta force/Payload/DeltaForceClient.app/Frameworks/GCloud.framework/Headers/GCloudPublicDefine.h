//
//  GCloudPublicDefine.h
//  TGSF
//
//  Created by vforkk on 14/1/14.
//  Copyright (c) 2014 TSF4G. All rights reserved.
//

#ifndef _GCloud_PublicDefine_h
#define _GCloud_PublicDefine_h

#include "ApolloBuffer.h"
#include "AString.h"
#include "GCloudInnerDefine.h"

namespace GCloud {
    
    ///////////////////////////////////////////////////////////////////////////////////
    // Macro & enum
    ///////////////////////////////////////////////////////////////////////////////////
    
#define ASYN
#define SYN
    
#define IN
#define OUT
#define INOUT
   
    typedef long long SeqId;
 
    enum
    {
        // Common
        kSuccess = 0,
        kErrorInnerError = 1,
        kErrorNetworkException = 2,
        kErrorTimeout = 3,
        kErrorInvalidArgument = 4,
        kErrorLengthError = 5,
        kErrorUnknown = 6,
        kErrorEmpty = 7,
        kErrorNotInitialized = 9,
        kErrorNotSupported = 10,
        kErrorNotInstalled = 11,
        kErrorSystemError = 12,
        kErrorNoPermission = 13,
        
        kErrorInvalidGameId,
        
        // AccountService, from 100
        kErrorInvalidToken = 100,
        kErrorNoToken = 101,
        kErrorAccessTokenExpired = 102,
        kErrorRefreshTokenExpired = 103,
        kErrorPayTokenExpired = 104,
        kErrorLoginFailed = 105,
        kErrorUserCancel = 106,
        kErrorUserDenied,
        kErrorChecking,
        kErrorNeedRealNameAuth,
        
        // Connector, from 200
        kErrorNoConnection = 200,
        kErrorConnectFailed = 201,
        kErrorIsConnecting,
        kErrorGcpError,
        kErrorPeerCloseConnection,
        kErrorPeerStopSession,
        kErrorPkgNotCompleted,
        kErrorSendError,
        kErrorRecvError,
        kErrorStayInQueue,
        kErrorSvrIsFull,
        kErrorTokenSvrError,
        kErrorAuthFailed,
        kErrorOverflow,
        
        // PayService, from 300
        // Common  from 400
        
        
        // TDir from 500
        kErrorLeafNotFound = 500,
        kErrorPlatformNotFound,
        kErrorAccDisabled,
        
        
        // LBS from 600
        kErrorLbsNeedOpenLocation = 600,
        kErrorLbsLocateFail,
        
        // LEAP from 700-799
        kErrorSimpleClientNull = 700,
        kErrorMSDGClientOffline = 701,
        
        kErrorOverlappingAccess = 710,
        
        kErrorSaveInvalidData = 731,
        kErrorSaveDataTooBig  = 732,
        kErrorSaveInvalidType = 733,
        kErrorSaveOverflowKeyLimit = 734,
        kErrorSaveFailedToAllocate = 735,
        
        kErrorLoadNoData      = 751,
        kErrorLoadInvalidType = 752,
        kErrorLoadFailedToAllocate = 753,
        
        kErrorOrderParamsInvalid = 771,
        kErrorOrderFailedToAllocate = 772,
        kErrorOrderTimeout = 773,
        
        kErrorEasyPayUnderProcessing = 781,
        kErrorEasyPayError = 782,
        kErrorEasyPayCancel = 783,
        kErrorEasyPayParamError = 784,
        kErrorEasyPayNeedLogin = 785,
        
        kErrorSetDeliveredNonexistent = 791,
        kErrorSetDeliveredParamsInvalid = 792,
        
        kErrorOthers = 10000,
        
        // Pebble RPC from 11000-11999
        kPebbleBase = 11000,
        kPebbleInitZKFailed = kPebbleBase + 1,
        kPebbleRpcTimeoutError = kPebbleBase + 2,
        kPebbleResolveServiceAddressError = kPebbleBase + 3,
        kPebbleSendRequestFailed = kPebbleBase + 4,
        kPebbleCreateServiceInstanceFailed = kPebbleBase + 5,
        kPebbleInvalidPara = kPebbleBase + 6,
        kPebbleRecvException = kPebbleBase + 7,
        kPebbleRecvFailed = kPebbleBase + 8,
        kPebbleMsgTypeError = kPebbleBase + 9,
        kPebbleOtherException = kPebbleBase + 10,
        kPebbleMissingResult = kPebbleBase + 11,
        kPebbleSystemError = kPebbleBase + 100,

        // Update from 12000-12999
        kUpdateBase = 12000,
        kUpdateInvalidProduct = kUpdateBase + 1,
        kUpdatePackageLineNotFound = kUpdateBase + 2,
        kUpdateVersionNotFound = kUpdateBase + 3, 
        kUpdatePackageNotSupportRollback = kUpdateBase + 4, 
        kUpdateGameIDNotFound = kUpdateBase + 5,  
        kUpdateGameIDNotSupplied = kUpdateBase + 6,
        kUpdateSubIDNotFound = kUpdateBase + 7, 
        kUpdateAuthSvrErr = kUpdateBase + 8,
        kUpdateAuthFailed = kUpdateBase + 9,
        kUpdateAuthUserDenied = kUpdateBase + 10,
        kUpdateAuthAnonDenied = kUpdateBase + 11,
        kUpdateClientIdentVerifyFailed = kUpdateBase + 12,
        kUpdateRequestExpired = kUpdateBase + 64,
        kUpdateDecodeError = kUpdateBase + 99,
        kUpdateErrUnknown = kUpdateBase + 100,
    };
    typedef int EErrorCode;
    
    struct GCLOUD_EXPORT_CPP Result : public GCloud::ApolloBufferBase
    {
        EErrorCode ErrorCode;
        GCloud::AString Reason;
        int Extend;
        int Extend2;
        //
        // Construtions
        //
    public:
        Result()
        : ErrorCode(kSuccess)
        , Extend(0)
        , Extend2(0)
        {
            
        }
        
        Result(EErrorCode errorCode)
        : ErrorCode(errorCode)
        , Extend(0)
        , Extend2(0)
        {
            
        }
        
        Result(EErrorCode errorCode, const char* reason)
        : ErrorCode(errorCode)
        , Reason(reason)
        , Extend(0)
        , Extend2(0)
        {
            
        }
        
        Result(EErrorCode errorCode, int ext, const char* reason)
        : ErrorCode(errorCode)
        , Reason(reason)
        , Extend(ext)
        , Extend2(0)
        {
            
        }
        
        Result(EErrorCode errorCode, int ext, int ext2, const char* reason)
        : ErrorCode(errorCode)
        , Reason(reason)
        , Extend(ext)
        , Extend2(ext2)
        {
            
        }
        
        Result(const Result& r)
        {
            ErrorCode = r.ErrorCode;
            Reason = r.Reason;
            Extend = r.Extend;
            Extend2= r.Extend2;
        }
        
        //
        // static functions
        //
    public:
        
        
        void Reset(EErrorCode error, const char* reason = "")
        {
            ErrorCode = error;
            Reason = reason;
            Extend = 0;
            Extend2 = 0;
        }
        
        void Success()
        {
            ErrorCode = kSuccess;
            Reason = "";
            Extend = 0;
            Extend2 = 0;
        }
        
        bool IsSuccess()const
        {
            return ErrorCode == kSuccess;
        }
        
        GCloud::AString ToString()const
        {
            char buf[50]={0};
            snprintf(buf, sizeof(buf), "%d, ext:%d, ext2:%d, ", ErrorCode, Extend, Extend2);
            
            GCloud::AString desc;
            desc = buf;
            desc += Reason;
            return desc;
        }
        
        bool operator == (EErrorCode errorCode)const
        {
            return ErrorCode == errorCode;
        }
        
        bool operator != (EErrorCode errorCode)const
        {
            return ErrorCode != errorCode;
        }
        
    public:
        virtual AObject* Clone()const;
        
        virtual void WriteTo(GCloud::CApolloBufferWriter& write)const
        {
            write.Write(ErrorCode);
            write.Write(Reason);
            write.Write(Extend);
            write.Write(Extend2);
        }
        
        virtual void ReadFrom(GCloud::CApolloBufferReader& reader)
        {
            int tmp;
            reader.Read(tmp);
            ErrorCode = (EErrorCode)tmp;
            reader.Read(Reason);
            reader.Read(Extend);
            reader.Read(Extend2);
        }
    };

    static const char* kGCloudModuleLWIP = "LWIP";

    enum PropertyType
    {
        kPropertyBase = 0,
        kPropertyCPU = 1,
        kPropertyDNS = 2,
        kPropertyDNSPolicy = 3,
    };

    struct GCLOUD_EXPORT_CPP PropertyInfo : public GCloud::ApolloBufferBase
    {
    protected:
        uint32_t InfoType;

    public:
        PropertyInfo() : InfoType(kPropertyBase) {}
        uint32_t GetInfoType() const { return InfoType; }

    protected:
        PropertyInfo(uint32_t type) : InfoType(type) {}

    public:
        virtual AObject* Clone() const;

        void WriteTo(GCloud::CApolloBufferWriter& writer) const { writer.Write(InfoType); }

        void ReadFrom(GCloud::CApolloBufferReader& reader) { reader.Read(InfoType); }
    };

    struct GCLOUD_EXPORT_CPP PropertyCPUInfo : public PropertyInfo
    {
    public:
        AString Module;    // Module name
        uint32_t CPUAffinity;  // 0 auto; >0 core mask, low - high, cpu0 - cpu31

    public:
        PropertyCPUInfo() : PropertyInfo(kPropertyCPU), CPUAffinity(0) {}

    public:
        virtual AObject* Clone() const;

        void WriteTo(GCloud::CApolloBufferWriter& writer) const
        {
            PropertyInfo::WriteTo(writer);
            writer.Write(Module);
            writer.Write(CPUAffinity);
        }

        void ReadFrom(GCloud::CApolloBufferReader& reader)
        {
            PropertyInfo::ReadFrom(reader);
            reader.Read(Module);
            reader.Read(CPUAffinity);
        }
    };

    struct GCLOUD_EXPORT_CPP PropertyDNSInfo : public PropertyInfo
    {
    public:
        AString Module;         // Module name: dmp1 | dmp2
        int DNSModeType;        // 0: LocalDns, 1: MultiDns, 2: HttpDns, 3: DoH, 4: CAresDns
        
    public:
        PropertyDNSInfo() : PropertyInfo(kPropertyDNS), DNSModeType(-1) {}
        
    public:
        virtual AObject* Clone() const;
        
        void WriteTo(GCloud::CApolloBufferWriter& writer) const
        {
            PropertyInfo::WriteTo(writer);
            writer.Write(Module);
            writer.Write(DNSModeType);
        }
        
        void ReadFrom(GCloud::CApolloBufferReader& reader)
        {
            PropertyInfo::ReadFrom(reader);
            reader.Read(Module);
            reader.Read(DNSModeType);
        }
    };

    struct GCLOUD_EXPORT_CPP PropertyDNSPolicyInfo : public PropertyInfo
    {
    public:
        AString Module;         // Module name: dmpv2 | puffer | dolphin
        int DNSPolicy;          // DNS循环策略: 1: LocalDns(循环), 2: LocalDns->HttpDns->LocalDns->LocalDns->..., 3: HttpDns->LocalDns->LocalDns->..., 4: HttpDns(循环)
        
    public:
        PropertyDNSPolicyInfo() : PropertyInfo(kPropertyDNSPolicy), DNSPolicy(-1) {}
        
    public:
        virtual AObject* Clone() const;
        
        void WriteTo(GCloud::CApolloBufferWriter& writer) const
        {
            PropertyInfo::WriteTo(writer);
            writer.Write(Module);
            writer.Write(DNSPolicy);
        }
        
        void ReadFrom(GCloud::CApolloBufferReader& reader)
        {
            PropertyInfo::ReadFrom(reader);
            reader.Read(Module);
            reader.Read(DNSPolicy);
        }
    };
    
    // Log
    typedef enum
    {
        kDebug,
        kInfo,
        kWarning,
        kEvent,
        kError,
        kNone,
    }LogPriority;
    
    
    typedef int StopReason;
    
    struct GCLOUD_EXPORT_CPP InitializeInfo : public GCloud::ApolloBufferBase
    {
        GCloud::AString PluginName;
        uint64_t GameId;
        GCloud::AString GameKey;
        GCloud::AString EncKey;
        
    public:
        InitializeInfo()
        : GameId(0)
        {
            
        }
        
        InitializeInfo(uint64_t gameId, const char* gameKey, const char* pluginName = "")
        {
            PluginName = pluginName;
            GameId = gameId;
            GameKey = gameKey;
        }
        
        
    public:
        virtual AObject* Clone()const;
        
        void WriteTo(GCloud::CApolloBufferWriter& writer)const
        {
            writer.Write(PluginName);
            writer.Write(GameId);
            writer.Write(GameKey);
            writer.Write(EncKey);
        }
        
        void ReadFrom(GCloud::CApolloBufferReader& reader)
        {
            reader.Read(PluginName);
            reader.Read(GameId);
            reader.Read(GameKey);
            reader.Read(EncKey);
        }
    };
    
    struct GCLOUD_EXPORT_CPP UserInfo: public GCloud::ApolloBufferBase
        {
            int ChannelID;
            GCloud::AString OpenID;
            UserInfo():ChannelID(0)
            {
            }
        public:
            virtual AObject* Clone()const;
            
            virtual void WriteTo(GCloud::CApolloBufferWriter& writer)const
            {
                writer.Write(ChannelID);
                writer.Write(OpenID);
            }
            
            virtual void ReadFrom(GCloud::CApolloBufferReader& reader)
            {
                reader.Read(ChannelID);
                reader.Read(OpenID);
            }
            bool operator == (UserInfo userInfo)const
            {
                if(OpenID==userInfo.OpenID&&ChannelID==userInfo.ChannelID)
                {
                    return true;
                }
                return false;
            }
            
            bool operator != (UserInfo userInfo)const
            {
                if(OpenID==userInfo.OpenID&&ChannelID==userInfo.ChannelID)
                {
                    return false;
                }
                return true;
            }
        };
}

#if defined(_WIN32) || defined(_WIN64)
typedef void (__stdcall *GCloudLogCallback)(GCloud::LogPriority pri, const char* msg);
#else
typedef void (*GCloudLogCallback)(GCloud::LogPriority pri, const char* msg);
#endif

#endif
