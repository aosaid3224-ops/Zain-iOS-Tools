//
//  HttpDnsPluginLifecycle.h
//  HttpDns
//
//  Created by fu chunhui on 2018/9/15.
//  Copyright © 2018年 fu chunhui. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GCloudPluginManager/GCloudAppLifecycleObserver.h"

@interface HttpDnsPluginLifecycle : NSObject <GCloudAppLifecycleObserver>

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;

@end
