//
//  UQMUtilsIOS.h
//  Crashot
//
//  Created by joyfyzhang on 2020/9/4.
//  Copyright © 2020 joyfyzhang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "UQMDefine.h"

#define GET_NSSTRING(cString) [NSString stringWithCString:(cString.c_str()?cString:"").c_str() encoding:NSUTF8StringEncoding]

@interface UQMUtilsIOS : NSObject

/**
 *  将NSDictionary转为标准JSON字符串
 *
 *  @param dict 目标字典
 *  @param prettyPrint 生成的JSON数据是否使用空格
 *
 *  @return 结果JSON字符串
 */
+ (NSString *)jsonStringFromDict:(NSDictionary *)dict prettyPrint:(BOOL)prettyPrint;

/**
 *  KVPair vector => NSDictionary
 *
 *  @param kvVector KVPair vector
 *
 *  @return 字典
 */
+ (NSDictionary *)dictFromKVVector:(UQM::UQMVector<UQM::UQMKVPair>)kvVector;

/**
 *  c++ map => NSDictionary
 *
 *  @param kvMap std::map<std::string,std::string>
 *
 *  @return 字典
 */
+ (NSDictionary *)dictFromKVMap:(std::map<std::string,std::string> &)kvMap;

///**
// *  获取原始设备型号
// *
// *  @return 设备型号
// */
//+ (NSString *)getCurrentDeviceModel;
@end
