//
//  APMDeviceInfoSupport.h
//  APMDeviceInfoSupport
//
//  Created by Tianyu Xia on 2022/9/29.
//  Copyright © 2022 xianglin. All rights reserved.
//

#import <Foundation/Foundation.h>

#if defined(__cplusplus)
extern "C" {
#endif
extern int apm_InitDeviceExtensionInfoSupport(void);
extern int apm_InitBatteryInfoSupport(void);

NSDictionary *apm_CollectGPUMessage(void);
NSDictionary *apm_CollectTemperatureMessage(void);
NSDictionary *apm_CollectCurrentMessage(void);
NSDictionary *apm_CollectVoltageMessage(void);
int apm_getBatteryMax(void);

#if defined(__cplusplus)
}
#endif


