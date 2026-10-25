 #ifndef GCloud_GROMELINK_GROMELINKSNIFFER_H_
 #define GCloud_GROMELINK_GROMELINKSNIFFER_H_

#include "GCloudPal.h"

namespace GCloud {
namespace GRomeLink {

class GCLOUD_EXPORT_CPP GRomeLinkSnifferObserver
{
public:
    GRomeLinkSnifferObserver(){ };
    
public:
    virtual void OnPickup(const char *result) = 0;
    virtual void OnPing(const char *tag,const char * result) = 0;
    virtual void OnPickupLobby(const char * extip, const char * result) = 0;
};
 
class GCLOUD_EXPORT_CPP GromeLinkSniffer {
public:
    enum IPv6Flag {
        IPV6_NONE = 0x0,
        IPV6_USE_IPV6 = 0x1,
        IPV6_USE_NAT64 = 0x10,
    };

    static GromeLinkSniffer &Instance();

    void SetObserver(GRomeLinkSnifferObserver *observer);
     
    int SetupCluster(const char *romelink, const char *romelink_v6, int policy, const char *clusters, const char *cluster_v6, int interval, int count, int timeout, const char *params,IPv6Flag ipv6_flag);
    
    int SetupLobbyCluster(const char *romelink,const char *romelink_v6, const char *cluster, int timeout,IPv6Flag ipv6Flag);
    
    void Ping(const char *tag, IPv6Flag ipv6Flag);

    void SetZSD(const char *params);

private: 
    GromeLinkSniffer();

private:
    GRomeLinkSnifferObserver *observer_;

};


} // end of namespace GRomeLink
} // end of namespace GCloud

 #endif
