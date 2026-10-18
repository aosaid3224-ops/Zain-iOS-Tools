//
//  MSDKDnsUnityManager.h
//  MSDKDns
//
//  Created by fu chunhui on 16/7/25.
//  Copyright © 2016年 MSDK. All rights reserved.
//

#ifndef MSDKDnsUnityManager_h
#define MSDKDnsUnityManager_h

#import <MSDKDns/MSDKDns.h>

@interface MSDKDnsUnityManager : NSObject

+ (id)sharedInstance;
- (NSString *)GetHostByName:(const char *)domain;
- (void)GetHostByNameAsync:(const char *)domain tag:(const char *)tag;
- (NSString *)GetHostByName:(const char *)domain netChannel:(const char *)netChannel;

- (int)SetRecursiveToken:(const char *)token;
- (NSString *)GetHostByNameRecursive:(const char *)domain timeOut:(int)timeOut;
- (NSString *)GetHostByNameForAllRecursive:(const char *)domain timeOut:(int)timeOut;

/**
 检查DNS结果是否来自HTTP
 @param domain 域名
 @return 检查结果，返回int值
    0(00): 本次DNS结果V4和V6均来自Local或为空
    1(01): 本次DNS结果V4来自Local或为空，V6来自Http
    2(10): 本次DNS结果V4来自Http，V6来自Local或为空
    3(11): 本次DNS结果V4和V6均来自Http
 */
- (int)CheckDnsResultFromHttp:(const char *)domain;

// 发送上报信息给unity
- (void)sendReportToUnity:(NSString *)eventName reportInfo:(NSDictionary *)reportInfo;
@end

#endif /* MSDKDnsUnityManager_h */
