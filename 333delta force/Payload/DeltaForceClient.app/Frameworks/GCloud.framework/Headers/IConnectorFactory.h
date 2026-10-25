//
//  IConnectorFactory.h
//  GFM
//
//  Created by vforkk on 6/6/17.
//  Copyright © 2017 vforkk. All rights reserved.
//

#ifndef IConnectorFactory_h
#define IConnectorFactory_h
#include "IConnector.h"
namespace GCloud {
    class GCLOUD_EXPORT_CPP IConnectorFactory
    {
    public:
        // deprecated in GCloudSDK Version 2.0.17, please use CreateConnector API instead!
        virtual Conn::IConnector* CreateConnector(Conn::ConnectorType type, bool manualUpdate, bool autoReconnect, bool autoLogin) = 0;
        
        virtual Conn::IConnector* CreateConnector(Conn::ConnectorType type, bool manualUpdate, bool autoReconnect, int msgMask) = 0;
        
        virtual Conn::IConnector* CreateConnector(Conn::ConnectorType type, int threadMode, bool autoReconnect, int msgMask) = 0;
        
        virtual void DestroyConnector(Conn::IConnector* connector) = 0;
    };
}

#endif /* Header_h */
