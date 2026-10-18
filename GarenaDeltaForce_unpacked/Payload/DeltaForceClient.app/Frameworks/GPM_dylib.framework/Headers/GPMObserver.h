
//
//  SDKObserver.h
//  APM
//
//  Created by 雍鹏亮 on 2019/10/23.
//  Copyright © 2019 xianglin. All rights reserved.
//


#ifndef ONESDK_TRI_IOS_GPM_PORTAL_OBSERVER_GPMOBSERVER_H_
#define ONESDK_TRI_IOS_GPM_PORTAL_OBSERVER_GPMOBSERVER_H_

class GPMObserver{
 public:
    virtual void GPMOnMarkLevelLoad(const char *sceneId) = 0;

    virtual void GPMOnSetQulaity(const char *quality) = 0;

    virtual void GPMOnLog(const char *log) = 0;

    virtual void GPMOnFpsNotify(const char *fpsString) = 0;

    virtual ~GPMObserver() {}
};

#endif  // ONESDK_TRI_IOS_GPM_PORTAL_OBSERVER_GPMOBSERVER_H_
