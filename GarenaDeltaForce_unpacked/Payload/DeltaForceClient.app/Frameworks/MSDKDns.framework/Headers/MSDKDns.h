//
//  MSDKDns.h
//  MSDKDns
//
//  Created by Mike on 6/24/15.
//  Copyright (c) 2015 MSDK. All rights reserved.
//
#ifndef MSDKDNS_H
#define MSDKDNS_H

// Only modify by script
#define MSDKDns_Version @"2.1.01.183"

#import <Foundation/Foundation.h>

@interface MSDKDns : NSObject

+ (id)sharedInstance;

#pragma mark - 设置业务基本信息，仅调用一次即可
/**
 设置业务基本信息（外部业务使用）

 @param appkey  业务appkey，用于上报
 @param dnsid   dns解析id，用于域名解析鉴权
 @param dnsKey  dns解析key，用于域名解析鉴权
 @param debug   是否开启Debug日志，YES：开启，NO：关闭。建议联调阶段开启，正式上线前关闭
 @param timeout 超时时间，单位ms，如设置0，则设置为默认值2000ms

 @return YES:设置成功 NO:设置失败
 */
- (BOOL)WGSetDnsAppKey:(NSString *)appkey DnsID:(int)dnsid DnsKey:(NSString *)dnsKey Debug:(BOOL)debug TimeOut:(int)timeout;

/**
 设置业务基本信息（内部及代理业务使用）

 @param appkey  业务appid
 @param debug   是否开启Debug日志，YES：开启，NO：关闭。建议联调阶段开启，正式上线前关闭
 @param timeout 超时时间，单位ms，如设置0，则设置为默认值2000ms
 @param useHttp 是否使用http路解析，YES：使用http路解析，NO：使用https路解析

 @return YES:设置成功 NO:设置失败
 */
- (BOOL)WGSetDnsAppKey:(NSString *)appkey Debug:(BOOL)debug TimeOut:(int)timeout;

/**
 设置用户id（内部及代理业务使用）

 @param dnsOpenId 用户openid

 @return YES:成功 NO:失败
 */
- (BOOL)WGSetDnsOpenId:(NSString *)dnsOpenId;

#pragma mark - 域名解析接口，按需调用
/**
 域名同步解析（通用接口）

 @param domain 域名

 @return 查询到的IP数组，超时（1s）或者未未查询到返回[0,0]数组
 */
- (NSArray *)WGGetHostByName:(NSString *)domain;

/**
 域名同步解析（带缓存命中标记输出）
 缓存 key 为 domain@wifi 或 domain@cellular，与 InChannel 接口共用同一套缓存

 @param domain  域名
 @param isCache 输出参数，YES 表示本次命中了缓存，NO 表示发起了网络请求

 @return 查询到的 IP 数组
 */
- (NSArray *)WGGetHostByName:(NSString *)domain isCache:(BOOL *)isCache;

/**
 检测当前活跃网络类型

 @return "wifi" 或 "cellular"
 */
- (NSString *)currentNetChannel;

- (NSArray *)WGGetHostByName:(NSString *)domain netChannel:(NSString *)netChannel;

/**
 InChannel 接口（带缓存命中标记输出）

 @param domain     域名
 @param netChannel 网络通道，"wifi" 或 "cellular"
 @param isCache    输出参数，YES 表示本次命中了缓存，NO 表示发起了网络请求

 @return 查询到的 IP 数组
 */
- (NSArray *)WGGetHostByName:(NSString *)domain netChannel:(NSString *)netChannel isCache:(BOOL *)isCache;

// 是否使用- (NSArray *)WGGetHostByName:(NSString *)domain netChannel:(NSString *)netChannel接口中，locandns请求，默认YES
- (void)WGSetChannelLocalDnsEnable:(BOOL)enable;

#pragma mark - For Plugin
/// 作为插件提供给其他组件的接口
/// - Parameters:
///   - domain: 解析域名
///   - pluginName: 组件名
///   - timeout: 超时时间
- (NSArray *)WGGetHostByName:(NSString *)domain pluginName:(NSString *)pluginName timeOut:(int)timeout;
- (NSArray *)WGGetHostByName:(NSString *)domain pluginName:(NSString *)pluginName timeOut:(int)timeout netChannel:(NSString *)netChannel;
- (NSArray *)WGGetHostByNameForAll:(NSString *)domain pluginName:(NSString *)pluginName timeOut:(int)timeout;

/// 加递归的解析接口，其他同上
/// 设置递归的参数
/// - Parameter token: token串
- (int)WGSetRecursiveToken:(NSString *)token;
- (NSArray *)WGGetRecursiveHostByName:(NSString *)domain pluginName:(NSString *)pluginName timeOut:(int)timeout;
- (void)WGGetRecursiveHostByNameAsync:(NSString *)domain pluginName:(NSString *)pluginName timeOut:(int)timeout returnIps:(void (^)(NSArray *ipsArray))handler;
- (NSArray *)WGGetRecursiveHostByNameForAll:(NSString *)domain pluginName:(NSString *)pluginName timeOut:(int)timeout;
/// 设置云控服务器地址
- (int)WGSetCloudCtlIP:(NSString *)ip assistIP:(NSString *)assistIP;
/// 是否开启使用备份服务地址,YES开启
- (int)WGSetCloudCtlBackupOpen:(BOOL)open;


/// 返回数据中加上错误码，
/// - Parameters:
///   - domain: 域名
///   - pluginName: 插件名
///   - timeout: 超时时间
///   - errInfo: 解析信息(格式：劫持码_V4错误码_V6错误码_耗时_解析服务ip_云控来源，如200_1_1_310_112.112.112.112_1)
- (NSArray *)WGGetRecursiveHostErrCodeByName:(NSString *)domain pluginName:(NSString *)pluginName timeOut:(int)timeout errInfo:(NSString **)errInfo;
- (NSArray *)WGGetRecursiveHostErrCodeByNameForAll:(NSString *)domain pluginName:(NSString *)pluginName timeOut:(int)timeout errInfo:(NSString **)errInfo;

#pragma mark - For Plugin END

/**
 域名异步解析（通用接口）

 @param domain  域名
 @param handler 返回查询到的IP数组，超时（1s）或者未未查询到返回[0,0]数组
 */
- (void)WGGetHostByNameAsync:(NSString *)domain returnIps:(void (^)(NSArray *ipsArray))handler;

#pragma mark - SNI场景，仅调用一次即可，请勿多次调用
/**
 SNI场景下设置需要拦截的域名列表
 建议使用该接口设置，仅拦截SNI场景下的域名，避免拦截其它场景下的域名

 @param hijackDomainArray 需要拦截的域名列表
 */
- (void)WGSetHijackDomainArray:(NSArray *)hijackDomainArray;

/**
 SNI场景下设置不需要拦截的域名列表

 @param noHijackDomainArray 不需要拦截的域名列表
 */
- (void)WGSetNoHijackDomainArray:(NSArray *)noHijackDomainArray;

#pragma mark - 返回详细数据
/**
详细数据查询接口

@param domain 域名（传入纯域名即可，接口内部会自动拼接当前网络类型作为缓存key查询；
              也支持传入 domain@netChannel 格式直接指定查询）

@return 查询到的详细信息
 格式示例：
 {
 "v4_ips":"1.1.1.1,2.2.2.2",
 "v6_ips":"FF01::1,FF01::2",
 "v4_ttl":"100",
 "v6_ttl":"100",
 "v4_client_ip":"6.6.6.6"
 "v6_client_ip":"FF01::6"
 }
*/
- (NSDictionary *)WGGetDnsDetail:(NSString *)domain;

// sdk是否初始化完成并且可用
- (BOOL)available;

/**
 检查DNS结果是否来自HTTP
 主要是检查缓存结果，需要在域名解析完成后立刻调用检查，方便业务接入确认解析是否来自Http
 
 @param domain 域名
 @return 检查结果，返回int值
    0(00): 本次DNS结果V4和V6均来自Local或为空
    1(01): 本次DNS结果V4来自Local或为空，V6来自Http
    2(10): 本次DNS结果V4来自Http，V6来自Local或为空
    3(11): 本次DNS结果V4和V6均来自Http
 */
- (int)WGCheckDnsResultFromHttp:(NSString *)domain;

@end
#endif
