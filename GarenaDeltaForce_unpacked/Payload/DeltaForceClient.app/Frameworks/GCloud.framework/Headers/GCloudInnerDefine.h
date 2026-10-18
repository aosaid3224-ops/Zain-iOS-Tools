#ifndef GCloud_Inner_Define_h
#define GCloud_Inner_Define_h

#define JNI_CLASS_GSDK_GCLOUD_GCLOUD "com/gsdk/gcloud/GCloud"
#define JNI_CLASS_GSDK_GCLOUD_NETINTERFACE_HELPER "com/gsdk/gcloud/netinterface/NetInterfaceHelper"
#define JNI_CLASS_GSDK_GCLOUD_NETINTERFACE_MSGWORK "com/gsdk/gcloud/netinterface/MsgWorker"
#define JNI_CLASS_GSDK_GCLOUD_QR_QRCODEAPI "com/gsdk/gcloud/qr/QRCodeAPI"
#define JNI_CLASS_GSDK_GCLOUD_DOLPHIN_CUIIPSMOBILE "com/gsdk/gcloud/dolphin/CuIIPSMobile"
#define JNI_CLASS_GSDK_GCLOUD_APKCHANNEL_APKCHANNELUTIL "com/gsdk/gcloud/dolphin/ApkChannelUtilOld"
#define JNI_CLASS_GSDK_GCLOUD_V3_APKCHANNEL_APKCHANNELUTIL "com/gsdk/gcloud/dolphin/ApkChannelUtilNew"
#define MAC_GSDK_GCLOUD_TDM_BUNDLE_ID "com.tdatamaster.TDataMaster"
#define MAC_GSDK_GCLOUDCORE_BUNDLE_ID "com.cros.gcloud.GCloudCore"

namespace GCloud {
    namespace Conn
    {
        enum
        {
            kChannelNone = 0,
            kChannelTWChat = 1,
            kChannelTQChat = 2,
            kChannelGuest = 3,
            kChannelFacebook,
            kChannelGameCenter,
            kChannelGooglePlay,
            kChannelTwitter = 9,
            kChannelGarena = 10,
            kChannelLine = 14,
            kChannelApple = 15,
        };

        enum EncryptMethod {
            kEncryptNone = 0,
            kEncryptTea  = 1,
            kEncryptTQCHAT   = 2,
            kEncryptAes  = 3,
            kEncryptAes2 = 4,
        };
    }
    
    typedef int ChannelType;
}
#endif
