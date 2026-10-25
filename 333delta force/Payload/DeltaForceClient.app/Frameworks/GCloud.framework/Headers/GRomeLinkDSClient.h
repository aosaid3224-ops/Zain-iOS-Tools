#ifndef GROMELINK_SOCKET_H_
#define GROMELINK_SOCKET_H_
namespace GRomeLink {

    #define GRomeLinkClientInterfaceVersion 20240122

    enum ErrorCode{
        em_error_no_error = 0,
        em_error_already_listened = -1,
        em_error_failed_to_start_listen = 2,
    };

    class ISocket {
    public:
        virtual ~ISocket(){}; 
    public:
        // Return 0 on success.
        virtual int Connect(const char *url) = 0;

        // Return 0 on success.
        virtual int Send(const char *buf, int len) = 0;     
        // Send on 4G Return 0 on success.
        virtual int SendOn4G(const char *buf, int len) = 0;     

        // Return length of recvbuffer.
        virtual int Recv(char *buf, int len) = 0;
        // Set the cookie of current connection.
        virtual void UpdateCookie(const char *cookie,int cookielen) = 0;  

        // Return Whether the network is connected.
        virtual bool IsConnected() = 0;

        // If has both wifi and 4G return true.
        virtual bool IsDualLinkAvaible() = 0;

        // Enable/Disable duallink. For both up and down streams.
        virtual bool SetDualLinkEnabled(bool enabled) = 0; 
        
        // Interface for report.
        virtual bool begin_report() = 0;
        virtual bool set_report(const char *key,const char *value) = 0;
        virtual bool commit_report() = 0;
    };

    class ISocketFactory{
        public:
        virtual ~ISocketFactory(){
        }

        virtual ISocket *CreateSocket() = 0;
        virtual void    DestorySocket(ISocket *ps) = 0;
        virtual bool Update() = 0;
    };
} //end of namespace GRomeLink


#if defined(LINUXLWIP) || defined(GROMELINK_USER)
extern "C" GRomeLink::ISocketFactory *GetISocketFactory();
#else
#include "GCloudPal.h"
extern "C" GCLOUD_EXPORT_API GRomeLink::ISocketFactory *GetISocketFactory();
#endif

#endif
