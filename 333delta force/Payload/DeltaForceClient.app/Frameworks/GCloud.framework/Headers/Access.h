//
//  Access.h
//  GCloud
//
//  Created by vforkk on 14/1/14.
//  Copyright (c) 2014 TSF4G. All rights reserved.
//

#ifndef GCloud_Access_h
#define GCloud_Access_h

#include "GCloudPublicDefine.h"

namespace GCloud {
	
    class IConnectorFactory;
    class IG6ConnectorFactory;

    class GCLOUD_EXPORT_CPP Access
    {
    protected:
        Access(){}
        virtual ~Access(){}
        
    public:
        static Access& GetInstance();
        static void ReleaseInstance();

    public:
        virtual IConnectorFactory* GetConnectorFactory() = 0;

        virtual IG6ConnectorFactory* GetG6ConnectorFactory() = 0;
    };
}

#endif
